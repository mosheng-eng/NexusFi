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

contract TimePowerLoan is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
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

    /// @dev error thrown when a repay amount is too little
    /// @param borrower_ address of the borrower
    /// @param debtIndex_ index of the debt
    /// @param minimumRequiredAmount_ minimum required amount to repay
    /// @param paidAmount_ amount paid by the borrower
    error RepayTooLittle(address borrower_, uint64 debtIndex_, uint128 minimumRequiredAmount_, uint128 paidAmount_);

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

    /// @dev event emitted when accumulated interest rates are updated
    /// @param timestamp_ the timestamp when accumulated interest rates are updated
    event AccumulatedInterestUpdated(uint64 timestamp_);

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
        /// @dev total normalized principal amount for the loan
        uint128 normalizedPrincipal;
        /// @dev interest rate index for the loan
        uint64 interestRateIndex;
        /// @dev address of the borrower
        uint64 borrowerIndex;
        /// @dev status of the loan
        LoanStatus status;
    }

    /// @dev debt information
    struct DebtInfo {
        /// @dev start time of the debt
        uint64 startTime;
        /// @dev maturity time of the debt
        uint64 maturityTime;
        /// @dev principal amount of the debt
        uint128 principal;
        /// @dev normalized principal amount of the debt
        uint128 normalizedPrincipal;
        /// @dev loan index for the debt
        uint64 loanIndex;
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
        /// @dev normalized principal amount for the tranche
        uint128 normalizedPrincipal;
    }

    /// @dev fixed point 18 precision
    /// @notice constant, not stored in storage
    uint256 public constant FIXED18 = 1_000_000_000_000_000_000;

    /// @dev precision in million (1_000_000 = 100%)
    /// @notice constant, not stored in storage
    uint256 public constant PRECISION = 1_000_000;

    /// @dev maximum second interest rate in fixed point 18 (1+36%)^(1/(365*24*60*60))
    /// @notice constant, not stored in storage
    uint256 public constant MAX_SECOND_INTEREST_RATE = 10000000097502800000;

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
            revert Errors.ZeroAddress("user");
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
            revert Errors.ZeroAddress("user");
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
            revert Errors.ZeroAddress("user");
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
            _accumulatedInterestRates.push(FIXED18);
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
        }

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
    {
        for (uint256 i = 0; i < _trustedBorrowers.length; i++) {
            if (_trustedBorrowers[i].borrower == msg.sender) {
                revert BorrowerAlreadyExists(msg.sender, uint64(i));
            }
        }

        _trustedBorrowers.push(TrustedBorrower({borrower: msg.sender, ceilingLimit: 0, remainingLimit: 0}));

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
                normalizedPrincipal: 0,
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

        _accumulateInterest();

        LoanInfo memory loan = _allLoans[loanIndex_];

        if (amount_ > loan.remainingLimit) {
            revert BorrowAmountOverLoanRemainingLimit(amount_, loan.remainingLimit, loanIndex_);
        }

        (uint256[] memory trancheAmounts, uint256 availableAmount) = _prepareFunds(uint256(amount_));

        isAllSatisfied_ = availableAmount == uint256(amount_);

        uint256 accumulatedInterestRate = _accumulatedInterestRates[loan.interestRateIndex];
        uint128 normalizedPrincipal = 0;

        for (uint256 i = 0; i < trancheAmounts.length; ++i) {
            if (trancheAmounts[i] == 0) {
                continue;
            }

            uint256 normalizedPrincipalForTranche = (trancheAmounts[i] * FIXED18) / accumulatedInterestRate;

            normalizedPrincipal += uint128(normalizedPrincipalForTranche);

            _allTranches.push(
                TrancheInfo({
                    vaultIndex: uint64(i),
                    debtIndex: uint64(_allDebts.length),
                    loanIndex: loanIndex_,
                    borrowerIndex: loan.borrowerIndex,
                    normalizedPrincipal: uint128(normalizedPrincipalForTranche)
                })
            );

            uint64 trancheIndex = uint64(_allTranches.length - 1);

            _tranchesInfoGroupedByDebt[uint64(_allDebts.length)].push(trancheIndex);
            _tranchesInfoGroupedByLoan[loanIndex_].push(trancheIndex);
            _tranchesInfoGroupedByBorrower[loan.borrowerIndex].push(trancheIndex);
            _tranchesInfoGroupedByVault[uint64(i)].push(trancheIndex);
        }

        loan.remainingLimit -= uint128(availableAmount);

        loan.normalizedPrincipal += normalizedPrincipal;

        _allLoans[loanIndex_] = loan;

        _allDebts.push(
            DebtInfo({
                startTime: uint64(block.timestamp),
                maturityTime: maturityTime_,
                principal: uint128(availableAmount),
                normalizedPrincipal: normalizedPrincipal,
                loanIndex: loanIndex_,
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
    /// @return totalDebt_ the total debt amount when defaulted
    function defaulted(address borrower_, uint64 debtIndex_, uint64 defaultedInterestRateIndex_)
        public
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
        onlyMaturedDebt(debtIndex_)
        onlyValidInterestRate(defaultedInterestRateIndex_)
        onlyLoanOwner(_allDebts[debtIndex_].loanIndex, borrower_)
        returns (uint128 totalDebt_)
    {
        _updateLoanInterestRates(_allDebts[debtIndex_].loanIndex, defaultedInterestRateIndex_);
        _allDebts[debtIndex_].status = DebtStatus.DEFAULTED;
        totalDebt_ = uint128(
            (
                uint256(_allDebts[debtIndex_].normalizedPrincipal)
                    * _accumulatedInterestRates[defaultedInterestRateIndex_]
            ) / FIXED18
        );
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
        _accumulateInterest();

        DebtInfo memory debt = _allDebts[debtIndex_];
        LoanInfo memory loan = _allLoans[debt.loanIndex];

        uint256 accumulatedInterestRate = _accumulatedInterestRates[loan.interestRateIndex];

        lossDebt_ = uint128((uint256(debt.normalizedPrincipal) * accumulatedInterestRate) / FIXED18);

        debt.status = DebtStatus.CLOSED;

        loan.normalizedPrincipal = loan.normalizedPrincipal - debt.normalizedPrincipal;
        loan.remainingLimit += debt.principal;

        debt.normalizedPrincipal = 0;
        debt.principal = 0;

        _allDebts[debtIndex_] = debt;
        _allLoans[debt.loanIndex] = loan;

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
    function updateLoanInterestRates(uint64 loanIndex_, uint64 newInterestRateIndex_)
        public
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
        onlyValidLoan(loanIndex_)
        onlyValidInterestRate(newInterestRateIndex_)
        onlyTrustedBorrower(_trustedBorrowers[_allLoans[loanIndex_].borrowerIndex].borrower)
    {
        _updateLoanInterestRates(loanIndex_, newInterestRateIndex_);
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

    /// @dev accumulate interest for all loans
    function pile() public {
        _accumulateInterest();
    }

    /// @dev calculates power(x,n) and x is in fixed point with given base
    /// @param x the base number in fixed point
    /// @param n the exponent
    /// @param base the fixed point base
    /// @return z the result of x^n in fixed point
    function _rpow(uint256 x, uint256 n, uint256 base) internal pure returns (uint256 z) {
        assembly {
            switch x
            case 0 {
                switch n
                case 0 { z := base }
                default { z := 0 }
            }
            default {
                switch mod(n, 2)
                case 0 { z := base }
                default { z := x }
                let half := div(base, 2) // for rounding.
                for { n := div(n, 2) } n { n := div(n, 2) } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) { revert(0, 0) }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) { revert(0, 0) }
                    x := div(xxRound, base)
                    if mod(n, 2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0, 0) }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) { revert(0, 0) }
                        z := div(zxRound, base)
                    }
                }
            }
        }
    }

    /// @dev internal function to accumulate interest for all loans
    function _accumulateInterest() internal {
        uint64 currentTime = uint64(block.timestamp);
        if (currentTime > _lastAccumulateInterestTime) {
            uint64 timePeriod = currentTime - _lastAccumulateInterestTime;
            for (uint256 i = 0; i < _secondInterestRates.length; i++) {
                _accumulatedInterestRates[i] =
                    (_accumulatedInterestRates[i] * _rpow(_secondInterestRates[i], timePeriod, FIXED18)) / FIXED18;
            }
            _lastAccumulateInterestTime = currentTime;

            emit AccumulatedInterestUpdated(currentTime);
        }
    }

    function _repay(address borrower_, uint64 debtIndex_, uint128 amount_)
        internal
        returns (bool isAllRepaid_, uint128 remainingDebt_)
    {
        _accumulateInterest();

        DebtInfo memory debt = _allDebts[debtIndex_];
        LoanInfo memory loan = _allLoans[debt.loanIndex];

        uint256 accumulatedInterestRate = _accumulatedInterestRates[loan.interestRateIndex];
        uint128 debtNormalizedPrincipal = debt.normalizedPrincipal;
        uint256 totalDebt = (uint256(debtNormalizedPrincipal) * accumulatedInterestRate) / FIXED18;

        if (amount_ >= totalDebt) {
            amount_ = uint128(totalDebt);
            isAllRepaid_ = true;
            debt.status = DebtStatus.REPAID;
        } else {
            isAllRepaid_ = false;
        }

        remainingDebt_ = uint128(totalDebt - uint256(amount_));

        uint128 remainingNormalizedPrincipal = uint128((uint256(remainingDebt_) * FIXED18) / accumulatedInterestRate);

        /// @dev loan normalized principal should decrease if repay amount is over debt interest
        /// @dev loan normalized principal should increase if repay amount is below debt interest
        loan.normalizedPrincipal = loan.normalizedPrincipal - debtNormalizedPrincipal + remainingNormalizedPrincipal;

        /// @dev repay amount is greater than or equal to debt total interest
        /// @dev loan remaining limit is impossible to decrease in this case
        if (amount_ + debt.principal >= totalDebt) {
            loan.remainingLimit += (amount_ + debt.principal - uint128(totalDebt));
        } else {
            uint128 decreasedLimit = uint128(totalDebt) - (amount_ + debt.principal);
            /// @dev repay amount is not enough to cover debt interest
            /// @dev loan limit will decrease in this case
            /// @dev meaning that unrepaid interest become new debt principal and reduce loan limit
            if (loan.remainingLimit > decreasedLimit) {
                loan.remainingLimit -= decreasedLimit;
            }
            /// @dev if loan remaining limit is not enough to cover the decreased limit, revert the transaction
            /// @dev borrower should repay more to cover the decreased limit
            else {
                revert RepayTooLittle(
                    borrower_, debtIndex_, uint128(totalDebt) - debt.principal - loan.remainingLimit, amount_
                );
            }
        }

        /// @dev debt normalized principal should decrease if repay amount is over debt interest
        /// @dev debt normalized principal should increase if repay amount is below debt interest
        debt.normalizedPrincipal = remainingNormalizedPrincipal;
        /// @dev debt principal should decrease if repay amount is over debt interest
        /// @dev debt principal should remain the same if repay amount is below debt interest
        debt.principal = remainingDebt_;

        _allDebts[debtIndex_] = debt;
        _allLoans[debt.loanIndex] = loan;

        IERC20(_loanToken).safeTransferFrom(borrower_, address(this), uint256(amount_));

        _distributeFunds(debtIndex_, debtNormalizedPrincipal, uint256(amount_));

        emit Repaid(borrower_, debtIndex_, amount_, isAllRepaid_);
    }

    function _updateLoanInterestRates(uint64 loanIndex_, uint64 newInterestRateIndex_)
        internal
        returns (uint128 newLoanNormalizedPrincipal_)
    {
        LoanInfo memory loanInfo = _allLoans[loanIndex_];

        if (newInterestRateIndex_ == loanInfo.interestRateIndex) {
            return loanInfo.normalizedPrincipal;
        }

        if (loanInfo.normalizedPrincipal > 0) {
            _accumulateInterest();

            uint256 oldAccumulatedInterestRate = _accumulatedInterestRates[loanInfo.interestRateIndex];
            uint256 newAccumulatedInterestRate = _accumulatedInterestRates[newInterestRateIndex_];

            uint64[] memory debtsIndex = _debtsInfoGroupedByLoan[loanIndex_];
            for (uint256 i = 0; i < debtsIndex.length; i++) {
                newLoanNormalizedPrincipal_ +=
                    _updateDebtInterestRate(debtsIndex[i], oldAccumulatedInterestRate, newAccumulatedInterestRate);
            }

            _allLoans[loanIndex_].normalizedPrincipal = newLoanNormalizedPrincipal_;
        }

        _allLoans[loanIndex_].interestRateIndex = newInterestRateIndex_;

        emit LoanInterestRateUpdated(loanIndex_, loanInfo.interestRateIndex, newInterestRateIndex_);
    }

    function _updateDebtInterestRate(
        uint64 debtIndex_,
        uint256 oldAccumulatedInterestRate_,
        uint256 newAccumulatedInterestRate_
    ) internal returns (uint128 newDebtNormalizedPrincipal_) {
        DebtInfo memory debtInfo = _allDebts[debtIndex_];
        if (debtInfo.status == DebtStatus.ACTIVE || debtInfo.status == DebtStatus.DEFAULTED) {
            uint64[] memory tranchesIndex = _tranchesInfoGroupedByDebt[debtIndex_];
            for (uint256 j = 0; j < tranchesIndex.length; j++) {
                newDebtNormalizedPrincipal_ += _updateTrancheInterestRate(
                    tranchesIndex[j], oldAccumulatedInterestRate_, newAccumulatedInterestRate_
                );
            }
            _allDebts[debtIndex_].normalizedPrincipal = newDebtNormalizedPrincipal_;
        }
    }

    function _updateTrancheInterestRate(
        uint64 trancheIndex_,
        uint256 oldAccumulatedInterestRate_,
        uint256 newAccumulatedInterestRate_
    ) internal returns (uint128 newTrancheNormalizedPrincipal_) {
        newTrancheNormalizedPrincipal_ = uint128(
            (uint256(_allTranches[trancheIndex_].normalizedPrincipal) * oldAccumulatedInterestRate_)
                / newAccumulatedInterestRate_
        );
        _allTranches[trancheIndex_].normalizedPrincipal = newTrancheNormalizedPrincipal_;
    }

    function _updateBorrowerLimit(address borrower_, uint128 newCeilingLimit_) internal {
        uint128 remainingLimit = _trustedBorrowers[_borrowerToIndex[borrower_]].remainingLimit;
        uint128 ceilingLimit = _trustedBorrowers[_borrowerToIndex[borrower_]].ceilingLimit;

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

    function _distributeFunds(uint64 debtIndex_, uint128 debtNormalizedPrincipal_, uint256 amount_) internal {
        uint64[] memory tranchesIndex = _tranchesInfoGroupedByDebt[debtIndex_];
        uint256 payoutAmount = 0;
        uint256 tranchNumber = tranchesIndex.length;
        for (uint256 i = 0; i < tranchNumber; ++i) {
            TrancheInfo memory tranche = _allTranches[tranchesIndex[i]];

            if (i == tranchNumber - 1) {
                /// @dev last tranche takes the remaining amount to avoid rounding issues
                uint256 lastTrancheRepayAmount = amount_ - payoutAmount;
                IERC20(_loanToken).safeTransfer(_trustedVaults[tranche.vaultIndex].vault, lastTrancheRepayAmount);
            } else {
                /// @dev calculate repay amount for each tranche based on their normalized principal
                uint256 trancheRepayAmount = (tranche.normalizedPrincipal * amount_) / debtNormalizedPrincipal_;
                payoutAmount += trancheRepayAmount;

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
            uint256 minimumLendAmount = amount_.mulDiv(uint256(_trustedVaults[i].minimumPercentage), uint256(PRECISION));
            uint256 maximumLendAmount = amount_.mulDiv(uint256(_trustedVaults[i].maximumPercentage), uint256(PRECISION));
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
