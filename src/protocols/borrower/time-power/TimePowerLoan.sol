// SPDX-Licensed-Identifier: MIT

pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IWhitelist} from "src/whitelist/IWhitelist.sol";
import {IBlacklist} from "src/blacklist/IBlacklist.sol";
import {Roles} from "src/common/Roles.sol";
import {Errors} from "src/common/Errors.sol";

contract TimePowerLoan is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using Math for uint256;

    /// @dev error thrown when a debt is not defaulted
    /// @param borrower_ address of the borrower
    /// @param debtIndex_ index of the debt
    error NotDefaultedDebt(address borrower_, uint64 debtIndex_);

    /// @dev error thrown when ceiling limit below remaining limit
    /// @param ceilingLimit_ ceiling limit
    /// @param remainingLimit_ remaining limit
    error CeilingLimitBelowRemainingLimit(uint128 ceilingLimit_, uint128 remainingLimit_);

    /// @dev error thrown when ceiling limit below used limit which is caculated by ceiling limit substract remaining limit
    /// @param ceilingLimit_ ceiling limit
    /// @param usedLimit_ difference of ceiling limit and remaining limit
    error CeilingLimitBelowUsedLimit(uint128 ceilingLimit_, uint128 usedLimit_);

    /// @dev event emitted when ceiling limit is updated
    /// @param oldCeilingLimit_ old ceiling limit
    /// @param newCeilingLimit_ new ceiling limit
    event CeilingLimitUpdated(uint128 oldCeilingLimit_, uint128 newCeilingLimit_);

    /// @dev event emitted when interest rate index is updated
    /// @param who_ address of the borrower
    /// @param oldInterestRateIndex_ old interest rate index
    /// @param newInterestRateIndex_ new interest rate index
    event InterestRateUpdated(address who_, uint64 oldInterestRateIndex_, uint64 newInterestRateIndex_);

    /// @dev status of a debt
    enum DebtStatus {
        /// @dev default value, not existed debt
        NOT_EXISTED,
        /// @dev debt is not approved by operator yet
        PENDING,
        /// @dev debt is approved and time is before or at maturity date
        ACTIVE,
        /// @dev debt is zero after maturity date
        REPAID,
        /// @dev debt is not zero after maturity date
        DEFAULTED,
        /// @dev debt is closed by operator after default
        CLOSED
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

    /// @dev loan information
    struct LoanInfo {
        /// @dev maximum loan for a borrower
        uint128 ceilingLimit;
        /// @dev remaining loan limit for a borrower
        uint128 remainingLimit;
        /// @dev total normalized principal amount for a borrower
        uint128 normalizedPrincipal;
        /// @dev interest rate index for a borrower
        uint64 interestRateIndex;
        /// @dev loan number for a borrower
        uint64 loanNo;
    }

    /// @dev debt information
    struct DebtInfo {
        /// @dev loan number for the debt
        uint64 loanNo;
        /// @dev debt index for the debt
        uint64 debtIndex;
        /// @dev start time of the debt
        uint64 startTime;
        /// @dev maturity time of the debt
        uint64 maturityTime;
        /// @dev normalized principal amount of the debt
        uint128 normalizedPrincipal;
        /// @dev status of the debt
        DebtStatus status;
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

    /// @dev mapping from borrower address to loan information
    /// @notice loan information stores summarized data of a borrower
    mapping(address => LoanInfo) public _loansInfo;

    /// @dev mapping from loan number to borrower address
    /// @notice convenient way to lookup borrower by loan number
    mapping(uint64 => address) public _loanBorrowers;

    /// @dev mapping from loan number to array of debt information
    /// @notice debt information stores detailed data of each debt of a loan
    mapping(uint64 => DebtInfo[]) public _debtsInfo;

    /// @dev array of trusted vaults
    /// @notice trusted vaults are the vaults that are allowed to lend to borrowers
    TrustedVault[] public _trustedVaults;

    /// @dev whitelist check modifier
    /// @param who_ The address to be checked against the whitelist
    modifier onlyWhitelisted(address who_) {
        if (_whitelist == address(0)) {
            revert Errors.ZeroAddress("whitelist");
        }
        if (who_ == address(0)) {
            revert Errors.ZeroAddress("user");
        }
        if (!IWhitelist(_whitelist).isWhitelisted(who_)) {
            revert IWhitelist.NotWhitelisted(who_);
        }

        _;
    }

    /// @dev not blacklisted check modifier
    /// @param who_ The address to be checked against the blacklist
    modifier onlyNotBlacklisted(address who_) {
        if (_blacklist == address(0)) {
            revert Errors.ZeroAddress("blacklist");
        }
        if (who_ == address(0)) {
            revert Errors.ZeroAddress("user");
        }
        if (IBlacklist(_blacklist).isBlacklisted(who_)) {
            revert IBlacklist.Blacklisted(who_);
        }

        _;
    }

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

    /// @dev only defaulted debt check modifier
    /// @param borrower_ The address of the borrower
    /// @param debtIndex_ The index of the debt
    modifier onlyDefaultedDebt(address borrower_, uint64 debtIndex_) {
        if (borrower_ == address(0)) {
            revert Errors.ZeroAddress("borrower");
        }
        if (_debtsInfo[_loansInfo[borrower_].loanNo][debtIndex_].status != DebtStatus.DEFAULTED) {
            revert NotDefaultedDebt(borrower_, debtIndex_);
        }

        _;
    }

    /// @dev valid interest rate index check modifier
    /// @param interestRateIndex_ The interest rate index to be checked
    modifier onlyValidInterestRate(uint64 interestRateIndex_) {
        if (interestRateIndex_ >= _secondInterestRates.length) {
            revert Errors.InvalidValue("interest rate index over bound");
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

    /// @dev request for a loan
    /// @param amount_ the amount of loan
    /// @param startTime_ the start time of the loan
    /// @param maturityTime_ the maturity time of the loan
    /// @return loanNo_ the loan number of the applied loan (bytes.concat(borrower address, loan index))
    function request(uint128 amount_, uint64 startTime_, uint64 maturityTime_)
        public
        whenNotPaused
        nonReentrant
        onlyNotBlacklisted(msg.sender)
        onlyWhitelisted(msg.sender)
        onlyInitialized
        returns (uint64 loanNo_)
    {
        return 1;
    }

    /// @dev approve a loan
    /// @param loanNo_ the loan number to be approved
    /// @param ceilingLimit_ the ceiling limit for the loan
    /// @param interestRateIndex_ the interest rate index to be applied
    function approve(uint64 loanNo_, uint128 ceilingLimit_, uint64 interestRateIndex_)
        public
        whenNotPaused
        nonReentrant
        onlyInitialized
        onlyRole(Roles.OPERATOR_ROLE)
    {}

    /// @dev borrow a loan
    /// @param loanNo_ the loan number to be borrowed
    /// @param amount_ the amount to be borrowed
    /// @return isAllSatisfied_ whether all borrowed amount is satisfied
    /// @return debtIndex_ the index of the debt
    function borrow(uint64 loanNo_, uint128 amount_)
        public
        whenNotPaused
        nonReentrant
        onlyNotBlacklisted(msg.sender)
        onlyWhitelisted(msg.sender)
        onlyInitialized
        returns (bool isAllSatisfied_, uint64 debtIndex_)
    {}

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
        returns (bool isAllRepaid_)
    {}

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
        returns (uint128 totalDebt_)
    {}

    /// @dev recover a defaulted debt
    /// @param borrower_ the address of the borrower
    /// @param debtIndex_ the index of the debt
    /// @param amount_ the amount to be recovered
    /// @return totalDebt_ the total debt amount after recovery
    function recovery(address borrower_, uint64 debtIndex_, uint128 amount_)
        public
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
        onlyDefaultedDebt(borrower_, debtIndex_)
        returns (uint128 totalDebt_)
    {}

    /// @dev close a defaulted debt
    /// @param borrower_ the address of the borrower
    /// @param debtIndex_ the index of the debt
    /// @return totalDebt_ the total debt amount when closed
    function close(address borrower_, uint64 debtIndex_)
        public
        onlyInitialized
        nonReentrant
        whenNotPaused
        onlyRole(Roles.OPERATOR_ROLE)
        onlyDefaultedDebt(borrower_, debtIndex_)
        returns (uint128 totalDebt_)
    {}

    /// @dev adds an address to the whitelist
    /// @param who_ the address to be added to the whitelist
    function addWhitelist(address who_) public onlyInitialized onlyRole(Roles.OPERATOR_ROLE) {
        IWhitelist(_whitelist).add(who_);
    }

    /// @dev removes an address from the whitelist
    /// @param who_ the address to be removed from the whitelist
    function removeWhitelist(address who_) public onlyInitialized onlyRole(Roles.OPERATOR_ROLE) {
        IWhitelist(_whitelist).remove(who_);
    }

    /// @dev adds an address to the blacklist
    /// @param who_ the address to be added to the blacklist
    function addBlacklist(address who_) public onlyInitialized onlyRole(Roles.OPERATOR_ROLE) {
        IBlacklist(_blacklist).add(who_);
    }

    /// @dev removes an address from the blacklist
    /// @param who_ the address to be removed from the blacklist
    function removeBlacklist(address who_) public onlyInitialized onlyRole(Roles.OPERATOR_ROLE) {
        IBlacklist(_blacklist).remove(who_);
    }

    function updateLimit(address who_, uint128 newCeilingLimit_)
        public
        onlyInitialized
        onlyRole(Roles.OPERATOR_ROLE)
        onlyWhitelisted(who_)
        onlyNotBlacklisted(who_)
    {
        uint128 remainingLimit = _loansInfo[who_].remainingLimit;
        uint128 ceilingLimit = _loansInfo[who_].ceilingLimit;

        if (ceilingLimit < remainingLimit) {
            revert CeilingLimitBelowRemainingLimit(ceilingLimit, remainingLimit);
        }

        uint128 usedLimit = ceilingLimit - remainingLimit;

        if (newCeilingLimit_ < usedLimit) {
            revert CeilingLimitBelowUsedLimit(newCeilingLimit_, usedLimit);
        }

        _loansInfo[who_].ceilingLimit = newCeilingLimit_;

        emit CeilingLimitUpdated(newCeilingLimit_, ceilingLimit);
    }

    /// @dev update interest rate index for a borrower
    /// @param who_ the address of the borrower
    /// @param newInterestRateIndex_ the new interest rate index to be applied
    function updateInterestRates(address who_, uint64 newInterestRateIndex_)
        public
        onlyInitialized
        onlyRole(Roles.OPERATOR_ROLE)
        onlyWhitelisted(who_)
        onlyNotBlacklisted(who_)
        onlyValidInterestRate(newInterestRateIndex_)
    {
        LoanInfo memory loanInfo = _loansInfo[who_];
        if (newInterestRateIndex_ == loanInfo.interestRateIndex) {
            return;
        }
        if (loanInfo.normalizedPrincipal > 0) {
            _accumulateInterest();

            uint256 oldAccumulatedInterestRate = _accumulatedInterestRates[loanInfo.interestRateIndex];
            uint256 newAccumulatedInterestRate = _accumulatedInterestRates[newInterestRateIndex_];

            loanInfo.normalizedPrincipal = 0;
            loanInfo.interestRateIndex = newInterestRateIndex_;

            DebtInfo[] storage debtsInfo = _debtsInfo[loanInfo.loanNo];
            for (uint256 i = 0; i < debtsInfo.length; i++) {
                if (debtsInfo[i].status == DebtStatus.ACTIVE || debtsInfo[i].status == DebtStatus.DEFAULTED) {
                    uint128 newDebtNormalizedPrincipal = uint128(
                        (uint256(debtsInfo[i].normalizedPrincipal) * oldAccumulatedInterestRate)
                            / newAccumulatedInterestRate
                    );
                    debtsInfo[i].normalizedPrincipal = newDebtNormalizedPrincipal;
                    loanInfo.normalizedPrincipal += newDebtNormalizedPrincipal;
                }
            }

            _loansInfo[who_] = loanInfo;

            emit InterestRateUpdated(who_, loanInfo.interestRateIndex, newInterestRateIndex_);
        }
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

    function _accumulateInterest() internal {}

    uint256[50] private __gap;
}
