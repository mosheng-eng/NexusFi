// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Errors} from "src/common/Errors.sol";
import {Roles} from "src/common/Roles.sol";

import {IWhitelist} from "src/whitelist/IWhitelist.sol";
import {UnderlyingToken} from "src/underlying/UnderlyingToken.sol";

/// @title UnderlyingTokenExchanger
/// @author Mr.Silent
/// @notice Contract to exchange between two ERC20 tokens at predefined exchange rates, with optional whitelist
/// @notice One token is assumed to be the underlying token (token0), the other is a depositing token (token1)
contract UnderlyingTokenExchanger is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice Emitted when an exchange is made
    /// @param who The address who made the exchange
    /// @param deposit True if exchanging token1 to token0, false if exchanging token0 to token1
    /// @param amountIn The amount of input tokens
    /// @param amountOut The amount of output tokens
    /// @dev when deposit is true, amountIn is token1 amount, amountOut is token0 amount
    /// @dev when deposit is false, amountIn is token0 amount, amountOut is token1 amount
    event Exchanged(address indexed who, bool deposit, uint128 amountIn, uint128 amountOut);

    /// @notice Emitted when exchange rates are updated
    /// @param zeroForOne True if updating token0 to token1 rate, false if updating token1 to token0 rate
    /// @param old_exchange_rate The old exchange rate
    /// @param new_exchange_rate The new exchange rate
    /// @dev when zeroForOne is true, updating token0 to token1 rate
    /// @dev when zeroForOne is false, updating token1 to token0 rate
    event ExchangeRatesUpdated(bool zeroForOne, uint64 old_exchange_rate, uint64 new_exchange_rate);

    /// @notice address of token0
    /// @notice token0 should be ERC20-compliant(UnderlyingToken)
    address public _token0;
    /// @notice decimals of token0
    /// @notice read from token0 contract at initialization, cached to save gas
    uint8 public _token0_decimals;
    /// @notice address of token1
    /// @notice token1 should be ERC20-compliant(DepositingToken)
    address public _token1;
    /// @notice decimals of token1
    /// @notice read from token1 contract at initialization, cached to save gas
    uint8 public _token1_decimals;
    /// @notice address of whitelist contract
    /// @notice if whitelist is enabled in the whitelist contract, only whitelisted addresses can call exchange function
    /// @notice if whitelist is disabled in the whitelist contract, anyone can call exchange function
    address public _whitelist;

    /// @notice precision for exchange rate calculation
    uint64 public _precision;
    /// @notice _token0_amount * rate * 10 ** _token1_decimals / _precision / 10 ** _token0_decimals  = _token1_amount
    /// @notice represents each token0 can be exchanged for how many token1s
    uint64 public _token0_token1_rate;
    /// @notice _token1_amount * rate * 10 ** _token0_decimals / _precision / 10 ** _token1_decimals = _token0_amount
    /// @notice represents each token1 can be exchanged for how many token0s
    uint64 public _token1_token0_rate;

    /// @dev whitelist check modifier
    /// @param _who The address to be checked against the whitelist
    modifier onlyWhitelist(address _who) {
        if (_whitelist == address(0)) {
            revert Errors.ZeroAddress("whitelist");
        }
        if (_who == address(0)) {
            revert Errors.ZeroAddress("user");
        }
        if (!IWhitelist(_whitelist).isWhitelisted(_who)) {
            revert IWhitelist.NotWhitelisted(_who);
        }

        _;
    }

    /// @dev initialized check modifier
    modifier onlyInitialized() {
        if (_token0 == address(0x0) || _token0_decimals == 0) {
            revert Errors.Uninitialized("token0");
        }
        if (_token1 == address(0x0) || _token1_decimals == 0) {
            revert Errors.Uninitialized("token1");
        }
        if (_precision == 0) {
            revert Errors.Uninitialized("precision");
        }
        if (_token0_token1_rate == 0) {
            revert Errors.Uninitialized("token0_token1_rate");
        }
        if (_token1_token0_rate == 0) {
            revert Errors.Uninitialized("token1_token0_rate");
        }

        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        /**
         * 0: address token0_,
         * 1: address token1_,
         * 2: address whitelist_,
         * 3: address owner_,
         */
        address[4] calldata addrs_,
        /**
         * [0~63]: uint64 precision_,
         * [64~127]: uint64 token0_2_token1_rate_,
         * [128~191]: uint64 token1_2_token0_rate_,
         * [192~223]: reserved
         */
        uint256 properties_
    ) external initializer {
        if (addrs_[0] == address(0x0)) {
            revert Errors.ZeroAddress("token0");
        }
        if (addrs_[1] == address(0x0)) {
            revert Errors.ZeroAddress("token1");
        }
        if (addrs_[2] == address(0x0)) {
            revert Errors.ZeroAddress("whitelist");
        }
        if (addrs_[3] == address(0x0)) {
            revert Errors.ZeroAddress("owner");
        }
        if (uint64(properties_) == 0) {
            revert Errors.InvalidValue("precision");
        }
        if (uint64(properties_ >> 64) == 0) {
            revert Errors.InvalidValue("token0_token1_rate");
        }
        if (uint64(properties_ >> 128) == 0) {
            revert Errors.InvalidValue("token1_token0_rate");
        }

        __AccessControl_init();
        __ReentrancyGuard_init();

        _token0 = addrs_[0];
        _token0_decimals = IERC20Metadata(_token0).decimals();
        _token1 = addrs_[1];
        _token1_decimals = IERC20Metadata(_token1).decimals();
        _whitelist = addrs_[2];
        _precision = uint64(properties_);
        _token0_token1_rate = uint64(properties_ >> 64);
        _token1_token0_rate = uint64(properties_ >> 128);

        _grantRole(Roles.OWNER_ROLE, addrs_[3]);
        _setRoleAdmin(Roles.OPERATOR_ROLE, Roles.OWNER_ROLE);
        _setRoleAdmin(Roles.INVESTMENT_MANAGER_ROLE, Roles.OWNER_ROLE);
    }

    function exchange(uint128 amountIn_, bool deposit_)
        public
        nonReentrant
        onlyInitialized
        onlyWhitelist(msg.sender)
        returns (uint128 amountOut_)
    {
        if (amountIn_ == 0) {
            revert Errors.InvalidValue("amountIn");
        }
        if (deposit_) {
            unchecked {
                // exchange token1 to token0
                amountOut_ = uint128(
                    (amountIn_ * _token1_token0_rate * (10 ** _token0_decimals))
                        / (_precision * (10 ** _token1_decimals))
                );
            }

            // mint token0 to user
            UnderlyingToken(_token0).mint(msg.sender, uint128(amountOut_));
            // transfer token1 from user to this contract
            IERC20(_token1).safeTransferFrom(msg.sender, address(this), amountIn_);

            emit Exchanged(msg.sender, deposit_, amountIn_, amountOut_);
        } else {
            unchecked {
                // exchange token0 to token1
                amountOut_ = uint128(
                    (amountIn_ * _token0_token1_rate * (10 ** _token1_decimals))
                        / (_precision * (10 ** _token0_decimals))
                );
            }

            // burn token0 from user
            UnderlyingToken(_token0).burnFrom(msg.sender, amountIn_);
            // transfer token1 from this contract to user
            IERC20(_token1).safeTransfer(msg.sender, amountOut_);

            emit Exchanged(msg.sender, deposit_, amountIn_, amountOut_);
        }
    }

    function dryrunExchange(uint128 amountIn_, bool deposit_)
        external
        view
        onlyInitialized
        returns (uint128 amountOut_)
    {
        if (amountIn_ == 0) {
            amountOut_ = 0;
        }
        if (deposit_) {
            unchecked {
                // exchange token1 to token0
                amountOut_ = uint128(
                    (amountIn_ * _token1_token0_rate * (10 ** _token0_decimals))
                        / (_precision * (10 ** _token1_decimals))
                );
            }
        } else {
            unchecked {
                // exchange token0 to token1
                amountOut_ = uint128(
                    (amountIn_ * _token0_token1_rate * (10 ** _token1_decimals))
                        / (_precision * (10 ** _token0_decimals))
                );
            }
        }
    }

    function apporveDepositTokenForInvestment(address investmentManager_, uint128 amount_)
        external
        onlyInitialized
        onlyRole(Roles.OPERATOR_ROLE)
    {
        if (investmentManager_ == address(0)) {
            revert Errors.ZeroAddress("investmentManager");
        }
        if (amount_ == 0) {
            revert Errors.InvalidValue("amount");
        }

        IERC20(_token1).safeIncreaseAllowance(investmentManager_, amount_);
    }

    function extractDepositTokenForInvestment(uint128 amount_)
        external
        onlyInitialized
        onlyRole(Roles.INVESTMENT_MANAGER_ROLE)
    {
        if (amount_ == 0) {
            revert Errors.InvalidValue("amount");
        }

        uint256 balance = IERC20(_token1).balanceOf(address(this));
        if (balance < amount_) {
            revert Errors.InsufficientBalance(balance, amount_);
        }
        uint256 allowance = IERC20(_token1).allowance(address(this), msg.sender);
        if (allowance < amount_) {
            revert Errors.InsufficientAllowance(allowance, amount_);
        }

        IERC20(_token1).safeTransfer(msg.sender, amount_);
    }

    function updateExchangeRate(bool zeroForOne_, uint64 new_exchange_rate_)
        external
        onlyInitialized
        onlyRole(Roles.OPERATOR_ROLE)
    {
        if (new_exchange_rate_ == 0) {
            revert Errors.InvalidValue("new_exchange_rate");
        }

        if (zeroForOne_) {
            // update token0 to token1 rate
            uint64 old_rate = _token0_token1_rate;
            _token0_token1_rate = new_exchange_rate_;
            emit ExchangeRatesUpdated(zeroForOne_, old_rate, new_exchange_rate_);
        } else {
            // update token1 to token0 rate
            uint64 old_rate = _token1_token0_rate;
            _token1_token0_rate = new_exchange_rate_;
            emit ExchangeRatesUpdated(zeroForOne_, old_rate, new_exchange_rate_);
        }
    }

    function token0() external view returns (address) {
        return _token0;
    }

    function token0Decimals() external view returns (uint8) {
        return _token0_decimals;
    }

    function token1() external view returns (address) {
        return _token1;
    }

    function token1Decimals() external view returns (uint8) {
        return _token1_decimals;
    }

    function whitelist() external view returns (address) {
        return _whitelist;
    }

    function precision() external view returns (uint64) {
        return _precision;
    }

    function token0ToToken1Rate() external view returns (uint64) {
        return _token0_token1_rate;
    }

    function token1ToToken0Rate() external view returns (uint64) {
        return _token1_token0_rate;
    }

    function contractName() external pure returns (string memory) {
        return "UnderlyingTokenExchanger";
    }
}
