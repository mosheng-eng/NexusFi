// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {Errors} from "src/common/Errors.sol";
import {MultisigWallet} from "src/multisig/MultisigWallet.sol";
import {BLS} from "src/multisig/utils/BLS.sol";
import {BLSTool} from "src/multisig/utils/BLSTool.sol";
import {BLSHelper} from "src/multisig/utils/BLSHelper.sol";
import {DeployContractSuit} from "script/DeployContractSuit.s.sol";

import {DepositAsset} from "test/mock/DepositAsset.sol";

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

    function testSubmitOperationsWithoutSIGToWalletPKOnG1() public returns (bytes32) {
        (MultisigWallet.Operation[] memory operations, bytes32 operationHash) = _operations(_multisigWalletPKOnG1);

        bytes32[] memory operationsHash = _multisigWalletPKOnG1.submitOperations(operations);

        assertEq(operationsHash.length, 1);
        assertEq(operationsHash[0], operationHash);
        (,,,,,, MultisigWallet.OperationStatus status,,,) = _multisigWalletPKOnG1._operations(operationHash);
        assertEq(uint8(status), uint8(MultisigWallet.OperationStatus.PENDING));

        return operationHash;
    }

    function testSubmitOperationsWithoutSIGToWalletPKOnG2() public returns (bytes32) {
        (MultisigWallet.Operation[] memory operations, bytes32 operationHash) = _operations(_multisigWalletPKOnG2);

        bytes32[] memory operationsHash = _multisigWalletPKOnG2.submitOperations(operations);

        assertEq(operationsHash.length, 1);
        assertEq(operationsHash[0], operationHash);
        (,,,,,, MultisigWallet.OperationStatus status,,,) = _multisigWalletPKOnG2._operations(operationHash);
        assertEq(uint8(status), uint8(MultisigWallet.OperationStatus.PENDING));

        return operationHash;
    }

    function testVerifyOperationsInWalletPKOnG1() public {
        (MultisigWallet.Operation[] memory operations, bytes32 operationHash) = _operations(_multisigWalletPKOnG1);

        bytes32[] memory operationsHash = _multisigWalletPKOnG1.submitOperations(operations);

        assertEq(operationsHash.length, 1);
        assertEq(operationsHash[0], operationHash);
        (,,,,,, MultisigWallet.OperationStatus status,,,) = _multisigWalletPKOnG1._operations(operationHash);
        assertEq(uint8(status), uint8(MultisigWallet.OperationStatus.PENDING));

        bytes[] memory aggregatedSignatures = new bytes[](1);
        aggregatedSignatures[0] = _signOnG2(operationHash);

        _multisigWalletPKOnG1.verifyOperations(operationsHash, aggregatedSignatures);

        (,,,,,, status,,,) = _multisigWalletPKOnG1._operations(operationHash);
        assertEq(uint8(status), uint8(MultisigWallet.OperationStatus.APPROVED));

        vm.warp(block.timestamp + 2 days);

        _multisigWalletPKOnG1.executeOperations(operationsHash);

        (,,,,,, status,,,) = _multisigWalletPKOnG1._operations(operationHash);
        assertEq(uint8(status), uint8(MultisigWallet.OperationStatus.EXECUTED));
    }

    function testVerifyOperationsInWalletPKOnG2() public {
        (MultisigWallet.Operation[] memory operations, bytes32 operationHash) = _operations(_multisigWalletPKOnG2);

        bytes32[] memory operationsHash = _multisigWalletPKOnG2.submitOperations(operations);

        assertEq(operationsHash.length, 1);
        assertEq(operationsHash[0], operationHash);
        (,,,,,, MultisigWallet.OperationStatus status,,,) = _multisigWalletPKOnG2._operations(operationHash);
        assertEq(uint8(status), uint8(MultisigWallet.OperationStatus.PENDING));

        bytes[] memory aggregatedSignatures = new bytes[](1);
        aggregatedSignatures[0] = _signOnG1(operationHash);

        _multisigWalletPKOnG2.verifyOperations(operationsHash, aggregatedSignatures);

        (,,,,,, status,,,) = _multisigWalletPKOnG2._operations(operationHash);
        assertEq(uint8(status), uint8(MultisigWallet.OperationStatus.APPROVED));

        vm.warp(block.timestamp + 2 days);

        _multisigWalletPKOnG2.executeOperations(operationsHash);

        (,,,,,, status,,,) = _multisigWalletPKOnG2._operations(operationHash);
        assertEq(uint8(status), uint8(MultisigWallet.OperationStatus.EXECUTED));
    }

    function testSubmitOperationsWithSIGToWalletPKOnG1() public returns (bytes32, bytes memory) {
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

        return (operationHash, operations[0].aggregatedSignature);
    }

    function testSubmitOperationsWithSIGToWalletPKOnG2() public returns (bytes32, bytes memory) {
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

        return (operationHash, operations[0].aggregatedSignature);
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

    function testInitializedModifier() public {
        MultisigWallet directCallMultisigWallet = new MultisigWallet();
        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "Mode or PK is not set"));
        directCallMultisigWallet.submitOperations(new MultisigWallet.Operation[](0));

        MultisigWallet nondirectCallMultisigWalletG1 = MultisigWallet(
            address(
                _deployer.deployMultisigWallet(
                    _owner,
                    MultisigWallet.WalletMode.PUBLIC_KEY_ON_G1,
                    abi.encode(BLS.G1Point({X: BLS.Unit({upper: 0, lower: 0}), Y: BLS.Unit({upper: 0, lower: 0})}))
                )
            )
        );
        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "Mode or PK is not set"));
        nondirectCallMultisigWalletG1.submitOperations(new MultisigWallet.Operation[](0));

        MultisigWallet nondirectCallMultisigWalletG2 = MultisigWallet(
            address(
                _deployer.deployMultisigWallet(
                    _owner,
                    MultisigWallet.WalletMode.PUBLIC_KEY_ON_G2,
                    abi.encode(
                        BLS.G2Point({
                            X0: BLS.Unit({upper: 0, lower: 0}),
                            X1: BLS.Unit({upper: 0, lower: 0}),
                            Y0: BLS.Unit({upper: 0, lower: 0}),
                            Y1: BLS.Unit({upper: 0, lower: 0})
                        })
                    )
                )
            )
        );
        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "Mode or PK is not set"));
        nondirectCallMultisigWalletG2.submitOperations(new MultisigWallet.Operation[](0));
    }

    function testInvalidInitialize() public {
        vm.expectRevert(MultisigWallet.EmptyPublicKey.selector);
        _deployer.deployMultisigWallet(_owner, MultisigWallet.WalletMode.PUBLIC_KEY_ON_G1, abi.encodePacked(""));
        vm.expectRevert(MultisigWallet.EmptyPublicKey.selector);
        _deployer.deployMultisigWallet(_owner, MultisigWallet.WalletMode.PUBLIC_KEY_ON_G2, abi.encodePacked(""));

        vm.expectRevert(
            abi.encodeWithSelector(MultisigWallet.InvalidPublicKey.selector, "Invalid public key length for G1")
        );
        _deployer.deployMultisigWallet(
            _owner, MultisigWallet.WalletMode.PUBLIC_KEY_ON_G1, abi.encode(BLS.Unit({upper: 0, lower: 0}))
        );
        vm.expectRevert(
            abi.encodeWithSelector(MultisigWallet.InvalidPublicKey.selector, "Invalid public key length for G2")
        );
        _deployer.deployMultisigWallet(
            _owner, MultisigWallet.WalletMode.PUBLIC_KEY_ON_G2, abi.encode(BLS.Unit({upper: 0, lower: 0}))
        );

        vm.expectRevert(abi.encodeWithSelector(MultisigWallet.UnsupportedWalletMode.selector, 0));
        _deployer.deployMultisigWallet(
            _owner, MultisigWallet.WalletMode.UNKNOWN, abi.encode(BLS.Unit({upper: 0, lower: 0}))
        );
    }

    function testSubmitInvalidOperations() public {
        console.log("case1: empty operations");
        vm.expectRevert(MultisigWallet.EmptyOperations.selector);
        _multisigWalletPKOnG1.submitOperations(new MultisigWallet.Operation[](0));
        vm.expectRevert(MultisigWallet.EmptyOperations.selector);
        _multisigWalletPKOnG2.submitOperations(new MultisigWallet.Operation[](0));

        MultisigWallet.Operation[] memory operationsG1;
        bytes32 operationHashG1;
        MultisigWallet.Operation[] memory operationsG2;
        bytes32 operationHashG2;

        console.log("case2: target is zero address");
        (operationsG1, operationHashG1) = _operations(_multisigWalletPKOnG1);
        operationsG1[0].target = address(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "Operation.target"));
        _multisigWalletPKOnG1.submitOperations(operationsG1);
        (operationsG2, operationHashG2) = _operations(_multisigWalletPKOnG2);
        operationsG2[0].target = address(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "Operation.target"));
        _multisigWalletPKOnG2.submitOperations(operationsG2);

        console.log("case3: Operation.expirationTime earlier than Operation.effectiveTime");
        (operationsG1, operationHashG1) = _operations(_multisigWalletPKOnG1);
        operationsG1[0].expirationTime = operationsG1[0].effectiveTime - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidValue.selector, "Operation.expirationTime earlier than Operation.effectiveTime"
            )
        );
        _multisigWalletPKOnG1.submitOperations(operationsG1);
        (operationsG2, operationHashG2) = _operations(_multisigWalletPKOnG2);
        operationsG2[0].expirationTime = operationsG2[0].effectiveTime - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidValue.selector, "Operation.expirationTime earlier than Operation.effectiveTime"
            )
        );
        _multisigWalletPKOnG2.submitOperations(operationsG2);

        console.log("case4: Operation.expirationTime earlier than current time");
        (operationsG1, operationHashG1) = _operations(_multisigWalletPKOnG1);
        vm.warp(block.timestamp + 30 days + 1 minutes);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.expirationTime earlier than current time")
        );
        _multisigWalletPKOnG1.submitOperations(operationsG1);
        (operationsG2, operationHashG2) = _operations(_multisigWalletPKOnG2);
        vm.warp(block.timestamp + 30 days + 1 minutes);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.expirationTime earlier than current time")
        );
        _multisigWalletPKOnG2.submitOperations(operationsG2);

        console.log("case5: Operation.gasLimit too low");
        (operationsG1, operationHashG1) = _operations(_multisigWalletPKOnG1);
        operationsG1[0].gasLimit = 21000 - 1;
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.gasLimit too low"));
        _multisigWalletPKOnG1.submitOperations(operationsG1);
        (operationsG2, operationHashG2) = _operations(_multisigWalletPKOnG2);
        operationsG2[0].gasLimit = 21000 - 1;
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.gasLimit too low"));
        _multisigWalletPKOnG2.submitOperations(operationsG2);

        console.log("case6: Operation.nonce invalid");
        (operationsG1, operationHashG1) = _operations(_multisigWalletPKOnG1);
        operationsG1[0].nonce = operationsG1[0].nonce + 1;
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.nonce invalid"));
        _multisigWalletPKOnG1.submitOperations(operationsG1);
        (operationsG2, operationHashG2) = _operations(_multisigWalletPKOnG2);
        operationsG2[0].nonce = operationsG2[0].nonce + 1;
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.nonce invalid"));
        _multisigWalletPKOnG2.submitOperations(operationsG2);

        console.log("case7: Operation.hashCheckCode invalid");
        (operationsG1, operationHashG1) = _operations(_multisigWalletPKOnG1);
        operationsG1[0].hashCheckCode = bytes8(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.hashCheckCode invalid"));
        _multisigWalletPKOnG1.submitOperations(operationsG1);
        (operationsG2, operationHashG2) = _operations(_multisigWalletPKOnG2);
        operationsG2[0].hashCheckCode = bytes8(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.hashCheckCode invalid"));
        _multisigWalletPKOnG2.submitOperations(operationsG2);

        console.log("case8: Operation.data too short");
        (operationsG1, operationHashG1) = _operations(_multisigWalletPKOnG1);
        operationsG1[0].data = new bytes(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.data too short"));
        _multisigWalletPKOnG1.submitOperations(operationsG1);
        (operationsG2, operationHashG2) = _operations(_multisigWalletPKOnG2);
        operationsG2[0].data = new bytes(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.data too short"));
        _multisigWalletPKOnG2.submitOperations(operationsG2);

        console.log("case9: Operation.aggregatedSignature invalid");
        (operationsG1, operationHashG1) = _operations(_multisigWalletPKOnG1);
        operationsG1[0].aggregatedSignature = abi.encodePacked("0xff");
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.aggregatedSignature invalid"));
        _multisigWalletPKOnG1.submitOperations(operationsG1);
        (operationsG2, operationHashG2) = _operations(_multisigWalletPKOnG2);
        operationsG2[0].aggregatedSignature = abi.encodePacked("0xff");
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.aggregatedSignature invalid"));
        _multisigWalletPKOnG2.submitOperations(operationsG2);

        console.log("case10: Operation.hashCheckCode mismatch");
        (operationsG1, operationHashG1) = _operations(_multisigWalletPKOnG1);
        operationsG1[0].hashCheckCode = bytes8(keccak256(abi.encodePacked("mismatch")));
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.hashCheckCode mismatch"));
        _multisigWalletPKOnG1.submitOperations(operationsG1);
        (operationsG2, operationHashG2) = _operations(_multisigWalletPKOnG2);
        operationsG2[0].hashCheckCode = bytes8(keccak256(abi.encodePacked("mismatch")));
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.hashCheckCode mismatch"));
        _multisigWalletPKOnG2.submitOperations(operationsG2);

        console.log("case11: Operation already exists (impossible)");

        /*
        // This is impossible to happen based on current protocol design, so comment it out.
        console.log("case11: Operation already exists");
        (operationsG1, operationHashG1) = _operations(_multisigWalletPKOnG1);
        _multisigWalletPKOnG1.submitOperations(operationsG1);
        operationsG1[0].nonce = operationsG1[0].nonce + 1;
        vm.expectRevert(MultisigWallet.OperationExists.selector);
        _multisigWalletPKOnG1.submitOperations(operationsG1);
        (operationsG2, operationHashG2) = _operations(_multisigWalletPKOnG2);
        _multisigWalletPKOnG2.submitOperations(operationsG2);
        operationsG2[0].nonce = operationsG2[0].nonce + 1;
        vm.expectRevert(MultisigWallet.OperationExists.selector);
        _multisigWalletPKOnG2.submitOperations(operationsG2);
        */

        (operationsG1, operationHashG1) = _operations(_multisigWalletPKOnG1);
        operationsG1[0].aggregatedSignature = _signOnG2(operationHashG1);
        _multisigWalletPKOnG1.submitOperations(operationsG1);
        (operationsG2, operationHashG2) = _operations(_multisigWalletPKOnG2);
        operationsG2[0].aggregatedSignature = _signOnG1(operationHashG2);
        _multisigWalletPKOnG2.submitOperations(operationsG2);

        console.log("case12: Aggregated signature not match public keys");
        bytes memory invalidAggregatedSignatureG2 = operationsG1[0].aggregatedSignature;
        (operationsG1, operationHashG1) = _operations(_multisigWalletPKOnG1);
        operationsG1[0].aggregatedSignature = invalidAggregatedSignatureG2;
        vm.expectRevert(abi.encodeWithSelector(MultisigWallet.AggregatedSignatureNotMatchPublicKeys.selector, 0));
        _multisigWalletPKOnG1.submitOperations(operationsG1);
        bytes memory invalidAggregatedSignatureG1 = operationsG2[0].aggregatedSignature;
        (operationsG2, operationHashG2) = _operations(_multisigWalletPKOnG2);
        operationsG2[0].aggregatedSignature = invalidAggregatedSignatureG1;
        vm.expectRevert(abi.encodeWithSelector(MultisigWallet.AggregatedSignatureNotMatchPublicKeys.selector, 0));
        _multisigWalletPKOnG2.submitOperations(operationsG2);
    }

    function testVerifyInvalidOperations() public {
        vm.expectRevert(MultisigWallet.EmptyOperations.selector);
        _multisigWalletPKOnG1.verifyOperations(new bytes32[](0), new bytes[](0));
        vm.expectRevert(MultisigWallet.EmptyOperations.selector);
        _multisigWalletPKOnG2.verifyOperations(new bytes32[](0), new bytes[](0));

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidValue.selector, "operationsHash_ and aggregatedSignatures_ length mismatch"
            )
        );
        _multisigWalletPKOnG1.verifyOperations(new bytes32[](1), new bytes[](0));
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidValue.selector, "operationsHash_ and aggregatedSignatures_ length mismatch"
            )
        );
        _multisigWalletPKOnG2.verifyOperations(new bytes32[](1), new bytes[](0));

        MultisigWallet.Operation[] memory operationsG1;
        bytes32[] memory operationHashG1;
        MultisigWallet.Operation[] memory operationsG2;
        bytes32[] memory operationHashG2;
        bytes[] memory aggregatedSignaturesG1 = new bytes[](1);
        bytes[] memory aggregatedSignaturesG2 = new bytes[](1);
        aggregatedSignaturesG1[0] = abi.encodePacked("0xff");
        aggregatedSignaturesG2[0] = abi.encodePacked("0xff");
        bytes32 validOpHashG1;
        (operationsG1, validOpHashG1) = _operations(_multisigWalletPKOnG1);
        operationHashG1 = _multisigWalletPKOnG1.submitOperations(operationsG1);
        vm.expectRevert(
            abi.encodeWithSelector(
                MultisigWallet.InvalidSignature.selector, "Invalid aggregated signature length for G1"
            )
        );
        _multisigWalletPKOnG1.verifyOperations(operationHashG1, aggregatedSignaturesG2);
        bytes32 validOpHashG2;
        (operationsG2, validOpHashG2) = _operations(_multisigWalletPKOnG2);
        operationHashG2 = _multisigWalletPKOnG2.submitOperations(operationsG2);
        vm.expectRevert(
            abi.encodeWithSelector(
                MultisigWallet.InvalidSignature.selector, "Invalid aggregated signature length for G2"
            )
        );
        _multisigWalletPKOnG2.verifyOperations(operationHashG2, aggregatedSignaturesG1);

        operationHashG1 = new bytes32[](5);
        operationHashG2 = new bytes32[](5);
        aggregatedSignaturesG1 = new bytes[](5);
        aggregatedSignaturesG2 = new bytes[](5);

        /// @dev op1: unexisting operation
        operationHashG1[0] = keccak256(abi.encodePacked("unexisting operation for wallet PK on G1"));
        aggregatedSignaturesG2[0] = _signOnG2(operationHashG1[0]);
        operationHashG2[0] = keccak256(abi.encodePacked("unexisting operation for wallet PK on G2"));
        aggregatedSignaturesG1[0] = _signOnG1(operationHashG2[0]);
        /// @dev op2: no aggregated signature
        operationHashG1[1] = validOpHashG1;
        aggregatedSignaturesG2[1] = abi.encodePacked("");
        operationHashG2[1] = validOpHashG2;
        aggregatedSignaturesG1[1] = abi.encodePacked("");
        /// @dev op3: not pending operation
        (operationHashG1[2], aggregatedSignaturesG2[2]) = testSubmitOperationsWithSIGToWalletPKOnG1();
        (operationHashG2[2], aggregatedSignaturesG1[2]) = testSubmitOperationsWithSIGToWalletPKOnG2();
        /// @dev op4: valid but not match aggregated signature
        operationHashG1[3] = testSubmitOperationsWithoutSIGToWalletPKOnG1();
        aggregatedSignaturesG2[3] = aggregatedSignaturesG2[2];
        operationHashG2[3] = testSubmitOperationsWithoutSIGToWalletPKOnG2();
        aggregatedSignaturesG1[3] = aggregatedSignaturesG1[2];
        /// @dev op5: valid and match aggregated signature
        operationHashG1[4] = testSubmitOperationsWithoutSIGToWalletPKOnG1();
        aggregatedSignaturesG2[4] = _signOnG2(operationHashG1[4]);
        operationHashG2[4] = testSubmitOperationsWithoutSIGToWalletPKOnG2();
        aggregatedSignaturesG1[4] = _signOnG1(operationHashG2[4]);

        bool[] memory resultsG1 = _multisigWalletPKOnG1.verifyOperations(operationHashG1, aggregatedSignaturesG2);
        assertFalse(resultsG1[0]);
        assertFalse(resultsG1[1]);
        assertFalse(resultsG1[2]);
        assertFalse(resultsG1[3]);
        assertTrue(resultsG1[4]);
        bool[] memory resultsG2 = _multisigWalletPKOnG2.verifyOperations(operationHashG2, aggregatedSignaturesG1);
        assertFalse(resultsG2[0]);
        assertFalse(resultsG2[1]);
        assertFalse(resultsG2[2]);
        assertFalse(resultsG2[3]);
        assertTrue(resultsG2[4]);
    }

    function testExecuteInvalidOperations() public {
        vm.expectRevert(MultisigWallet.EmptyOperations.selector);
        _multisigWalletPKOnG1.executeOperations(new bytes32[](0));
        vm.expectRevert(MultisigWallet.EmptyOperations.selector);
        _multisigWalletPKOnG2.executeOperations(new bytes32[](0));

        MultisigWallet.Operation[] memory operationsG1;
        bytes32[] memory operationHashG1;
        MultisigWallet.Operation[] memory operationsG2;
        bytes32[] memory operationHashG2;

        (operationsG1,) = _operations(_multisigWalletPKOnG1);
        operationHashG1 = _multisigWalletPKOnG1.submitOperations(operationsG1);
        vm.expectRevert(
            abi.encodeWithSelector(
                MultisigWallet.ExecuteUnapprovedOperation.selector, MultisigWallet.OperationStatus.PENDING
            )
        );
        _multisigWalletPKOnG1.executeOperations(operationHashG1);
        (operationsG2,) = _operations(_multisigWalletPKOnG2);
        operationHashG2 = _multisigWalletPKOnG2.submitOperations(operationsG2);
        vm.expectRevert(
            abi.encodeWithSelector(
                MultisigWallet.ExecuteUnapprovedOperation.selector, MultisigWallet.OperationStatus.PENDING
            )
        );
        _multisigWalletPKOnG2.executeOperations(operationHashG2);

        bytes32 operationHash;
        (operationsG1, operationHash) = _operations(_multisigWalletPKOnG1);
        operationsG1[0].aggregatedSignature = _signOnG2(operationHash);
        operationHashG1 = _multisigWalletPKOnG1.submitOperations(operationsG1);
        vm.expectRevert(
            abi.encodeWithSelector(
                MultisigWallet.ExecuteUneffectiveOperation.selector,
                operationsG1[0].effectiveTime,
                uint32(block.timestamp)
            )
        );
        _multisigWalletPKOnG1.executeOperations(operationHashG1);
        (operationsG2, operationHash) = _operations(_multisigWalletPKOnG2);
        operationsG2[0].aggregatedSignature = _signOnG1(operationHash);
        operationHashG2 = _multisigWalletPKOnG2.submitOperations(operationsG2);
        vm.expectRevert(
            abi.encodeWithSelector(
                MultisigWallet.ExecuteUneffectiveOperation.selector,
                operationsG2[0].effectiveTime,
                uint32(block.timestamp)
            )
        );
        _multisigWalletPKOnG2.executeOperations(operationHashG2);

        uint256 currentTime = block.timestamp + 31 days;
        vm.warp(currentTime);
        vm.expectRevert(
            abi.encodeWithSelector(
                MultisigWallet.ExecuteExpiredOperation.selector, operationsG1[0].expirationTime, uint32(currentTime)
            )
        );
        _multisigWalletPKOnG1.executeOperations(operationHashG1);
        vm.expectRevert(
            abi.encodeWithSelector(
                MultisigWallet.ExecuteExpiredOperation.selector, operationsG2[0].expirationTime, uint32(currentTime)
            )
        );
        _multisigWalletPKOnG2.executeOperations(operationHashG2);

        vm.mockCallRevert(operationsG1[0].target, operationsG1[0].data, abi.encode(uint256(0)));
        vm.mockCallRevert(operationsG2[0].target, operationsG2[0].data, abi.encode(uint256(0)));
        vm.warp(block.timestamp - 2 days);
        _multisigWalletPKOnG1.executeOperations(operationHashG1);
        (,,,,,, MultisigWallet.OperationStatus statusG1,,,) = _multisigWalletPKOnG1._operations(operationHashG1[0]);
        assertTrue(statusG1 == MultisigWallet.OperationStatus.FAILED);
        _multisigWalletPKOnG2.executeOperations(operationHashG2);
        (,,,,,, MultisigWallet.OperationStatus statusG2,,,) = _multisigWalletPKOnG2._operations(operationHashG2[0]);
        assertTrue(statusG2 == MultisigWallet.OperationStatus.FAILED);
        vm.clearMockedCalls();
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

    function _signOnG2(bytes32 operationHash_) internal view returns (bytes memory aggregatedSignature_) {
        uint256[] memory sks = new uint256[](_privateKeys.length);
        bytes[] memory messages = new bytes[](_privateKeys.length);

        for (uint256 i = 0; i < _privateKeys.length; i++) {
            sks[i] = _privateKeys[i];
            messages[i] = abi.encode(operationHash_);
        }

        BLS.G2Point memory sigOnG2 = BLSTool.buildSIGsOnG2(sks, messages);

        aggregatedSignature_ = abi.encode(sigOnG2);
    }

    function _signOnG1(bytes32 operationHash_) internal view returns (bytes memory aggregatedSignature_) {
        uint256[] memory sks = new uint256[](_privateKeys.length);
        bytes[] memory messages = new bytes[](_privateKeys.length);

        for (uint256 i = 0; i < _privateKeys.length; i++) {
            sks[i] = _privateKeys[i];
            messages[i] = abi.encode(operationHash_);
        }

        BLS.G1Point memory sigOnG1 = BLSTool.buildSIGsOnG1(sks, messages);

        aggregatedSignature_ = abi.encode(sigOnG1);
    }

    function _calldata() internal view returns (bytes memory calldata_) {
        calldata_ = abi.encodeWithSelector(ERC20.balanceOf.selector, _owner);
    }
}
