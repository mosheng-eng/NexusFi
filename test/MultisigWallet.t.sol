// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {MultisigWallet} from "../src/multisig/MultisigWallet.sol";
import {BLS} from "../src/multisig/utils/BLS.sol";
import {BLSTool} from "../src/multisig/utils/BLSTool.sol";
import {BLSHelper} from "../src/multisig/utils/BLSHelper.sol";
import {DeployContractSuit} from "../script/DeployContractSuit.s.sol";

import {DepositAsset} from "./mock/DepositAsset.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";

contract MultisigWalletTest is Test {
    using stdJson for string;
    using BLS for BLS.G1Point;
    using BLS for BLS.G2Point;
    using BLS for BLS.G1Point[];
    using BLS for BLS.G2Point[];
    using BLSTool for BLS.G1Point;
    using BLSTool for BLS.G2Point;
    using BLSTool for BLS.G1Point[];
    using BLSTool for BLS.G2Point[];
    using Bytes for bytes;

    DeployContractSuit internal _deployer = new DeployContractSuit();

    DepositAsset internal _depositAsset = new DepositAsset("Deposit Asset", "DPT");

    MultisigWallet internal _multisigWalletPKOnG1;
    MultisigWallet internal _multisigWalletPKOnG2;

    uint256[] internal _privateKeys;

    address _owner = makeAddr("owner");

    string internal _root;

    function setUp() public {
        /// @dev read public keys from json file
        _root = vm.projectRoot();
        uint256[] memory privateKeys = new uint256[](3);
        privateKeys[0] = vm.parseUint(string.concat("0x", vm.readFile(string.concat(_root, "/keys/mosheng.key"))));
        privateKeys[1] = vm.parseUint(string.concat("0x", vm.readFile(string.concat(_root, "/keys/mr.silent.key"))));
        privateKeys[2] = vm.parseUint(string.concat("0x", vm.readFile(string.concat(_root, "/keys/liuke.key"))));

        /// @dev aggregate public keys
        BLS.G1Point memory aggregatedPublicKeysOnG1 = BLSTool.calculatePKsOnG1(privateKeys);
        BLS.G2Point memory aggregatedPublicKeysOnG2 = BLSTool.calculatePKsOnG2(privateKeys);

        _multisigWalletPKOnG1 = MultisigWallet(
            _deployer.deployMultisigWallet(
                _owner, MultisigWallet.WalletMode.PUBLIC_KEY_ON_G1, abi.encode(aggregatedPublicKeysOnG1)
            )
        );
        _multisigWalletPKOnG2 = MultisigWallet(
            _deployer.deployMultisigWallet(
                _owner, MultisigWallet.WalletMode.PUBLIC_KEY_ON_G2, abi.encode(aggregatedPublicKeysOnG2)
            )
        );

        _privateKeys.push(privateKeys[0]);
        _privateKeys.push(privateKeys[1]);
        _privateKeys.push(privateKeys[2]);

        _depositAsset.mint(_owner, 10000e6);

        vm.label(_owner, "Owner");
        vm.label(address(_deployer), "Deployer");
        vm.label(address(_depositAsset), "DepositAsset");
        vm.label(address(_multisigWalletPKOnG1), "MultisigWalletPKOnG1");
        vm.label(address(_multisigWalletPKOnG2), "MultisigWalletPKOnG2");
        vm.label(BLS.G1_ADD, "G1_ADD");
        vm.label(BLS.G1_MSM, "G1_MSM");
        vm.label(BLS.G2_ADD, "G2_ADD");
        vm.label(BLS.G2_MSM, "G2_MSM");
        vm.label(BLS.PAIRING, "PAIRING");
        vm.label(BLS.MAP_FP_TO_G1, "MAP_FP_TO_G1");
        vm.label(BLS.MAP_FP2_TO_G2, "MAP_FP2_TO_G2");
    }

    function testNull() public pure {
        assertTrue(true);
    }

    function testGeneratorG1() public pure {
        BLS.G1Point memory point = BLS.generatorG1();
        assertEq(point.X.upper, BLS.G1_X_UPPER);
        assertEq(point.X.lower, BLS.G1_X_LOWER);
        assertEq(point.Y.upper, BLS.G1_Y_UPPER);
        assertEq(point.Y.lower, BLS.G1_Y_LOWER);
    }

    function testGeneratorG2() public pure {
        BLS.G2Point memory point = BLS.generatorG2();
        assertEq(point.X0.upper, BLS.G2_X0_UPPER);
        assertEq(point.X0.lower, BLS.G2_X0_LOWER);
        assertEq(point.X1.upper, BLS.G2_X1_UPPER);
        assertEq(point.X1.lower, BLS.G2_X1_LOWER);
        assertEq(point.Y0.upper, BLS.G2_Y0_UPPER);
        assertEq(point.Y0.lower, BLS.G2_Y0_LOWER);
        assertEq(point.Y1.upper, BLS.G2_Y1_UPPER);
        assertEq(point.Y1.lower, BLS.G2_Y1_LOWER);
    }

    function testHashToFp() public view {
        bytes[] memory pointsToFp =
            BLSHelper.hashToFp(abi.encodePacked("test input"), "BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_NUL_", 2);

        assertEq(pointsToFp.length, 2);
        assertEq(pointsToFp[0].length, 64);
        assertEq(pointsToFp[1].length, 64);

        console.log(string.concat("  FP1-1: ", vm.toString(pointsToFp[0])));
        console.log(string.concat("  FP1-2: ", vm.toString(pointsToFp[1])));
    }

    function testHashToFp2() public view {
        bytes[] memory fp2 =
            BLSHelper.hashToFp2(abi.encodePacked("test input"), "BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_NUL_", 2);

        assertEq(fp2.length, 2);
        assertEq(fp2[0].length, 128);
        assertEq(fp2[1].length, 128);

        console.log(string.concat("FP2-1.X: ", vm.toString(fp2[0].slice(0, 64))));
        console.log(string.concat("FP2-1.Y: ", vm.toString(fp2[0].slice(64, 128))));
        console.log(string.concat("FP2-2.X: ", vm.toString(fp2[1].slice(0, 64))));
        console.log(string.concat("FP2-2.Y: ", vm.toString(fp2[1].slice(64, 128))));
    }

    function testHashToG1() public view {
        BLS.G1Point[] memory pointsOnG1 = new BLS.G1Point[](2);

        pointsOnG1[0] = BLS.hashToG1(BLS.BLS_DOMAIN, abi.encodePacked("point1"));
        pointsOnG1[1] = BLS.hashToG1(BLS.BLS_DOMAIN, abi.encodePacked("point2"));

        assertNotEq(pointsOnG1[0].X.upper, pointsOnG1[1].X.upper);
        assertNotEq(pointsOnG1[0].X.lower, pointsOnG1[1].X.lower);
        assertNotEq(pointsOnG1[0].Y.upper, pointsOnG1[1].Y.upper);
        assertNotEq(pointsOnG1[0].Y.lower, pointsOnG1[1].Y.lower);
    }

    function testHashToG2() public view {
        BLS.G2Point[] memory pointsOnG2 = new BLS.G2Point[](2);

        pointsOnG2[0] = BLS.hashToG2(BLS.BLS_DOMAIN, abi.encodePacked("point1"));
        pointsOnG2[1] = BLS.hashToG2(BLS.BLS_DOMAIN, abi.encodePacked("point2"));

        assertNotEq(pointsOnG2[0].X0.upper, pointsOnG2[1].X0.upper);
        assertNotEq(pointsOnG2[0].X0.lower, pointsOnG2[1].X0.lower);
        assertNotEq(pointsOnG2[0].X1.upper, pointsOnG2[1].X1.upper);
        assertNotEq(pointsOnG2[0].X1.lower, pointsOnG2[1].X1.lower);
        assertNotEq(pointsOnG2[0].Y0.upper, pointsOnG2[1].Y0.upper);
        assertNotEq(pointsOnG2[0].Y0.lower, pointsOnG2[1].Y0.lower);
        assertNotEq(pointsOnG2[0].Y1.upper, pointsOnG2[1].Y1.upper);
        assertNotEq(pointsOnG2[0].Y1.lower, pointsOnG2[1].Y1.lower);
    }

    function testCalculatePKsOnG1() public view {
        uint256[] memory sks = new uint256[](1);
        sks[0] = 0x69868d4d7d64868027726b31a98fa5b8a392f3fc06bb026afb4c9899bf50c249;

        BLS.G1Point memory pkOnG1 = BLSTool.calculatePKsOnG1(sks);

        assertNotEq(pkOnG1.X.upper, 0);
        assertNotEq(pkOnG1.X.lower, 0);
        assertNotEq(pkOnG1.Y.upper, 0);
        assertNotEq(pkOnG1.Y.lower, 0);
    }

    function testAggregatePKsOnG1() public view {
        BLS.G1Point[] memory pksOnG1 = new BLS.G1Point[](2);

        uint256[] memory sk1 = new uint256[](1);
        sk1[0] = 0x69868d4d7d64868027726b31a98fa5b8a392f3fc06bb026afb4c9899bf50c249;
        pksOnG1[0] = BLSTool.calculatePKsOnG1(sk1);

        uint256[] memory sk2 = new uint256[](1);
        sk2[0] = 0x341ed3baa2c136041f72860c7dcb12803245463239f25f3e0112613e38a21962;
        pksOnG1[1] = BLSTool.calculatePKsOnG1(sk2);

        BLS.G1Point memory aggregatedPKOnG1 = pksOnG1.aggregatePKsOnG1();

        assertGt(aggregatedPKOnG1.X.upper, 0);
        assertGt(aggregatedPKOnG1.X.lower, 0);
        assertGt(aggregatedPKOnG1.Y.upper, 0);
        assertGt(aggregatedPKOnG1.Y.lower, 0);
    }

    function testBuildSIGsOnG1() public view {
        uint256[] memory sks = new uint256[](1);
        sks[0] = 0x69868d4d7d64868027726b31a98fa5b8a392f3fc06bb026afb4c9899bf50c249;

        bytes[] memory messages = new bytes[](1);
        messages[0] = abi.encodePacked("test message");

        BLS.G1Point memory sigsOnG1 = BLSTool.buildSIGsOnG1(sks, messages);

        assertNotEq(sigsOnG1.X.upper, 0);
        assertNotEq(sigsOnG1.X.lower, 0);
        assertNotEq(sigsOnG1.Y.upper, 0);
        assertNotEq(sigsOnG1.Y.lower, 0);
    }

    function testAggregateSIGsOnG1() public view {
        BLS.G1Point[] memory sigsOnG1 = new BLS.G1Point[](2);

        uint256[] memory sk1 = new uint256[](1);
        sk1[0] = 0x69868d4d7d64868027726b31a98fa5b8a392f3fc06bb026afb4c9899bf50c249;
        bytes[] memory message1 = new bytes[](1);
        message1[0] = abi.encodePacked("test message 1");
        sigsOnG1[0] = BLSTool.buildSIGsOnG1(sk1, message1);

        uint256[] memory sk2 = new uint256[](1);
        sk2[0] = 0x341ed3baa2c136041f72860c7dcb12803245463239f25f3e0112613e38a21962;
        bytes[] memory message2 = new bytes[](1);
        message2[0] = abi.encodePacked("test message 2");
        sigsOnG1[1] = BLSTool.buildSIGsOnG1(sk2, message2);

        BLS.G1Point memory aggregatedSigsOnG1 = sigsOnG1.aggregateSIGsOnG1();

        assertNotEq(aggregatedSigsOnG1.X.upper, 0);
        assertNotEq(aggregatedSigsOnG1.X.lower, 0);
        assertNotEq(aggregatedSigsOnG1.Y.upper, 0);
        assertNotEq(aggregatedSigsOnG1.Y.lower, 0);
    }

    function testCalculatePKsOnG2() public view {
        uint256[] memory sks = new uint256[](1);
        sks[0] = 0x69868d4d7d64868027726b31a98fa5b8a392f3fc06bb026afb4c9899bf50c249;

        BLS.G2Point memory pkOnG2 = BLSTool.calculatePKsOnG2(sks);

        assertNotEq(pkOnG2.X0.upper, 0);
        assertNotEq(pkOnG2.X0.lower, 0);
        assertNotEq(pkOnG2.X1.upper, 0);
        assertNotEq(pkOnG2.X1.lower, 0);
        assertNotEq(pkOnG2.Y0.upper, 0);
        assertNotEq(pkOnG2.Y0.lower, 0);
        assertNotEq(pkOnG2.Y1.upper, 0);
        assertNotEq(pkOnG2.Y1.lower, 0);
    }

    function testAggregatePKsOnG2() public view {
        BLS.G2Point[] memory pksOnG2 = new BLS.G2Point[](2);

        uint256[] memory sk1 = new uint256[](1);
        sk1[0] = 0x69868d4d7d64868027726b31a98fa5b8a392f3fc06bb026afb4c9899bf50c249;
        pksOnG2[0] = BLSTool.calculatePKsOnG2(sk1);

        uint256[] memory sk2 = new uint256[](1);
        sk2[0] = 0x341ed3baa2c136041f72860c7dcb12803245463239f25f3e0112613e38a21962;
        pksOnG2[1] = BLSTool.calculatePKsOnG2(sk2);

        BLS.G2Point memory aggregatedPKOnG2 = pksOnG2.aggregatePKsOnG2();

        assertGt(aggregatedPKOnG2.X0.upper, 0);
        assertGt(aggregatedPKOnG2.X0.lower, 0);
        assertGt(aggregatedPKOnG2.X1.upper, 0);
        assertGt(aggregatedPKOnG2.X1.lower, 0);
        assertGt(aggregatedPKOnG2.Y0.upper, 0);
        assertGt(aggregatedPKOnG2.Y0.lower, 0);
        assertGt(aggregatedPKOnG2.Y1.upper, 0);
        assertGt(aggregatedPKOnG2.Y1.lower, 0);
    }

    function testBuildSIGsOnG2() public view {
        uint256[] memory sks = new uint256[](1);
        sks[0] = 0x69868d4d7d64868027726b31a98fa5b8a392f3fc06bb026afb4c9899bf50c249;

        bytes[] memory messages = new bytes[](1);
        messages[0] = abi.encodePacked("test message");

        BLS.G2Point memory sigsOnG2 = BLSTool.buildSIGsOnG2(sks, messages);

        assertNotEq(sigsOnG2.X0.upper, 0);
        assertNotEq(sigsOnG2.X0.lower, 0);
        assertNotEq(sigsOnG2.X1.upper, 0);
        assertNotEq(sigsOnG2.X1.lower, 0);
        assertNotEq(sigsOnG2.Y0.upper, 0);
        assertNotEq(sigsOnG2.Y0.lower, 0);
        assertNotEq(sigsOnG2.Y1.upper, 0);
        assertNotEq(sigsOnG2.Y1.lower, 0);
    }

    function testAggregateSIGsOnG2() public view {
        BLS.G2Point[] memory sigsOnG2 = new BLS.G2Point[](2);

        uint256[] memory sk1 = new uint256[](1);
        sk1[0] = 0x69868d4d7d64868027726b31a98fa5b8a392f3fc06bb026afb4c9899bf50c249;
        bytes[] memory message1 = new bytes[](1);
        message1[0] = abi.encodePacked("test message 1");
        sigsOnG2[0] = BLSTool.buildSIGsOnG2(sk1, message1);

        uint256[] memory sk2 = new uint256[](1);
        sk2[0] = 0x341ed3baa2c136041f72860c7dcb12803245463239f25f3e0112613e38a21962;
        bytes[] memory message2 = new bytes[](1);
        message2[0] = abi.encodePacked("test message 2");
        sigsOnG2[1] = BLSTool.buildSIGsOnG2(sk2, message2);

        BLS.G2Point memory aggregatedSigsOnG2 = sigsOnG2.aggregateSIGsOnG2();

        assertNotEq(aggregatedSigsOnG2.X0.upper, 0);
        assertNotEq(aggregatedSigsOnG2.X0.lower, 0);
        assertNotEq(aggregatedSigsOnG2.X1.upper, 0);
        assertNotEq(aggregatedSigsOnG2.X1.lower, 0);
        assertNotEq(aggregatedSigsOnG2.Y0.upper, 0);
        assertNotEq(aggregatedSigsOnG2.Y0.lower, 0);
        assertNotEq(aggregatedSigsOnG2.Y1.upper, 0);
        assertNotEq(aggregatedSigsOnG2.Y1.lower, 0);
    }

    function testSumPointsOnG1() public view {
        BLS.G1Point[] memory pointsOnG1 = new BLS.G1Point[](2);

        pointsOnG1[0] = BLS.hashToG1(BLS.BLS_DOMAIN, abi.encodePacked("point1"));
        pointsOnG1[1] = BLS.hashToG1(BLS.BLS_DOMAIN, abi.encodePacked("point2"));

        BLS.G1Point memory summedPointOnG1 = pointsOnG1.sumPointsOnG1();

        assertNotEq(summedPointOnG1.X.upper, 0);
        assertNotEq(summedPointOnG1.X.lower, 0);
        assertNotEq(summedPointOnG1.Y.upper, 0);
        assertNotEq(summedPointOnG1.Y.lower, 0);
    }

    function testSumPointsOnG2() public view {
        BLS.G2Point[] memory pointsOnG2 = new BLS.G2Point[](2);

        pointsOnG2[0] = BLS.hashToG2(BLS.BLS_DOMAIN, abi.encodePacked("point1"));
        pointsOnG2[1] = BLS.hashToG2(BLS.BLS_DOMAIN, abi.encodePacked("point2"));

        BLS.G2Point memory summedPointOnG2 = pointsOnG2.sumPointsOnG2();

        assertNotEq(summedPointOnG2.X0.upper, 0);
        assertNotEq(summedPointOnG2.X0.lower, 0);
        assertNotEq(summedPointOnG2.X1.upper, 0);
        assertNotEq(summedPointOnG2.X1.lower, 0);
        assertNotEq(summedPointOnG2.Y0.upper, 0);
        assertNotEq(summedPointOnG2.Y0.lower, 0);
        assertNotEq(summedPointOnG2.Y1.upper, 0);
        assertNotEq(summedPointOnG2.Y1.lower, 0);
    }

    function testScalarsMulPointsOnG1() public view {
        uint256[] memory scalars = new uint256[](1);
        scalars[0] = 0x02;

        BLS.G1Point[] memory srcPointsOnG1 = new BLS.G1Point[](1);
        srcPointsOnG1[0] = BLS.hashToG1(BLS.BLS_DOMAIN, abi.encodePacked("source point"));

        BLS.G1Point memory dstPointsOnG1 = srcPointsOnG1.scalarsMulPointsOnG1(scalars);

        assertNotEq(dstPointsOnG1.X.upper, 0);
        assertNotEq(dstPointsOnG1.X.lower, 0);
        assertNotEq(dstPointsOnG1.Y.upper, 0);
        assertNotEq(dstPointsOnG1.Y.lower, 0);
    }

    function testScalarsMulPointsOnG2() public view {
        uint256[] memory scalars = new uint256[](1);
        scalars[0] = 0x02;

        BLS.G2Point[] memory srcPointsOnG2 = new BLS.G2Point[](1);
        srcPointsOnG2[0] = BLS.hashToG2(BLS.BLS_DOMAIN, abi.encodePacked("source point"));

        BLS.G2Point memory dstPointsOnG2 = srcPointsOnG2.scalarsMulPointsOnG2(scalars);

        assertNotEq(dstPointsOnG2.X0.upper, 0);
        assertNotEq(dstPointsOnG2.X0.lower, 0);
        assertNotEq(dstPointsOnG2.X1.upper, 0);
        assertNotEq(dstPointsOnG2.X1.lower, 0);
        assertNotEq(dstPointsOnG2.Y0.upper, 0);
        assertNotEq(dstPointsOnG2.Y0.lower, 0);
        assertNotEq(dstPointsOnG2.Y1.upper, 0);
        assertNotEq(dstPointsOnG2.Y1.lower, 0);
    }

    function testPairWhenPKOnG1() public view {
        uint256[] memory sks = new uint256[](1);
        sks[0] = 0x69868d4d7d64868027726b31a98fa5b8a392f3fc06bb026afb4c9899bf50c249;

        BLS.G1Point memory pkOnG1 = BLSTool.calculatePKsOnG1(sks);

        bytes[] memory messages = new bytes[](1);
        messages[0] = abi.encodePacked("test message");

        BLS.G2Point memory msgOnG2 = BLS.hashToG2(BLS.BLS_DOMAIN, messages[0]);

        BLS.G2Point memory sigOnG2 = BLSTool.buildSIGsOnG2(sks, messages);

        assertTrue(sigOnG2.pairWhenPKOnG1(pkOnG1, msgOnG2));
    }

    function testPairWhenPKOnG2() public view {
        uint256[] memory sks = new uint256[](1);
        sks[0] = 0x69868d4d7d64868027726b31a98fa5b8a392f3fc06bb026afb4c9899bf50c249;

        BLS.G2Point memory pkOnG2 = BLSTool.calculatePKsOnG2(sks);

        bytes[] memory messages = new bytes[](1);
        messages[0] = abi.encodePacked("test message");

        BLS.G1Point memory msgOnG1 = BLS.hashToG1(BLS.BLS_DOMAIN, messages[0]);

        BLS.G1Point memory sigOnG1 = BLSTool.buildSIGsOnG1(sks, messages);

        assertTrue(sigOnG1.pairWhenPKOnG2(pkOnG2, msgOnG1));
    }

    function testSubmitOperationsWithoutSIGToWalletPKOnG1() public {
        (MultisigWallet.Operation[] memory operations, bytes32 operationHash) = _operations(_multisigWalletPKOnG1);

        bytes32[] memory operationsHash = _multisigWalletPKOnG1.submitOperations(operations);

        assertEq(operationsHash.length, 1);
        assertEq(operationsHash[0], operationHash);
        (,,,,,, MultisigWallet.OperationStatus status,,,) = _multisigWalletPKOnG1._operations(operationHash);
        assertEq(uint8(status), uint8(MultisigWallet.OperationStatus.PENDING));
    }

    function testSubmitOperationsWithoutSIGToWalletPKOnG2() public {
        (MultisigWallet.Operation[] memory operations, bytes32 operationHash) = _operations(_multisigWalletPKOnG2);

        bytes32[] memory operationsHash = _multisigWalletPKOnG2.submitOperations(operations);

        assertEq(operationsHash.length, 1);
        assertEq(operationsHash[0], operationHash);
        (,,,,,, MultisigWallet.OperationStatus status,,,) = _multisigWalletPKOnG2._operations(operationHash);
        assertEq(uint8(status), uint8(MultisigWallet.OperationStatus.PENDING));
    }

    function testSubmitOperationsWithSIGToWalletPKOnG1() public {
        (MultisigWallet.Operation[] memory operations, bytes32 operationHash) = _operations(_multisigWalletPKOnG1);
        assertEq(operations.length, 1);

        uint256[] memory sks = new uint256[](_privateKeys.length);
        bytes[] memory messages = new bytes[](_privateKeys.length);

        for (uint256 i = 0; i < _privateKeys.length; i++) {
            sks[i] = _privateKeys[i];
            messages[i] = abi.encode(operationHash);
        }

        BLS.G2Point memory sigOnG2 = BLSTool.buildSIGsOnG2(sks, messages);

        operations[0].aggregatedSignature = abi.encode(sigOnG2);

        bytes32[] memory operationsHash = _multisigWalletPKOnG1.submitOperations(operations);

        assertEq(operationsHash.length, 1);
        assertEq(operationsHash[0], operationHash);
        (,,,,,, MultisigWallet.OperationStatus status,,,) = _multisigWalletPKOnG1._operations(operationHash);
        assertEq(uint8(status), uint8(MultisigWallet.OperationStatus.APPROVED));
    }

    function testSubmitOperationsWithSIGToWalletPKOnG2() public {
        (MultisigWallet.Operation[] memory operations, bytes32 operationHash) = _operations(_multisigWalletPKOnG2);
        assertEq(operations.length, 1);

        uint256[] memory sks = new uint256[](_privateKeys.length);
        bytes[] memory messages = new bytes[](_privateKeys.length);

        for (uint256 i = 0; i < _privateKeys.length; i++) {
            sks[i] = _privateKeys[i];
            messages[i] = abi.encode(operationHash);
        }

        BLS.G1Point memory sigOnG1 = BLSTool.buildSIGsOnG1(sks, messages);

        operations[0].aggregatedSignature = abi.encode(sigOnG1);

        bytes32[] memory operationsHash = _multisigWalletPKOnG2.submitOperations(operations);

        assertEq(operationsHash.length, 1);
        assertEq(operationsHash[0], operationHash);
        (,,,,,, MultisigWallet.OperationStatus status,,,) = _multisigWalletPKOnG2._operations(operationHash);
        assertEq(uint8(status), uint8(MultisigWallet.OperationStatus.APPROVED));
    }

    function testExecuteOperationsToWalletPKOnG1() public {
        (MultisigWallet.Operation[] memory operations, bytes32 operationHash) = _operations(_multisigWalletPKOnG1);
        assertEq(operations.length, 1);

        uint256[] memory sks = new uint256[](_privateKeys.length);
        bytes[] memory messages = new bytes[](_privateKeys.length);

        for (uint256 i = 0; i < _privateKeys.length; i++) {
            sks[i] = _privateKeys[i];
            messages[i] = abi.encode(operationHash);
        }

        BLS.G2Point memory sigOnG2 = BLSTool.buildSIGsOnG2(sks, messages);

        operations[0].aggregatedSignature = abi.encode(sigOnG2);

        bytes32[] memory operationsHash = _multisigWalletPKOnG1.submitOperations(operations);

        assertEq(operationsHash.length, 1);
        assertEq(operationsHash[0], operationHash);
        (,,,,,, MultisigWallet.OperationStatus status,,,) = _multisigWalletPKOnG1._operations(operationHash);
        assertEq(uint8(status), uint8(MultisigWallet.OperationStatus.APPROVED));

        vm.warp((operations[0].effectiveTime + operations[0].expirationTime) / 2);
        _multisigWalletPKOnG1.executeOperations(operationsHash);

        (,,,,,, status,,,) = _multisigWalletPKOnG1._operations(operationHash);
        assertEq(uint8(status), uint8(MultisigWallet.OperationStatus.EXECUTED));
    }

    function testExecuteOperationsToWalletPKOnG2() public {
        (MultisigWallet.Operation[] memory operations, bytes32 operationHash) = _operations(_multisigWalletPKOnG2);
        assertEq(operations.length, 1);

        uint256[] memory sks = new uint256[](_privateKeys.length);
        bytes[] memory messages = new bytes[](_privateKeys.length);

        for (uint256 i = 0; i < _privateKeys.length; i++) {
            sks[i] = _privateKeys[i];
            messages[i] = abi.encode(operationHash);
        }

        BLS.G1Point memory sigOnG1 = BLSTool.buildSIGsOnG1(sks, messages);

        operations[0].aggregatedSignature = abi.encode(sigOnG1);

        bytes32[] memory operationsHash = _multisigWalletPKOnG2.submitOperations(operations);

        assertEq(operationsHash.length, 1);
        assertEq(operationsHash[0], operationHash);
        (,,,,,, MultisigWallet.OperationStatus status,,,) = _multisigWalletPKOnG2._operations(operationHash);
        assertEq(uint8(status), uint8(MultisigWallet.OperationStatus.APPROVED));

        vm.warp((operations[0].effectiveTime + operations[0].expirationTime) / 2);
        _multisigWalletPKOnG2.executeOperations(operationsHash);

        (,,,,,, status,,,) = _multisigWalletPKOnG2._operations(operationHash);
        assertEq(uint8(status), uint8(MultisigWallet.OperationStatus.EXECUTED));
    }

    function _operations(MultisigWallet multisigWallet_)
        internal
        view
        returns (MultisigWallet.Operation[] memory operations_, bytes32 operationHash_)
    {
        operations_ = new MultisigWallet.Operation[](1);
        operations_[0].target = address(_depositAsset);
        operations_[0].value = 0;
        operations_[0].effectiveTime = uint32(block.timestamp + 1 days);
        operations_[0].expirationTime = uint32(block.timestamp + 30 days);
        operations_[0].gasLimit = uint32(gasleft());
        operations_[0].nonce = multisigWallet_._nonce();
        operations_[0].data = _calldata();
        operationHash_ = keccak256(
            abi.encodePacked(
                operations_[0].target,
                operations_[0].value,
                operations_[0].effectiveTime,
                operations_[0].expirationTime,
                operations_[0].gasLimit,
                operations_[0].nonce,
                operations_[0].data
            )
        );
        operations_[0].hashCheckCode = bytes8(operationHash_);
    }

    function _calldata() internal view returns (bytes memory calldata_) {
        calldata_ = abi.encodeWithSelector(ERC20.balanceOf.selector, _owner);
    }
}
