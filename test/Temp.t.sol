// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {FixedTermStaking} from "src/protocols/lender/fixed-term/FixedTermStaking.sol";

contract TempTest is Test {
    address internal _investor;
    FixedTermStaking internal _fixedTermStaking;

    function setUp() public {
        _investor = vm.envAddress("NEXUSFI_OWNER");
        _fixedTermStaking = FixedTermStaking(vm.envAddress("FIXED_TERM_STAKING"));

        vm.label(_investor, "Investor");
        vm.label(address(_fixedTermStaking), "FixedTermStaking");
    }

    function testTemp() public {
        vm.prank(_investor);
        _fixedTermStaking.unstake(1);
    }
}
