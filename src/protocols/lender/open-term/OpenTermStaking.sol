// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {UnderlyingToken} from "src/underlying/UnderlyingToken.sol";
import {UnderlyingTokenExchanger} from "src/underlying/UnderlyingTokenExchanger.sol";
import {IWhitelist} from "src/whitelist/IWhitelist.sol";
import {OpenTermToken} from "src/protocols/lender/open-term/OpenTermToken.sol";
import {Errors} from "src/common/Errors.sol";
import {Roles} from "src/common/Roles.sol";

import {OpenTermStakingLibs} from "src/protocols/lender/open-term/utils/OpenTermStakingLibs.sol";

contract OpenTermStaking is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OpenTermToken
{
    using OpenTermStakingLibs for uint64;
    using OpenTermStakingLibs for uint128;
    using OpenTermStakingLibs for address;
    using OpenTermStakingLibs for OpenTermStakingLibs.AssetInfo[];

    /// @dev ERC20 token used for staking
    /// @notice stored in slot 0
    address public _underlyingToken;
    /// @dev only allow whitelisted address to stake/unstake
    /// @notice stored in slot 1
    address public _whitelist;
    /// @dev address of the exchanger contract for deposit/withdraw underlying tokens
    /// @notice stored in slot 2
    /// @notice we use exchanger to calculate how much deposit token should be invested into each vault when staking
    /// @notice we use exchanger to calculate how much deposit token should be withdrawn from each vault when unstaking
    address public _exchanger;
    /// @dev record of the total underlying tokens as interest bearing (including principal and interest)
    /// @notice stored in slot 3
    uint128 public _totalInterestBearing;
    /// @dev record of the total fees collected
    /// @notice stored in slot 3
    uint128 public _totalFee;
    /// @dev minimum remaining balance to prevent small stakes
    /// @notice stored in slot 4
    uint128 public _dustBalance;
    /// @dev maximum underlying tokens that can be accepted as interest bearing (including interest)
    /// @notice stored in slot 4
    uint128 public _maxSupply;
    /// @dev fee rate for staking operations
    /// @notice stored in slot 5
    uint64 public _stakeFeeRate;
    /// @dev fee rate for unstaking operations
    /// @notice stored in slot 5
    uint64 public _unstakeFeeRate;
    /// @dev timestamp of oracle latest report
    /// @notice stored in slot 5
    uint64 public _lastFeedTime;
    /// @dev list of all assets in the basket
    /// @notice dynamic array storage, initialized when deploying this contract
    OpenTermStakingLibs.AssetInfo[] internal _assetsInfoBasket;

    /// @dev whitelist check modifier
    /// @param who_ The address to be checked against the whitelist
    modifier onlyWhitelisted(address who_) {
        _whitelist.onlyWhitelisted(who_);

        _;
    }

    /// @dev initialization check modifier
    modifier onlyInitialized() {
        _assetsInfoBasket.onlyInitialized(
            /**
             * address _underlyingToken,
             * address _whitelist,
             * address _exchanger,
             */
            [_underlyingToken, _whitelist, _exchanger],
            /**
             * uint128 _maxSupply,
             * uint128 _lastFeedTime
             */
            [_maxSupply, uint128(_lastFeedTime)]
        );

        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        /**
         * 0: address owner_,
         * 1: address underlyingToken_,
         * 2: address whitelist_,
         * 3: address exchanger_,
         */
        address[4] calldata addrs_,
        /**
         * [0~63]: uint64 reserveField_,
         * [64~127]: uint64 stakeFeeRate_,
         * [128~191]: uint64 unstakeFeeRate_,
         * [192~255]: uint64 startFeedTime_
         */
        uint256 properties_,
        /**
         * [0~127]: uint128 dustBalance_,
         * [128~255]: uint128 maxSupply_,
         */
        uint256 limits_,
        string calldata name_,
        string calldata symbol_,
        OpenTermStakingLibs.AssetInfo[] calldata assetsInfoBasket_
    ) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __OpenTermToken_init(name_, symbol_);

        _assetsInfoBasket.initialize(addrs_, properties_, name_, symbol_, assetsInfoBasket_);

        _underlyingToken = addrs_[1];
        _whitelist = addrs_[2];
        _exchanger = addrs_[3];
        _stakeFeeRate = uint64(properties_ >> 64);
        _unstakeFeeRate = uint64(properties_ >> 128);
        _lastFeedTime = (uint64(properties_ >> 192)).normalizeTimestamp();
        _dustBalance = uint128(limits_);
        _maxSupply = uint128(limits_ >> 128);

        _grantRole(Roles.OWNER_ROLE, addrs_[0]);
        _setRoleAdmin(Roles.OPERATOR_ROLE, Roles.OWNER_ROLE);

        /// @dev Prevent PoolBankrupt error when first stake (divide by zero)
        /// @dev This is a dummy mint of 1 token to the contract itself
        /// @dev No real underlying tokens are staked here
        /// @dev Fail if assert equal between underlying token balance and totalInterestBearing & totalFees before first feeding
        _totalInterestBearing = 1;
        /// @dev Mint 1 open-term staking token to the contract itself
        /// @dev This ensures 1:1 ratio at the beginning when stake happens before first feeding
        mint(address(this), 1);
    }

    /// @notice any whitelisted address can stake tokens when not paused
    /// @param stakeAmount_ The amount of tokens to stake (including fees)
    /// @return The amount of open-term staking tokens minted
    /// @return The net amount of underlying tokens staked (excluding fees)
    function stake(uint128 stakeAmount_)
        external
        whenNotPaused
        nonReentrant
        onlyWhitelisted(msg.sender)
        onlyInitialized
        returns (uint128, uint128)
    {
        /**
         * uint128 sharesAmount_,
         * uint128 stakedAmount_,
         * uint128 updatedTotalInterestBearing_,
         * uint128 updatedTotalFee_
         */
        uint128[4] memory results = _assetsInfoBasket.stake(
            /**
             * address from_,
             * address to_,
             * address underlyingToken_,
             * address exchanger_,
             */
            [msg.sender, msg.sender, _underlyingToken, _exchanger],
            /**
             * uint128 stakeAmount_,
             * uint128 maxSupply_,
             * uint128 dustBalance_,
             * uint128 totalInterestBearing_,
             * uint128 totalFee_,
             * uint128 stakeFeeRate_,
             * uint128 totalSupply_
             */
            [
                stakeAmount_,
                _maxSupply,
                _dustBalance,
                _totalInterestBearing,
                _totalFee,
                uint128(_stakeFeeRate),
                uint128(totalSupply())
            ]
        );
        unchecked {
            _totalInterestBearing = results[2];
            _totalFee = results[3];
        }
        mint(msg.sender, results[0]);
        return (results[0], results[1]);
    }

    /// @notice any whitelisted address can unstake tokens when not paused
    /// @param unstakeAmount_ The amount of tokens to unstake (including fees)
    /// @return The amount of open-term staking tokens burned
    /// @return The net amount of underlying tokens paid (excluding fees)
    function unstake(uint128 unstakeAmount_)
        external
        whenNotPaused
        nonReentrant
        onlyWhitelisted(msg.sender)
        onlyInitialized
        returns (uint128, uint128)
    {
        /**
         * uint128 sharesAmount_,
         * uint128 unstakedAmount_,
         * uint128 updatedTotalInterestBearing_,
         * uint128 updatedTotalFee_
         */
        uint128[4] memory results = _assetsInfoBasket.unstake(
            /**
             * address from_,
             * address to_,
             * address underlyingToken_,
             * address exchanger_,
             */
            [msg.sender, msg.sender, _underlyingToken, _exchanger],
            /**
             * uint128 unstakeAmount_,
             * uint128 maxSharesAmount_,
             * uint128 totalInterestBearing_,
             * uint128 totalFee_,
             * uint128 unstakeFeeRate_,
             * uint128 totalSupply_
             */
            [
                unstakeAmount_,
                uint128(sharesOf(msg.sender)),
                _totalInterestBearing,
                _totalFee,
                uint128(_unstakeFeeRate),
                uint128(totalSupply())
            ]
        );
        unchecked {
            _totalInterestBearing = results[2];
            _totalFee = results[3];
        }
        burn(msg.sender, results[0]);
        return (results[0], results[1]);
    }

    /// @notice only controller roles can stake tokens on behalf of another address
    /// @param stakeAmount_ The amount of underlying tokens to stake (including fees)
    /// @param who_ The address from which the underlying tokens will be transferred and the open-term staking tokens will be minted to
    /// @return The amount of open-term staking tokens minted
    /// @return The net amount of underlying tokens staked (excluding fees)
    function stakeFrom(uint128 stakeAmount_, address who_)
        external
        onlyRole(Roles.OPERATOR_ROLE)
        whenNotPaused
        nonReentrant
        onlyWhitelisted(who_)
        onlyInitialized
        returns (uint128, uint128)
    {
        /**
         * uint128 sharesAmount_,
         * uint128 stakedAmount_,
         * uint128 updatedTotalInterestBearing_,
         * uint128 updatedTotalFee_
         */
        uint128[4] memory results = _assetsInfoBasket.stake(
            /**
             * address from_,
             * address to_,
             * address underlyingToken_,
             * address exchanger_,
             */
            [who_, who_, _underlyingToken, _exchanger],
            /**
             * uint128 stakeAmount_,
             * uint128 maxSupply_,
             * uint128 dustBalance_,
             * uint128 totalInterestBearing_,
             * uint128 totalFee_,
             * uint128 stakeFeeRate_,
             * uint128 totalSupply_
             */
            [
                stakeAmount_,
                _maxSupply,
                _dustBalance,
                _totalInterestBearing,
                _totalFee,
                uint128(_stakeFeeRate),
                uint128(totalSupply())
            ]
        );
        unchecked {
            _totalInterestBearing = results[2];
            _totalFee = results[3];
        }
        mint(who_, results[0]);
        return (results[0], results[1]);
    }

    /// @notice only controller roles can unstake tokens on behalf of another address
    /// @param unstakeAmount_ The amount of underlying tokens to unstake (including fees)
    /// @param who_ The address from which the open-term staking tokens will be burned and the underlying tokens will be transferred to
    /// @return The amount of open-term staking tokens burned
    /// @return The net amount of underlying tokens paid (excluding fees)
    function unstakeFrom(uint128 unstakeAmount_, address who_)
        external
        onlyRole(Roles.OPERATOR_ROLE)
        whenNotPaused
        nonReentrant
        onlyWhitelisted(who_)
        onlyInitialized
        returns (uint128, uint128)
    {
        /**
         * uint128 sharesAmount_,
         * uint128 unstakedAmount_,
         * uint128 updatedTotalInterestBearing_,
         * uint128 updatedTotalFee_
         */
        uint128[4] memory results = _assetsInfoBasket.unstake(
            /**
             * address from_,
             * address to_,
             * address underlyingToken_,
             * address exchanger_,
             */
            [who_, who_, _underlyingToken, _exchanger],
            /**
             * uint128 unstakeAmount_,
             * uint128 maxSharesAmount_,
             * uint128 totalInterestBearing_,
             * uint128 totalFee_,
             * uint128 unstakeFeeRate_,
             * uint128 totalSupply_
             */
            [
                unstakeAmount_,
                uint128(sharesOf(who_)),
                _totalInterestBearing,
                _totalFee,
                uint128(_unstakeFeeRate),
                uint128(totalSupply())
            ]
        );
        unchecked {
            _totalInterestBearing = results[2];
            _totalFee = results[3];
        }
        burn(who_, results[0]);
        return (results[0], results[1]);
    }

    /// @notice any address can call this method to feed interest rate when not paused
    /// @param timestamp_ The timestamp to feed (non-normalized)
    /// @return dividends_ Whether there are dividends to distribute
    function feed(uint64 timestamp_) external whenNotPaused nonReentrant returns (bool dividends_) {
        (dividends_, _lastFeedTime, _totalInterestBearing) = OpenTermStakingLibs.feed(
            timestamp_, false, _lastFeedTime, _totalInterestBearing, getTotalAssetValueInBasket(), _underlyingToken
        );
    }

    /// @notice only operator role can call this method
    /// @param timestamp_ The timestamp to feed (non-normalized)
    /// @return dividends_ Whether there are dividends to distribute
    function feedForce(uint64 timestamp_)
        external
        whenNotPaused
        nonReentrant
        onlyRole(Roles.OPERATOR_ROLE)
        returns (bool dividends_)
    {
        (dividends_, _lastFeedTime, _totalInterestBearing) = OpenTermStakingLibs.feed(
            timestamp_, true, _lastFeedTime, _totalInterestBearing, getTotalAssetValueInBasket(), _underlyingToken
        );
    }

    /// @notice Method to update staking fee rate
    /// @param newStakeFeeRate_ The new staking fee rate
    /// @dev only operator role can call this method
    /// @dev only influence future staking operations
    function updateStakeFeeRate(uint64 newStakeFeeRate_) external onlyRole(Roles.OPERATOR_ROLE) {
        if (newStakeFeeRate_ > OpenTermStakingLibs.MAX_FEE_RATE) {
            revert OpenTermStakingLibs.InvalidFeeRate(newStakeFeeRate_);
        }
        uint64 oldStakeFeeRate = _stakeFeeRate;
        _stakeFeeRate = newStakeFeeRate_;
        emit OpenTermStakingLibs.StakeFeeRateUpdated(oldStakeFeeRate, newStakeFeeRate_);
    }

    /// @notice Method to update unstaking fee rate
    /// @param newUnstakeFeeRate_ The new unstaking fee rate
    /// @dev only operator role can call this method
    /// @dev only influence future unstaking operations
    function updateUnstakeFeeRate(uint64 newUnstakeFeeRate_) external onlyRole(Roles.OPERATOR_ROLE) {
        if (newUnstakeFeeRate_ > OpenTermStakingLibs.MAX_FEE_RATE) {
            revert OpenTermStakingLibs.InvalidFeeRate(newUnstakeFeeRate_);
        }
        uint64 oldUnstakeFeeRate = _unstakeFeeRate;
        _unstakeFeeRate = newUnstakeFeeRate_;
        emit OpenTermStakingLibs.UnstakeFeeRateUpdated(oldUnstakeFeeRate, newUnstakeFeeRate_);
    }

    /// @notice Method to update the dust balance limit
    /// @param newDustBalance_ The new dust balance limit
    /// @dev only operator role can call this method
    /// @dev only influence future staking operations
    function updateDustBalance(uint128 newDustBalance_) external onlyRole(Roles.OPERATOR_ROLE) {
        /// @dev New limit should not be compatible with current remaining balance
        if (_maxSupply - _totalInterestBearing < newDustBalance_) {
            revert OpenTermStakingLibs.InvalidValue("dustBalance");
        }

        uint128 oldDustBalance = _dustBalance;
        _dustBalance = newDustBalance_;

        emit OpenTermStakingLibs.DustBalanceUpdated(oldDustBalance, newDustBalance_);
    }

    /// @notice Method to update the maximum supply limit
    /// @param newMaxSupply_ The new maximum supply limit
    /// @dev only operator role can call this method
    /// @dev only influence future staking operations
    function updateMaxSupply(uint128 newMaxSupply_) external onlyRole(Roles.OPERATOR_ROLE) {
        /// @dev New limit should not be lower than current total interest bearing
        if (newMaxSupply_ < _totalInterestBearing) {
            revert OpenTermStakingLibs.InvalidValue("newMaxSupply");
        }

        /// @dev New limit should not be compatible with current dust balance
        if (newMaxSupply_ - _totalInterestBearing < _dustBalance) {
            revert OpenTermStakingLibs.InvalidValue("newMaxSupply");
        }

        uint128 oldMaxSupply = _maxSupply;
        _maxSupply = newMaxSupply_;

        emit OpenTermStakingLibs.MaxSupplyUpdated(oldMaxSupply, newMaxSupply_);
    }

    /// @notice Pause staking and unstaking operations
    function pause() external onlyRole(Roles.OPERATOR_ROLE) whenNotPaused {
        _pause();
    }

    /// @notice Unpause staking and unstaking operations
    function unpause() external onlyRole(Roles.OPERATOR_ROLE) whenPaused {
        _unpause();
    }

    /// @notice Method to add new assets into the basket
    /// @param newAssetInfo_ The array of new asset information to be added into the basket
    /// @dev only operator role can call this method
    /// @dev only influence future staking operations
    function addNewAssetIntoBasket(OpenTermStakingLibs.AssetInfo[] calldata newAssetInfo_)
        external
        onlyRole(Roles.OPERATOR_ROLE)
    {
        _assetsInfoBasket.addNewAssetIntoBasket(newAssetInfo_, _exchanger);
    }

    /// @notice Override balanceOf to calculate based on totalInterestBearing and shares
    /// @param account_ The address to query the balance of
    /// @return The balance of the account in underlying tokens
    /// @dev This method ensures OpenTermToken as a rebaseing token that is shown in wallets
    function balanceOf(address account_) public view override(OpenTermToken) returns (uint256) {
        return (_totalInterestBearing * sharesOf(account_)) / totalSupply();
    }

    /// @param totalValue_ The total value of all assets in the basket, converted to the underlying token
    function getTotalAssetValueInBasket() public view returns (uint128 totalValue_) {
        totalValue_ = _assetsInfoBasket.totalAssetValueInBasket(_exchanger);
    }

    function assetsInfoBasket() external view returns (OpenTermStakingLibs.AssetInfo[] memory) {
        return _assetsInfoBasket;
    }

    function assetInfoAt(uint256 index_) external view returns (OpenTermStakingLibs.AssetInfo memory) {
        return _assetsInfoBasket[index_];
    }

    uint256[50] private __gap;
}
