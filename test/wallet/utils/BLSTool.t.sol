// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {BLSTool} from "src/wallet/utils/BLSTool.sol";

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

contract BLSToolTest is Test {
    function setUp() public pure {
        console.log("Nothing to set up");
    }

    function testSecretKeysNotMatchMessagesLength() public {
        vm.expectRevert(BLSTool.SecretKeysNotMatchMessagesLength.selector);
        BLSTool.buildSIGsOnG1(new uint256[](1), new bytes[](2));
        vm.expectRevert(BLSTool.SecretKeysNotMatchMessagesLength.selector);
        BLSTool.buildSIGsOnG2(new uint256[](1), new bytes[](2));
    }
}
