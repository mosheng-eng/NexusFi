// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IWhitelist} from "src/whitelist/IWhitelist.sol";
import {UnderlyingTokenExchanger} from "src/underlying/UnderlyingTokenExchanger.sol";
import {FixedTermStakingDefs} from "src/protocols/lender/fixed-term/utils/FixedTermStakingDefs.sol";

//import {console} from "forge-std/Test.sol";

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
        returns (uint128 totalValue_, uint128[] memory valueOfEachVaults_)
    {
        uint256 assetNumberInBasket = assetsInfoBasket_.length;
        valueOfEachVaults_ = new uint128[](assetNumberInBasket);
        for (uint256 i = 0; i < assetNumberInBasket; i++) {
            FixedTermStakingDefs.AssetInfo memory assetInfo = assetsInfoBasket_[i];
            valueOfEachVaults_[i] = UnderlyingTokenExchanger(exchanger_).dryrunExchange(
                uint128(IERC4626(assetInfo.targetVault).maxWithdraw(address(this))), true
            );
            totalValue_ += valueOfEachVaults_[i];
        }
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
        //        console.log("timestamp_", timestamp_);
        uint256[] memory timepoints = timepoints_;
        uint256 idx = timepoints.upperBoundMemory(uint256(timestamp_));
        for (uint256 i = 0; i < idx; ++i) {
            interestBearingPrincipal_ = interestBearingPrincipal_ + startDate_principal_[uint64(timepoints[i])]
                - maturityDate_principal_[uint64(timepoints[i])];
        }
        //        console.log("interestBearingPrincipal_", interestBearingPrincipal_);
    }

    function normalizeTimestamp(uint64 timestamp_) public pure returns (uint64 normalizedTimestamp_) {
        normalizedTimestamp_ = uint64(((timestamp_ + 17 hours) / 1 days) * 1 days + 7 hours);
    }

    function updateInterestDifferenceOfNeighboringVaults(
        FixedTermStakingDefs.AssetInfo[] storage assetsInfoBasket_,
        mapping(address => mapping(uint64 => int128)) storage dailyInterestDifferenceOfNeighboringVaults_,
        uint128[] memory valueOfEachVaults_,
        uint64 normalizedTimestamp_
    ) public {
        uint256 len = assetsInfoBasket_.length;
        if (valueOfEachVaults_.length != len) {
            revert FixedTermStakingDefs.InvalidValue("require value of all vaults in basket");
        }
        for (uint256 i = 0; i < len; i++) {
            uint256 preIndex = _preIndex(i, len);
            FixedTermStakingDefs.AssetInfo memory assetInfo = assetsInfoBasket_[i];
            int128 interestDifference = (int128(valueOfEachVaults_[i]) - int128(assetInfo.lastAssetValue))
                - (int128(valueOfEachVaults_[preIndex]) - int128(assetsInfoBasket_[preIndex].lastAssetValue));
            dailyInterestDifferenceOfNeighboringVaults_[assetInfo.targetVault][normalizedTimestamp_] +=
                interestDifference;
        }
        for (uint256 i = 0; i < len; i++) {
            assetsInfoBasket_[i].lastAssetValue = valueOfEachVaults_[i];
        }
    }

    /// @dev Split the interest to each vault in the basket according to the interest difference records of neighboring vaults when feeding interest
    /// @dev interest difference should be summed up from start date to maturity date and ordered the same as the vault order in the basket
    /// @param interest_ the total interest to be split into each vault
    /// @param sumOfInterestDifference_ the sum of interest difference of neighboring vaults from start date to maturity date, ordered the same as the vault order in the basket
    /// @return interestCollectedFromEachVaults_ the interest from each vault, ordered the same as the vault order in the basket
    function collectInterestFromAllVaults(int128 interest_, int128[] memory sumOfInterestDifference_)
        public
        pure
        returns (int128[] memory interestCollectedFromEachVaults_)
    {
        uint256 len = sumOfInterestDifference_.length;
        if (len == 0) {
            return new int128[](0);
        }

        interestCollectedFromEachVaults_ = new int128[](len);

        for (uint256 i = 0; i < len; i++) {
            uint256 coefficient = len - 1;
            int128 originalInterest = interest_;
            for (uint256 j = _nextIndex(i, len); j != i; j = _nextIndex(j, len)) {
                originalInterest -= int128(int256(coefficient--)) * sumOfInterestDifference_[j];
            }
            interestCollectedFromEachVaults_[i] = originalInterest / int128(int256(len));
        }
    }

    /// @dev Get the pre index of the specified index in a circular array with the specified length, which is used to find the neighbor vaults in the basket
    /// @param index_ the specified index in the circular array
    /// @param length_ the length of the circular array
    /// @return the pre index of the specified index in the circular array
    function _preIndex(uint256 index_, uint256 length_) internal pure returns (uint256) {
        if (length_ == 0) {
            revert FixedTermStakingDefs.InvalidValue("length is zero");
        }
        return (index_ + length_ - 1) % length_;
    }

    /// @dev Get the next index of the specified index in a circular array with the specified length, which is used to find the neighbor vaults in the basket
    /// @param index_ the specified index in the circular array
    /// @param length_ the length of the circular array
    /// @return the next index of the specified index in the circular array
    function _nextIndex(uint256 index_, uint256 length_) internal pure returns (uint256) {
        if (length_ == 0) {
            revert FixedTermStakingDefs.InvalidValue("length is zero");
        }
        return (index_ + 1) % length_;
    }
}
