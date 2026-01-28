// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IWhitelist} from "src/whitelist/IWhitelist.sol";
import {UnderlyingTokenExchanger} from "src/underlying/UnderlyingTokenExchanger.sol";
import {OpenTermStakingDefs} from "src/protocols/lender/open-term/utils/OpenTermStakingDefs.sol";

library OpenTermStakingLibs {
    function addNewAssetIntoBasket(
        OpenTermStakingDefs.AssetInfo[] storage assetsInfoBasket_,
        OpenTermStakingDefs.AssetInfo[] calldata newAssetInfo_,
        address exchanger_
    ) public {
        if (newAssetInfo_.length == 0) {
            revert OpenTermStakingDefs.InvalidValue("empty newAssetInfo");
        }
        uint64 totalWeight = 0;
        for (uint256 i = 0; i < assetsInfoBasket_.length; i++) {
            totalWeight += assetsInfoBasket_[i].weight;
        }
        for (uint256 i = 0; i < newAssetInfo_.length; i++) {
            if (newAssetInfo_[i].targetVault == address(0)) {
                revert OpenTermStakingDefs.ZeroAddress("new asset's vault");
            }
            if (newAssetInfo_[i].weight == 0 || newAssetInfo_[i].weight > OpenTermStakingDefs.PRECISION) {
                revert OpenTermStakingDefs.InvalidValue("weight of new asset in basket");
            }
            totalWeight += newAssetInfo_[i].weight;
            if (totalWeight > OpenTermStakingDefs.PRECISION) {
                revert OpenTermStakingDefs.InvalidValue("total weight of assets in basket and new assets");
            }
            if (IERC4626(newAssetInfo_[i].targetVault).asset() != UnderlyingTokenExchanger(exchanger_)._token1()) {
                revert OpenTermStakingDefs.VaultAssetNotEqualExchangerToken1(
                    IERC4626(newAssetInfo_[i].targetVault).asset(), UnderlyingTokenExchanger(exchanger_)._token1()
                );
            }
            assetsInfoBasket_.push(newAssetInfo_[i]);
        }
    }

    function totalAssetValueInBasket(OpenTermStakingDefs.AssetInfo[] storage assetsInfoBasket_, address exchanger_)
        public
        view
        returns (uint128 totalValue_)
    {
        uint256 assetNumberInBasket = assetsInfoBasket_.length;
        for (uint256 i = 0; i < assetNumberInBasket; i++) {
            OpenTermStakingDefs.AssetInfo memory assetInfo = assetsInfoBasket_[i];
            totalValue_ += uint128(IERC4626(assetInfo.targetVault).maxWithdraw(address(this)));
        }
        return UnderlyingTokenExchanger(exchanger_).dryrunExchange(totalValue_, true);
    }

    function onlyWhitelisted(address whitelist_, address who_) public view {
        if (whitelist_ == address(0)) {
            revert OpenTermStakingDefs.ZeroAddress("whitelist");
        }
        if (who_ == address(0)) {
            revert OpenTermStakingDefs.ZeroAddress("user");
        }
        if (!IWhitelist(whitelist_).isWhitelisted(who_)) {
            revert IWhitelist.NotWhitelisted(who_);
        }
    }

    function onlyInitialized(
        OpenTermStakingDefs.AssetInfo[] storage assetsInfoBasket_,
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
            revert OpenTermStakingDefs.Uninitialized("underlyingToken");
        }
        if (addrs_[1] == address(0)) {
            revert OpenTermStakingDefs.Uninitialized("whitelist");
        }
        if (addrs_[2] == address(0)) {
            revert OpenTermStakingDefs.Uninitialized("exchanger");
        }
        if (paras_[0] == 0) {
            revert OpenTermStakingDefs.Uninitialized("maxSupply");
        }
        if (paras_[1] == 0) {
            revert OpenTermStakingDefs.Uninitialized("lastFeedTime");
        }
        if (assetsInfoBasket_.length == 0) {
            revert OpenTermStakingDefs.Uninitialized("assetsInfoBasket");
        }
    }

    function normalizeTimestamp(uint64 timestamp_) public pure returns (uint64 normalizedTimestamp_) {
        normalizedTimestamp_ = uint64(((timestamp_ + 17 hours) / 1 days) * 1 days + 7 hours);
    }
}
