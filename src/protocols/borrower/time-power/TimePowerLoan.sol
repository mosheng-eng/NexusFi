// SPDX-Licensed-Identifier: MIT

pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IWhitelist} from "src/whitelist/IWhitelist.sol";
import {IBlacklist} from "src/blacklist/IBlacklist.sol";
import {Roles} from "src/common/Roles.sol";
import {Errors} from "src/common/Errors.sol";

contract TimePowerLoan is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using Math for uint256;

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
        /// @dev maximum loan for a borrower without decimals
        uint128 ceilingLimit;
        /// @dev remaining loan limit for a borrower without decimals
        uint128 remainingLimit;
        /// @dev total normalized principal amount for a borrower
        uint128 normalizedPrincipal;
        /// @dev interest rate index for a borrower
        uint128 interestRateIndex;
    }

    /// @dev debt information
    struct DebtInfo {
        /// @dev status of the debt
        DebtStatus status;
        /// @dev normalized principal amount of the debt
        uint128 normalizedPrincipal;
        /// @dev start time of the debt
        uint64 startTime;
        /// @dev maturity time of the debt
        uint64 maturityTime;
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

    /// @dev mapping from borrower address to array of debt information
    /// @notice debt information stores detailed data of each debt of a borrower
    mapping(address => DebtInfo[]) public _debtsInfo;

    /// @dev array of trusted vaults
    /// @notice trusted vaults are the vaults that are allowed to lend to borrowers
    TrustedVault[] public _trustedVaults;

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

    /// @dev calculates power(x,n) and x is in fixed point with given base
    /// @param x the base number in fixed point
    /// @param n the exponent
    /// @param base the fixed point base
    /// @return z the result of x^n in fixed point
    function rpow(uint256 x, uint256 n, uint256 base) public pure returns (uint256 z) {
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

    uint256[50] private __gap;
}
