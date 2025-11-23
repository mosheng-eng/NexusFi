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
    }

    function invariantTotalInterestBearingAlwaysEqualTotalAssetsValueAfterFeed() public {
        _currentTime = _openTermStakingHandler.getCurrentTime();

        require(_currentTime == 1759301999, "should be 2025-10-01 14:59:59 UTC+8 "); // 2025-10-01 14:59:59 UTC+8

        vm.warp((_currentTime += 1 days) + 1 minutes);

        _openTermStaking.feed(_currentTime);

        assertEq(
            _openTermStaking._totalInterestBearing(),
            uint128(_openTermStaking.getTotalAssetValueInBasket()),
            "Total interest bearing should always equal total asset value after feed"
        );
    }
}
