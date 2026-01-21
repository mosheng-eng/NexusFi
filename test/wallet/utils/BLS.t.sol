// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {BLS} from "src/wallet/utils/BLS.sol";

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

contract BLSTest is Test {
    function setUp() public pure {
        console.log("Nothing to set up");
    }

    function testSumEmptyPoints() public {
        vm.expectRevert(BLS.EmptyPointsToSum.selector);
        BLS.sumPointsOnG1(new BLS.G1Point[](0));
        vm.expectRevert(BLS.EmptyPointsToSum.selector);
        BLS.sumPointsOnG2(new BLS.G2Point[](0));
    }

    function testSumValidPoints() public view {
        BLS.G1Point[] memory pointsOnG1 = new BLS.G1Point[](2);
        pointsOnG1[0] = BLS.hashToG1(BLS.BLS_DOMAIN, abi.encodePacked("point1"));
        pointsOnG1[1] = BLS.hashToG1(BLS.BLS_DOMAIN, abi.encodePacked("point2"));
        BLS.sumPointsOnG1(pointsOnG1);
        BLS.add(pointsOnG1[0], pointsOnG1[1]);

        BLS.G2Point[] memory pointsOnG2 = new BLS.G2Point[](2);
        pointsOnG2[0] = BLS.hashToG2(BLS.BLS_DOMAIN, abi.encodePacked("point1"));
        pointsOnG2[1] = BLS.hashToG2(BLS.BLS_DOMAIN, abi.encodePacked("point2"));
        BLS.sumPointsOnG2(pointsOnG2);
        BLS.add(pointsOnG2[0], pointsOnG2[1]);
    }

    function testSumPointsFailed() public {
        BLS.G1Point[] memory pointsOnG1 = new BLS.G1Point[](2);
        pointsOnG1[0] = BLS.hashToG1(BLS.BLS_DOMAIN, abi.encodePacked("point1"));
        pointsOnG1[1] = BLS.hashToG1(BLS.BLS_DOMAIN, abi.encodePacked("point2"));
        vm.mockCallRevert(BLS.G1_ADD, abi.encodeWithSelector(0x00000000), abi.encode(uint256(0)));
        vm.expectRevert(BLS.SumPointsFailed.selector);
        BLS.sumPointsOnG1(pointsOnG1);
        vm.clearMockedCalls();

        BLS.G2Point[] memory pointsOnG2 = new BLS.G2Point[](2);
        pointsOnG2[0] = BLS.hashToG2(BLS.BLS_DOMAIN, abi.encodePacked("point1"));
        pointsOnG2[1] = BLS.hashToG2(BLS.BLS_DOMAIN, abi.encodePacked("point2"));
        vm.mockCallRevert(BLS.G2_ADD, abi.encodeWithSelector(0x00000000), abi.encode(uint256(0)));
        vm.expectRevert(BLS.SumPointsFailed.selector);
        BLS.sumPointsOnG2(pointsOnG2);
        vm.clearMockedCalls();
    }

    function testHashToPointFailed() public {
        vm.mockCallRevert(BLS.MAP_FP_TO_G1, abi.encodeWithSelector(0x00000000), abi.encode(uint256(0)));
        vm.expectRevert(BLS.HashToFpFailed.selector);
        BLS.hashToG1(BLS.BLS_DOMAIN, abi.encodePacked("point1"));
        vm.clearMockedCalls();

        vm.mockCallRevert(BLS.MAP_FP2_TO_G2, abi.encodeWithSelector(0x00000000), abi.encode(uint256(0)));
        vm.expectRevert(BLS.HashToFp2Failed.selector);
        BLS.hashToG2(BLS.BLS_DOMAIN, abi.encodePacked("point1"));
        vm.clearMockedCalls();
    }

    function testScalarMulPointsFailed() public {
        BLS.G1Point memory pointOnG1 = BLS.hashToG1(BLS.BLS_DOMAIN, abi.encodePacked("point1"));
        vm.mockCallRevert(BLS.G1_MSM, abi.encodeWithSelector(0x00000000), abi.encode(uint256(0)));
        vm.expectRevert(BLS.ScalarsMulPointsOnG1Failed.selector);
        BLS.scalarMulPointOnG1(pointOnG1, 123456789);
        vm.expectRevert(BLS.ScalarsLengthNotMatchG1PointsLength.selector);
        BLS.scalarsMulPointsOnG1(new BLS.G1Point[](1), new uint256[](2));
        vm.clearMockedCalls();

        BLS.G2Point memory pointOnG2 = BLS.hashToG2(BLS.BLS_DOMAIN, abi.encodePacked("point1"));
        vm.mockCallRevert(BLS.G2_MSM, abi.encodeWithSelector(0x00000000), abi.encode(uint256(0)));
        vm.expectRevert(BLS.ScalarsMulPointsOnG2Failed.selector);
        BLS.scalarMulPointOnG2(pointOnG2, 123456789);
        vm.expectRevert(BLS.ScalarsLengthNotMatchG2PointsLength.selector);
        BLS.scalarsMulPointsOnG2(new BLS.G2Point[](1), new uint256[](2));
        vm.clearMockedCalls();
    }

    function testPairingFailed() public {
        BLS.G1Point[] memory pointsOnG1 = new BLS.G1Point[](1);
        pointsOnG1[0] = BLS.hashToG1(BLS.BLS_DOMAIN, abi.encodePacked("point1"));
        BLS.G2Point[] memory pointsOnG2 = new BLS.G2Point[](1);
        pointsOnG2[0] = BLS.hashToG2(BLS.BLS_DOMAIN, abi.encodePacked("point2"));

        vm.mockCallRevert(BLS.PAIRING, abi.encodeWithSelector(0x00000000), abi.encode(uint256(0)));
        vm.expectRevert(BLS.PairWhenPKOnG1Failed.selector);
        BLS.pairWhenPKOnG1(pointsOnG2[0], pointsOnG1[0], pointsOnG2[0]);
        vm.expectRevert(BLS.PairWhenPKOnG2Failed.selector);
        BLS.pairWhenPKOnG2(pointsOnG1[0], pointsOnG2[0], pointsOnG1[0]);
        vm.expectRevert(BLS.GeneralPairingFailed.selector);
        BLS.generalPairing(pointsOnG1, pointsOnG2);
        vm.clearMockedCalls();
    }
}
