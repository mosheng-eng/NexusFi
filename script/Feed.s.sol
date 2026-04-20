// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

import {FixedTermStaking} from "src/protocols/lender/fixed-term/FixedTermStaking.sol";
import {OpenTermStaking} from "src/protocols/lender/open-term/OpenTermStaking.sol";

contract Feed is Script {
    FixedTermStaking internal _fixedTermStaking;
    OpenTermStaking internal _openTermStaking;

    function run() external {
        _openTermStaking = OpenTermStaking(vm.envAddress("OPEN_TERM_STAKING"));
        _fixedTermStaking = FixedTermStaking(vm.envAddress("FIXED_TERM_STAKING"));

        uint64 lastFeedTime = _openTermStaking._lastFeedTime();

        vm.startBroadcast();

        while (block.timestamp - lastFeedTime > 1 days) {
            _openTermStaking.feed(lastFeedTime + 1);
            lastFeedTime = _openTermStaking._lastFeedTime();
        }

        vm.stopBroadcast();

        lastFeedTime = _fixedTermStaking._lastFeedTime();

        vm.startBroadcast();

        while (block.timestamp - lastFeedTime > 1 days) {
            _fixedTermStaking.feed(lastFeedTime + 1);
            lastFeedTime = _fixedTermStaking._lastFeedTime();
        }

        vm.stopBroadcast();
    }
}
