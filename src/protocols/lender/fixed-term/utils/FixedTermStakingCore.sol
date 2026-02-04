// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Errors} from "src/common/Errors.sol";
import {UnderlyingToken} from "src/underlying/UnderlyingToken.sol";
import {UnderlyingTokenExchanger} from "src/underlying/UnderlyingTokenExchanger.sol";
import {FixedTermStakingLibs} from "src/protocols/lender/fixed-term/utils/FixedTermStakingLibs.sol";
import {FixedTermStakingDefs} from "src/protocols/lender/fixed-term/utils/FixedTermStakingDefs.sol";

library FixedTermStakingCore {
    using Arrays for uint256[];
    using FixedTermStakingLibs for uint64;
    using FixedTermStakingLibs for uint256[];

    function initialize(
        FixedTermStakingDefs.AssetInfo[] storage assetsInfoBasket_,
        /**
         * 0: address owner_,
         * 1: address underlyingToken_,
         * 2: address whitelist_,
         * 3: address exchanger_,
         */
        address[4] calldata addrs_,
        /**
         * [0~63]: uint64 lockPeriod_,
         * [64~127]: uint64 stakeFeeRate_,
         * [128~191]: uint64 unstakeFeeRate_,
         * [192~255]: uint64 startFeedTime_
         */
        uint256 properties_,
        string calldata name_,
        string calldata symbol_,
        FixedTermStakingDefs.AssetInfo[] calldata newAssetsInfoBasket_
    ) public {
        if (addrs_.length != 4) {
            revert Errors.InvalidValue("addresses length mismatch");
        }
        if (addrs_[0] == address(0)) {
            revert FixedTermStakingDefs.ZeroAddress("owner");
        }
        if (addrs_[1] == address(0)) {
            revert FixedTermStakingDefs.ZeroAddress("underlyingToken");
        }
        if (addrs_[2] == address(0)) {
            revert FixedTermStakingDefs.ZeroAddress("whitelist");
        }
        if (addrs_[3] == address(0)) {
            revert FixedTermStakingDefs.ZeroAddress("exchanger");
        }
        if (uint64(properties_) == 0 || uint64(properties_) % 1 days != 0) {
            revert FixedTermStakingDefs.InvalidValue("lockPeriod");
        }
        if (uint64(properties_ >> 64) >= FixedTermStakingDefs.MAX_FEE_RATE) {
            revert FixedTermStakingDefs.InvalidValue("stakeFeeRate");
        }
        if (uint64(properties_ >> 128) >= FixedTermStakingDefs.MAX_FEE_RATE) {
            revert FixedTermStakingDefs.InvalidValue("unstakeFeeRate");
        }
        if (uint64(properties_ >> 192) == 0) {
            revert FixedTermStakingDefs.InvalidValue("startFeedTime");
        }
        if (bytes(name_).length == 0) {
            revert FixedTermStakingDefs.InvalidValue("name");
        }
        if (bytes(symbol_).length == 0) {
            revert FixedTermStakingDefs.InvalidValue("symbol");
        }
        if (newAssetsInfoBasket_.length == 0) {
            revert FixedTermStakingDefs.InvalidValue("assetsInfoBasket");
        }

        uint64 totalWeight = 0;
        for (uint256 i = 0; i < newAssetsInfoBasket_.length; i++) {
            if (newAssetsInfoBasket_[i].targetVault == address(0)) {
                revert FixedTermStakingDefs.ZeroAddress("asset vault");
            }
            if (newAssetsInfoBasket_[i].weight == 0 || newAssetsInfoBasket_[i].weight > FixedTermStakingDefs.PRECISION)
            {
                revert FixedTermStakingDefs.InvalidValue("weight of asset in basket");
            }
            totalWeight += newAssetsInfoBasket_[i].weight;
            if (totalWeight > FixedTermStakingDefs.PRECISION) {
                revert FixedTermStakingDefs.InvalidValue("total weight of assets in basket");
            }
            if (IERC4626(newAssetsInfoBasket_[i].targetVault).asset() != UnderlyingTokenExchanger(addrs_[3])._token1())
            {
                revert FixedTermStakingDefs.VaultAssetNotEqualExchangerToken1(
                    IERC4626(newAssetsInfoBasket_[i].targetVault).asset(), UnderlyingTokenExchanger(addrs_[3])._token1()
                );
            }
            if (UnderlyingTokenExchanger(addrs_[3])._token0() != addrs_[1]) {
                revert FixedTermStakingDefs.ExchangerToken0NotEqualUnderlyingToken(
                    UnderlyingTokenExchanger(addrs_[3])._token0(), addrs_[1]
                );
            }
            assetsInfoBasket_.push(newAssetsInfoBasket_[i]);
        }
    }

    function stake(
        mapping(uint256 => FixedTermStakingDefs.StakeInfo) storage tokenId_stakeInfo_,
        mapping(uint64 => uint128) storage startDate_principal_,
        mapping(uint64 => uint128) storage maturityDate_principal_,
        FixedTermStakingDefs.AssetInfo[] storage assetsInfoBasket_,
        uint256[] storage timepoints_,
        /**
         * address from_,
         * address to_,
         * address underlyingToken_,
         * address exchanger_,
         */
        address[4] memory addrs_,
        /**
         * uint128 totalPrincipal_,
         * uint128 remainingBalance_,
         * uint128 totalFee_,
         * uint128 stakeAmount_,
         * uint128 dustBalance_,
         * uint128 maxSupply_,
         * uint128 tokenId_,
         * uint64 stakeFeeRate_,
         * uint64 lockPeriod_,
         */
        uint128[9] memory paras_
    )
        public
        returns (
            /**
             * uint128 updatedTotalPrincipal_,
             * uint128 updatedRemainingBalance_,
             * uint128 updatedTotalFee_,
             */
            uint128[3] memory results_,
            uint256[] memory updatedTimepoints_
        )
    {
        if (paras_[3] == 0) {
            revert FixedTermStakingDefs.InvalidValue("stakeAmount");
        }
        if (addrs_[0] == address(0)) {
            revert FixedTermStakingDefs.ZeroAddress("from");
        }
        if (addrs_[1] == address(0)) {
            revert FixedTermStakingDefs.ZeroAddress("to");
        }
        uint256 allowance = IERC20(addrs_[2]).allowance(addrs_[0], address(this));
        if (allowance < uint256(paras_[3])) {
            revert FixedTermStakingDefs.InsufficientAllowance(uint128(allowance), paras_[3]);
        }
        uint256 balance = IERC20(addrs_[2]).balanceOf(addrs_[0]);
        if (balance < uint256(paras_[3])) {
            revert FixedTermStakingDefs.InsufficientBalance(uint128(balance), paras_[3]);
        }

        uint128 fee = (paras_[3] * paras_[7] + FixedTermStakingDefs.PRECISION - 1) / FixedTermStakingDefs.PRECISION;
        uint128 amountAfterFee = paras_[3] - fee;

        if (paras_[0] + amountAfterFee > paras_[5]) {
            revert FixedTermStakingDefs.ExceedMaxSupply(amountAfterFee, paras_[0], paras_[5]);
        }
        if (paras_[1] < amountAfterFee || paras_[1] - amountAfterFee < paras_[4]) {
            revert FixedTermStakingDefs.BelowDustBalance(amountAfterFee, paras_[1], paras_[4]);
        }

        /// @dev calculate startDate and maturityDate
        uint64 startDate = uint64(block.timestamp).normalizeTimestamp();
        uint64 maturityDate = startDate + uint64(paras_[8]);

        if (startDate_principal_[startDate] == 0) {
            timepoints_.push(startDate);
        }
        if (maturityDate_principal_[maturityDate] == 0) {
            timepoints_.push(maturityDate);
        }

        updatedTimepoints_ = timepoints_;
        updatedTimepoints_ = updatedTimepoints_.sort();

        startDate_principal_[startDate] += amountAfterFee;
        maturityDate_principal_[maturityDate] += amountAfterFee;

        unchecked {
            results_[0] = paras_[0] + amountAfterFee;
            results_[1] = paras_[1] - amountAfterFee;
            results_[2] = paras_[2] + fee;
        }

        SafeERC20.safeTransferFrom(IERC20(addrs_[2]), addrs_[0], address(this), paras_[3]);

        tokenId_stakeInfo_[paras_[6]] = FixedTermStakingDefs.StakeInfo({
            principal: amountAfterFee,
            startDate: startDate,
            maturityDate: maturityDate,
            status: FixedTermStakingDefs.StakeStatus.ACTIVE
        });

        for (uint256 i = 0; i < assetsInfoBasket_.length; i++) {
            FixedTermStakingDefs.AssetInfo memory assetInfo = assetsInfoBasket_[i];
            uint128 assetAmount = UnderlyingTokenExchanger(addrs_[3]).dryrunExchange(
                (amountAfterFee * assetInfo.weight) / FixedTermStakingDefs.PRECISION, false
            );
            if (assetAmount > 0) {
                UnderlyingTokenExchanger(addrs_[3]).extractDepositTokenForInvestment(assetAmount);
                SafeERC20.safeIncreaseAllowance(
                    IERC20(UnderlyingTokenExchanger(addrs_[3])._token1()), assetInfo.targetVault, assetAmount
                );
                if (IERC4626(assetInfo.targetVault).deposit(assetAmount, address(this)) == 0) {
                    revert FixedTermStakingDefs.DepositFailed(assetAmount, 0, assetInfo.targetVault);
                }
            }
        }

        emit FixedTermStakingDefs.Stake(addrs_[0], addrs_[1], amountAfterFee, paras_[6]);
    }

    function unstake(
        mapping(uint256 => FixedTermStakingDefs.StakeInfo) storage tokenId_stakeInfo_,
        mapping(uint64 => int64) storage accumulatedInterestRate_,
        FixedTermStakingDefs.AssetInfo[] storage assetsInfoBasket_,
        /**
         * address from_,
         * address to_,
         * address tokenOwner_,
         * address underlyingToken_,
         * address exchanger_,
         */
        address[5] memory addrs_,
        /**
         * uint256 tokenId_,
         * uint128 totalPrincipal_,
         * uint128 remainingBalance_,
         * uint128 totalFee_,
         * int128 totalInterest_,
         * uint64 lastFeedTime_,
         * uint64 unstakeFeeRate_,
         * uint256 maxTokenId_
         */
        int256[8] memory paras_
    )
        public
        returns (
            /**
             * uint128 repayAmount_,
             * uint128 updatedTotalPrincipal_,
             * uint128 updatedRemainingBalance_,
             * uint128 updatedTotalFee_,
             * int128 updatedTotalInterest_,
             */
            int256[5] memory results_
        )
    {
        if (uint256(paras_[0]) == 0 || uint256(paras_[0]) >= uint256(paras_[7])) {
            revert FixedTermStakingDefs.InvalidValue("tokenId");
        }
        if (addrs_[0] == address(0)) {
            revert FixedTermStakingDefs.ZeroAddress("from");
        }
        if (addrs_[1] == address(0)) {
            revert FixedTermStakingDefs.ZeroAddress("to");
        }

        FixedTermStakingDefs.StakeInfo storage stakeInfo = tokenId_stakeInfo_[uint256(paras_[0])];

        if (stakeInfo.status == FixedTermStakingDefs.StakeStatus.NOT_EXISTED) {
            revert FixedTermStakingDefs.InvalidValue("tokenId");
        }

        if (stakeInfo.status == FixedTermStakingDefs.StakeStatus.CLOSED) {
            revert FixedTermStakingDefs.AlreadyUnstaked(uint256(paras_[0]));
        }

        if (addrs_[2] != addrs_[0]) {
            revert FixedTermStakingDefs.NotTokenOwner(addrs_[0], uint256(paras_[0]));
        }

        if (block.timestamp < stakeInfo.maturityDate) {
            revert FixedTermStakingDefs.StakeNotMatured(
                uint256(paras_[0]), stakeInfo.maturityDate, uint64(block.timestamp)
            );
        }

        if (stakeInfo.maturityDate > uint64(uint256(paras_[5]))) {
            revert FixedTermStakingDefs.WaitingForMaturityDateFeed();
        }

        int64 accumulatedInterestRateOnStartDate = accumulatedInterestRate_[stakeInfo.startDate];
        int64 accumulatedInterestRateOnMaturityDate = accumulatedInterestRate_[stakeInfo.maturityDate];

        int128 interest = int128(stakeInfo.principal)
            * (accumulatedInterestRateOnMaturityDate - accumulatedInterestRateOnStartDate)
            / SafeCast.toInt128(int256(uint256(FixedTermStakingDefs.PRECISION)));

        uint128 fee = int128(stakeInfo.principal) + interest < 0
            ? 0
            : (
                uint128(int128(stakeInfo.principal) + interest) * uint64(uint256(paras_[6]))
                    + FixedTermStakingDefs.PRECISION - 1
            ) / FixedTermStakingDefs.PRECISION;

        unchecked {
            results_[0] = int256(
                uint256(
                    int128(stakeInfo.principal) + interest < 0
                        ? 0
                        : uint128(int128(stakeInfo.principal) + interest) - fee
                )
            );
            results_[1] = int256(uint256(uint128(uint256(paras_[1])) - stakeInfo.principal));
            results_[2] = int256(uint256(uint128(uint256(paras_[2])) + stakeInfo.principal));
            results_[3] = int256(uint256(uint128(uint256(paras_[3])) + fee));
            results_[4] = int256(int128(paras_[4]) - interest);
        }

        stakeInfo.status = FixedTermStakingDefs.StakeStatus.CLOSED;

        uint256 assetNumberInBasket = assetsInfoBasket_.length;
        /// @dev Keep track of unprepared asset amount due to vault withdraw limit
        /// @dev This amount will be adjusted in the next asset withdraw
        /// @dev If unprepared asset amount is not zero after all assets withdraw, it means protocol loss
        /// @dev In such case, protocol should compensate the loss to exchanger later to make sure exchanger can repay user fully
        /// @dev Or protocol can adjust rate between underlying token and deposit token in exchanger to make up the loss
        /// @dev However, this means underlying token is unpegged from deposit token, which should be avoided if possible
        uint128 unpreparedAssetAmount = 0;
        for (uint256 i = 0; i < assetNumberInBasket; i++) {
            FixedTermStakingDefs.AssetInfo memory assetInfo = assetsInfoBasket_[i];
            /// @dev When user unstake a fixed-term staking, protocol should withdraw corresponding amount from each vault
            /// @dev The key issue is how much underlying token should be withdrawn from all vaults
            /// @dev We choose to only withdraw principal amount from each vaults by proportion, just like what we did when staking
            /// @dev No matter vaults value will decrease or increase later, protocol have settled with user immediately when user unstakes
            uint128 assetAmount = UnderlyingTokenExchanger(addrs_[4]).dryrunExchange(
                ((uint128(uint256(results_[0])) + fee) * assetInfo.weight + FixedTermStakingDefs.PRECISION - 1)
                    / FixedTermStakingDefs.PRECISION,
                false
            );
            /// @dev Check the maximum withdrawable amount from the vault
            uint128 maxAssetAmount = uint128(IERC4626(assetInfo.targetVault).maxWithdraw(address(this)));
            /// @dev Adjust the withdraw amount if it exceeds the maximum withdrawable amount
            /// @dev This may happen when asset portfolio is modified, e.g. one asset's weight is increased significantly after this stake
            /// @dev In this case, protocol should follow the new strategy and be responsible for the loss or profit
            if (assetAmount > maxAssetAmount) {
                unpreparedAssetAmount += (assetAmount - maxAssetAmount);

                assetAmount = maxAssetAmount;
            } else if (assetAmount + unpreparedAssetAmount > maxAssetAmount) {
                unpreparedAssetAmount -= (maxAssetAmount - assetAmount);

                assetAmount = maxAssetAmount;
            } else {
                assetAmount += unpreparedAssetAmount;

                unpreparedAssetAmount = 0;
            }
            if (assetAmount > 0) {
                /// @dev Withdraw asset from each vault where owner is this contract and receiver is the exchanger contract
                /// @dev User will retrieve assets from exchanger contract later
                uint128 sharesAmount =
                    uint128(IERC4626(assetInfo.targetVault).withdraw(assetAmount, addrs_[4], address(this)));

                if (sharesAmount == 0) {
                    revert FixedTermStakingDefs.WithdrawFailed(assetAmount, 0, assetInfo.targetVault);
                }
            }
        }

        /// @dev If there is still unprepared asset amount due to vault withdraw limits
        /// @dev Try to withdraw the unprepared amount from other vaults again
        if (unpreparedAssetAmount > 0) {
            for (uint256 i = 0; i < assetNumberInBasket; i++) {
                FixedTermStakingDefs.AssetInfo memory assetInfo = assetsInfoBasket_[i];
                /// @dev Check the maximum withdrawable amount from the vault
                uint128 maxAssetAmount = uint128(IERC4626(assetInfo.targetVault).maxWithdraw(address(this)));
                if (maxAssetAmount >= unpreparedAssetAmount) {
                    if (IERC4626(assetInfo.targetVault).withdraw(unpreparedAssetAmount, addrs_[4], address(this)) == 0)
                    {
                        revert FixedTermStakingDefs.WithdrawFailed(unpreparedAssetAmount, 0, assetInfo.targetVault);
                    }
                    unpreparedAssetAmount = 0;

                    break;
                } else if (maxAssetAmount > 0) {
                    if (IERC4626(assetInfo.targetVault).withdraw(maxAssetAmount, addrs_[4], address(this)) == 0) {
                        revert FixedTermStakingDefs.WithdrawFailed(maxAssetAmount, 0, assetInfo.targetVault);
                    }
                    unpreparedAssetAmount -= maxAssetAmount;
                }
            }
        }

        if (unpreparedAssetAmount > 0) {
            /// @dev Emit event to warn off-chain monitoring system
            /// @dev Protocl should top-up equivalent amount of asset tokens to exchanger to avoid unpegging risk
            emit FixedTermStakingDefs.UnderlyingTokenUnpeggedRisk(unpreparedAssetAmount);
        }

        /// @dev After withdrawing from all vaults, we repay underlying tokens to user
        /// @dev User will retrieve assets from exchanger contract later
        if (results_[0] > 0) {
            SafeERC20.safeTransfer(IERC20(addrs_[3]), addrs_[1], uint256(results_[0]));
        }

        emit FixedTermStakingDefs.Unstake(addrs_[0], addrs_[1], stakeInfo.principal, interest, uint256(paras_[0]));
    }

    function feed(
        mapping(uint64 => int64) storage accumulatedInterestRate_,
        mapping(uint64 => uint128) storage startDate_principal_,
        mapping(uint64 => uint128) storage maturityDate_principal_,
        uint256[] storage timepoints_,
        uint64 timestamp_,
        bool force_,
        uint64 lastFeedTime_,
        int128 interest_,
        int128 totalInterest_,
        address underlyingToken_
    ) public returns (bool dividends_, uint64 updatedLastFeedTime_, int128 updatedTotalInterest_) {
        uint64 normalizedTimestamp = timestamp_.normalizeTimestamp();
        uint128 interestBearingPrincipal;

        /// @dev Only allow to force feed at last feed time or normal feed at next day
        if (
            /// @dev Duplicated feeds at the same day require force
            /// @dev Normal feed at next day does not require force
            /// @dev Advanced feed before next day is not allowed
            (normalizedTimestamp == lastFeedTime_ && force_)
                || (normalizedTimestamp == lastFeedTime_ + 1 days && block.timestamp >= normalizedTimestamp)
        ) {
            /// @dev Calculate interest bearing principal at normalizedTimestamp
            /// @dev Sum up all principals that started before or on normalizedTimestamp and not yet matured
            interestBearingPrincipal = timepoints_.calculateInterestBearingPrincipal(
                startDate_principal_, maturityDate_principal_, normalizedTimestamp
            );
            if (interestBearingPrincipal == 0) {
                accumulatedInterestRate_[normalizedTimestamp] = accumulatedInterestRate_[lastFeedTime_];

                /// @dev Unnecessary to calculate interest rate when there is no interest bearing principal
                /// @dev Because you can not divide interest by zero
                /// @dev Thus unnecessary to calculate interest amount either
                updatedLastFeedTime_ = normalizedTimestamp;

                if (interest_ < 0) {
                    /// @dev Vaults value decreased, pool lost money
                    interest_ = -interest_;

                    /// @dev Check pool reserve before burning underlying tokens
                    /// @dev This balance includes fees collected
                    uint128 fixedTermStakingHoldUnderlyingTokenBalance =
                        uint128(IERC20(underlyingToken_).balanceOf(address(this)));

                    if (uint128(interest_) > fixedTermStakingHoldUnderlyingTokenBalance) {
                        /// @dev Not enough underlying tokens to burn, just burn what we have
                        /// @dev This should never happen under normal circumstances
                        /// @dev unless there are bad guys attack the pool or vault and steal underlying tokens
                        /// @dev In such case, protocol should contribute all fees collected to compensate the loss
                        interest_ = int128(fixedTermStakingHoldUnderlyingTokenBalance);
                    }

                    if (interest_ > 0) {
                        UnderlyingToken(underlyingToken_).burn(uint256(uint128(interest_)));

                        emit FixedTermStakingDefs.Feed(updatedLastFeedTime_, -interest_);

                        dividends_ = true;
                    }
                } else if (interest_ > 0) {
                    /// @dev Vaults value increased, pool earned money
                    UnderlyingToken(underlyingToken_).mint(address(this), uint256(uint128(interest_)));

                    emit FixedTermStakingDefs.Feed(updatedLastFeedTime_, interest_);

                    dividends_ = true;
                } else {
                    emit FixedTermStakingDefs.Feed(updatedLastFeedTime_, 0);

                    dividends_ = false;
                }

                /// @dev Update total interest
                updatedTotalInterest_ = totalInterest_ + interest_;
            } else {
                /// @dev Calculate interest earned or lost since last feed time
                //int128 interest = int128(totalAssetValueInBasket_) - int128(totalPrincipal_) - int128(totalInterest_);
                /// @dev Calculate interest rate per day in base points (1_000_000 = 100%)
                int64 interestRate =
                    int64(interest_ * int128(int64(FixedTermStakingDefs.PRECISION)) / int128(interestBearingPrincipal));
                /// @dev Prevent malicious oracle feed to asset vaults which may cause unbelievable interest rate
                if (
                    interestRate >= FixedTermStakingDefs.MAX_INTEREST_RATE_PER_DAY
                        || interestRate <= FixedTermStakingDefs.MIN_INTEREST_RATE_PER_DAY
                ) {
                    revert FixedTermStakingDefs.UnbelievableInterestRate(
                        interestRate,
                        FixedTermStakingDefs.MAX_INTEREST_RATE_PER_DAY,
                        FixedTermStakingDefs.MIN_INTEREST_RATE_PER_DAY
                    );
                }
                /// @dev Update accumulated interest rate at normalizedTimestamp
                accumulatedInterestRate_[normalizedTimestamp] = accumulatedInterestRate_[lastFeedTime_] + interestRate;

                /// @dev Update last feed time
                updatedLastFeedTime_ = normalizedTimestamp;

                if (interest_ < 0) {
                    /// @dev Vaults value decreased, pool lost money
                    interest_ = -interest_;

                    /// @dev Check pool reserve before burning underlying tokens
                    /// @dev This balance includes fees collected
                    uint128 fixedTermStakingHoldUnderlyingTokenBalance =
                        uint128(IERC20(underlyingToken_).balanceOf(address(this)));

                    if (uint128(interest_) > fixedTermStakingHoldUnderlyingTokenBalance) {
                        /// @dev Not enough underlying tokens to burn, just burn what we have
                        /// @dev This should never happen under normal circumstances
                        /// @dev unless there are bad guys attack the pool or vault and steal underlying tokens
                        /// @dev In such case, protocol should contribute all fees collected to compensate the loss
                        interest_ = int128(fixedTermStakingHoldUnderlyingTokenBalance);
                    }

                    if (interest_ > 0) {
                        UnderlyingToken(underlyingToken_).burn(uint256(uint128(interest_)));

                        emit FixedTermStakingDefs.Feed(updatedLastFeedTime_, -interest_);

                        dividends_ = true;
                    }
                } else if (interest_ > 0) {
                    /// @dev Vaults value increased, pool earned money
                    UnderlyingToken(underlyingToken_).mint(address(this), uint256(uint128(interest_)));

                    emit FixedTermStakingDefs.Feed(updatedLastFeedTime_, interest_);

                    dividends_ = true;
                } else {
                    emit FixedTermStakingDefs.Feed(updatedLastFeedTime_, 0);

                    dividends_ = false;
                }

                /// @dev Update total interest
                updatedTotalInterest_ = totalInterest_ + interest_;
            }
        }
        /// @dev Handle invalid feeding attempts
        else {
            /// @dev Attempt to feed at an ancient time (before last feed time)
            if (normalizedTimestamp < lastFeedTime_) {
                revert FixedTermStakingDefs.AncientFeedTimeUpdateIsNotAllowed(
                    normalizedTimestamp, lastFeedTime_, uint64(block.timestamp)
                );
            }

            /// @dev Attempt to feed at last feed time without force (only controller can force feed)
            if ((normalizedTimestamp == lastFeedTime_ || accumulatedInterestRate_[normalizedTimestamp] != 0) && !force_)
            {
                revert FixedTermStakingDefs.LastFeedTimeUpdateRequireForce(
                    normalizedTimestamp, lastFeedTime_, uint64(block.timestamp)
                );
            }

            /// @dev Attempt to feed at a future time beyond next day
            if (!(normalizedTimestamp == lastFeedTime_ + 1 days && block.timestamp >= normalizedTimestamp)) {
                revert FixedTermStakingDefs.FutureFeedTimeUpdateIsNotAllowed(
                    normalizedTimestamp, lastFeedTime_, uint64(block.timestamp)
                );
            }

            /// @dev This case should never happen
            revert("Unrecognized condition!");
        }
    }
}
