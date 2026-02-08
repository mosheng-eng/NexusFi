// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {FixedTermStaking} from "src/protocols/lender/fixed-term/FixedTermStaking.sol";

contract TempTest is Test {
    address internal _investor;
    FixedTermStaking internal _fixedTermStaking;

    function setUp() public {
        _investor = address(0xF265639351621C68867d089d95c14a1f0edBfB48);
        _fixedTermStaking = FixedTermStaking(address(0x751aadf0E0e313CcE119eaD623F6Dd327e7969B8));
    }

    function testTemp() public {
        vm.prank(_investor);
        _fixedTermStaking.unstake(1);
    }
}
