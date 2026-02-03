// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Errors} from "src/common/Errors.sol";
import {UnderlyingToken} from "src/underlying/UnderlyingToken.sol";
import {UnderlyingTokenExchanger} from "src/underlying/UnderlyingTokenExchanger.sol";
import {OpenTermStakingDefs} from "src/protocols/lender/open-term/utils/OpenTermStakingDefs.sol";
import {OpenTermStakingLibs} from "src/protocols/lender/open-term/utils/OpenTermStakingLibs.sol";

library OpenTermStakingCore {
    using OpenTermStakingLibs for uint64;

    function initialize(
        OpenTermStakingDefs.AssetInfo[] storage assetsInfoBasket_,
        address[4] calldata addrs_,
        uint256 properties_,
        string calldata name_,
        string calldata symbol_,
        OpenTermStakingDefs.AssetInfo[] calldata newAssetsInfoBasket_
    ) public {
        if (addrs_.length != 4) {
            revert Errors.InvalidValue("addresses length mismatch");
        }
        if (addrs_[0] == address(0)) {
            revert OpenTermStakingDefs.ZeroAddress("owner");
        }
        if (addrs_[1] == address(0)) {
            revert OpenTermStakingDefs.ZeroAddress("underlyingToken");
        }
        if (addrs_[2] == address(0)) {
            revert OpenTermStakingDefs.ZeroAddress("whitelist");
        }
        if (addrs_[3] == address(0)) {
            revert OpenTermStakingDefs.ZeroAddress("underlyingTokenExchanger");
        }
        if (uint64(properties_ >> 64) >= OpenTermStakingDefs.MAX_FEE_RATE) {
            revert OpenTermStakingDefs.InvalidValue("stakeFeeRate");
        }
        if (uint64(properties_ >> 128) >= OpenTermStakingDefs.MAX_FEE_RATE) {
            revert OpenTermStakingDefs.InvalidValue("unstakeFeeRate");
        }
        if (uint64(properties_ >> 192) == 0) {
            revert OpenTermStakingDefs.InvalidValue("startFeedTime");
        }
        if (bytes(name_).length == 0) {
            revert OpenTermStakingDefs.InvalidValue("name");
        }
        if (bytes(symbol_).length == 0) {
            revert OpenTermStakingDefs.InvalidValue("symbol");
        }
        if (newAssetsInfoBasket_.length == 0) {
            revert OpenTermStakingDefs.InvalidValue("assetsInfoBasket");
        }

        uint64 totalWeight = 0;
        for (uint256 i = 0; i < newAssetsInfoBasket_.length; i++) {
            if (newAssetsInfoBasket_[i].targetVault == address(0)) {
                revert OpenTermStakingDefs.ZeroAddress("asset vault");
            }
            if (newAssetsInfoBasket_[i].weight == 0 || newAssetsInfoBasket_[i].weight > OpenTermStakingDefs.PRECISION) {
                revert OpenTermStakingDefs.InvalidValue("weight of asset in basket");
            }
            totalWeight += newAssetsInfoBasket_[i].weight;
            if (totalWeight > OpenTermStakingDefs.PRECISION) {
                revert OpenTermStakingDefs.InvalidValue("total weight of assets in basket");
            }
            if (IERC4626(newAssetsInfoBasket_[i].targetVault).asset() != UnderlyingTokenExchanger(addrs_[3])._token1())
            {
                revert OpenTermStakingDefs.VaultAssetNotEqualExchangerToken1(
                    IERC4626(newAssetsInfoBasket_[i].targetVault).asset(), UnderlyingTokenExchanger(addrs_[3])._token1()
                );
            }
            if (UnderlyingTokenExchanger(addrs_[3])._token0() != addrs_[1]) {
                revert OpenTermStakingDefs.ExchangerToken0NotEqualUnderlyingToken(
                    UnderlyingTokenExchanger(addrs_[3])._token0(), addrs_[1]
                );
            }
            assetsInfoBasket_.push(newAssetsInfoBasket_[i]);
        }
    }

    function stake(
        OpenTermStakingDefs.AssetInfo[] storage assetsInfoBasket_,
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
            revert OpenTermStakingDefs.InvalidValue("stakeAmount");
        }
        if (addrs_[0] == address(0)) {
            revert OpenTermStakingDefs.ZeroAddress("from");
        }
        if (addrs_[1] == address(0)) {
            revert OpenTermStakingDefs.ZeroAddress("to");
        }
        uint256 allowance = IERC20(addrs_[2]).allowance(addrs_[0], address(this));
        if (allowance < uint256(paras_[0])) {
            revert OpenTermStakingDefs.InsufficientAllowance(uint128(allowance), paras_[0]);
        }
        uint256 balance = IERC20(addrs_[2]).balanceOf(addrs_[0]);
        if (balance < uint256(paras_[0])) {
            revert OpenTermStakingDefs.InsufficientBalance(uint128(balance), paras_[0]);
        }

        uint128 fee = (paras_[0] * paras_[5] + OpenTermStakingDefs.PRECISION - 1) / OpenTermStakingDefs.PRECISION;
        results_[1] = paras_[0] - fee;

        if (paras_[3] + results_[1] > paras_[1]) {
            revert OpenTermStakingDefs.ExceedMaxSupply(results_[1], paras_[3], paras_[1]);
        }
        uint128 remainingBalance = paras_[1] - paras_[3] - results_[1];
        if (remainingBalance < paras_[2]) {
            revert OpenTermStakingDefs.BelowDustBalance(results_[1], remainingBalance, paras_[2]);
        }

        if (paras_[3] == 0) {
            revert OpenTermStakingDefs.PoolBankrupt();
        }
        results_[0] = uint128(results_[1] * uint256(paras_[6])) / paras_[3];

        unchecked {
            results_[2] = paras_[3] + results_[1];
            results_[3] = paras_[4] + fee;
        }

        SafeERC20.safeTransferFrom(IERC20(addrs_[2]), addrs_[0], address(this), paras_[0]);

        for (uint256 i = 0; i < assetsInfoBasket_.length; i++) {
            OpenTermStakingDefs.AssetInfo memory assetInfo = assetsInfoBasket_[i];
            uint128 assetAmount = UnderlyingTokenExchanger(addrs_[3]).dryrunExchange(
                (results_[1] * assetInfo.weight) / OpenTermStakingDefs.PRECISION, false
            );
            if (assetAmount > 0) {
                UnderlyingTokenExchanger(addrs_[3]).extractDepositTokenForInvestment(assetAmount);
                SafeERC20.safeIncreaseAllowance(
                    IERC20(UnderlyingTokenExchanger(addrs_[3])._token1()), assetInfo.targetVault, assetAmount
                );
                if (IERC4626(assetInfo.targetVault).deposit(assetAmount, address(this)) == 0) {
                    revert OpenTermStakingDefs.DepositFailed(assetAmount, 0, assetInfo.targetVault);
                }
            }
        }

        emit OpenTermStakingDefs.Stake(addrs_[0], addrs_[1], results_[1], results_[0], fee);
    }

    function unstake(
        OpenTermStakingDefs.AssetInfo[] storage assetsInfoBasket_,
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
            revert OpenTermStakingDefs.InvalidValue("unstakeAmount");
        }
        if (addrs_[0] == address(0)) {
            revert OpenTermStakingDefs.ZeroAddress("from");
        }
        if (addrs_[1] == address(0)) {
            revert OpenTermStakingDefs.ZeroAddress("to");
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

        uint128 fee = (paras_[0] * paras_[4] + OpenTermStakingDefs.PRECISION - 1) / OpenTermStakingDefs.PRECISION;
        results_[1] = paras_[0] - fee;

        unchecked {
            results_[3] = paras_[3] + fee;
            results_[2] = paras_[2] - paras_[0];
        }

        uint256 assetNumberInBasket = assetsInfoBasket_.length;
        for (uint256 i = 0; i < assetNumberInBasket; i++) {
            OpenTermStakingDefs.AssetInfo memory assetInfo = assetsInfoBasket_[i];
            /// @dev When user unstake an open-term staking, protocol should withdraw corresponding amount from each vault
            /// @dev The key issue is how much underlying token should be withdrawn from all vaults
            /// @dev We choose to withdraw unstake amount rather than unstaked amount from each vaults by proportion.
            /// @dev This is because fee is collected in underlying token and should be withdrawn from each vault to cover the fee immediately.
            /// @dev No matter vaults value will decrease or increase later, protocol have settled with user immediately when user unstakes
            uint128 assetAmount = UnderlyingTokenExchanger(addrs_[3]).dryrunExchange(
                (paras_[0] * assetInfo.weight) / OpenTermStakingDefs.PRECISION, false
            );
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
                    revert OpenTermStakingDefs.WithdrawFailed(assetAmount, 0, assetInfo.targetVault);
                }
            }
        }

        /// @dev After withdrawing from all vaults, we repay underlying tokens to user
        /// @dev User will retrieve assets from exchanger contract later
        if (results_[1] > 0) {
            SafeERC20.safeTransfer(IERC20(addrs_[2]), addrs_[1], results_[1]);
        }

        emit OpenTermStakingDefs.Unstake(addrs_[0], addrs_[1], results_[1], results_[0], fee);
    }

    function feed(
        uint64 timestamp_,
        bool force_,
        uint64 lastFeedTime_,
        uint128 totalInterestBearing_,
        int128 interest_,
        address underlyingToken_
    ) public returns (bool dividends_, uint64 updatedLastFeedTime_, uint128 updatedTotalInterestBearing_) {
        uint64 normalizedTimestamp = timestamp_.normalizeTimestamp();

        /// @dev Only allow to force feed at last feed time or normal feed at next day
        if (
            (normalizedTimestamp == lastFeedTime_ && force_)
                || (normalizedTimestamp == lastFeedTime_ + 1 days && block.timestamp >= normalizedTimestamp)
        ) {
            updatedLastFeedTime_ = normalizedTimestamp;
            dividends_ = true;

            if (interest_ < 0) {
                /// @dev Vaults value decreased, pool lost money
                interest_ = -interest_;

                if (totalInterestBearing_ < uint128(interest_)) {
                    /// @dev Lost all principal and interest bearing
                    /// @dev This is impossible to happen in mathmatical sense
                    /// @dev Because both totalAssetValueInBasket and totalInterestBearing are uint128 values
                    /// @dev The absolute value of interest is never larger than totalInterestBearing
                    interest_ = int128(totalInterestBearing_);
                    updatedTotalInterestBearing_ = 0;
                } else {
                    /// @dev Just lost part of principal and interest bearing
                    updatedTotalInterestBearing_ = totalInterestBearing_ - uint128(interest_);
                }

                /// @dev Check pool reserve before burning underlying tokens
                /// @dev This balance includes fees collected
                uint128 openTermStakingHoldUnderlyingTokenBalance =
                    uint128(IERC20(underlyingToken_).balanceOf(address(this)));

                if (uint128(interest_) > openTermStakingHoldUnderlyingTokenBalance) {
                    /// @dev Not enough underlying tokens to burn, just burn what we have
                    /// @dev This should never happen under normal circumstances
                    /// @dev unless there are bad guys attack the pool or vault and steal underlying tokens
                    /// @dev In such case, protocol should contribute all fees collected to compensate the loss
                    interest_ = int128(openTermStakingHoldUnderlyingTokenBalance);
                }

                if (interest_ > 0) {
                    UnderlyingToken(underlyingToken_).burn(uint256(uint128(interest_)));
                }
            } else if (interest_ > 0) {
                /// @dev Vaults value increased, pool earned money
                updatedTotalInterestBearing_ = totalInterestBearing_ + uint128(interest_);
                UnderlyingToken(underlyingToken_).mint(address(this), uint256(uint128(interest_)));
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
                revert OpenTermStakingDefs.AncientFeedTimeUpdateIsNotAllowed(
                    normalizedTimestamp, lastFeedTime_, uint64(block.timestamp)
                );
            }

            /// @dev Attempt to feed at last feed time without force (only controller can force feed)
            if (normalizedTimestamp == lastFeedTime_ && !force_) {
                revert OpenTermStakingDefs.LastFeedTimeUpdateRequireForce(
                    normalizedTimestamp, lastFeedTime_, uint64(block.timestamp)
                );
            }

            /// @dev Attempt to feed at a future time beyond next day
            if (!(normalizedTimestamp == lastFeedTime_ + 1 days && block.timestamp >= normalizedTimestamp)) {
                revert OpenTermStakingDefs.FutureFeedTimeUpdateIsNotAllowed(
                    normalizedTimestamp, lastFeedTime_, uint64(block.timestamp)
                );
            }

            /// @dev This case should never happen
            revert("Unrecognized condition!");
        }
    }
}
