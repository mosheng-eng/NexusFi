// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {OpenTermStakingHandler} from "test/protocols/lender/open-term/handler/OpenTermStakingHandler.sol";
import {OpenTermStaking} from "src/protocols/lender/open-term/OpenTermStaking.sol";

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

contract OpenTermStakingInvariant is Test {
    OpenTermStakingHandler internal _openTermStakingHandler;
    OpenTermStaking internal _openTermStaking;

    uint64 internal _currentTime;

    function setUp() public {
        _openTermStakingHandler = new OpenTermStakingHandler();
        _openTermStaking = _openTermStakingHandler.getOpenTermStaking();
        _currentTime = _openTermStakingHandler.getCurrentTime();
        console.log("current time at setUp:", _currentTime);
        bytes4[] memory targetSelectors = new bytes4[](3);
        targetSelectors[0] = OpenTermStakingHandler.stake.selector;
        targetSelectors[1] = OpenTermStakingHandler.unstake.selector;
        targetSelectors[2] = OpenTermStakingHandler.updateVaultNAV.selector;
        targetSelector(StdInvariant.FuzzSelector({addr: address(_openTermStakingHandler), selectors: targetSelectors}));
        targetContract(address(_openTermStakingHandler));
        console.log("setup finished");
    }

    function invariantTotalInterestBearingAlwaysEqualTotalAssetsValueAfterFeed() public {
        uint64 lastFeedTime = _openTermStaking._lastFeedTime();

        _openTermStaking.feedForce(lastFeedTime - 1);

        /// @dev allow 100 units of error due to price floating and rounding
        assertLe(
            _abs(_openTermStaking._totalInterestBearing(), uint128(_openTermStaking.getTotalAssetValueInBasket())), 100
        );
    }

    function _abs(uint256 a_, uint256 b_) internal pure returns (uint256) {
        return a_ >= b_ ? a_ - b_ : b_ - a_;
    }

    function _normalizeTimestamp(uint64 timestamp_) internal pure returns (uint64 normalizedTimestamp_) {
        normalizedTimestamp_ = uint64(((timestamp_ + 17 hours) / 1 days) * 1 days + 7 hours);
    }
}
