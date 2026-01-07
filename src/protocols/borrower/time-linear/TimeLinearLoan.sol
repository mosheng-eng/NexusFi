// SPDX-Licensed-Identifier: MIT

pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IWhitelist} from "src/whitelist/IWhitelist.sol";
import {IBlacklist} from "src/blacklist/IBlacklist.sol";
import {Roles} from "src/common/Roles.sol";
import {Errors} from "src/common/Errors.sol";

contract TimeLinearLoan is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using Math for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    /// @dev error thrown when an address is not a trusted borrower
    /// @param borrower_ address of the borrower
    error NotTrustedBorrower(address borrower_);

    /// @dev error thrown when a borrower is not valid
    /// @param borrowerIndex_ index of the borrower
    error NotValidBorrower(uint64 borrowerIndex_);

    /// @dev error thrown when a loan is not valid
    /// @param loanIndex_ index of the loan
    error NotValidLoan(uint64 loanIndex_);

    /// @dev error thrown when borrower is not the owner of the loan
    /// @param loanIndex_ index of the loan
    /// @param loanOwer_ address of the loan owner
    /// @param borrower_ address of the borrower
    error NotLoanOwner(uint64 loanIndex_, address loanOwer_, address borrower_);

    /// @dev error thrown when a loan is not pending
    /// @param loanIndex_ index of the loan
    error NotPendingLoan(uint64 loanIndex_);

    /// @dev error thrown when a debt is not valid
    /// @param debtIndex_ index of the debt
    error NotValidDebt(uint64 debtIndex_);

    /// @dev error thrown when a debt is not defaulted
    /// @param debtIndex_ index of the debt
    error NotDefaultedDebt(uint64 debtIndex_);

    /// @dev error thrown when a debt is not matured
    /// @param debtIndex_ index of the debt
    error NotMaturedDebt(uint64 debtIndex_);

    /// @dev error thrown when a tranche is not valid
    /// @param trancheIndex_ index of the tranche
    error NotValidTranche(uint64 trancheIndex_);

    /// @dev error thrown when an address is not a trusted vault
    /// @param vault_ address of the vault
    error NotTrustedVault(address vault_);

    /// @dev error thrown when a vault is not valid
    /// @param vaultIndex_ index of the vault
    error NotValidVault(uint64 vaultIndex_);

    /// @dev error thrown when an interest rate index is not valid
    /// @param interestRateIndex_ index of the interest rate
    error NotValidInterestRate(uint64 interestRateIndex_);

    /// @dev error thrown when ceiling limit below remaining limit
    /// @param ceilingLimit_ ceiling limit
    /// @param remainingLimit_ remaining limit
    error CeilingLimitBelowRemainingLimit(uint128 ceilingLimit_, uint128 remainingLimit_);

    /// @dev error thrown when ceiling limit below used limit which is caculated by ceiling limit substract remaining limit
    /// @param ceilingLimit_ ceiling limit
    /// @param usedLimit_ difference of ceiling limit and remaining limit
    error CeilingLimitBelowUsedLimit(uint128 ceilingLimit_, uint128 usedLimit_);

    /// @dev error thrown when loan ceiling limit exceeds borrower's remaining limit
    /// @param loanCeilingLimit_ loan ceiling limit
    /// @param borrowerRemainingLimit_ borrower's remaining limit
    error LoanCeilingLimitExceedsBorrowerRemainingLimit(uint128 loanCeilingLimit_, uint128 borrowerRemainingLimit_);

    /// @dev error thrown when borrower already exists
    /// @param borrower_ address of the borrower
    /// @param borrowerIndex_ index of the borrower
    error BorrowerAlreadyExists(address borrower_, uint64 borrowerIndex_);

    /// @dev error thrown when agree join request but ceiling limit is zero
    /// @param borrower_ address of the borrower
    error AgreeJoinRequestShouldHaveNonZeroCeilingLimit(address borrower_);

    /// @dev error thrown when duplicated agree join request
    /// @param borrower_ address of the borrower
    error UpdateCeilingLimitDirectly(address borrower_);

    /// @dev error thrown when borrow amount exceeds loan remaining limit
    /// @param borrowAmount_ amount of the borrow
    /// @param loanRemainingLimit_ remaining limit of the loan
    /// @param loanIndex_ index of the loan
    error BorrowAmountOverLoanRemainingLimit(uint128 borrowAmount_, uint128 loanRemainingLimit_, uint64 loanIndex_);

    /// @dev error thrown when maturity time is before or at block timestamp
    /// @param maturityTime_ maturity time
    /// @param blockTimestamp_ block timestamp
    error MaturityTimeShouldAfterBlockTimestamp(uint64 maturityTime_, uint64 blockTimestamp_);

    /// @dev event emitted when borrower ceiling limit is updated
    /// @param oldCeilingLimit_ old ceiling limit
    /// @param newCeilingLimit_ new ceiling limit
    event BorrowerCeilingLimitUpdated(uint128 oldCeilingLimit_, uint128 newCeilingLimit_);

    /// @dev event emitted when loan ceiling limit is updated
    /// @param oldCeilingLimit_ old ceiling limit
    /// @param newCeilingLimit_ new ceiling limit
    event LoanCeilingLimitUpdated(uint128 oldCeilingLimit_, uint128 newCeilingLimit_);

    /// @dev event emitted when interest rate index is updated
    /// @param loanIndex_ index of the loan
    /// @param oldInterestRateIndex_ old interest rate index
    /// @param newInterestRateIndex_ new interest rate index
    event LoanInterestRateUpdated(uint64 loanIndex_, uint64 oldInterestRateIndex_, uint64 newInterestRateIndex_);

    /// @dev event emitted when trusted vault is updated
    /// @param oldVault_ address of the old trusted vault
    /// @param oldMinimumPercentage_ minimum percentage of the old trusted vault
    /// @param oldMaximumPercentage_ maximum percentage of the old trusted vault
    /// @param newVault_ address of the new trusted vault
    /// @param newMinimumPercentage_ minimum percentage of the new trusted vault
    /// @param newMaximumPercentage_ maximum percentage of the new trusted vault
    /// @param vaultIndex_ index of the trusted vault
    event TrustedVaultUpdated(
        address oldVault_,
        uint48 oldMinimumPercentage_,
        uint48 oldMaximumPercentage_,
        address newVault_,
        uint48 newMinimumPercentage_,
        uint48 newMaximumPercentage_,
        uint256 vaultIndex_
    );

    /// @dev event emitted when trusted vault is added
    /// @param vault_ address of the trusted vault
    /// @param minimumPercentage_ minimum percentage
    /// @param maximumPercentage_ maximum percentage
    event TrustedVaultAdded(address vault_, uint48 minimumPercentage_, uint48 maximumPercentage_, uint256 vaultIndex_);

    /// @dev event emitted when trusted borrower is added
    /// @param borrower_ address of the trusted borrower
    /// @param borrowerIndex_ index of the trusted borrower
    event TrustedBorrowerAdded(address borrower_, uint64 borrowerIndex_);

    /// @dev event emitted when a borrower join request is agreed
    /// @param borrower_ address of the borrower
    /// @param newCeilingLimit_ new ceiling limit of the borrower
    event AgreeJoinRequest(address borrower_, uint128 newCeilingLimit_);

    /// @dev event emitted when a loan request is received
    /// @param borrower_ address of the borrower
    /// @param loanIndex_ index of the loan
    /// @param amount_ amount of the loan request
    event ReceiveLoanRequest(address borrower_, uint64 loanIndex_, uint128 amount_);

    /// @dev event emitted when a loan request is approved
    /// @param borrower_ address of the borrower
    /// @param loanIndex_ index of the loan
    /// @param ceilingLimit_ ceiling limit of the approved loan
    /// @param interestRateIndex_ interest rate index of the approved loan
    event ApproveLoanRequest(address borrower_, uint64 loanIndex_, uint128 ceilingLimit_, uint64 interestRateIndex_);

    /// @dev event emitted when a new debt is borrowed
    /// @param borrower_ address of the borrower
    /// @param loanIndex_ index of the loan
    /// @param amount_ amount of the borrowed debt
    /// @param isAllSatisfied_ whether the borrowed debt is fully satisfied
    /// @param debtIndex_ index of the new debt
    event Borrowed(address borrower_, uint64 loanIndex_, uint128 amount_, bool isAllSatisfied_, uint64 debtIndex_);

    /// @dev event emitted when a debt is repaid
    /// @param borrower_ address of the borrower
    /// @param debtIndex_ index of the debt
    /// @param amount_ amount of the repaid debt
    /// @param isAllRepaid_ whether the debt is fully repaid
    event Repaid(address borrower_, uint64 debtIndex_, uint128 amount_, bool isAllRepaid_);

    /// @dev event emitted when a debt is defaulted
    /// @param borrower_ address of the borrower
    /// @param debtIndex_ index of the debt
    /// @param remainingDebt_ amount of the remaining debt
    /// @param defaultedInterestRateIndex_ interest rate index at the time of default
    event Defaulted(address borrower_, uint64 debtIndex_, uint128 remainingDebt_, uint64 defaultedInterestRateIndex_);

    /// @dev event emitted when a defaulted debt is recovered
    /// @param borrower_ address of the borrower
    /// @param debtIndex_ index of the debt
    /// @param recoveredAmount_ amount of the recovered debt
    /// @param remainingDebt_ amount of the remaining debt after recovery
    event Recovery(address borrower_, uint64 debtIndex_, uint128 recoveredAmount_, uint128 remainingDebt_);

    /// @dev event emitted when a defaulted debt is closed
    /// @param borrower_ address of the borrower
    /// @param debtIndex_ index of the debt
    /// @param lossDebt_ amount of the loss debt
    event Closed(address borrower_, uint64 debtIndex_, uint128 lossDebt_);

    /// @dev status of a debt
    enum DebtStatus {
        /// @dev default value, not existed debt
        NOT_EXISTED,
        /// @dev debt is approved and time is before or at maturity date
        ACTIVE,
        /// @dev debt is zero after maturity date
        REPAID,
        /// @dev debt is not zero after maturity date
        DEFAULTED,
        /// @dev debt is closed by operator after default
        CLOSED
    }

    /// @dev status of a loan
    enum LoanStatus {
        /// @dev default value, not existed loan
        NOT_EXISTED,
        /// @dev loan is not approved by operator yet
        PENDING,
        /// @dev loan is approved by operator
        APPROVED,
        /// @dev loan is rejected by operator
        REJECTED
    }

    /// @dev trusted vault information
    struct TrustedVault {
        /// @dev address of the trusted vault
        address vault;
        /// @dev minimum percentage of each loan that borrow from this vault in million (1_000_000 = 100%)
        uint48 minimumPercentage;
        /// @dev maximum percentage of each loan that borrow from this vault in million (1_000_000 = 100%)
        uint48 maximumPercentage;
    }

    /// @dev trusted borrower information
    struct TrustedBorrower {
        /// @dev address of the trusted borrower
        address borrower;
        /// @dev ceiling limit for the trusted borrower
        uint128 ceilingLimit;
        /// @dev remaining limit for the trusted borrower, decreased when new loan is approved
        uint128 remainingLimit;
    }

    /// @dev loan information
    struct LoanInfo {
        /// @dev maximum limit for the loan
        uint128 ceilingLimit;
        /// @dev remaining limit for the loan, decreased when new debt is borrowed
        uint128 remainingLimit;
        /// @dev interest rate index for the loan
        uint64 interestRateIndex;
        /// @dev address of the borrower
        uint64 borrowerIndex;
        /// @dev status of the loan
        LoanStatus status;
    }

    /// @dev debt information
    struct DebtInfo {
        /// @dev loan index for the debt
        uint64 loanIndex;
        /// @dev start time of the debt
        uint64 startTime;
        /// @dev maturity time of the debt
        uint64 maturityTime;
        /// @dev last update time of the debt
        uint64 lastUpdateTime;
        /// @dev principal amount of the debt
        uint128 principal;
        /// @dev net remaining debt amount of the debt
        uint128 netRemainingDebt;
        /// @dev interest bearing amount of the debt
        uint128 interestBearingAmount;
        /// @dev net remaining interest amount of the debt
        uint128 netRemainingInterest;
        /// @dev status of the debt
        DebtStatus status;
    }

    /// @dev tranche information
    struct TrancheInfo {
        /// @dev vault index for the tranche
        uint64 vaultIndex;
        /// @dev debt index for the tranche
        uint64 debtIndex;
        /// @dev loan index for the tranche
        uint64 loanIndex;
        /// @dev borrower index for the tranche
        uint64 borrowerIndex;
        /// @dev principal amount for the tranche
        uint128 principal;
    }

    /// @dev fixed point 18 precision
    /// @notice constant, not stored in storage
    uint256 public constant FIXED18 = 1_000_000_000_000_000_000;

    /// @dev precision in million (1_000_000 = 100%)
    /// @notice constant, not stored in storage
    uint256 public constant PRECISION = 1_000_000;

    /// @dev maximum second interest rate in FIXED18 : 36% / (365 * 24 * 60 * 60)
    /// @notice constant, not stored in storage
    uint256 public constant MAX_SECOND_INTEREST_RATE = 11415525114;

    /// @dev maximum loan amount without decimals for each debt
    /// @notice constant, not stored in storage
    uint256 public constant MAX_LOAN_AMOUNT = 1_000_000;

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
    LoanInfo[] public _allLoans;

    /// @dev store all debts
    /// @notice each debt is identified by its index in this array
    DebtInfo[] public _allDebts;

    /// @dev store all tranches
    /// @notice each tranche is identified by its index in this array
    TrancheInfo[] public _allTranches;

    /// @dev store all trusted vaults
    /// @notice each trusted vault is identified by its index in this array
    TrustedVault[] public _trustedVaults;

    /// @dev store all trusted borrowers
    /// @notice each trusted borrower is identified by its index in this array
    TrustedBorrower[] public _trustedBorrowers;

    /// @dev second interest rates in FIXED18
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
            revert NotTrustedBorrower(borrower_);
        }

        _;
    }

    /// @dev only valid borrower check modifier
    /// @param borrowerIndex_ The index of the borrower to be checked
    /// @notice require borrower is in trusted borrowers list and ceiling limit is not zero
    modifier onlyValidBorrower(uint64 borrowerIndex_) {
        if (borrowerIndex_ >= _trustedBorrowers.length) {
            revert NotValidBorrower(borrowerIndex_);
        }
        if (
            _trustedBorrowers[borrowerIndex_].borrower == address(0)
                || _trustedBorrowers[borrowerIndex_].ceilingLimit == 0
        ) {
            revert NotValidBorrower(borrowerIndex_);
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
            revert NotTrustedVault(vault_);
        }

        _;
    }

    /// @dev only defaulted debt check modifier
    /// @param debtIndex_ The index of the debt
    modifier onlyDefaultedDebt(uint64 debtIndex_) {
        if (debtIndex_ >= _allDebts.length) {
            revert NotValidDebt(debtIndex_);
        }
        if (_allDebts[debtIndex_].status != DebtStatus.DEFAULTED) {
            revert NotDefaultedDebt(debtIndex_);
        }

        _;
    }

    /// @dev only matured debt check modifier
    /// @param debtIndex_ The index of the debt
    modifier onlyMaturedDebt(uint64 debtIndex_) {
        if (debtIndex_ >= _allDebts.length) {
            revert NotValidDebt(debtIndex_);
        }
        if (block.timestamp < _allDebts[debtIndex_].maturityTime) {
            revert NotMaturedDebt(debtIndex_);
        }

        _;
    }

    /// @dev valid debt check modifier
    /// @param debtIndex_ The debt index to be checked
    modifier onlyValidDebt(uint64 debtIndex_) {
        if (debtIndex_ >= _allDebts.length) {
            revert NotValidDebt(debtIndex_);
        }
        if (_allDebts[debtIndex_].status != DebtStatus.ACTIVE) {
            revert NotValidDebt(debtIndex_);
        }

        _;
    }

    /// @dev valid interest rate index check modifier
    /// @param interestRateIndex_ The interest rate index to be checked
    modifier onlyValidInterestRate(uint64 interestRateIndex_) {
        if (interestRateIndex_ >= _secondInterestRates.length) {
            revert NotValidInterestRate(interestRateIndex_);
        }
        if (_secondInterestRates[interestRateIndex_] == 0) {
            revert NotValidInterestRate(interestRateIndex_);
        }

        _;
    }

    /// @dev only loan owner check modifier
    /// @param loanIndex_ The index of the loan
    /// @param borrower_ The address of the borrower
    modifier onlyLoanOwner(uint64 loanIndex_, address borrower_) {
        if (loanIndex_ >= _allLoans.length) {
            revert NotValidLoan(loanIndex_);
        }
        address loanOwner = _trustedBorrowers[_allLoans[loanIndex_].borrowerIndex].borrower;
        if (loanOwner != borrower_) {
            revert NotLoanOwner(loanIndex_, loanOwner, borrower_);
        }

        _;
    }

    /// @dev valid loan check modifier
    /// @param loanIndex_ The index of the loan
    modifier onlyValidLoan(uint64 loanIndex_) {
        if (loanIndex_ >= _allLoans.length) {
            revert NotValidLoan(loanIndex_);
        }
        if (_allLoans[loanIndex_].status != LoanStatus.APPROVED) {
            revert NotValidLoan(loanIndex_);
        }

        _;
    }

    /// @dev valid tranche check modifier
    /// @param trancheIndex_ The index of the tranche
    modifier onlyValidTranche(uint64 trancheIndex_) {
        if (trancheIndex_ >= _allTranches.length) {
            revert NotValidTranche(trancheIndex_);
        }

        _;
    }

    /// @dev valid vault check modifier
    /// @param vaultIndex_ The index of the vault
    modifier onlyValidVault(uint64 vaultIndex_) {
        if (vaultIndex_ >= _trustedVaults.length) {
            revert NotValidVault(vaultIndex_);
        }
        if (_trustedVaults[vaultIndex_].vault == address(0) || _trustedVaults[vaultIndex_].maximumPercentage == 0) {
            revert NotValidVault(vaultIndex_);
        }

        _;
    }

    /// @dev only pending loan check modifier
    /// @param loanIndex_ The index of the loan
    modifier onlyPendingLoan(uint64 loanIndex_) {
        if (loanIndex_ >= _allLoans.length) {
            revert NotValidLoan(loanIndex_);
        }
        if (_allLoans[loanIndex_].status != LoanStatus.PENDING) {
            revert NotPendingLoan(loanIndex_);
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
        address[] memory addrs_,
        /**
         * annual interest rates sorted in ascending order
         */
        uint64[] memory secondInterestRates_,
        /**
         * vaults that are allowed to lend to borrowers
         */
        TrustedVault[] memory trustedVaults_
    ) external initializer {
        if (addrs_.length != 4) {
            revert Errors.InvalidValue("addresses length mismatch");
        }
        if (addrs_[0] == address(0)) {
            revert Errors.ZeroAddress("owner");
        }
        if (addrs_[1] == address(0)) {
            revert Errors.ZeroAddress("whitelist");
        }
        if (addrs_[2] == address(0)) {
            revert Errors.ZeroAddress("blacklist");
        }
        if (addrs_[3] == address(0)) {
            revert Errors.ZeroAddress("loanToken");
        }
        if (secondInterestRates_.length == 0) {
            revert Errors.InvalidValue("second interest rates length is zero");
        }
        for (uint256 i = 0; i < secondInterestRates_.length; i++) {
            if (secondInterestRates_[i] == 0 || secondInterestRates_[i] > MAX_SECOND_INTEREST_RATE) {
                revert Errors.InvalidValue("second interest rates value invalid");
            }
            if (i > 0 && secondInterestRates_[i] <= secondInterestRates_[i - 1]) {
                revert Errors.InvalidValue("second interest rates not sorted or duplicated");
            }
            _secondInterestRates.push(secondInterestRates_[i]);
        }
        if (trustedVaults_.length == 0) {
            revert Errors.InvalidValue("trusted vaults length is zero");
        }
        for (uint256 i = 0; i < trustedVaults_.length; i++) {
            if (trustedVaults_[i].vault == address(0)) {
                revert Errors.ZeroAddress("trusted vault address");
            }
            if (IERC4626(trustedVaults_[i].vault).asset() != addrs_[3]) {
                revert Errors.InvalidValue("trusted vault asset and loan token mismatch");
            }
            if (trustedVaults_[i].minimumPercentage > trustedVaults_[i].maximumPercentage) {
                revert Errors.InvalidValue("trusted vault percentage");
            }
            if (trustedVaults_[i].maximumPercentage > PRECISION) {
                revert Errors.InvalidValue("trusted vault maximum percentage exceeds 100%");
            }
            _trustedVaults.push(trustedVaults_[i]);
            _vaultToIndex[trustedVaults_[i].vault] = uint64(_trustedVaults.length - 1);
        }

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
        for (uint256 i = 0; i < _trustedBorrowers.length; i++) {
            if (_trustedBorrowers[i].borrower == msg.sender) {
                revert BorrowerAlreadyExists(msg.sender, uint64(i));
            }
        }

        _trustedBorrowers.push(TrustedBorrower({borrower: msg.sender, ceilingLimit: 0, remainingLimit: 0}));
        borrowerIndex_ = uint64(_trustedBorrowers.length - 1);
        _borrowerToIndex[msg.sender] = borrowerIndex_;

        emit TrustedBorrowerAdded(msg.sender, uint64(_trustedBorrowers.length - 1));
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
        if (newCeilingLimit_ == 0) {
            revert AgreeJoinRequestShouldHaveNonZeroCeilingLimit(borrower_);
        }

        if (_trustedBorrowers[_borrowerToIndex[borrower_]].ceilingLimit != 0) {
            revert UpdateCeilingLimitDirectly(borrower_);
        }

        _updateBorrowerLimit(borrower_, newCeilingLimit_);

        emit AgreeJoinRequest(borrower_, newCeilingLimit_);
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
        uint64 borrowerIndex = _borrowerToIndex[msg.sender];
        uint128 borrowerRemainingLimit = _trustedBorrowers[borrowerIndex].remainingLimit;

        if (amount_ > borrowerRemainingLimit) {
            revert LoanCeilingLimitExceedsBorrowerRemainingLimit(amount_, borrowerRemainingLimit);
        }

        _trustedBorrowers[borrowerIndex].remainingLimit = borrowerRemainingLimit - amount_;

        _allLoans.push(
            LoanInfo({
                ceilingLimit: amount_,
                remainingLimit: amount_,
                interestRateIndex: 0,
                borrowerIndex: borrowerIndex,
                status: LoanStatus.PENDING
            })
        );

        loanIndex_ = uint64(_allLoans.length - 1);

        _loansInfoGroupedByBorrower[borrowerIndex].push(loanIndex_);

        emit ReceiveLoanRequest(msg.sender, loanIndex_, amount_);
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
        LoanInfo memory loan = _allLoans[loanIndex_];

        uint64 borrowerIndex = loan.borrowerIndex;
        uint128 requestCeilingLimit = loan.ceilingLimit;

        if (ceilingLimit_ < requestCeilingLimit) {
            uint128 diffCeilingLimit = requestCeilingLimit - ceilingLimit_;

            _trustedBorrowers[borrowerIndex].remainingLimit += diffCeilingLimit;
            loan.ceilingLimit = ceilingLimit_;
            loan.remainingLimit -= diffCeilingLimit;
        }

        loan.interestRateIndex = interestRateIndex_;
        loan.status = LoanStatus.APPROVED;

        _allLoans[loanIndex_] = loan;

        emit ApproveLoanRequest(
            _trustedBorrowers[borrowerIndex].borrower, loanIndex_, ceilingLimit_, interestRateIndex_
        );
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
            revert MaturityTimeShouldAfterBlockTimestamp(maturityTime_, uint64(block.timestamp));
        }

        LoanInfo memory loan = _allLoans[loanIndex_];

        if (amount_ > loan.remainingLimit) {
            revert BorrowAmountOverLoanRemainingLimit(amount_, loan.remainingLimit, loanIndex_);
        }

        (uint256[] memory trancheAmounts, uint256 availableAmount) = _prepareFunds(uint256(amount_));

        isAllSatisfied_ = availableAmount == uint256(amount_);

        for (uint256 i = 0; i < trancheAmounts.length; ++i) {
            if (trancheAmounts[i] == 0) {
                continue;
            }

            _allTranches.push(
                TrancheInfo({
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
            DebtInfo({
                loanIndex: loanIndex_,
                startTime: uint64(block.timestamp),
                maturityTime: maturityTime_,
                lastUpdateTime: uint64(block.timestamp),
                principal: uint128(availableAmount),
                netRemainingDebt: uint128(availableAmount),
                interestBearingAmount: uint128(availableAmount),
                netRemainingInterest: 0,
                status: DebtStatus.ACTIVE
            })
        );

        debtIndex_ = uint64(_allDebts.length - 1);

        _debtsInfoGroupedByLoan[loanIndex_].push(debtIndex_);
        _debtsInfoGroupedByBorrower[loan.borrowerIndex].push(debtIndex_);

        IERC20(_loanToken).safeTransfer(msg.sender, availableAmount);

        emit Borrowed(msg.sender, loanIndex_, uint128(availableAmount), isAllSatisfied_, debtIndex_);
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
        remainingDebt_ = _updateLoanInterestRate(_allDebts[debtIndex_].loanIndex, defaultedInterestRateIndex_, false);
        _allDebts[debtIndex_].status = DebtStatus.DEFAULTED;

        emit Defaulted(borrower_, debtIndex_, remainingDebt_, defaultedInterestRateIndex_);
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
        emit Recovery(borrower_, debtIndex_, uint128(amount_), remainingDebt_);
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
        DebtInfo memory debtInfo = _allDebts[debtIndex_];
        LoanInfo memory loanInfo = _allLoans[debtInfo.loanIndex];

        loanInfo.remainingLimit += (debtInfo.netRemainingDebt - debtInfo.netRemainingInterest);

        lossDebt_ = debtInfo.netRemainingDebt;

        if (debtInfo.lastUpdateTime < block.timestamp) {
            lossDebt_ += uint128(
                uint256(debtInfo.interestBearingAmount * (block.timestamp - debtInfo.lastUpdateTime)).mulDiv(
                    _secondInterestRates[loanInfo.interestRateIndex], FIXED18, Math.Rounding.Ceil
                )
            );
        }

        debtInfo.status = DebtStatus.CLOSED;
        debtInfo.netRemainingDebt = 0;
        debtInfo.netRemainingInterest = 0;
        debtInfo.interestBearingAmount = 0;
        debtInfo.lastUpdateTime = uint64(block.timestamp);

        _allDebts[debtIndex_] = debtInfo;
        _allLoans[debtInfo.loanIndex] = loanInfo;

        emit Closed(borrower_, debtIndex_, lossDebt_);
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
        _updateBorrowerLimit(borrower_, newCeilingLimit_);
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
        uint128 remainingLimit = _allLoans[loanIndex_].remainingLimit;
        uint128 ceilingLimit = _allLoans[loanIndex_].ceilingLimit;

        if (ceilingLimit < remainingLimit) {
            revert CeilingLimitBelowRemainingLimit(ceilingLimit, remainingLimit);
        }

        uint128 usedLimit = ceilingLimit - remainingLimit;

        if (newCeilingLimit < usedLimit) {
            revert CeilingLimitBelowUsedLimit(newCeilingLimit, usedLimit);
        }

        if (newCeilingLimit > ceilingLimit) {
            uint128 increasedLimit = newCeilingLimit - ceilingLimit;
            uint128 borrowerRemainingLimit = _trustedBorrowers[_allLoans[loanIndex_].borrowerIndex].remainingLimit;
            if (borrowerRemainingLimit < increasedLimit) {
                revert LoanCeilingLimitExceedsBorrowerRemainingLimit(newCeilingLimit, borrowerRemainingLimit);
            }
            _trustedBorrowers[_allLoans[loanIndex_].borrowerIndex].remainingLimit =
                borrowerRemainingLimit - increasedLimit;
        }

        _allLoans[loanIndex_].ceilingLimit = newCeilingLimit;
        _allLoans[loanIndex_].remainingLimit = newCeilingLimit - usedLimit;

        emit LoanCeilingLimitUpdated(newCeilingLimit, ceilingLimit);
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
        _updateLoanInterestRate(loanIndex_, newInterestRateIndex_, false);
    }

    /// @dev update trusted vault information
    /// @param trustedVault_ the new trusted vault information
    /// @param vaultIndex_ the index of the trusted vault to be updated, add to the end if vaultIndex_ over current length
    /// @return isUpdated_ whether the trusted vault is updated or added
    /// @notice if attempting to remove a trusted vault, use update with maximumPercentage set to 0
    function updateTrustedVaults(TrustedVault memory trustedVault_, uint256 vaultIndex_)
        public
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
        returns (bool isUpdated_)
    {
        if (trustedVault_.vault == address(0)) {
            revert Errors.ZeroAddress("trusted vault address");
        }
        if (IERC4626(trustedVault_.vault).asset() != _loanToken) {
            revert Errors.InvalidValue("trusted vault asset and loan token mismatch");
        }
        if (trustedVault_.minimumPercentage > trustedVault_.maximumPercentage) {
            revert Errors.InvalidValue("trusted vault percentage");
        }
        if (trustedVault_.maximumPercentage > PRECISION) {
            revert Errors.InvalidValue("trusted vault maximum percentage exceeds 100%");
        }
        if (vaultIndex_ >= _trustedVaults.length) {
            _trustedVaults.push(trustedVault_);
            emit TrustedVaultAdded(
                trustedVault_.vault,
                trustedVault_.minimumPercentage,
                trustedVault_.maximumPercentage,
                _trustedVaults.length - 1
            );
            isUpdated_ = false;
        } else {
            TrustedVault memory oldVault = _trustedVaults[vaultIndex_];
            _trustedVaults[vaultIndex_] = trustedVault_;

            emit TrustedVaultUpdated(
                oldVault.vault,
                oldVault.minimumPercentage,
                oldVault.maximumPercentage,
                trustedVault_.vault,
                trustedVault_.minimumPercentage,
                trustedVault_.maximumPercentage,
                vaultIndex_
            );

            isUpdated_ = true;
        }
    }

    /// @dev accumulate interest for specific debt
    function pile(uint64 debtIndex_) public {
        _updateDebt(debtIndex_, false);
    }

    /// @dev accumulate interest for all debt
    function pile() public {
        for (uint64 i = 0; i < _allDebts.length; i++) {
            _updateDebt(i, false);
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
            LoanInfo memory borrowerLoan = _allLoans[borrowerLoanIndexes[i]];
            totalDebt_ += _updateLoanInterestRate(borrowerLoanIndexes[i], borrowerLoan.interestRateIndex, true);
        }
    }

    /// @dev get total debt of a vault
    /// @param vault_ the address of the vault
    /// @return totalDebt_ the total debt amount of the vault
    function totalDebtOfVault(address vault_) public onlyTrustedVault(vault_) returns (uint256 totalDebt_) {
        uint64[] memory vaultTrancheIndexes = _tranchesInfoGroupedByVault[_vaultToIndex[vault_]];
        for (uint256 i = 0; i < vaultTrancheIndexes.length; i++) {
            TrancheInfo memory trancheInfo = _allTranches[vaultTrancheIndexes[i]];
            DebtInfo memory debtInfo = _allDebts[trancheInfo.debtIndex];
            totalDebt_ += uint256(_updateDebt(trancheInfo.debtIndex, true)).mulDiv(
                trancheInfo.principal, debtInfo.principal, Math.Rounding.Ceil
            );
        }
    }

    function getSecondInterestRateAtIndex(uint64 interestRateIndex_) public view returns (uint256) {
        return _secondInterestRates[interestRateIndex_];
    }

    function getTrancheInfoAtIndex(uint64 trancheIndex_) public view returns (TrancheInfo memory) {
        return _allTranches[trancheIndex_];
    }

    function getDebtInfoAtIndex(uint64 debtIndex_) public view returns (DebtInfo memory) {
        return _allDebts[debtIndex_];
    }

    function getLoanInfoAtIndex(uint64 loanIndex_) public view returns (LoanInfo memory) {
        return _allLoans[loanIndex_];
    }

    function getBorrowerInfoAtIndex(uint64 borrowerIndex_) public view returns (TrustedBorrower memory) {
        return _trustedBorrowers[borrowerIndex_];
    }

    function getBorrowerAtIndex(uint64 borrowerIndex_) public view returns (address) {
        return _trustedBorrowers[borrowerIndex_].borrower;
    }

    function getVaultInfoAtIndex(uint64 vaultIndex_) public view returns (TrustedVault memory) {
        return _trustedVaults[vaultIndex_];
    }

    function getVaultAtIndex(uint64 vaultIndex_) public view returns (address) {
        return _trustedVaults[vaultIndex_].vault;
    }

    function getTranchesOfDebt(uint64 debtIndex_) public view returns (uint64[] memory) {
        return _tranchesInfoGroupedByDebt[debtIndex_];
    }

    function getTranchesOfLoan(uint64 loanIndex_) public view returns (uint64[] memory) {
        return _tranchesInfoGroupedByLoan[loanIndex_];
    }

    function getTranchesOfBorrower(uint64 borrowerIndex_) public view returns (uint64[] memory) {
        return _tranchesInfoGroupedByBorrower[borrowerIndex_];
    }

    function getTranchesOfVault(uint64 vaultIndex_) public view returns (uint64[] memory) {
        return _tranchesInfoGroupedByVault[vaultIndex_];
    }

    function getDebtsOfLoan(uint64 loanIndex_) public view returns (uint64[] memory) {
        return _debtsInfoGroupedByLoan[loanIndex_];
    }

    function getDebtsOfBorrower(uint64 borrowerIndex_) public view returns (uint64[] memory) {
        return _debtsInfoGroupedByBorrower[borrowerIndex_];
    }

    function getLoansOfBorrower(uint64 borrowerIndex_) public view returns (uint64[] memory) {
        return _loansInfoGroupedByBorrower[borrowerIndex_];
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

    function getTotalInterestRates() public view returns (uint256) {
        return _secondInterestRates.length;
    }

    function _repay(address borrower_, uint64 debtIndex_, uint128 amount_)
        internal
        returns (bool isAllRepaid_, uint128 remainingDebt_)
    {
        /// @dev cache storage to memory
        DebtInfo memory debt = _allDebts[debtIndex_];
        LoanInfo memory loan = _allLoans[debt.loanIndex];

        /// @dev calculate total repaid principal before this repay
        /// @dev used to adjust loan remaining limit after this repay
        uint128 totalRepaidPrincipalBeforeRepay = debt.principal + debt.netRemainingInterest - debt.netRemainingDebt;

        /// @dev calculate interest increment since last update
        uint128 interestIncrement = uint128(
            uint256(debt.interestBearingAmount * (block.timestamp - debt.lastUpdateTime)).mulDiv(
                _secondInterestRates[loan.interestRateIndex], FIXED18, Math.Rounding.Ceil
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
            debt.status = DebtStatus.REPAID;
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

        _distributeFunds(debtIndex_, debt.principal, uint256(amount_));

        emit Repaid(borrower_, debtIndex_, amount_, isAllRepaid_);
    }

    function _updateLoanInterestRate(uint64 loanIndex_, uint64 newInterestRateIndex_, bool dryrun_)
        internal
        returns (uint128 remainingDebt_)
    {
        LoanInfo memory loanInfo = _allLoans[loanIndex_];

        uint64[] memory debtsIndex = _debtsInfoGroupedByLoan[loanIndex_];
        for (uint256 i = 0; i < debtsIndex.length; i++) {
            remainingDebt_ += _updateDebt(debtsIndex[i], dryrun_);
        }

        if (!dryrun_) {
            _allLoans[loanIndex_].interestRateIndex = newInterestRateIndex_;

            emit LoanInterestRateUpdated(loanIndex_, loanInfo.interestRateIndex, newInterestRateIndex_);
        }
    }

    function _updateDebt(uint64 debtIndex_, bool dryrun_) internal returns (uint128 remainingDebt_) {
        DebtInfo memory debtInfo = _allDebts[debtIndex_];
        LoanInfo memory loanInfo = _allLoans[debtInfo.loanIndex];
        if (
            (debtInfo.status == DebtStatus.ACTIVE || debtInfo.status == DebtStatus.DEFAULTED)
                && debtInfo.lastUpdateTime < block.timestamp
        ) {
            uint128 interestIncrement = uint128(
                uint256(debtInfo.interestBearingAmount * (block.timestamp - debtInfo.lastUpdateTime)).mulDiv(
                    _secondInterestRates[loanInfo.interestRateIndex], FIXED18, Math.Rounding.Ceil
                )
            );

            debtInfo.netRemainingDebt += interestIncrement;
            debtInfo.netRemainingInterest += interestIncrement;
            debtInfo.lastUpdateTime = uint64(block.timestamp);

            if (!dryrun_) {
                _allDebts[debtIndex_] = debtInfo;
            }
        }
        remainingDebt_ = debtInfo.netRemainingDebt;
    }

    function _updateBorrowerLimit(address borrower_, uint128 newCeilingLimit_) internal {
        TrustedBorrower memory trustedBorrower = _trustedBorrowers[_borrowerToIndex[borrower_]];
        uint128 remainingLimit = trustedBorrower.remainingLimit;
        uint128 ceilingLimit = trustedBorrower.ceilingLimit;

        if (ceilingLimit < remainingLimit) {
            revert CeilingLimitBelowRemainingLimit(ceilingLimit, remainingLimit);
        }

        uint128 usedLimit = ceilingLimit - remainingLimit;

        if (newCeilingLimit_ < usedLimit) {
            revert CeilingLimitBelowUsedLimit(newCeilingLimit_, usedLimit);
        }

        _trustedBorrowers[_borrowerToIndex[borrower_]].ceilingLimit = newCeilingLimit_;
        _trustedBorrowers[_borrowerToIndex[borrower_]].remainingLimit = newCeilingLimit_ - usedLimit;

        emit BorrowerCeilingLimitUpdated(ceilingLimit, newCeilingLimit_);
    }

    function _distributeFunds(uint64 debtIndex_, uint128 principal_, uint256 amount_) internal {
        uint64[] memory tranchesIndex = _tranchesInfoGroupedByDebt[debtIndex_];
        uint256 totalRepaidAmount = 0;
        uint256 trancheNumber = tranchesIndex.length;
        for (uint256 i = 0; i < trancheNumber; ++i) {
            TrancheInfo memory tranche = _allTranches[tranchesIndex[i]];

            if (i == trancheNumber - 1) {
                /// @dev last tranche takes the remaining amount to avoid rounding issues
                uint256 lastTrancheRepayAmount = amount_ - totalRepaidAmount;

                IERC20(_loanToken).safeTransfer(_trustedVaults[tranche.vaultIndex].vault, lastTrancheRepayAmount);
            } else {
                /// @dev calculate repay amount for each tranche based on their principal
                uint256 trancheRepayAmount = amount_.mulDiv(tranche.principal, principal_, Math.Rounding.Floor);
                totalRepaidAmount += trancheRepayAmount;

                IERC20(_loanToken).safeTransfer(_trustedVaults[tranche.vaultIndex].vault, trancheRepayAmount);
            }
        }
    }

    function _prepareFunds(uint256 amount_)
        internal
        returns (uint256[] memory trancheAmounts_, uint256 availableAmount_)
    {
        uint256 vaultNumber = _trustedVaults.length;

        /// @dev store tranche amounts for this debt from each vault
        /// @dev default lend value is zero
        trancheAmounts_ = new uint256[](vaultNumber);

        for (uint256 i = 0; i < vaultNumber; ++i) {
            uint256 minimumLendAmount =
                amount_.mulDiv(uint256(_trustedVaults[i].minimumPercentage), uint256(PRECISION), Math.Rounding.Floor);
            uint256 maximumLendAmount =
                amount_.mulDiv(uint256(_trustedVaults[i].maximumPercentage), uint256(PRECISION), Math.Rounding.Ceil);
            uint256 vaultTotalAssets = IERC4626(_trustedVaults[i].vault).totalAssets();
            uint256 vaultLendAmount;

            /// @dev vault cannot provide minimum lend amount for this debt
            if (vaultTotalAssets < minimumLendAmount) {
                vaultLendAmount = 0;
            }
            /// @dev vault can provide between minimum and maximum lend amount for this debt
            /// @dev vault provides all its assets
            else if (vaultTotalAssets < maximumLendAmount) {
                vaultLendAmount = vaultTotalAssets;
            }
            /// @dev vault can provide maximum lend amount for this debt
            else {
                vaultLendAmount = maximumLendAmount;
            }

            /// @dev not enough funds collected yet, continue to collect from next vault
            if (availableAmount_ + vaultLendAmount <= amount_) {
                trancheAmounts_[i] = vaultLendAmount;
                availableAmount_ += vaultLendAmount;
                IERC20(_loanToken).safeTransferFrom(_trustedVaults[i].vault, address(this), vaultLendAmount);
                continue;
            }
            /// @dev enough funds collected, finalize tranche amounts and break
            else {
                vaultLendAmount = amount_ - availableAmount_;
                trancheAmounts_[i] = vaultLendAmount;
                availableAmount_ += vaultLendAmount;
                IERC20(_loanToken).safeTransferFrom(_trustedVaults[i].vault, address(this), vaultLendAmount);
                break;
            }
        }
    }

    uint256[50] private __gap;
}
