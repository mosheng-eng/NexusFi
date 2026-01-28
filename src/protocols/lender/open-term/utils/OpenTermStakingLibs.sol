// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IWhitelist} from "src/whitelist/IWhitelist.sol";
import {UnderlyingToken} from "src/underlying/UnderlyingToken.sol";
import {UnderlyingTokenExchanger} from "src/underlying/UnderlyingTokenExchanger.sol";

import {Errors} from "src/common/Errors.sol";
import {Roles} from "src/common/Roles.sol";

library OpenTermStakingLibs {
    /// @notice Event emitted when stake happens
    /// @param from the address who pay for underlying tokens
    /// @param to the address who receive the open-term staking tokens
    /// @param amount the net amount of underlying tokens staked (excluding fees)
    /// @param shares the amount of open-term staking tokens minted
    /// @param fee the fee charged for staking in underlying tokens
    event Stake(address indexed from, address indexed to, uint128 amount, uint128 shares, uint128 fee);

    /// @notice Event emitted when unstake happens
    /// @param from the address who pay for open-term staking tokens
    /// @param to the address who receive the underlying tokens
    /// @param amount the net amount of underlying tokens paid (excluding fees)
    /// @param shares the amount of open-term staking tokens burned
    /// @param fee the fee charged for unstaking in underlying tokens
    event Unstake(address indexed from, address indexed to, uint128 amount, uint128 shares, uint128 fee);

    /// @notice Event emitted when update stake fee rate
    /// @param oldFeeRate the old stake fee rate
    /// @param newFeeRate the new stake fee rate
    event StakeFeeRateUpdated(uint64 oldFeeRate, uint64 newFeeRate);

    /// @notice Event emitted when update unstake fee rate
    /// @param oldFeeRate the old unstake fee rate
    /// @param newFeeRate the new unstake fee rate
    event UnstakeFeeRateUpdated(uint64 oldFeeRate, uint64 newFeeRate);

    /// @notice Event emitted when update maximum supply
    /// @param oldMaxSupply the old maximum supply
    /// @param newMaxSupply the new maximum supply
    event MaxSupplyUpdated(uint128 oldMaxSupply, uint128 newMaxSupply);

    /// @notice Event emitted when update dust balance
    /// @param oldDustBalance the old dust balance
    /// @param newDustBalance the new dust balance
    event DustBalanceUpdated(uint128 oldDustBalance, uint128 newDustBalance);

    /// @notice Error reverted when staking amount over staker's balance
    /// @param balance the staker's balance
    /// @param stakeAmount the staking amount
    error InsufficientBalance(uint128 balance, uint128 stakeAmount);

    /// @notice Error reverted when staking amount over staker's allowance to this contract
    /// @param allowance the staker's allowance to this contract
    /// @param stakeAmount the staking amount
    error InsufficientAllowance(uint128 allowance, uint128 stakeAmount);

    /// @notice Error reverted when staking amount after fee plus total principal over max supply
    /// @param stakeAmountAfterFee the staking amount after fee deduction
    /// @param totalPrincipal the total principal amount staked
    /// @param maxSupply the maximum supply of tokens that can be staked
    error ExceedMaxSupply(uint128 stakeAmountAfterFee, uint128 totalPrincipal, uint128 maxSupply);

    /// @notice Error reverted when remaining balance substracting staking amount after fee is below dust balance
    /// @param stakeAmountAfterFee the staking amount after fee deduction
    /// @param remainingBalance the remaining balance before staking
    /// @param dustBalance the minimum remaining balance to prevent small stakes
    error BelowDustBalance(uint128 stakeAmountAfterFee, uint128 remainingBalance, uint128 dustBalance);

    /// @notice Error reverted when fee rate is over maximum limit
    /// @param feeRate the fee rate that was attempted to be set
    error InvalidFeeRate(uint64 feeRate);

    /// @notice Error reverted when an address is zero
    /// @param addr the name of the address
    error ZeroAddress(string addr);

    /// @notice Error reverted when a required parameter is uninitialized
    /// @param name the name of the uninitialized parameter
    error Uninitialized(string name);

    /// @notice Error reverted when a parameter value is invalid
    /// @param name the name of the invalid parameter
    error InvalidValue(string name);

    /// @notice Error reverted when feeding at an ancient time which is already fed
    /// @param update the time that inputs into feed function (normalized time)
    /// @param last the last time that feed function was called (normalized time)
    /// @param current the current time (non-normalized time)
    error AncientFeedTimeUpdateIsNotAllowed(uint64 update, uint64 last, uint64 current);

    /// @notice Error reverted when feeding at the current time which is already fed
    /// @param update the time that inputs into feed function (normalized time)
    /// @param last the last time that feed function was called (normalized time)
    /// @param current the current time (non-normalized time)
    error LastFeedTimeUpdateRequireForce(uint64 update, uint64 last, uint64 current);

    /// @notice Error reverted when feeding at a future time which is not allowed
    /// @param update the time that inputs into feed function (normalized time)
    /// @param last the last time that feed function was called (normalized time)
    /// @param current the current time (non-normalized time)
    error FutureFeedTimeUpdateIsNotAllowed(uint64 update, uint64 last, uint64 current);

    /// @notice Error reverted when vault asset is not the same as exchanger token1
    /// @param vaultAsset the asset of the vault
    /// @param exchangerToken1 the token1 of the exchanger
    error VaultAssetNotEqualExchangerToken1(address vaultAsset, address exchangerToken1);

    /// @notice Error reverted when exchanger token0 is not the same as underlying token
    /// @param exchangerToken0 the token0 of the exchanger
    /// @param underlyingToken the underlying token
    error ExchangerToken0NotEqualUnderlyingToken(address exchangerToken0, address underlyingToken);

    /// @notice Error reverted when interest rate is unbelievable (over maximum limit)
    /// @param interestRate the interest rate that was attempted to feed
    /// @param maxInterestRate the maximum interest rate per day
    /// @param minInterestRate the minimum interest rate per day
    error UnbelievableInterestRate(int64 interestRate, int64 maxInterestRate, int64 minInterestRate);

    /// @notice Error reverted when investment into target vault failed
    /// @param depositAmount the amount attempted to deposit
    /// @param sharesAmount the amount of shares received from deposit
    /// @param targetVault the address of the target vault
    error DepositFailed(uint128 depositAmount, uint128 sharesAmount, address targetVault);

    /// @notice Error reverted when withdraw from target vault failed
    /// @param withdrawAmount the amount attempted to withdraw
    /// @param sharesAmount the amount of shares received from withdraw
    /// @param targetVault the address of the target vault
    error WithdrawFailed(uint128 withdrawAmount, uint128 sharesAmount, address targetVault);

    /// @notice Error reverted when the staking pool is bankrupt (total interest plus total principal is non-positive)
    error PoolBankrupt();

    /// @dev information of each asset in a basket
    /// @notice used in multi-asset basket
    struct AssetInfo {
        /// @dev the address of the asset vault, which must implement IERC4626
        address targetVault;
        /// @dev weight of the asset in the basket, in million (1_000_000 = 100%)
        uint64 weight;
    }

    /// @dev precision in million (1_000_000 = 100%)
    /// @notice constant, not stored in storage
    uint64 public constant PRECISION = 1_000_000;
    /// @dev maximum fee rate (5%)
    /// @notice constant, not stored in storage
    uint64 public constant MAX_FEE_RATE = 50_000;

    function initialize(
        AssetInfo[] storage assetsInfoBasket_,
        address[4] calldata addrs_,
        uint256 properties_,
        string calldata name_,
        string calldata symbol_,
        AssetInfo[] calldata newAssetsInfoBasket_
    ) public {
        if (addrs_.length != 4) {
            revert Errors.InvalidValue("addresses length mismatch");
        }
        if (addrs_[0] == address(0)) {
            revert ZeroAddress("owner");
        }
        if (addrs_[1] == address(0)) {
            revert ZeroAddress("underlyingToken");
        }
        if (addrs_[2] == address(0)) {
            revert ZeroAddress("whitelist");
        }
        if (addrs_[3] == address(0)) {
            revert ZeroAddress("underlyingTokenExchanger");
        }
        if (uint64(properties_ >> 64) >= MAX_FEE_RATE) {
            revert InvalidValue("stakeFeeRate");
        }
        if (uint64(properties_ >> 128) >= MAX_FEE_RATE) {
            revert InvalidValue("unstakeFeeRate");
        }
        if (uint64(properties_ >> 192) == 0) {
            revert InvalidValue("startFeedTime");
        }
        if (bytes(name_).length == 0) {
            revert InvalidValue("name");
        }
        if (bytes(symbol_).length == 0) {
            revert InvalidValue("symbol");
        }
        if (newAssetsInfoBasket_.length == 0) {
            revert InvalidValue("assetsInfoBasket");
        }

        uint64 totalWeight = 0;
        for (uint256 i = 0; i < newAssetsInfoBasket_.length; i++) {
            if (newAssetsInfoBasket_[i].targetVault == address(0)) {
                revert ZeroAddress("asset vault");
            }
            if (newAssetsInfoBasket_[i].weight == 0 || newAssetsInfoBasket_[i].weight > PRECISION) {
                revert InvalidValue("weight of asset in basket");
            }
            totalWeight += newAssetsInfoBasket_[i].weight;
            if (totalWeight > PRECISION) {
                revert InvalidValue("total weight of assets in basket");
            }
            if (IERC4626(newAssetsInfoBasket_[i].targetVault).asset() != UnderlyingTokenExchanger(addrs_[3])._token1())
            {
                revert VaultAssetNotEqualExchangerToken1(
                    IERC4626(newAssetsInfoBasket_[i].targetVault).asset(), UnderlyingTokenExchanger(addrs_[3])._token1()
                );
            }
            if (UnderlyingTokenExchanger(addrs_[3])._token0() != addrs_[1]) {
                revert ExchangerToken0NotEqualUnderlyingToken(UnderlyingTokenExchanger(addrs_[3])._token0(), addrs_[1]);
            }
            assetsInfoBasket_.push(newAssetsInfoBasket_[i]);
        }
    }

    function stake(
        AssetInfo[] storage assetsInfoBasket_,
        /**
         * address from_,
         * address to_,
         * address underlyingToken_,
         * address exchanger_,
         */
        address[4] memory addrs_,
        /**
         * uint128 stakeAmount_,
         * uint128 maxSupply_,
         * uint128 dustBalance_,
         * uint128 totalInterestBearing_,
         * uint128 totalFee_,
         * uint128 stakeFeeRate_,
         * uint128 totalSupply_
         */
        uint128[7] memory paras_
    )
        public
        returns (
            /**
             * uint128 sharesAmount_,
             * uint128 stakedAmount_,
             * uint128 updatedTotalInterestBearing_,
             * uint128 updatedTotalFee_
             */
            uint128[4] memory results_
        )
    {
        if (paras_[0] == 0) {
            revert InvalidValue("stakeAmount");
        }
        if (addrs_[0] == address(0)) {
            revert ZeroAddress("from");
        }
        if (addrs_[1] == address(0)) {
            revert ZeroAddress("to");
        }
        uint256 allowance = IERC20(addrs_[2]).allowance(addrs_[0], address(this));
        if (allowance < uint256(paras_[0])) {
            revert InsufficientAllowance(uint128(allowance), paras_[0]);
        }
        uint256 balance = IERC20(addrs_[2]).balanceOf(addrs_[0]);
        if (balance < uint256(paras_[0])) {
            revert InsufficientBalance(uint128(balance), paras_[0]);
        }

        uint128 fee = (paras_[0] * paras_[5] + PRECISION - 1) / PRECISION;
        results_[1] = paras_[0] - fee;

        if (paras_[3] + results_[1] > paras_[1]) {
            revert ExceedMaxSupply(results_[1], paras_[3], paras_[1]);
        }
        uint128 remainingBalance = paras_[1] - paras_[3] - results_[1];
        if (remainingBalance < paras_[2]) {
            revert BelowDustBalance(results_[1], remainingBalance, paras_[2]);
        }

        if (paras_[3] == 0) {
            revert PoolBankrupt();
        }
        results_[0] = uint128(results_[1] * uint256(paras_[6])) / paras_[3];

        unchecked {
            results_[2] = paras_[3] + results_[1];
            results_[3] = paras_[4] + fee;
        }

        SafeERC20.safeTransferFrom(IERC20(addrs_[2]), addrs_[0], address(this), paras_[0]);

        for (uint256 i = 0; i < assetsInfoBasket_.length; i++) {
            AssetInfo memory assetInfo = assetsInfoBasket_[i];
            uint128 assetAmount =
                UnderlyingTokenExchanger(addrs_[3]).dryrunExchange((results_[1] * assetInfo.weight) / PRECISION, false);
            if (assetAmount > 0) {
                UnderlyingTokenExchanger(addrs_[3]).extractDepositTokenForInvestment(assetAmount);
                SafeERC20.safeIncreaseAllowance(
                    IERC20(UnderlyingTokenExchanger(addrs_[3])._token1()), assetInfo.targetVault, assetAmount
                );
                if (IERC4626(assetInfo.targetVault).deposit(assetAmount, address(this)) == 0) {
                    revert DepositFailed(assetAmount, 0, assetInfo.targetVault);
                }
            }
        }

        emit Stake(addrs_[0], addrs_[1], results_[1], results_[0], fee);
    }

    function unstake(
        AssetInfo[] storage assetsInfoBasket_,
        /**
         * address from_,
         * address to_,
         * address underlyingToken_,
         * address exchanger_,
         */
        address[4] memory addrs_,
        /**
         * uint128 unstakeAmount_,
         * uint128 maxSharesAmount_,
         * uint128 totalInterestBearing_,
         * uint128 totalFee_,
         * uint128 unstakeFeeRate_,
         * uint128 totalSupply_
         */
        uint128[6] memory paras_
    )
        public
        returns (
            /**
             * uint128 sharesAmount_,
             * uint128 unstakedAmount_,
             * uint128 updatedTotalInterestBearing_,
             * uint128 updatedTotalFee_
             */
            uint128[4] memory results_
        )
    {
        if (paras_[0] == 0) {
            revert InvalidValue("unstakeAmount");
        }
        if (addrs_[0] == address(0)) {
            revert ZeroAddress("from");
        }
        if (addrs_[1] == address(0)) {
            revert ZeroAddress("to");
        }

        results_[0] = uint128(paras_[0] * paras_[5]) / paras_[2] + 1;

        if (results_[0] > paras_[1]) {
            results_[0] = paras_[1];
            uint128 unstakeAmount = uint128(results_[0] * paras_[2]) / paras_[5];
            if (unstakeAmount > paras_[0]) {
                revert("This is impossible!");
            } else {
                paras_[0] = unstakeAmount;
            }
        }

        uint128 fee = (paras_[0] * paras_[4] + PRECISION - 1) / PRECISION;
        results_[1] = paras_[0] - fee;

        unchecked {
            results_[3] = paras_[3] + fee;
            results_[2] = paras_[2] - paras_[0];
        }

        uint256 assetNumberInBasket = assetsInfoBasket_.length;
        for (uint256 i = 0; i < assetNumberInBasket; i++) {
            AssetInfo memory assetInfo = assetsInfoBasket_[i];
            /// @dev When user unstake an open-term staking, protocol should withdraw corresponding amount from each vault
            /// @dev The key issue is how much underlying token should be withdrawn from all vaults
            /// @dev We choose to withdraw unstake amount rather than unstaked amount from each vaults by proportion.
            /// @dev This is because fee is collected in underlying token and should be withdrawn from each vault to cover the fee immediately.
            /// @dev No matter vaults value will decrease or increase later, protocol have settled with user immediately when user unstakes
            uint128 assetAmount =
                UnderlyingTokenExchanger(addrs_[3]).dryrunExchange((paras_[0] * assetInfo.weight) / PRECISION, false);
            /// @dev Check the maximum withdrawable amount from the vault
            uint128 maxAssetAmount = uint128(IERC4626(assetInfo.targetVault).maxWithdraw(address(this)));
            /// @dev Adjust the withdraw amount if it exceeds the maximum withdrawable amount
            /// @dev This may happen when asset portfolio is modified, e.g. one asset's weight is increased significantly after last stake or unstake
            /// @dev In this case, protocol should follow the new strategy and be responsible for the loss or profit
            if (assetAmount > maxAssetAmount) {
                assetAmount = maxAssetAmount;
            }
            if (assetAmount > 0) {
                /// @dev Withdraw asset from each vault where owner is this contract and receiver is the exchanger contract
                /// @dev User will retrieve assets from exchanger contract later
                uint128 sharesAmount =
                    uint128(IERC4626(assetInfo.targetVault).withdraw(assetAmount, addrs_[3], address(this)));

                if (sharesAmount == 0) {
                    revert WithdrawFailed(assetAmount, 0, assetInfo.targetVault);
                }
            }
        }

        /// @dev After withdrawing from all vaults, we repay underlying tokens to user
        /// @dev User will retrieve assets from exchanger contract later
        if (results_[1] > 0) {
            SafeERC20.safeTransfer(IERC20(addrs_[2]), addrs_[1], results_[1]);
        }

        emit Unstake(addrs_[0], addrs_[1], results_[1], results_[0], fee);
    }

    function feed(
        uint64 timestamp_,
        bool force_,
        uint64 lastFeedTime_,
        uint128 totalInterestBearing_,
        uint128 totalAssetValueInBasket_,
        address underlyingToken_
    ) public returns (bool dividends_, uint64 updatedLastFeedTime_, uint128 updatedTotalInterestBearing_) {
        uint64 normalizedTimestamp = normalizeTimestamp(timestamp_);

        /// @dev Only allow to force feed at last feed time or normal feed at next day
        if (
            (normalizedTimestamp == lastFeedTime_ && force_)
                || (normalizedTimestamp == lastFeedTime_ + 1 days && block.timestamp >= normalizedTimestamp)
        ) {
            /// @dev Calculate interest earned or lost since last feed time
            int128 interest = int128(totalAssetValueInBasket_) - int128(totalInterestBearing_);

            updatedLastFeedTime_ = normalizedTimestamp;
            dividends_ = true;

            if (interest < 0) {
                /// @dev Vaults value decreased, pool lost money
                interest = -interest;

                if (totalInterestBearing_ < uint128(interest)) {
                    /// @dev Lost all principal and interest bearing
                    /// @dev This is impossible to happen in mathmatical sense
                    /// @dev Because both totalAssetValueInBasket and totalInterestBearing are uint128 values
                    /// @dev The absolute value of interest is never larger than totalInterestBearing
                    interest = int128(totalInterestBearing_);
                    updatedTotalInterestBearing_ = 0;
                } else {
                    /// @dev Just lost part of principal and interest bearing
                    updatedTotalInterestBearing_ = totalInterestBearing_ - uint128(interest);
                }

                /// @dev Check pool reserve before burning underlying tokens
                /// @dev This balance includes fees collected
                uint128 openTermStakingHoldUnderlyingTokenBalance =
                    uint128(IERC20(underlyingToken_).balanceOf(address(this)));

                if (uint128(interest) > openTermStakingHoldUnderlyingTokenBalance) {
                    /// @dev Not enough underlying tokens to burn, just burn what we have
                    /// @dev This should never happen under normal circumstances
                    /// @dev unless there are bad guys attack the pool or vault and steal underlying tokens
                    /// @dev In such case, protocol should contribute all fees collected to compensate the loss
                    interest = int128(openTermStakingHoldUnderlyingTokenBalance);
                }

                if (interest > 0) {
                    UnderlyingToken(underlyingToken_).burn(uint256(uint128(interest)));
                }
            } else if (interest > 0) {
                /// @dev Vaults value increased, pool earned money
                updatedTotalInterestBearing_ = totalInterestBearing_ + uint128(interest);
                UnderlyingToken(underlyingToken_).mint(address(this), uint256(uint128(interest)));
            } else {
                /// @dev No change in vaults value
                dividends_ = false;
                updatedTotalInterestBearing_ = totalInterestBearing_;
            }
        }
        /// @dev Handle invalid feeding attempts
        else {
            /// @dev Attempt to feed at an ancient time (before last feed time)
            if (normalizedTimestamp < lastFeedTime_) {
                revert AncientFeedTimeUpdateIsNotAllowed(normalizedTimestamp, lastFeedTime_, uint64(block.timestamp));
            }

            /// @dev Attempt to feed at last feed time without force (only controller can force feed)
            if (normalizedTimestamp == lastFeedTime_ && !force_) {
                revert LastFeedTimeUpdateRequireForce(normalizedTimestamp, lastFeedTime_, uint64(block.timestamp));
            }

            /// @dev Attempt to feed at a future time beyond next day
            if (!(normalizedTimestamp == lastFeedTime_ + 1 days && block.timestamp >= normalizedTimestamp)) {
                revert FutureFeedTimeUpdateIsNotAllowed(normalizedTimestamp, lastFeedTime_, uint64(block.timestamp));
            }

            /// @dev This case should never happen
            revert("Unrecognized condition!");
        }
    }

    function addNewAssetIntoBasket(
        AssetInfo[] storage assetsInfoBasket_,
        AssetInfo[] calldata newAssetInfo_,
        address exchanger_
    ) public {
        if (newAssetInfo_.length == 0) {
            revert InvalidValue("empty newAssetInfo");
        }
        uint64 totalWeight = 0;
        for (uint256 i = 0; i < assetsInfoBasket_.length; i++) {
            totalWeight += assetsInfoBasket_[i].weight;
        }
        for (uint256 i = 0; i < newAssetInfo_.length; i++) {
            if (newAssetInfo_[i].targetVault == address(0)) {
                revert ZeroAddress("new asset's vault");
            }
            if (newAssetInfo_[i].weight == 0 || newAssetInfo_[i].weight > PRECISION) {
                revert InvalidValue("weight of new asset in basket");
            }
            totalWeight += newAssetInfo_[i].weight;
            if (totalWeight > PRECISION) {
                revert InvalidValue("total weight of assets in basket and new assets");
            }
            if (IERC4626(newAssetInfo_[i].targetVault).asset() != UnderlyingTokenExchanger(exchanger_)._token1()) {
                revert VaultAssetNotEqualExchangerToken1(
                    IERC4626(newAssetInfo_[i].targetVault).asset(), UnderlyingTokenExchanger(exchanger_)._token1()
                );
            }
            assetsInfoBasket_.push(newAssetInfo_[i]);
        }
    }

    function totalAssetValueInBasket(AssetInfo[] storage assetsInfoBasket_, address exchanger_)
        public
        view
        returns (uint128 totalValue_)
    {
        uint256 assetNumberInBasket = assetsInfoBasket_.length;
        for (uint256 i = 0; i < assetNumberInBasket; i++) {
            AssetInfo memory assetInfo = assetsInfoBasket_[i];
            totalValue_ += uint128(IERC4626(assetInfo.targetVault).maxWithdraw(address(this)));
        }
        return UnderlyingTokenExchanger(exchanger_).dryrunExchange(totalValue_, true);
    }

    function onlyWhitelisted(address whitelist_, address who_) public view {
        if (whitelist_ == address(0)) {
            revert ZeroAddress("whitelist");
        }
        if (who_ == address(0)) {
            revert ZeroAddress("user");
        }
        if (!IWhitelist(whitelist_).isWhitelisted(who_)) {
            revert IWhitelist.NotWhitelisted(who_);
        }
    }

    function onlyInitialized(
        AssetInfo[] storage assetsInfoBasket_,
        /**
         * address _underlyingToken,
         * address _whitelist,
         * address _exchanger,
         */
        address[3] memory addrs_,
        /**
         * uint128 _maxSupply,
         * uint64 _lastFeedTime
         */
        uint128[2] memory paras_
    ) public view {
        if (addrs_[0] == address(0)) {
            revert Uninitialized("underlyingToken");
        }
        if (addrs_[1] == address(0)) {
            revert Uninitialized("whitelist");
        }
        if (addrs_[2] == address(0)) {
            revert Uninitialized("exchanger");
        }
        if (paras_[0] == 0) {
            revert Uninitialized("maxSupply");
        }
        if (paras_[1] == 0) {
            revert Uninitialized("lastFeedTime");
        }
        if (assetsInfoBasket_.length == 0) {
            revert Uninitialized("assetsInfoBasket");
        }
    }

    function normalizeTimestamp(uint64 timestamp_) public pure returns (uint64 normalizedTimestamp_) {
        normalizedTimestamp_ = uint64(((timestamp_ + 17 hours) / 1 days) * 1 days + 7 hours);
    }
}
