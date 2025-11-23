// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {BLSHelper} from "src/multisig/utils/BLSHelper.sol";
import {BLS} from "src/multisig/utils/BLS.sol";

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

contract BLSHelperTest is Test {
    function setUp() public pure {
        console.log("Nothing to set up");
    }

    function testFuzzHashToFp(bytes32 input_) public view {
        bytes[] memory fps = BLSHelper.hashToFp(abi.encodePacked(input_), BLS.BLS_DOMAIN, 2);
        assertEq(fps.length, 2);
    }

    function testFuzzHashToFp2(bytes32 input_) public view {
        bytes[] memory fp2s = BLSHelper.hashToFp2(abi.encodePacked(input_), BLS.BLS_DOMAIN, 2);
        assertEq(fp2s.length, 2);
    }

    function testRevert() public {
        vm.expectRevert(abi.encodeWithSelector(BLSHelper.EllTooLarge.selector, uint256(256)));
        BLSHelper.hashToFp(abi.encodePacked("Please revert!"), BLS.BLS_DOMAIN, 128);
        vm.expectRevert(abi.encodeWithSelector(BLSHelper.EllTooLarge.selector, uint64(256)));
        BLSHelper.hashToFp2(abi.encodePacked("Please revert!"), BLS.BLS_DOMAIN, 64);

        string memory longDST = vm.toString(new bytes(256));

        vm.expectRevert(abi.encodeWithSelector(BLSHelper.DSTTooLong.selector, uint256(514)));
        BLSHelper.expandMessageXMD(abi.encodePacked("Please revert!"), longDST, uint16(256));
    }
}
