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

import {TimePowerLoanCore} from "@nexusfi/contracts/protocols/borrower/time-power/utils/TimePowerLoanCore.sol";
import {TimePowerLoanLibs} from "@nexusfi/contracts/protocols/borrower/time-power/utils/TimePowerLoanLibs.sol";
import {TimePowerLoanDefs} from "@nexusfi/contracts/protocols/borrower/time-power/utils/TimePowerLoanDefs.sol";
import {IWhitelist} from "@nexusfi/contracts/whitelist/IWhitelist.sol";
import {IBlacklist} from "@nexusfi/contracts/blacklist/IBlacklist.sol";
import {Roles} from "@nexusfi/contracts/common/Roles.sol";
import {Errors} from "@nexusfi/contracts/common/Errors.sol";

contract TimePowerLoan is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using Math for uint256;
    using SafeERC20 for IERC20;
    using TimePowerLoanLibs for TimePowerLoanDefs.DebtInfo[];
    using TimePowerLoanLibs for TimePowerLoanDefs.LoanInfo[];
    using TimePowerLoanLibs for TimePowerLoanDefs.TrustedVault[];
    using TimePowerLoanCore for uint256[];
    using TimePowerLoanCore for TimePowerLoanDefs.LoanInfo[];
    using TimePowerLoanCore for TimePowerLoanDefs.TrustedVault[];
    using TimePowerLoanCore for TimePowerLoanDefs.TrustedBorrower[];

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

    /// @dev last accumulate interest time
    /// @notice used to calculate accumulated interest rates
    uint64 public _lastAccumulateInterestTime;

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
    TimePowerLoanDefs.LoanInfo[] public _allLoans;

    /// @dev store all debts
    /// @notice each debt is identified by its index in this array
    TimePowerLoanDefs.DebtInfo[] public _allDebts;

    /// @dev store all tranches
    /// @notice each tranche is identified by its index in this array
    TimePowerLoanDefs.TrancheInfo[] public _allTranches;

    /// @dev store all trusted vaults
    /// @notice each trusted vault is identified by its index in this array
    TimePowerLoanDefs.TrustedVault[] public _trustedVaults;

    /// @dev store all trusted borrowers
    /// @notice each trusted borrower is identified by its index in this array
    TimePowerLoanDefs.TrustedBorrower[] public _trustedBorrowers;

    /// @dev second interest rates in fixed point 18
    /// @notice second interest rates should be unique and sorted in ascending order
    /// @notice second interest rates has 18 decimals
    /// @notice second interest rates should be caculated offchain and provided during initialize
    /// @notice if annual interest rate is 36%, second interest rate is (1+36%)^(1/(365*24*60*60))
    uint256[] public _secondInterestRates;

    /// @dev accumulated interest rates in fixed point 18
    /// @notice accumulated interest rates is calculated by formula accumulatedInterestRates[i] = power(secondInterestRates[i], timePeriod)
    /// @notice accumulated interest rates should correspond to second interest rates
    uint256[] public _accumulatedInterestRates;

    /// @dev initialization check modifier
    modifier onlyInitialized() {
        TimePowerLoanLibs.onlyInitialized(
            [_whitelist, _blacklist, _loanToken], [_secondInterestRates.length, _trustedVaults.length]
        );

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
            revert TimePowerLoanDefs.NotTrustedBorrower(borrower_);
        }

        _;
    }

    /// @dev only valid borrower check modifier
    /// @param borrowerIndex_ The index of the borrower to be checked
    /// @notice require borrower is in trusted borrowers list and ceiling limit is not zero
    modifier onlyValidBorrower(uint64 borrowerIndex_) {
        if (borrowerIndex_ >= _trustedBorrowers.length) {
            revert TimePowerLoanDefs.NotValidBorrower(borrowerIndex_);
        }
        if (
            _trustedBorrowers[borrowerIndex_].borrower == address(0)
                || _trustedBorrowers[borrowerIndex_].ceilingLimit == 0
        ) {
            revert TimePowerLoanDefs.NotValidBorrower(borrowerIndex_);
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
            revert TimePowerLoanDefs.NotTrustedVault(vault_);
        }

        _;
    }

    /// @dev only defaulted debt check modifier
    /// @param debtIndex_ The index of the debt
    modifier onlyDefaultedDebt(uint64 debtIndex_) {
        if (debtIndex_ >= _allDebts.length) {
            revert TimePowerLoanDefs.NotValidDebt(debtIndex_);
        }
        if (_allDebts[debtIndex_].status != TimePowerLoanDefs.DebtStatus.DEFAULTED) {
            revert TimePowerLoanDefs.NotDefaultedDebt(debtIndex_);
        }

        _;
    }

    /// @dev only matured debt check modifier
    /// @param debtIndex_ The index of the debt
    modifier onlyMaturedDebt(uint64 debtIndex_) {
        if (debtIndex_ >= _allDebts.length) {
            revert TimePowerLoanDefs.NotValidDebt(debtIndex_);
        }
        if (block.timestamp < _allDebts[debtIndex_].maturityTime) {
            revert TimePowerLoanDefs.NotMaturedDebt(debtIndex_);
        }

        _;
    }

    /// @dev valid debt check modifier
    /// @param debtIndex_ The debt index to be checked
    modifier onlyValidDebt(uint64 debtIndex_) {
        if (debtIndex_ >= _allDebts.length) {
            revert TimePowerLoanDefs.NotValidDebt(debtIndex_);
        }
        if (_allDebts[debtIndex_].status != TimePowerLoanDefs.DebtStatus.ACTIVE) {
            revert TimePowerLoanDefs.NotValidDebt(debtIndex_);
        }

        _;
    }

    /// @dev valid interest rate index check modifier
    /// @param interestRateIndex_ The interest rate index to be checked
    modifier onlyValidInterestRate(uint64 interestRateIndex_) {
        if (interestRateIndex_ >= _secondInterestRates.length) {
            revert TimePowerLoanDefs.NotValidInterestRate(interestRateIndex_);
        }
        if (_secondInterestRates[interestRateIndex_] == 0) {
            revert TimePowerLoanDefs.NotValidInterestRate(interestRateIndex_);
        }

        _;
    }

    /// @dev only loan owner check modifier
    /// @param loanIndex_ The index of the loan
    /// @param borrower_ The address of the borrower
    modifier onlyLoanOwner(uint64 loanIndex_, address borrower_) {
        if (loanIndex_ >= _allLoans.length) {
            revert TimePowerLoanDefs.NotValidLoan(loanIndex_);
        }
        address loanOwner = _trustedBorrowers[_allLoans[loanIndex_].borrowerIndex].borrower;
        if (loanOwner != borrower_) {
            revert TimePowerLoanDefs.NotLoanOwner(loanIndex_, loanOwner, borrower_);
        }

        _;
    }

    /// @dev valid loan check modifier
    /// @param loanIndex_ The index of the loan
    modifier onlyValidLoan(uint64 loanIndex_) {
        if (loanIndex_ >= _allLoans.length) {
            revert TimePowerLoanDefs.NotValidLoan(loanIndex_);
        }
        if (_allLoans[loanIndex_].status != TimePowerLoanDefs.LoanStatus.APPROVED) {
            revert TimePowerLoanDefs.NotValidLoan(loanIndex_);
        }

        _;
    }

    /// @dev valid tranche check modifier
    /// @param trancheIndex_ The index of the tranche
    modifier onlyValidTranche(uint64 trancheIndex_) {
        if (trancheIndex_ >= _allTranches.length) {
            revert TimePowerLoanDefs.NotValidTranche(trancheIndex_);
        }

        _;
    }

    /// @dev valid vault check modifier
    /// @param vaultIndex_ The index of the vault
    modifier onlyValidVault(uint64 vaultIndex_) {
        if (vaultIndex_ >= _trustedVaults.length) {
            revert TimePowerLoanDefs.NotValidVault(vaultIndex_);
        }
        if (_trustedVaults[vaultIndex_].vault == address(0) || _trustedVaults[vaultIndex_].maximumPercentage == 0) {
            revert TimePowerLoanDefs.NotValidVault(vaultIndex_);
        }

        _;
    }

    /// @dev only pending loan check modifier
    /// @param loanIndex_ The index of the loan
    modifier onlyPendingLoan(uint64 loanIndex_) {
        if (loanIndex_ >= _allLoans.length) {
            revert TimePowerLoanDefs.NotValidLoan(loanIndex_);
        }
        if (_allLoans[loanIndex_].status != TimePowerLoanDefs.LoanStatus.PENDING) {
            revert TimePowerLoanDefs.NotPendingLoan(loanIndex_);
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
        TimePowerLoanDefs.TrustedVault[] memory trustedVaults_
    ) external virtual initializer {
        __TimePowerLoan_init(addrs_, secondInterestRates_, trustedVaults_);
    }

    /// @dev join as a trusted borrower
    /// @notice borrower ceiling limit are set to 0 initially
    /// @notice operator should agree or disagree (don't do anything) the join request later
    function join()
        public
        virtual
        onlyInitialized
        whenNotPaused
        nonReentrant
        onlyNotBlacklisted(msg.sender)
        onlyWhitelisted(msg.sender)
        returns (uint64 borrowerIndex_)
    {
        borrowerIndex_ = _join(msg.sender);
    }

    /// @dev agree a borrower join request
    /// @param borrower_ the address of the borrower
    /// @param newCeilingLimit_ the ceiling limit to be applied for the borrower
    /// @notice if operator agrees, ceiling limit should be set to a value greater than 0
    function agree(address borrower_, uint128 newCeilingLimit_)
        public
        virtual
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
        onlyWhitelisted(borrower_)
        onlyNotBlacklisted(borrower_)
        onlyTrustedBorrower(borrower_)
    {
        _agree(borrower_, newCeilingLimit_);
    }

    /// @dev request for a loan
    /// @param amount_ the amount of loan
    /// @return loanIndex_ the loan number of the applied loan (bytes.concat(borrower address, loan index))
    function request(uint128 amount_)
        public
        virtual
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyNotBlacklisted(msg.sender)
        onlyWhitelisted(msg.sender)
        onlyTrustedBorrower(msg.sender)
        onlyValidBorrower(_borrowerToIndex[msg.sender])
        returns (uint64 loanIndex_)
    {
        loanIndex_ = _request(amount_, msg.sender);
    }

    /// @dev approve a loan
    /// @param loanIndex_ the loan number to be approved
    /// @param ceilingLimit_ the ceiling limit for the loan
    /// @param interestRateIndex_ the interest rate index to be applied
    function approve(uint64 loanIndex_, uint128 ceilingLimit_, uint64 interestRateIndex_)
        public
        virtual
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
        onlyPendingLoan(loanIndex_)
        onlyValidInterestRate(interestRateIndex_)
    {
        _approve(loanIndex_, ceilingLimit_, interestRateIndex_);
    }

    /// @dev borrow a loan
    /// @param loanIndex_ the loan number to be borrowed
    /// @param amount_ the amount to be borrowed
    /// @param maturityTime_ the maturity time of the debt
    /// @return isAllSatisfied_ whether all borrowed amount is satisfied
    /// @return debtIndex_ the index of the debt
    function borrow(uint64 loanIndex_, uint128 amount_, uint64 maturityTime_)
        public
        virtual
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyNotBlacklisted(msg.sender)
        onlyWhitelisted(msg.sender)
        onlyValidLoan(loanIndex_)
        onlyLoanOwner(loanIndex_, msg.sender)
        returns (bool isAllSatisfied_, uint64 debtIndex_)
    {
        (isAllSatisfied_, debtIndex_) = _borrow(loanIndex_, amount_, maturityTime_);
    }

    /// @dev repay a loan
    /// @param debtIndex_ the index of the debt to be repaid
    /// @param amount_ the amount to be repaid
    /// @return isAllRepaid_ whether all debt is repaid
    function repay(uint64 debtIndex_, uint128 amount_)
        public
        virtual
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
        virtual
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
        onlyMaturedDebt(debtIndex_)
        onlyValidInterestRate(defaultedInterestRateIndex_)
        onlyLoanOwner(_allDebts[debtIndex_].loanIndex, borrower_)
        returns (uint128 remainingDebt_)
    {
        _updateLoanInterestRate(_allDebts[debtIndex_].loanIndex, defaultedInterestRateIndex_);
        _allDebts[debtIndex_].status = TimePowerLoanDefs.DebtStatus.DEFAULTED;
        remainingDebt_ = uint128(
            uint256(_allDebts[debtIndex_].normalizedPrincipal).mulDiv(
                _accumulatedInterestRates[defaultedInterestRateIndex_], TimePowerLoanDefs.FIXED18, Math.Rounding.Ceil
            )
        );
        emit TimePowerLoanDefs.Defaulted(borrower_, debtIndex_, remainingDebt_, defaultedInterestRateIndex_);
    }

    /// @dev recover a defaulted debt
    /// @param borrower_ the address of the borrower
    /// @param debtIndex_ the index of the debt
    /// @param amount_ the amount to be recovered
    /// @return isAllRepaid_ whether all debt is repaid
    /// @return remainingDebt_ the remaining debt amount after recovery
    function recovery(address borrower_, uint64 debtIndex_, uint128 amount_)
        public
        virtual
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
        onlyDefaultedDebt(debtIndex_)
        onlyLoanOwner(_allDebts[debtIndex_].loanIndex, borrower_)
        returns (bool isAllRepaid_, uint128 remainingDebt_)
    {
        (isAllRepaid_, remainingDebt_) = _repay(borrower_, debtIndex_, amount_);
        emit TimePowerLoanDefs.Recovery(borrower_, debtIndex_, uint128(amount_), remainingDebt_);
    }

    /// @dev close a defaulted debt
    /// @param borrower_ the address of the borrower
    /// @param debtIndex_ the index of the debt
    /// @return lossDebt_ the loss debt amount
    function close(address borrower_, uint64 debtIndex_)
        public
        virtual
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
        onlyDefaultedDebt(debtIndex_)
        onlyLoanOwner(_allDebts[debtIndex_].loanIndex, borrower_)
        returns (uint128 lossDebt_)
    {
        _accumulateInterest();

        TimePowerLoanDefs.DebtInfo memory debt = _allDebts[debtIndex_];
        TimePowerLoanDefs.LoanInfo memory loan = _allLoans[debt.loanIndex];

        uint256 accumulatedInterestRate = _accumulatedInterestRates[loan.interestRateIndex];

        lossDebt_ = uint128(
            uint256(debt.normalizedPrincipal).mulDiv(
                accumulatedInterestRate, TimePowerLoanDefs.FIXED18, Math.Rounding.Ceil
            )
        );

        debt.status = TimePowerLoanDefs.DebtStatus.CLOSED;

        loan.normalizedPrincipal = loan.normalizedPrincipal - debt.normalizedPrincipal;
        loan.remainingLimit += debt.principal;

        debt.normalizedPrincipal = 0;
        debt.principal = 0;

        _allDebts[debtIndex_] = debt;
        _allLoans[debt.loanIndex] = loan;

        uint64[] memory trancheIndexes = _tranchesInfoGroupedByDebt[debtIndex_];
        for (uint256 i = 0; i < trancheIndexes.length; ++i) {
            _allTranches[trancheIndexes[i]].normalizedPrincipal = 0;
        }

        emit TimePowerLoanDefs.Closed(borrower_, debtIndex_, lossDebt_);
    }

    /// @dev update ceiling limit for a borrower
    /// @param borrower_ the address of the borrower
    /// @param newCeilingLimit_ the new ceiling limit to be applied
    function updateBorrowerLimit(address borrower_, uint128 newCeilingLimit_)
        public
        virtual
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

    function updateLoanLimit(uint64 loanIndex_, uint128 newCeilingLimit_)
        public
        virtual
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
        onlyValidLoan(loanIndex_)
        onlyTrustedBorrower(_trustedBorrowers[_allLoans[loanIndex_].borrowerIndex].borrower)
    {
        _allLoans.updateLoanLimit(loanIndex_, newCeilingLimit_, _trustedBorrowers);
    }

    /// @dev update interest rate index for a borrower
    /// @param loanIndex_ the index of the loan
    /// @param newInterestRateIndex_ the new interest rate index to be applied
    function updateLoanInterestRate(uint64 loanIndex_, uint64 newInterestRateIndex_)
        public
        virtual
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
        onlyValidLoan(loanIndex_)
        onlyValidInterestRate(newInterestRateIndex_)
        onlyTrustedBorrower(_trustedBorrowers[_allLoans[loanIndex_].borrowerIndex].borrower)
    {
        _updateLoanInterestRate(loanIndex_, newInterestRateIndex_);
    }

    /// @dev update trusted vault information
    /// @param trustedVault_ the new trusted vault information
    /// @param vaultIndex_ the index of the trusted vault to be updated, add to the end if vaultIndex_ over current length
    /// @return isUpdated_ whether the trusted vault is updated or added
    /// @notice if attempting to remove a trusted vault, use update with maximumPercentage set to 0
    function updateTrustedVaults(TimePowerLoanDefs.TrustedVault memory trustedVault_, uint256 vaultIndex_)
        public
        virtual
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
        returns (bool isUpdated_)
    {
        isUpdated_ = _trustedVaults.updateTrustedVaults(trustedVault_, vaultIndex_, _loanToken);
    }

    /// @dev accumulate interest for all loans
    function pile() public virtual {
        _accumulateInterest();
    }

    /// @dev get total debt of a borrower
    /// @param borrower_ the address of the borrower
    /// @return totalDebt_ the total debt amount of the borrower
    function totalDebtOfBorrower(address borrower_)
        public
        virtual
        onlyTrustedBorrower(borrower_)
        returns (uint256 totalDebt_)
    {
        _accumulateInterest();
        uint64[] memory borrowerLoans = _loansInfoGroupedByBorrower[_borrowerToIndex[borrower_]];
        for (uint256 i = 0; i < borrowerLoans.length; i++) {
            TimePowerLoanDefs.LoanInfo memory borrowerLoan = _allLoans[borrowerLoans[i]];
            totalDebt_ +=
                (uint256(borrowerLoan.normalizedPrincipal) * _accumulatedInterestRates[borrowerLoan.interestRateIndex]);
        }
        totalDebt_ = totalDebt_.mulDiv(
            TimePowerLoanDefs.FIXED18, TimePowerLoanDefs.FIXED18 * TimePowerLoanDefs.FIXED18, Math.Rounding.Ceil
        );
    }

    /// @dev get total debt of a vault
    /// @param vault_ the address of the vault
    /// @return totalDebt_ the total debt amount of the vault
    function totalDebtOfVault(address vault_)
        public
        view
        virtual
        onlyTrustedVault(vault_)
        returns (uint256 totalDebt_)
    {
        uint256[] memory accumulatedInterestRates = _dryrunAccumulatedInterest();
        uint64[] memory vaultTranches = _tranchesInfoGroupedByVault[_vaultToIndex[vault_]];
        for (uint256 i = 0; i < vaultTranches.length; i++) {
            TimePowerLoanDefs.TrancheInfo memory vaultTranche = _allTranches[vaultTranches[i]];
            TimePowerLoanDefs.LoanInfo memory trancheLoan = _allLoans[vaultTranche.loanIndex];
            totalDebt_ +=
                (uint256(vaultTranche.normalizedPrincipal) * accumulatedInterestRates[trancheLoan.interestRateIndex]);
        }
        totalDebt_ = totalDebt_.mulDiv(
            TimePowerLoanDefs.FIXED18, TimePowerLoanDefs.FIXED18 * TimePowerLoanDefs.FIXED18, Math.Rounding.Ceil
        );
    }

    function getTotalTrustedBorrowers() public view virtual returns (uint256) {
        return _trustedBorrowers.length;
    }

    function getTotalLoans() public view virtual returns (uint256) {
        return _allLoans.length;
    }

    function getTotalDebts() public view virtual returns (uint256) {
        return _allDebts.length;
    }

    function getTotalTrustedVaults() public view virtual returns (uint256) {
        return _trustedVaults.length;
    }

    function getTotalTranches() public view virtual returns (uint256) {
        return _allTranches.length;
    }

    function _join(address borrower_) internal returns (uint64 borrowerIndex_) {
        borrowerIndex_ = _trustedBorrowers.join(_borrowerToIndex, borrower_);
    }

    function _agree(address borrower_, uint128 newCeilingLimit_) internal {
        _trustedBorrowers.agree(_borrowerToIndex, borrower_, newCeilingLimit_);
    }

    function _request(uint128 amount_, address borrower_) internal returns (uint64 loanIndex_) {
        loanIndex_ =
            _trustedBorrowers.request(_borrowerToIndex, _allLoans, _loansInfoGroupedByBorrower, amount_, borrower_);
    }

    function _approve(uint64 loanIndex_, uint128 ceilingLimit_, uint64 interestRateIndex_) internal {
        _trustedBorrowers.approve(_allLoans, loanIndex_, ceilingLimit_, interestRateIndex_);
    }

    function __TimePowerLoan_init(
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
        TimePowerLoanDefs.TrustedVault[] memory trustedVaults_
    ) internal onlyInitializing {
        _trustedVaults.initialize(
            _vaultToIndex, _secondInterestRates, _accumulatedInterestRates, addrs_, secondInterestRates_, trustedVaults_
        );

        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        _whitelist = addrs_[1];
        _blacklist = addrs_[2];
        _loanToken = addrs_[3];
        _loanTokenDecimals = IERC20Metadata(_loanToken).decimals();
        _lastAccumulateInterestTime = uint64(block.timestamp);

        _grantRole(Roles.OWNER_ROLE, addrs_[0]);
        _setRoleAdmin(Roles.OPERATOR_ROLE, Roles.OWNER_ROLE);
    }

    /// @dev internal function to accumulate interest for all loans
    function _accumulateInterest() internal {
        _lastAccumulateInterestTime =
            _accumulatedInterestRates.accumulateInterest(_secondInterestRates, _lastAccumulateInterestTime);
    }

    function _dryrunAccumulatedInterest() internal view returns (uint256[] memory accumulatedInterestRates_) {
        accumulatedInterestRates_ =
            _accumulatedInterestRates.dryrunAccumulatedInterest(_secondInterestRates, _lastAccumulateInterestTime);
    }

    function _borrow(uint64 loanIndex_, uint128 amount_, uint64 maturityTime_)
        internal
        returns (bool isAllSatisfied_, uint64 debtIndex_)
    {
        _accumulateInterest();

        (isAllSatisfied_, debtIndex_) = _allLoans.borrow(
            _allTranches,
            _allDebts,
            _trustedVaults,
            _debtsInfoGroupedByLoan,
            _debtsInfoGroupedByBorrower,
            _tranchesInfoGroupedByDebt,
            _tranchesInfoGroupedByLoan,
            _tranchesInfoGroupedByBorrower,
            _tranchesInfoGroupedByVault,
            _accumulatedInterestRates,
            loanIndex_,
            amount_,
            maturityTime_,
            _loanToken,
            msg.sender
        );
    }

    function _repay(address borrower_, uint64 debtIndex_, uint128 amount_)
        internal
        returns (bool isAllRepaid_, uint128 remainingDebt_)
    {
        _accumulateInterest();

        (isAllRepaid_, remainingDebt_) = _allLoans.repay(
            _allTranches,
            _allDebts,
            _trustedVaults,
            _tranchesInfoGroupedByDebt,
            _accumulatedInterestRates,
            borrower_,
            debtIndex_,
            amount_,
            _loanToken
        );
    }

    function _updateLoanInterestRate(uint64 loanIndex_, uint64 newInterestRateIndex_)
        internal
        returns (uint128 newLoanNormalizedPrincipal_)
    {
        TimePowerLoanDefs.LoanInfo memory loanInfo = _allLoans[loanIndex_];

        if (newInterestRateIndex_ == loanInfo.interestRateIndex) {
            return loanInfo.normalizedPrincipal;
        }

        if (loanInfo.normalizedPrincipal > 0) {
            _accumulateInterest();

            uint256 oldAccumulatedInterestRate = _accumulatedInterestRates[loanInfo.interestRateIndex];
            uint256 newAccumulatedInterestRate = _accumulatedInterestRates[newInterestRateIndex_];

            uint64[] memory debtsIndex = _debtsInfoGroupedByLoan[loanIndex_];
            for (uint256 i = 0; i < debtsIndex.length; i++) {
                newLoanNormalizedPrincipal_ += _allDebts.updateDebtInterestRate(
                    debtsIndex[i],
                    _allTranches,
                    _tranchesInfoGroupedByDebt,
                    oldAccumulatedInterestRate,
                    newAccumulatedInterestRate
                );
            }

            _allLoans[loanIndex_].normalizedPrincipal = newLoanNormalizedPrincipal_;
        }

        _allLoans[loanIndex_].interestRateIndex = newInterestRateIndex_;

        emit TimePowerLoanDefs.LoanInterestRateUpdated(loanIndex_, loanInfo.interestRateIndex, newInterestRateIndex_);
    }

    uint256[50] private __gap;
}
