// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IWhitelist} from "src/whitelist/IWhitelist.sol";
import {UnderlyingTokenExchanger} from "src/underlying/UnderlyingTokenExchanger.sol";
import {FixedTermStakingDefs} from "src/protocols/lender/fixed-term/utils/FixedTermStakingDefs.sol";

library FixedTermStakingLibs {
    using Arrays for uint256[];

    function addNewAssetIntoBasket(
        FixedTermStakingDefs.AssetInfo[] storage assetsInfoBasket_,
        FixedTermStakingDefs.AssetInfo[] calldata newAssetInfo_,
        address exchanger_
    ) public {
        if (newAssetInfo_.length == 0) {
            revert FixedTermStakingDefs.InvalidValue("empty newAssetInfo");
        }
        uint64 totalWeight = 0;
        for (uint256 i = 0; i < assetsInfoBasket_.length; i++) {
            totalWeight += assetsInfoBasket_[i].weight;
        }
        for (uint256 i = 0; i < newAssetInfo_.length; i++) {
            if (newAssetInfo_[i].targetVault == address(0)) {
                revert FixedTermStakingDefs.ZeroAddress("new asset's vault");
            }
            if (newAssetInfo_[i].weight == 0 || newAssetInfo_[i].weight > FixedTermStakingDefs.PRECISION) {
                revert FixedTermStakingDefs.InvalidValue("weight of new asset in basket");
            }
            totalWeight += newAssetInfo_[i].weight;
            if (totalWeight > FixedTermStakingDefs.PRECISION) {
                revert FixedTermStakingDefs.InvalidValue("total weight of assets in basket and new assets");
            }
            if (IERC4626(newAssetInfo_[i].targetVault).asset() != UnderlyingTokenExchanger(exchanger_)._token1()) {
                revert FixedTermStakingDefs.VaultAssetNotEqualExchangerToken1(
                    IERC4626(newAssetInfo_[i].targetVault).asset(), UnderlyingTokenExchanger(exchanger_)._token1()
                );
            }
            assetsInfoBasket_.push(newAssetInfo_[i]);
        }
    }

    function totalAssetValueInBasket(FixedTermStakingDefs.AssetInfo[] storage assetsInfoBasket_, address exchanger_)
        public
        view
        returns (uint128 totalValue_)
    {
        uint256 assetNumberInBasket = assetsInfoBasket_.length;
        for (uint256 i = 0; i < assetNumberInBasket; i++) {
            FixedTermStakingDefs.AssetInfo memory assetInfo = assetsInfoBasket_[i];
            totalValue_ += uint128(IERC4626(assetInfo.targetVault).maxWithdraw(address(this)));
        }
        return UnderlyingTokenExchanger(exchanger_).dryrunExchange(totalValue_, true);
    }

    function onlyWhitelisted(address whitelist_, address who_) public view {
        if (whitelist_ == address(0)) {
            revert FixedTermStakingDefs.ZeroAddress("whitelist");
        }
        if (who_ == address(0)) {
            revert FixedTermStakingDefs.ZeroAddress("user");
        }
        if (!IWhitelist(whitelist_).isWhitelisted(who_)) {
            revert IWhitelist.NotWhitelisted(who_);
        }
    }

    function onlyInitialized(
        FixedTermStakingDefs.AssetInfo[] storage assetsInfoBasket_,
        /**
         * address _underlyingToken,
         * address _whitelist,
         * address _exchanger,
         */
        address[3] memory addrs_,
        /**
         * uint64 _lockPeriod,
         * uint128 _maxSupply,
         * uint64 _lastFeedTime
         */
        uint128[3] memory paras_
    ) public view {
        if (addrs_[0] == address(0)) {
            revert FixedTermStakingDefs.Uninitialized("underlyingToken");
        }
        if (addrs_[1] == address(0)) {
            revert FixedTermStakingDefs.Uninitialized("whitelist");
        }
        if (addrs_[2] == address(0)) {
            revert FixedTermStakingDefs.Uninitialized("exchanger");
        }
        if (paras_[0] == 0) {
            revert FixedTermStakingDefs.Uninitialized("lockPeriod");
        }
        if (paras_[1] == 0) {
            revert FixedTermStakingDefs.Uninitialized("maxSupply");
        }
        if (paras_[2] == 0) {
            revert FixedTermStakingDefs.Uninitialized("lastFeedTime");
        }
        if (assetsInfoBasket_.length == 0) {
            revert FixedTermStakingDefs.Uninitialized("assetsInfoBasket");
        }
    }

    function calculateInterestBearingPrincipal(
        uint256[] storage timepoints_,
        mapping(uint64 => uint128) storage startDate_principal_,
        mapping(uint64 => uint128) storage maturityDate_principal_,
        uint64 timestamp_
    ) public view returns (uint128 interestBearingPrincipal_) {
        uint64 normalizedTimestamp = normalizeTimestamp(timestamp_);
        uint256[] memory timepoints = timepoints_;
        uint256 idx = timepoints.upperBoundMemory(uint256(normalizedTimestamp));
        for (uint256 i = 0; i < idx; ++i) {
            interestBearingPrincipal_ = interestBearingPrincipal_ + startDate_principal_[uint64(timepoints[i])]
                - maturityDate_principal_[uint64(timepoints[i])];
        }
    }

    function normalizeTimestamp(uint64 timestamp_) public pure returns (uint64 normalizedTimestamp_) {
        normalizedTimestamp_ = uint64(((timestamp_ + 17 hours) / 1 days) * 1 days + 7 hours);
    }
}
