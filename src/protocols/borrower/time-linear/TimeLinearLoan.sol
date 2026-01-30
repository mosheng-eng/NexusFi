// SPDX-Licensed-Identifier: MIT

pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {TimeLinearLoanCore} from "src/protocols/borrower/time-linear/utils/TimeLinearLoanCore.sol";
import {TimeLinearLoanLibs} from "src/protocols/borrower/time-linear/utils/TimeLinearLoanLibs.sol";
import {TimeLinearLoanDefs} from "src/protocols/borrower/time-linear/utils/TimeLinearLoanDefs.sol";
import {IWhitelist} from "src/whitelist/IWhitelist.sol";
import {IBlacklist} from "src/blacklist/IBlacklist.sol";
import {Roles} from "src/common/Roles.sol";
import {Errors} from "src/common/Errors.sol";

contract TimeLinearLoan is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using Math for uint256;
    using SafeERC20 for IERC20;
    using TimeLinearLoanCore for TimeLinearLoanDefs.DebtInfo[];
    using TimeLinearLoanCore for TimeLinearLoanDefs.TrustedVault[];
    using TimeLinearLoanCore for TimeLinearLoanDefs.TrustedBorrower[];
    using TimeLinearLoanLibs for TimeLinearLoanDefs.LoanInfo[];
    using TimeLinearLoanLibs for TimeLinearLoanDefs.DebtInfo[];
    using TimeLinearLoanLibs for TimeLinearLoanDefs.TrustedVault[];
    using TimeLinearLoanLibs for TimeLinearLoanDefs.TrustedBorrower[];

    /// @dev address of the whitelist contract
    /// @notice whitelist contract should implement IWhitelist interface
    address public _whitelist;

    /// @dev address of the blacklist contract
    /// @notice blacklist contract should implement IBlacklist interface
    address public _blacklist;

    /// @dev address of the loan token which is lent to borrower
    /// @notice loan token should be an ERC20 token
    address public _loanToken;

    /// @dev decimals of the loan token
    /// @notice loan token decimals should be the same as ERC20(loanToken).decimals()
    uint8 public _loanTokenDecimals;

    /// @dev mapping of trusted borrower index to loans indexes
    /// @notice used to group loans by borrower
    mapping(uint64 => uint64[]) public _loansInfoGroupedByBorrower;

    /// @dev mapping of loan index to debts indexes
    /// @notice used to group debts by loan
    mapping(uint64 => uint64[]) public _debtsInfoGroupedByLoan;

    /// @dev mapping of borrower index to debts indexes
    /// @notice used to group debts by borrower
    mapping(uint64 => uint64[]) public _debtsInfoGroupedByBorrower;

    /// @dev mapping of debt index to tranches indexes
    /// @notice used to group tranches by debt
    mapping(uint64 => uint64[]) public _tranchesInfoGroupedByDebt;

    /// @dev mapping of loan index to tranches indexes
    /// @notice used to group tranches by loan
    mapping(uint64 => uint64[]) public _tranchesInfoGroupedByLoan;

    /// @dev mapping of borrower index to tranches indexes
    /// @notice used to group tranches by borrower
    mapping(uint64 => uint64[]) public _tranchesInfoGroupedByBorrower;

    /// @dev mapping of vault index to tranches indexes
    /// @notice used to group tranches by vault
    mapping(uint64 => uint64[]) public _tranchesInfoGroupedByVault;

    /// @dev mapping of borrower address to borrower index
    /// @notice used to find borrower index by address conveniently
    mapping(address => uint64) public _borrowerToIndex;

    /// @dev mapping of vault address to vault index
    /// @notice used to find vault index by address conveniently
    mapping(address => uint64) public _vaultToIndex;

    /// @dev store all loans
    /// @notice each loan is identified by its index in this array
    TimeLinearLoanDefs.LoanInfo[] public _allLoans;

    /// @dev store all debts
    /// @notice each debt is identified by its index in this array
    TimeLinearLoanDefs.DebtInfo[] public _allDebts;

    /// @dev store all tranches
    /// @notice each tranche is identified by its index in this array
    TimeLinearLoanDefs.TrancheInfo[] public _allTranches;

    /// @dev store all trusted vaults
    /// @notice each trusted vault is identified by its index in this array
    TimeLinearLoanDefs.TrustedVault[] public _trustedVaults;

    /// @dev store all trusted borrowers
    /// @notice each trusted borrower is identified by its index in this array
    TimeLinearLoanDefs.TrustedBorrower[] public _trustedBorrowers;

    /// @dev second interest rates in TimeLinearLoanDefs.FIXED18
    /// @notice second interest rates should be unique and sorted in ascending order
    /// @notice second interest rates has 18 decimals
    /// @notice second interest rates should be caculated offchain and provided during initialize
    /// @notice if annual interest rate is 36%, second interest rate is 36% / (365 * 24 * 60 * 60)
    uint256[] public _secondInterestRates;

    /// @dev initialization check modifier
    modifier onlyInitialized() {
        if (_whitelist == address(0)) {
            revert Errors.Uninitialized("whitelist");
        }
        if (_blacklist == address(0)) {
            revert Errors.Uninitialized("blacklist");
        }
        if (_loanToken == address(0)) {
            revert Errors.Uninitialized("loanToken");
        }
        if (_secondInterestRates.length == 0) {
            revert Errors.Uninitialized("secondInterestRates");
        }
        if (_trustedVaults.length == 0) {
            revert Errors.Uninitialized("trustedVaults");
        }

        _;
    }

    /// @dev whitelist check modifier
    /// @param borrower_ The address to be checked against the whitelist
    modifier onlyWhitelisted(address borrower_) {
        if (_whitelist == address(0)) {
            revert Errors.ZeroAddress("whitelist");
        }
        if (borrower_ == address(0)) {
            revert Errors.ZeroAddress("borrower");
        }
        if (!IWhitelist(_whitelist).isWhitelisted(borrower_)) {
            revert IWhitelist.NotWhitelisted(borrower_);
        }

        _;
    }

    /// @dev not blacklisted check modifier
    /// @param borrower_ The address to be checked against the blacklist
    modifier onlyNotBlacklisted(address borrower_) {
        if (_blacklist == address(0)) {
            revert Errors.ZeroAddress("blacklist");
        }
        if (borrower_ == address(0)) {
            revert Errors.ZeroAddress("borrower");
        }
        if (IBlacklist(_blacklist).isBlacklisted(borrower_)) {
            revert IBlacklist.Blacklisted(borrower_);
        }

        _;
    }

    /// @dev only trusted borrower check modifier
    /// @param borrower_ The address of the borrower to be checked
    /// @notice require borrower is in trusted borrowers list, no matter ceiling limit is zero or not
    modifier onlyTrustedBorrower(address borrower_) {
        if (borrower_ == address(0)) {
            revert Errors.ZeroAddress("borrower");
        }
        if (_trustedBorrowers[_borrowerToIndex[borrower_]].borrower != borrower_) {
            revert TimeLinearLoanDefs.NotTrustedBorrower(borrower_);
        }

        _;
    }

    /// @dev only valid borrower check modifier
    /// @param borrowerIndex_ The index of the borrower to be checked
    /// @notice require borrower is in trusted borrowers list and ceiling limit is not zero
    modifier onlyValidBorrower(uint64 borrowerIndex_) {
        if (borrowerIndex_ >= _trustedBorrowers.length) {
            revert TimeLinearLoanDefs.NotValidBorrower(borrowerIndex_);
        }
        if (
            _trustedBorrowers[borrowerIndex_].borrower == address(0)
                || _trustedBorrowers[borrowerIndex_].ceilingLimit == 0
        ) {
            revert TimeLinearLoanDefs.NotValidBorrower(borrowerIndex_);
        }

        _;
    }

    /// @dev only trusted vault check modifier
    /// @param vault_ The address of the vault to be checked
    modifier onlyTrustedVault(address vault_) {
        if (vault_ == address(0)) {
            revert Errors.ZeroAddress("vault");
        }
        if (_trustedVaults[_vaultToIndex[vault_]].vault != vault_) {
            revert TimeLinearLoanDefs.NotTrustedVault(vault_);
        }

        _;
    }

    /// @dev only defaulted debt check modifier
    /// @param debtIndex_ The index of the debt
    modifier onlyDefaultedDebt(uint64 debtIndex_) {
        if (debtIndex_ >= _allDebts.length) {
            revert TimeLinearLoanDefs.NotValidDebt(debtIndex_);
        }
        if (_allDebts[debtIndex_].status != TimeLinearLoanDefs.DebtStatus.DEFAULTED) {
            revert TimeLinearLoanDefs.NotDefaultedDebt(debtIndex_);
        }

        _;
    }

    /// @dev only matured debt check modifier
    /// @param debtIndex_ The index of the debt
    modifier onlyMaturedDebt(uint64 debtIndex_) {
        if (debtIndex_ >= _allDebts.length) {
            revert TimeLinearLoanDefs.NotValidDebt(debtIndex_);
        }
        if (block.timestamp < _allDebts[debtIndex_].maturityTime) {
            revert TimeLinearLoanDefs.NotMaturedDebt(debtIndex_);
        }

        _;
    }

    /// @dev valid debt check modifier
    /// @param debtIndex_ The debt index to be checked
    modifier onlyValidDebt(uint64 debtIndex_) {
        if (debtIndex_ >= _allDebts.length) {
            revert TimeLinearLoanDefs.NotValidDebt(debtIndex_);
        }
        if (_allDebts[debtIndex_].status != TimeLinearLoanDefs.DebtStatus.ACTIVE) {
            revert TimeLinearLoanDefs.NotValidDebt(debtIndex_);
        }

        _;
    }

    /// @dev valid interest rate index check modifier
    /// @param interestRateIndex_ The interest rate index to be checked
    modifier onlyValidInterestRate(uint64 interestRateIndex_) {
        if (interestRateIndex_ >= _secondInterestRates.length) {
            revert TimeLinearLoanDefs.NotValidInterestRate(interestRateIndex_);
        }
        if (_secondInterestRates[interestRateIndex_] == 0) {
            revert TimeLinearLoanDefs.NotValidInterestRate(interestRateIndex_);
        }

        _;
    }

    /// @dev only loan owner check modifier
    /// @param loanIndex_ The index of the loan
    /// @param borrower_ The address of the borrower
    modifier onlyLoanOwner(uint64 loanIndex_, address borrower_) {
        if (loanIndex_ >= _allLoans.length) {
            revert TimeLinearLoanDefs.NotValidLoan(loanIndex_);
        }
        address loanOwner = _trustedBorrowers[_allLoans[loanIndex_].borrowerIndex].borrower;
        if (loanOwner != borrower_) {
            revert TimeLinearLoanDefs.NotLoanOwner(loanIndex_, loanOwner, borrower_);
        }

        _;
    }

    /// @dev valid loan check modifier
    /// @param loanIndex_ The index of the loan
    modifier onlyValidLoan(uint64 loanIndex_) {
        if (loanIndex_ >= _allLoans.length) {
            revert TimeLinearLoanDefs.NotValidLoan(loanIndex_);
        }
        if (_allLoans[loanIndex_].status != TimeLinearLoanDefs.LoanStatus.APPROVED) {
            revert TimeLinearLoanDefs.NotValidLoan(loanIndex_);
        }

        _;
    }

    /// @dev valid tranche check modifier
    /// @param trancheIndex_ The index of the tranche
    modifier onlyValidTranche(uint64 trancheIndex_) {
        if (trancheIndex_ >= _allTranches.length) {
            revert TimeLinearLoanDefs.NotValidTranche(trancheIndex_);
        }

        _;
    }

    /// @dev valid vault check modifier
    /// @param vaultIndex_ The index of the vault
    modifier onlyValidVault(uint64 vaultIndex_) {
        if (vaultIndex_ >= _trustedVaults.length) {
            revert TimeLinearLoanDefs.NotValidVault(vaultIndex_);
        }
        if (_trustedVaults[vaultIndex_].vault == address(0) || _trustedVaults[vaultIndex_].maximumPercentage == 0) {
            revert TimeLinearLoanDefs.NotValidVault(vaultIndex_);
        }

        _;
    }

    /// @dev only pending loan check modifier
    /// @param loanIndex_ The index of the loan
    modifier onlyPendingLoan(uint64 loanIndex_) {
        if (loanIndex_ >= _allLoans.length) {
            revert TimeLinearLoanDefs.NotValidLoan(loanIndex_);
        }
        if (_allLoans[loanIndex_].status != TimeLinearLoanDefs.LoanStatus.PENDING) {
            revert TimeLinearLoanDefs.NotPendingLoan(loanIndex_);
        }

        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        /**
         * 0: address owner_,
         * 1: address whitelist_,
         * 2: address blacklist_,
         * 3: address loanToken_,
         */
        address[4] memory addrs_,
        /**
         * annual interest rates sorted in ascending order
         */
        uint64[] memory secondInterestRates_,
        /**
         * vaults that are allowed to lend to borrowers
         */
        TimeLinearLoanDefs.TrustedVault[] memory trustedVaults_
    ) external initializer {
        _trustedVaults.initialize(_vaultToIndex, _secondInterestRates, addrs_, secondInterestRates_, trustedVaults_);

        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        _whitelist = addrs_[1];
        _blacklist = addrs_[2];
        _loanToken = addrs_[3];
        _loanTokenDecimals = IERC20Metadata(_loanToken).decimals();

        _grantRole(Roles.OWNER_ROLE, addrs_[0]);
        _setRoleAdmin(Roles.OPERATOR_ROLE, Roles.OWNER_ROLE);
    }

    /// @dev join as a trusted borrower
    /// @notice borrower ceiling limit are set to 0 initially
    /// @notice operator should agree or disagree (don't do anything) the join request later
    function join()
        public
        onlyInitialized
        whenNotPaused
        nonReentrant
        onlyNotBlacklisted(msg.sender)
        onlyWhitelisted(msg.sender)
        returns (uint64 borrowerIndex_)
    {
        borrowerIndex_ = _trustedBorrowers.join(_borrowerToIndex);
    }

    /// @dev agree a borrower join request
    /// @param borrower_ the address of the borrower
    /// @param newCeilingLimit_ the ceiling limit to be applied for the borrower
    /// @notice if operator agrees, ceiling limit should be set to a value greater than 0
    function agree(address borrower_, uint128 newCeilingLimit_)
        public
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
        onlyWhitelisted(borrower_)
        onlyNotBlacklisted(borrower_)
        onlyTrustedBorrower(borrower_)
    {
        _trustedBorrowers.agree(_borrowerToIndex, borrower_, newCeilingLimit_);
    }

    /// @dev request for a loan
    /// @param amount_ the amount of loan
    /// @return loanIndex_ the loan number of the applied loan (bytes.concat(borrower address, loan index))
    function request(uint128 amount_)
        public
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyNotBlacklisted(msg.sender)
        onlyWhitelisted(msg.sender)
        onlyTrustedBorrower(msg.sender)
        onlyValidBorrower(_borrowerToIndex[msg.sender])
        returns (uint64 loanIndex_)
    {
        loanIndex_ = _trustedBorrowers.request(_borrowerToIndex, _allLoans, _loansInfoGroupedByBorrower, amount_);
    }

    /// @dev approve a loan
    /// @param loanIndex_ the loan number to be approved
    /// @param ceilingLimit_ the ceiling limit for the loan
    /// @param interestRateIndex_ the interest rate index to be applied
    function approve(uint64 loanIndex_, uint128 ceilingLimit_, uint64 interestRateIndex_)
        public
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
        onlyPendingLoan(loanIndex_)
        onlyValidInterestRate(interestRateIndex_)
    {
        _trustedBorrowers.approve(_allLoans, loanIndex_, ceilingLimit_, interestRateIndex_);
    }

    /// @dev borrow a loan
    /// @param loanIndex_ the loan number to be borrowed
    /// @param amount_ the amount to be borrowed
    /// @param maturityTime_ the maturity time of the debt
    /// @return isAllSatisfied_ whether all borrowed amount is satisfied
    /// @return debtIndex_ the index of the debt
    function borrow(uint64 loanIndex_, uint128 amount_, uint64 maturityTime_)
        public
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyNotBlacklisted(msg.sender)
        onlyWhitelisted(msg.sender)
        onlyValidLoan(loanIndex_)
        onlyLoanOwner(loanIndex_, msg.sender)
        returns (bool isAllSatisfied_, uint64 debtIndex_)
    {
        if (maturityTime_ <= uint64(block.timestamp)) {
            revert TimeLinearLoanDefs.MaturityTimeShouldAfterBlockTimestamp(maturityTime_, uint64(block.timestamp));
        }

        TimeLinearLoanDefs.LoanInfo memory loan = _allLoans[loanIndex_];

        if (amount_ > loan.remainingLimit) {
            revert TimeLinearLoanDefs.BorrowAmountOverLoanRemainingLimit(amount_, loan.remainingLimit, loanIndex_);
        }

        (uint256[] memory trancheAmounts, uint256 availableAmount) =
            _trustedVaults.prepareFunds(_loanToken, uint256(amount_));

        isAllSatisfied_ = availableAmount == uint256(amount_);

        for (uint256 i = 0; i < trancheAmounts.length; ++i) {
            if (trancheAmounts[i] == 0) {
                continue;
            }

            _allTranches.push(
                TimeLinearLoanDefs.TrancheInfo({
                    vaultIndex: uint64(i),
                    debtIndex: uint64(_allDebts.length),
                    loanIndex: loanIndex_,
                    borrowerIndex: loan.borrowerIndex,
                    principal: uint128(trancheAmounts[i])
                })
            );

            uint64 trancheIndex = uint64(_allTranches.length - 1);

            _tranchesInfoGroupedByDebt[uint64(_allDebts.length)].push(trancheIndex);
            _tranchesInfoGroupedByLoan[loanIndex_].push(trancheIndex);
            _tranchesInfoGroupedByBorrower[loan.borrowerIndex].push(trancheIndex);
            _tranchesInfoGroupedByVault[uint64(i)].push(trancheIndex);
        }

        loan.remainingLimit -= uint128(availableAmount);

        _allLoans[loanIndex_] = loan;

        _allDebts.push(
            TimeLinearLoanDefs.DebtInfo({
                loanIndex: loanIndex_,
                startTime: uint64(block.timestamp),
                maturityTime: maturityTime_,
                lastUpdateTime: uint64(block.timestamp),
                principal: uint128(availableAmount),
                netRemainingDebt: uint128(availableAmount),
                interestBearingAmount: uint128(availableAmount),
                netRemainingInterest: 0,
                status: TimeLinearLoanDefs.DebtStatus.ACTIVE
            })
        );

        debtIndex_ = uint64(_allDebts.length - 1);

        _debtsInfoGroupedByLoan[loanIndex_].push(debtIndex_);
        _debtsInfoGroupedByBorrower[loan.borrowerIndex].push(debtIndex_);

        IERC20(_loanToken).safeTransfer(msg.sender, availableAmount);

        emit TimeLinearLoanDefs.Borrowed(msg.sender, loanIndex_, uint128(availableAmount), isAllSatisfied_, debtIndex_);
    }

    /// @dev repay a loan
    /// @param debtIndex_ the index of the debt to be repaid
    /// @param amount_ the amount to be repaid
    /// @return isAllRepaid_ whether all debt is repaid
    function repay(uint64 debtIndex_, uint128 amount_)
        public
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyNotBlacklisted(msg.sender)
        onlyWhitelisted(msg.sender)
        onlyValidDebt(debtIndex_)
        onlyLoanOwner(_allDebts[debtIndex_].loanIndex, msg.sender)
        returns (bool isAllRepaid_, uint128 remainingDebt_)
    {
        (isAllRepaid_, remainingDebt_) = _repay(msg.sender, debtIndex_, amount_);
    }

    /// @dev mark a debt as defaulted
    /// @param borrower_ the address of the borrower
    /// @param debtIndex_ the index of the debt
    /// @param defaultedInterestRateIndex_ the interest rate index applied for the defaulted debt
    /// @return remainingDebt_ the remaining debt amount after default
    function defaulted(address borrower_, uint64 debtIndex_, uint64 defaultedInterestRateIndex_)
        public
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
        onlyMaturedDebt(debtIndex_)
        onlyValidInterestRate(defaultedInterestRateIndex_)
        onlyLoanOwner(_allDebts[debtIndex_].loanIndex, borrower_)
        returns (uint128 remainingDebt_)
    {
        remainingDebt_ = _allLoans.updateLoanInterestRate(
            _allDebts[debtIndex_].loanIndex,
            defaultedInterestRateIndex_,
            _allDebts,
            _secondInterestRates,
            _debtsInfoGroupedByLoan,
            false
        );
        _allDebts[debtIndex_].status = TimeLinearLoanDefs.DebtStatus.DEFAULTED;

        emit TimeLinearLoanDefs.Defaulted(borrower_, debtIndex_, remainingDebt_, defaultedInterestRateIndex_);
    }

    /// @dev recover a defaulted debt
    /// @param borrower_ the address of the borrower
    /// @param debtIndex_ the index of the debt
    /// @param amount_ the amount to be recovered
    /// @return isAllRepaid_ whether all debt is repaid
    /// @return remainingDebt_ the remaining debt amount after recovery
    function recovery(address borrower_, uint64 debtIndex_, uint128 amount_)
        public
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
        onlyDefaultedDebt(debtIndex_)
        onlyLoanOwner(_allDebts[debtIndex_].loanIndex, borrower_)
        returns (bool isAllRepaid_, uint128 remainingDebt_)
    {
        (isAllRepaid_, remainingDebt_) = _repay(borrower_, debtIndex_, amount_);
        emit TimeLinearLoanDefs.Recovery(borrower_, debtIndex_, uint128(amount_), remainingDebt_);
    }

    /// @dev close a defaulted debt
    /// @param borrower_ the address of the borrower
    /// @param debtIndex_ the index of the debt
    /// @return lossDebt_ the loss debt amount
    function close(address borrower_, uint64 debtIndex_)
        public
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
        onlyDefaultedDebt(debtIndex_)
        onlyLoanOwner(_allDebts[debtIndex_].loanIndex, borrower_)
        returns (uint128 lossDebt_)
    {
        lossDebt_ = _allDebts.close(borrower_, debtIndex_, _allLoans, _secondInterestRates);
    }

    /// @dev adds an address to the whitelist
    /// @param borrower_ the address to be added to the whitelist
    function addWhitelist(address borrower_)
        public
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
    {
        IWhitelist(_whitelist).add(borrower_);
    }

    /// @dev removes an address from the whitelist
    /// @param borrower_ the address to be removed from the whitelist
    function removeWhitelist(address borrower_)
        public
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
    {
        IWhitelist(_whitelist).remove(borrower_);
    }

    /// @dev adds an address to the blacklist
    /// @param borrower_ the address to be added to the blacklist
    function addBlacklist(address borrower_)
        public
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
    {
        IBlacklist(_blacklist).add(borrower_);
    }

    /// @dev removes an address from the blacklist
    /// @param borrower_ the address to be removed from the blacklist
    function removeBlacklist(address borrower_)
        public
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
    {
        IBlacklist(_blacklist).remove(borrower_);
    }

    /// @dev update ceiling limit for a borrower
    /// @param borrower_ the address of the borrower
    /// @param newCeilingLimit_ the new ceiling limit to be applied
    function updateBorrowerLimit(address borrower_, uint128 newCeilingLimit_)
        public
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
        onlyWhitelisted(borrower_)
        onlyNotBlacklisted(borrower_)
        onlyTrustedBorrower(borrower_)
    {
        _trustedBorrowers.updateBorrowerLimit(_borrowerToIndex, borrower_, newCeilingLimit_);
    }

    function updateLoanLimit(uint64 loanIndex_, uint128 newCeilingLimit)
        public
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
        onlyValidLoan(loanIndex_)
        onlyTrustedBorrower(_trustedBorrowers[_allLoans[loanIndex_].borrowerIndex].borrower)
    {
        _allLoans.updateLoanLimit(loanIndex_, newCeilingLimit, _trustedBorrowers);
    }

    /// @dev update interest rate index for a borrower
    /// @param loanIndex_ the index of the loan
    /// @param newInterestRateIndex_ the new interest rate index to be applied
    function updateLoanInterestRate(uint64 loanIndex_, uint64 newInterestRateIndex_)
        public
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
        onlyValidLoan(loanIndex_)
        onlyValidInterestRate(newInterestRateIndex_)
        onlyTrustedBorrower(_trustedBorrowers[_allLoans[loanIndex_].borrowerIndex].borrower)
    {
        _allLoans.updateLoanInterestRate(
            loanIndex_, newInterestRateIndex_, _allDebts, _secondInterestRates, _debtsInfoGroupedByLoan, false
        );
    }

    /// @dev update trusted vault information
    /// @param trustedVault_ the new trusted vault information
    /// @param vaultIndex_ the index of the trusted vault to be updated, add to the end if vaultIndex_ over current length
    /// @return isUpdated_ whether the trusted vault is updated or added
    /// @notice if attempting to remove a trusted vault, use update with maximumPercentage set to 0
    function updateTrustedVaults(TimeLinearLoanDefs.TrustedVault memory trustedVault_, uint256 vaultIndex_)
        public
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
        returns (bool isUpdated_)
    {
        isUpdated_ = _trustedVaults.updateTrustedVaults(trustedVault_, vaultIndex_, _loanToken);
    }

    /// @dev accumulate interest for specific debt
    function pile(uint64 debtIndex_) public {
        _allDebts.updateDebt(debtIndex_, _allLoans, _secondInterestRates, false);
    }

    /// @dev accumulate interest for all debt
    function pile() public {
        for (uint64 i = 0; i < _allDebts.length; i++) {
            _allDebts.updateDebt(i, _allLoans, _secondInterestRates, false);
        }
    }

    /// @dev get total debt of a borrower
    /// @param borrower_ the address of the borrower
    /// @return totalDebt_ the total debt amount of the borrower
    function totalDebtOfBorrower(address borrower_)
        public
        onlyTrustedBorrower(borrower_)
        returns (uint256 totalDebt_)
    {
        uint64[] memory borrowerLoanIndexes = _loansInfoGroupedByBorrower[_borrowerToIndex[borrower_]];
        for (uint256 i = 0; i < borrowerLoanIndexes.length; i++) {
            TimeLinearLoanDefs.LoanInfo memory borrowerLoan = _allLoans[borrowerLoanIndexes[i]];
            totalDebt_ += _allLoans.updateLoanInterestRate(
                borrowerLoanIndexes[i],
                borrowerLoan.interestRateIndex,
                _allDebts,
                _secondInterestRates,
                _debtsInfoGroupedByLoan,
                true
            );
        }
    }

    /// @dev get total debt of a vault
    /// @param vault_ the address of the vault
    /// @return totalDebt_ the total debt amount of the vault
    function totalDebtOfVault(address vault_) public onlyTrustedVault(vault_) returns (uint256 totalDebt_) {
        uint64[] memory vaultTrancheIndexes = _tranchesInfoGroupedByVault[_vaultToIndex[vault_]];
        for (uint256 i = 0; i < vaultTrancheIndexes.length; i++) {
            TimeLinearLoanDefs.TrancheInfo memory trancheInfo = _allTranches[vaultTrancheIndexes[i]];
            TimeLinearLoanDefs.DebtInfo memory debtInfo = _allDebts[trancheInfo.debtIndex];
            totalDebt_ += uint256(_allDebts.updateDebt(trancheInfo.debtIndex, _allLoans, _secondInterestRates, true))
                .mulDiv(trancheInfo.principal, debtInfo.principal, Math.Rounding.Ceil);
        }
    }

    function getTotalTrustedBorrowers() public view returns (uint256) {
        return _trustedBorrowers.length;
    }

    function getTotalTrustedVaults() public view returns (uint256) {
        return _trustedVaults.length;
    }

    function getTotalLoans() public view returns (uint256) {
        return _allLoans.length;
    }

    function getTotalDebts() public view returns (uint256) {
        return _allDebts.length;
    }

    function getTotalTranches() public view returns (uint256) {
        return _allTranches.length;
    }

    function _repay(address borrower_, uint64 debtIndex_, uint128 amount_)
        internal
        returns (bool isAllRepaid_, uint128 remainingDebt_)
    {
        /// @dev cache storage to memory
        TimeLinearLoanDefs.DebtInfo memory debt = _allDebts[debtIndex_];
        TimeLinearLoanDefs.LoanInfo memory loan = _allLoans[debt.loanIndex];

        /// @dev calculate total repaid principal before this repay
        /// @dev used to adjust loan remaining limit after this repay
        uint128 totalRepaidPrincipalBeforeRepay = debt.principal + debt.netRemainingInterest - debt.netRemainingDebt;

        /// @dev calculate interest increment since last update
        uint128 interestIncrement = uint128(
            uint256(debt.interestBearingAmount * (block.timestamp - debt.lastUpdateTime)).mulDiv(
                _secondInterestRates[loan.interestRateIndex], TimeLinearLoanDefs.FIXED18, Math.Rounding.Ceil
            )
        );

        /// @dev calculate net remaining debt before repay
        uint128 netRemainingDebtBeforeRepay = debt.netRemainingDebt + interestIncrement;

        /// @dev adjust repay amount if exceeds net remaining debt
        /// @dev protocol only accepts repay amount up to net remaining debt
        amount_ = amount_ > netRemainingDebtBeforeRepay ? netRemainingDebtBeforeRepay : amount_;

        /// @dev calculate net remaining debt after repay
        /// @dev be cautious that amount_ is already adjusted above
        uint128 netRemainingDebtAfterRepay = netRemainingDebtBeforeRepay - amount_;

        /// @dev caculate net remaining interest before repay
        uint128 netRemainingInterestBeforeRepay = debt.netRemainingInterest + interestIncrement;

        /// @dev repay amount covers total remaining interest by now
        if (amount_ >= netRemainingInterestBeforeRepay) {
            /// @dev interest bearing amount for next repayment equals to net remaining debt after repay
            /// @dev net reaming debt has considered both principal and interest
            debt.interestBearingAmount = netRemainingDebtAfterRepay;
            /// @dev offcourse net remaining interest becomes zero after repay
            debt.netRemainingInterest = 0;
        }
        /// @dev repay amount only covers part of total remaining interest by now
        else {
            /// @dev interest bearing amount for next repayment remains unchanged, because principal is not repaid this time
            /// @dev net remaining interest decreases by the repay amount, because only part interest is repaid this time
            debt.netRemainingInterest = netRemainingInterestBeforeRepay - amount_;
        }

        /// @dev store net remaining debt for next repayment calculation
        debt.netRemainingDebt = netRemainingDebtAfterRepay;
        /// @dev store last update time for next interest calculation
        debt.lastUpdateTime = uint64(block.timestamp);

        /// @dev if debt has no remaining debt, mark it as repaid
        if (debt.netRemainingDebt == 0) {
            isAllRepaid_ = true;
            debt.status = TimeLinearLoanDefs.DebtStatus.REPAID;
        }

        /// @dev calculate total repaid principal after this repay
        /// @dev used to adjust loan remaining limit after this repay
        uint128 totalRepaidPrincipalAfterRepay = debt.principal + debt.netRemainingInterest - debt.netRemainingDebt;

        /// @dev adjust loan remaining limit according to the repaid principal amount
        /// @dev only repaid principal increases loan remaining limit
        loan.remainingLimit += (totalRepaidPrincipalAfterRepay - totalRepaidPrincipalBeforeRepay);

        /// @dev calculate remaining debt to be returned
        remainingDebt_ = debt.netRemainingDebt;

        _allDebts[debtIndex_] = debt;
        _allLoans[debt.loanIndex] = loan;

        IERC20(_loanToken).safeTransferFrom(borrower_, address(this), uint256(amount_));

        _trustedVaults.distributeFunds(
            _allTranches, _tranchesInfoGroupedByDebt, _loanToken, debtIndex_, debt.principal, uint256(amount_)
        );

        emit TimeLinearLoanDefs.Repaid(borrower_, debtIndex_, amount_, isAllRepaid_);
    }

    uint256[50] private __gap;
}
