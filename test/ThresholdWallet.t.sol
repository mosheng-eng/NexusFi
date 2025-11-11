// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ThresholdWallet} from "src/multisig/ThresholdWallet.sol";
import {BLS} from "../src/multisig/utils/BLS.sol";
import {BLSTool} from "../src/multisig/utils/BLSTool.sol";
import {BLSHelper} from "../src/multisig/utils/BLSHelper.sol";
import {DeployContractSuit} from "../script/DeployContractSuit.s.sol";
import {Errors} from "src/common/Errors.sol";

import {DepositAsset} from "./mock/DepositAsset.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";

import {stdStorage, StdStorage, Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract ThresholdWalletTest is Test {
    using stdStorage for StdStorage;
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

    /// @notice Error thrown when the signers array is empty
    error EmptySigners();

    /// @notice Error thrown when the signers' count does not match the threshold derived from public keys
    error SignersShouldMatchThresholdFromPublicKeys();

    DeployContractSuit internal _deployer = new DeployContractSuit();

    ThresholdWallet internal _thresholdWallet;

    DepositAsset internal _depositAsset = new DepositAsset("Deposit Asset", "DPT");

    ThresholdWallet internal _thresholdWalletPKOnG1;
    ThresholdWallet internal _thresholdWalletPKOnG2;

    uint256[] internal _privateKeys;
    bytes[] internal _publicKeysOnG1;
    bytes[] internal _publicKeysOnG2;
    bytes[] internal _memberIDsOnG1;
    bytes[] internal _memberIDsOnG2;

    address _owner = makeAddr("owner");

    string internal _root;

    uint128 constant THRESHOLD = 2;

    function setUp() public {
        /// @dev read public keys from json file
        _root = vm.projectRoot();
        uint256[] memory privateKeys = new uint256[](3);
        privateKeys[0] = vm.parseUint(string.concat("0x", vm.readFile(string.concat(_root, "/keys/mosheng.key"))));
        privateKeys[1] = vm.parseUint(string.concat("0x", vm.readFile(string.concat(_root, "/keys/mr.silent.key"))));
        privateKeys[2] = vm.parseUint(string.concat("0x", vm.readFile(string.concat(_root, "/keys/liuke.key"))));

        bytes[] memory publicKeysOnG1 = new bytes[](3);
        bytes[] memory publicKeysOnG2 = new bytes[](3);
        bytes[] memory memberIDsOnG1 = new bytes[](3);
        bytes[] memory memberIDsOnG2 = new bytes[](3);
        uint256[] memory thresholdFromPublicKeysOnG1 = new uint256[](3);
        uint256[] memory thresholdFromPublicKeysOnG2 = new uint256[](3);
        BLS.G1Point[] memory thresholdPointsOnG1 = new BLS.G1Point[](3);
        BLS.G2Point[] memory thresholdPointsOnG2 = new BLS.G2Point[](3);

        publicKeysOnG1[0] = abi.encode(_calculateSinglePKOnG1(privateKeys[0]));
        publicKeysOnG1[1] = abi.encode(_calculateSinglePKOnG1(privateKeys[1]));
        publicKeysOnG1[2] = abi.encode(_calculateSinglePKOnG1(privateKeys[2]));

        bytes memory publicKeysOnG1InLine = _concatBytes(publicKeysOnG1);

        thresholdFromPublicKeysOnG1[0] = uint256(keccak256(bytes.concat(publicKeysOnG1[0], publicKeysOnG1InLine)));
        thresholdFromPublicKeysOnG1[1] = uint256(keccak256(bytes.concat(publicKeysOnG1[1], publicKeysOnG1InLine)));
        thresholdFromPublicKeysOnG1[2] = uint256(keccak256(bytes.concat(publicKeysOnG1[2], publicKeysOnG1InLine)));

        thresholdPointsOnG2[0] = BLS.hashToG2(BLS.BLS_DOMAIN, abi.encodePacked(thresholdFromPublicKeysOnG1[0]));
        thresholdPointsOnG2[1] = BLS.hashToG2(BLS.BLS_DOMAIN, abi.encodePacked(thresholdFromPublicKeysOnG1[1]));
        thresholdPointsOnG2[2] = BLS.hashToG2(BLS.BLS_DOMAIN, abi.encodePacked(thresholdFromPublicKeysOnG1[2]));

        memberIDsOnG2[0] =
            abi.encode(_signMemberIDsOnG2(thresholdFromPublicKeysOnG1, privateKeys, thresholdPointsOnG2[0]));
        memberIDsOnG2[1] =
            abi.encode(_signMemberIDsOnG2(thresholdFromPublicKeysOnG1, privateKeys, thresholdPointsOnG2[1]));
        memberIDsOnG2[2] =
            abi.encode(_signMemberIDsOnG2(thresholdFromPublicKeysOnG1, privateKeys, thresholdPointsOnG2[2]));

        publicKeysOnG2[0] = abi.encode(_calculateSinglePKOnG2(privateKeys[0]));
        publicKeysOnG2[1] = abi.encode(_calculateSinglePKOnG2(privateKeys[1]));
        publicKeysOnG2[2] = abi.encode(_calculateSinglePKOnG2(privateKeys[2]));

        bytes memory publicKeysOnG2InLine = _concatBytes(publicKeysOnG2);

        thresholdFromPublicKeysOnG2[0] = uint256(keccak256(bytes.concat(publicKeysOnG2[0], publicKeysOnG2InLine)));
        thresholdFromPublicKeysOnG2[1] = uint256(keccak256(bytes.concat(publicKeysOnG2[1], publicKeysOnG2InLine)));
        thresholdFromPublicKeysOnG2[2] = uint256(keccak256(bytes.concat(publicKeysOnG2[2], publicKeysOnG2InLine)));

        thresholdPointsOnG1[0] = BLS.hashToG1(BLS.BLS_DOMAIN, abi.encodePacked(thresholdFromPublicKeysOnG2[0]));
        thresholdPointsOnG1[1] = BLS.hashToG1(BLS.BLS_DOMAIN, abi.encodePacked(thresholdFromPublicKeysOnG2[1]));
        thresholdPointsOnG1[2] = BLS.hashToG1(BLS.BLS_DOMAIN, abi.encodePacked(thresholdFromPublicKeysOnG2[2]));

        memberIDsOnG1[0] =
            abi.encode(_signMemberIDsOnG1(thresholdFromPublicKeysOnG2, privateKeys, thresholdPointsOnG1[0]));
        memberIDsOnG1[1] =
            abi.encode(_signMemberIDsOnG1(thresholdFromPublicKeysOnG2, privateKeys, thresholdPointsOnG1[1]));
        memberIDsOnG1[2] =
            abi.encode(_signMemberIDsOnG1(thresholdFromPublicKeysOnG2, privateKeys, thresholdPointsOnG1[2]));

        _thresholdWalletPKOnG1 = ThresholdWallet(
            _deployer.deployThresholdWallet(
                _owner, ThresholdWallet.WalletMode.PUBLIC_KEY_ON_G1, THRESHOLD, publicKeysOnG1, memberIDsOnG2
            )
        );
        _thresholdWalletPKOnG2 = ThresholdWallet(
            _deployer.deployThresholdWallet(
                _owner, ThresholdWallet.WalletMode.PUBLIC_KEY_ON_G2, THRESHOLD, publicKeysOnG2, memberIDsOnG1
            )
        );

        _privateKeys.push(privateKeys[0]);
        _privateKeys.push(privateKeys[1]);
        _privateKeys.push(privateKeys[2]);

        _publicKeysOnG1.push(publicKeysOnG1[0]);
        _publicKeysOnG1.push(publicKeysOnG1[1]);
        _publicKeysOnG1.push(publicKeysOnG1[2]);

        _publicKeysOnG2.push(publicKeysOnG2[0]);
        _publicKeysOnG2.push(publicKeysOnG2[1]);
        _publicKeysOnG2.push(publicKeysOnG2[2]);

        _memberIDsOnG1.push(memberIDsOnG1[0]);
        _memberIDsOnG1.push(memberIDsOnG1[1]);
        _memberIDsOnG1.push(memberIDsOnG1[2]);

        _memberIDsOnG2.push(memberIDsOnG2[0]);
        _memberIDsOnG2.push(memberIDsOnG2[1]);
        _memberIDsOnG2.push(memberIDsOnG2[2]);

        _depositAsset.mint(_owner, 10000e6);

        vm.label(_owner, "Owner");
        vm.label(address(_deployer), "Deployer");
        vm.label(address(_depositAsset), "DepositAsset");
        vm.label(address(_thresholdWalletPKOnG1), "ThresholdWalletPKOnG1");
        vm.label(address(_thresholdWalletPKOnG2), "ThresholdWalletPKOnG2");
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

    function testSubmitOperationsWithoutSIGToWalletPKOnG1() public returns (bytes32) {
        (ThresholdWallet.Operation[] memory operations, bytes32 operationHash) = _operations(_thresholdWalletPKOnG1);

        bytes32[] memory operationsHash = _thresholdWalletPKOnG1.submitOperations(operations);

        assertEq(operationsHash.length, 1);
        assertEq(operationsHash[0], operationHash);
        (,,,,,, ThresholdWallet.OperationStatus status,,,) = _thresholdWalletPKOnG1._operations(operationHash);
        assertEq(uint8(status), uint8(ThresholdWallet.OperationStatus.PENDING));

        return operationHash;
    }

    function testSubmitOperationsWithoutSIGToWalletPKOnG2() public returns (bytes32) {
        (ThresholdWallet.Operation[] memory operations, bytes32 operationHash) = _operations(_thresholdWalletPKOnG2);

        bytes32[] memory operationsHash = _thresholdWalletPKOnG2.submitOperations(operations);

        assertEq(operationsHash.length, 1);
        assertEq(operationsHash[0], operationHash);
        (,,,,,, ThresholdWallet.OperationStatus status,,,) = _thresholdWalletPKOnG2._operations(operationHash);
        assertEq(uint8(status), uint8(ThresholdWallet.OperationStatus.PENDING));

        return operationHash;
    }

    function testVerifyOperationsInWalletPKOnG1() public {
        (ThresholdWallet.Operation[] memory operations, bytes32 operationHash) = _operations(_thresholdWalletPKOnG1);

        bytes32[] memory operationsHash = _thresholdWalletPKOnG1.submitOperations(operations);

        assertEq(operationsHash.length, 1);
        assertEq(operationsHash[0], operationHash);
        (,,,,,, ThresholdWallet.OperationStatus status,,,) = _thresholdWalletPKOnG1._operations(operationHash);
        assertEq(uint8(status), uint8(ThresholdWallet.OperationStatus.PENDING));

        bytes[] memory aggregatedSignatures = new bytes[](1);
        bytes[][] memory signers = new bytes[][](1);
        (aggregatedSignatures[0], signers[0]) = _signOnG2(operationHash);

        _thresholdWalletPKOnG1.verifyOperations(operationsHash, aggregatedSignatures, signers);

        (,,,,,, status,,,) = _thresholdWalletPKOnG1._operations(operationHash);
        assertEq(uint8(status), uint8(ThresholdWallet.OperationStatus.APPROVED));

        vm.warp(block.timestamp + 2 days);

        _thresholdWalletPKOnG1.executeOperations(operationsHash);

        (,,,,,, status,,,) = _thresholdWalletPKOnG1._operations(operationHash);
        assertEq(uint8(status), uint8(ThresholdWallet.OperationStatus.EXECUTED));
    }

    function testVerifyOperationsInWalletPKOnG2() public {
        (ThresholdWallet.Operation[] memory operations, bytes32 operationHash) = _operations(_thresholdWalletPKOnG2);

        bytes32[] memory operationsHash = _thresholdWalletPKOnG2.submitOperations(operations);

        assertEq(operationsHash.length, 1);
        assertEq(operationsHash[0], operationHash);
        (,,,,,, ThresholdWallet.OperationStatus status,,,) = _thresholdWalletPKOnG2._operations(operationHash);
        assertEq(uint8(status), uint8(ThresholdWallet.OperationStatus.PENDING));

        bytes[] memory aggregatedSignatures = new bytes[](1);
        bytes[][] memory signers = new bytes[][](1);
        (aggregatedSignatures[0], signers[0]) = _signOnG1(operationHash);

        _thresholdWalletPKOnG2.verifyOperations(operationsHash, aggregatedSignatures, signers);

        (,,,,,, status,,,) = _thresholdWalletPKOnG2._operations(operationHash);
        assertEq(uint8(status), uint8(ThresholdWallet.OperationStatus.APPROVED));

        vm.warp(block.timestamp + 2 days);

        _thresholdWalletPKOnG2.executeOperations(operationsHash);

        (,,,,,, status,,,) = _thresholdWalletPKOnG2._operations(operationHash);
        assertEq(uint8(status), uint8(ThresholdWallet.OperationStatus.EXECUTED));
    }

    function testSubmitOperationsWithSIGToWalletPKOnG1() public returns (bytes32, bytes memory, bytes[] memory) {
        (ThresholdWallet.Operation[] memory operations, bytes32 operationHash) = _operations(_thresholdWalletPKOnG1);
        assertEq(operations.length, 1);

        uint256[] memory sks = new uint256[](2);
        bytes[] memory pks = new bytes[](2);
        BLS.G2Point[] memory memberIDs = new BLS.G2Point[](2);
        BLS.G2Point[] memory messages = new BLS.G2Point[](2);

        sks[0] = _privateKeys[0];
        sks[1] = _privateKeys[1];
        pks[0] = _publicKeysOnG1[0];
        pks[1] = _publicKeysOnG1[1];
        memberIDs[0] = abi.decode(_memberIDsOnG2[0], (BLS.G2Point));
        memberIDs[1] = abi.decode(_memberIDsOnG2[1], (BLS.G2Point));
        messages[0] = BLS.hashToG2(BLS.BLS_DOMAIN, abi.encode(operationHash));
        messages[1] = BLS.hashToG2(BLS.BLS_DOMAIN, abi.encode(operationHash));

        operations[0].aggregatedSignature = abi.encode(
            messages[0].scalarMulPointOnG2(sks[0]).add(memberIDs[0]).add(
                messages[1].scalarMulPointOnG2(sks[1]).add(memberIDs[1])
            )
        );
        operations[0].signers = pks;

        bytes32[] memory operationsHash = _thresholdWalletPKOnG1.submitOperations(operations);

        assertEq(operationsHash.length, 1);
        assertEq(operationsHash[0], operationHash);
        (,,,,,, ThresholdWallet.OperationStatus status,,,) = _thresholdWalletPKOnG1._operations(operationHash);
        assertEq(uint8(status), uint8(ThresholdWallet.OperationStatus.APPROVED));

        return (operationHash, operations[0].aggregatedSignature, operations[0].signers);
    }

    function testSubmitOperationsWithSIGToWalletPKOnG2() public returns (bytes32, bytes memory, bytes[] memory) {
        (ThresholdWallet.Operation[] memory operations, bytes32 operationHash) = _operations(_thresholdWalletPKOnG2);
        assertEq(operations.length, 1);

        uint256[] memory sks = new uint256[](2);
        bytes[] memory pks = new bytes[](2);
        BLS.G1Point[] memory memberIDs = new BLS.G1Point[](2);
        BLS.G1Point[] memory messages = new BLS.G1Point[](2);

        sks[0] = _privateKeys[0];
        sks[1] = _privateKeys[1];
        pks[0] = _publicKeysOnG2[0];
        pks[1] = _publicKeysOnG2[1];
        memberIDs[0] = abi.decode(_memberIDsOnG1[0], (BLS.G1Point));
        memberIDs[1] = abi.decode(_memberIDsOnG1[1], (BLS.G1Point));
        messages[0] = BLS.hashToG1(BLS.BLS_DOMAIN, abi.encode(operationHash));
        messages[1] = BLS.hashToG1(BLS.BLS_DOMAIN, abi.encode(operationHash));

        operations[0].aggregatedSignature = abi.encode(
            messages[0].scalarMulPointOnG1(sks[0]).add(memberIDs[0]).add(
                messages[1].scalarMulPointOnG1(sks[1]).add(memberIDs[1])
            )
        );
        operations[0].signers = pks;

        bytes32[] memory operationsHash = _thresholdWalletPKOnG2.submitOperations(operations);

        assertEq(operationsHash.length, 1);
        assertEq(operationsHash[0], operationHash);
        (,,,,,, ThresholdWallet.OperationStatus status,,,) = _thresholdWalletPKOnG2._operations(operationHash);
        assertEq(uint8(status), uint8(ThresholdWallet.OperationStatus.APPROVED));

        return (operationHash, operations[0].aggregatedSignature, operations[0].signers);
    }

    function testExecuteOperationsToWalletPKOnG1() public {
        (ThresholdWallet.Operation[] memory operations, bytes32 operationHash) = _operations(_thresholdWalletPKOnG1);
        assertEq(operations.length, 1);

        uint256[] memory sks = new uint256[](2);
        bytes[] memory pks = new bytes[](2);
        BLS.G2Point[] memory memberIDs = new BLS.G2Point[](2);
        BLS.G2Point[] memory messages = new BLS.G2Point[](2);

        sks[0] = _privateKeys[0];
        sks[1] = _privateKeys[1];
        pks[0] = _publicKeysOnG1[0];
        pks[1] = _publicKeysOnG1[1];
        memberIDs[0] = abi.decode(_memberIDsOnG2[0], (BLS.G2Point));
        memberIDs[1] = abi.decode(_memberIDsOnG2[1], (BLS.G2Point));
        messages[0] = BLS.hashToG2(BLS.BLS_DOMAIN, abi.encode(operationHash));
        messages[1] = BLS.hashToG2(BLS.BLS_DOMAIN, abi.encode(operationHash));

        operations[0].aggregatedSignature = abi.encode(
            messages[0].scalarMulPointOnG2(sks[0]).add(memberIDs[0]).add(
                messages[1].scalarMulPointOnG2(sks[1]).add(memberIDs[1])
            )
        );
        operations[0].signers = pks;

        bytes32[] memory operationsHash = _thresholdWalletPKOnG1.submitOperations(operations);

        assertEq(operationsHash.length, 1);
        assertEq(operationsHash[0], operationHash);
        (,,,,,, ThresholdWallet.OperationStatus status,,,) = _thresholdWalletPKOnG1._operations(operationHash);
        assertEq(uint8(status), uint8(ThresholdWallet.OperationStatus.APPROVED));

        vm.warp((operations[0].effectiveTime + operations[0].expirationTime) / 2);
        _thresholdWalletPKOnG1.executeOperations(operationsHash);

        (,,,,,, status,,,) = _thresholdWalletPKOnG1._operations(operationHash);
        assertEq(uint8(status), uint8(ThresholdWallet.OperationStatus.EXECUTED));
    }

    function testExecuteOperationsToWalletPKOnG2() public {
        (ThresholdWallet.Operation[] memory operations, bytes32 operationHash) = _operations(_thresholdWalletPKOnG2);
        assertEq(operations.length, 1);

        uint256[] memory sks = new uint256[](2);
        bytes[] memory pks = new bytes[](2);
        BLS.G1Point[] memory memberIDs = new BLS.G1Point[](2);
        BLS.G1Point[] memory messages = new BLS.G1Point[](2);

        sks[0] = _privateKeys[0];
        sks[1] = _privateKeys[1];
        pks[0] = _publicKeysOnG2[0];
        pks[1] = _publicKeysOnG2[1];
        memberIDs[0] = abi.decode(_memberIDsOnG1[0], (BLS.G1Point));
        memberIDs[1] = abi.decode(_memberIDsOnG1[1], (BLS.G1Point));
        messages[0] = BLS.hashToG1(BLS.BLS_DOMAIN, abi.encode(operationHash));
        messages[1] = BLS.hashToG1(BLS.BLS_DOMAIN, abi.encode(operationHash));

        operations[0].aggregatedSignature = abi.encode(
            messages[0].scalarMulPointOnG1(sks[0]).add(memberIDs[0]).add(
                messages[1].scalarMulPointOnG1(sks[1]).add(memberIDs[1])
            )
        );
        operations[0].signers = pks;

        bytes32[] memory operationsHash = _thresholdWalletPKOnG2.submitOperations(operations);

        assertEq(operationsHash.length, 1);
        assertEq(operationsHash[0], operationHash);
        (,,,,,, ThresholdWallet.OperationStatus status,,,) = _thresholdWalletPKOnG2._operations(operationHash);
        assertEq(uint8(status), uint8(ThresholdWallet.OperationStatus.APPROVED));

        vm.warp((operations[0].effectiveTime + operations[0].expirationTime) / 2);
        _thresholdWalletPKOnG2.executeOperations(operationsHash);

        (,,,,,, status,,,) = _thresholdWalletPKOnG2._operations(operationHash);
        assertEq(uint8(status), uint8(ThresholdWallet.OperationStatus.EXECUTED));
    }

    function testInitializedModifier() public {
        ThresholdWallet directCallThresholdWallet = new ThresholdWallet();
        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "Mode or PK is not set"));
        directCallThresholdWallet.submitOperations(new ThresholdWallet.Operation[](0));

        vm.mockCall(BLS.PAIRING, abi.encodeWithSelector(0x00000000), abi.encode(uint256(1)));
        bytes[] memory publicKeysOnG1 = _publicKeysOnG1;
        assertEq(publicKeysOnG1.length, 3);
        publicKeysOnG1[0] = abi.encode(BLS.G1Point(BLS.Unit({upper: 0, lower: 0}), BLS.Unit({upper: 0, lower: 0})));
        publicKeysOnG1[1] = abi.encode(BLS.G1Point(BLS.Unit({upper: 0, lower: 0}), BLS.Unit({upper: 0, lower: 0})));
        publicKeysOnG1[2] = abi.encode(BLS.G1Point(BLS.Unit({upper: 0, lower: 0}), BLS.Unit({upper: 0, lower: 0})));
        ThresholdWallet nondirectCallThresholdWalletG1 = ThresholdWallet(
            address(
                _deployer.deployThresholdWallet(
                    _owner, ThresholdWallet.WalletMode.PUBLIC_KEY_ON_G1, THRESHOLD, publicKeysOnG1, _memberIDsOnG2
                )
            )
        );
        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "Mode or PK is not set"));
        nondirectCallThresholdWalletG1.submitOperations(new ThresholdWallet.Operation[](0));

        bytes[] memory publicKeysOnG2 = _publicKeysOnG2;
        assertEq(publicKeysOnG2.length, 3);
        publicKeysOnG2[0] = abi.encode(
            BLS.G2Point(
                BLS.Unit({upper: 0, lower: 0}),
                BLS.Unit({upper: 0, lower: 0}),
                BLS.Unit({upper: 0, lower: 0}),
                BLS.Unit({upper: 0, lower: 0})
            )
        );
        publicKeysOnG2[1] = abi.encode(
            BLS.G2Point(
                BLS.Unit({upper: 0, lower: 0}),
                BLS.Unit({upper: 0, lower: 0}),
                BLS.Unit({upper: 0, lower: 0}),
                BLS.Unit({upper: 0, lower: 0})
            )
        );
        publicKeysOnG2[2] = abi.encode(
            BLS.G2Point(
                BLS.Unit({upper: 0, lower: 0}),
                BLS.Unit({upper: 0, lower: 0}),
                BLS.Unit({upper: 0, lower: 0}),
                BLS.Unit({upper: 0, lower: 0})
            )
        );
        ThresholdWallet nondirectCallThresholdWalletG2 = ThresholdWallet(
            address(
                _deployer.deployThresholdWallet(
                    _owner, ThresholdWallet.WalletMode.PUBLIC_KEY_ON_G2, THRESHOLD, publicKeysOnG2, _memberIDsOnG1
                )
            )
        );
        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "Mode or PK is not set"));
        nondirectCallThresholdWalletG2.submitOperations(new ThresholdWallet.Operation[](0));
        vm.clearMockedCalls();
    }

    function testInvalidInitialize() public {
        vm.expectRevert(ThresholdWallet.EmptyPublicKey.selector);
        _deployer.deployThresholdWallet(
            _owner, ThresholdWallet.WalletMode.PUBLIC_KEY_ON_G1, THRESHOLD, new bytes[](0), _memberIDsOnG2
        );
        vm.expectRevert(ThresholdWallet.EmptyPublicKey.selector);
        _deployer.deployThresholdWallet(
            _owner, ThresholdWallet.WalletMode.PUBLIC_KEY_ON_G2, THRESHOLD, new bytes[](0), _memberIDsOnG1
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ThresholdWallet.InvalidPublicKey.selector, "Public keys length mismatch with member IDs length"
            )
        );
        _deployer.deployThresholdWallet(
            _owner, ThresholdWallet.WalletMode.PUBLIC_KEY_ON_G1, THRESHOLD, new bytes[](1), _memberIDsOnG2
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                ThresholdWallet.InvalidPublicKey.selector, "Public keys length mismatch with member IDs length"
            )
        );
        _deployer.deployThresholdWallet(
            _owner, ThresholdWallet.WalletMode.PUBLIC_KEY_ON_G2, THRESHOLD, new bytes[](1), _memberIDsOnG1
        );

        vm.expectRevert(ThresholdWallet.ThresholdShouldBetweenOneAndTotalSigners.selector);
        _deployer.deployThresholdWallet(
            _owner, ThresholdWallet.WalletMode.PUBLIC_KEY_ON_G1, 0, _publicKeysOnG1, _memberIDsOnG2
        );
        vm.expectRevert(ThresholdWallet.ThresholdShouldBetweenOneAndTotalSigners.selector);
        _deployer.deployThresholdWallet(
            _owner,
            ThresholdWallet.WalletMode.PUBLIC_KEY_ON_G1,
            uint128(_publicKeysOnG1.length + 1),
            _publicKeysOnG1,
            _memberIDsOnG2
        );
        vm.expectRevert(ThresholdWallet.ThresholdShouldBetweenOneAndTotalSigners.selector);
        _deployer.deployThresholdWallet(
            _owner, ThresholdWallet.WalletMode.PUBLIC_KEY_ON_G2, 0, _publicKeysOnG2, _memberIDsOnG1
        );
        vm.expectRevert(ThresholdWallet.ThresholdShouldBetweenOneAndTotalSigners.selector);
        _deployer.deployThresholdWallet(
            _owner,
            ThresholdWallet.WalletMode.PUBLIC_KEY_ON_G2,
            uint128(_publicKeysOnG2.length + 1),
            _publicKeysOnG2,
            _memberIDsOnG1
        );

        bytes[] memory publicKeysOnG1;

        bytes[] memory publicKeysOnG2;

        publicKeysOnG1 = _publicKeysOnG1;
        assertEq(publicKeysOnG1.length, 3);
        publicKeysOnG1[0] = abi.encode(BLS.Unit({upper: 0, lower: 0}));
        publicKeysOnG1[1] = abi.encode(BLS.Unit({upper: 0, lower: 0}));
        publicKeysOnG1[2] = abi.encode(BLS.Unit({upper: 0, lower: 0}));
        vm.expectRevert(
            abi.encodeWithSelector(ThresholdWallet.InvalidPublicKey.selector, "Invalid public key length for G1")
        );
        _deployer.deployThresholdWallet(
            _owner, ThresholdWallet.WalletMode.PUBLIC_KEY_ON_G1, THRESHOLD, publicKeysOnG1, _memberIDsOnG2
        );
        publicKeysOnG2 = _publicKeysOnG2;
        assertEq(publicKeysOnG2.length, 3);
        publicKeysOnG2[0] = abi.encode(BLS.Unit({upper: 0, lower: 0}));
        publicKeysOnG2[1] = abi.encode(BLS.Unit({upper: 0, lower: 0}));
        publicKeysOnG2[2] = abi.encode(BLS.Unit({upper: 0, lower: 0}));
        vm.expectRevert(
            abi.encodeWithSelector(ThresholdWallet.InvalidPublicKey.selector, "Invalid public key length for G2")
        );
        _deployer.deployThresholdWallet(
            _owner, ThresholdWallet.WalletMode.PUBLIC_KEY_ON_G2, THRESHOLD, publicKeysOnG2, _memberIDsOnG1
        );

        publicKeysOnG1 = _publicKeysOnG1;
        assertEq(publicKeysOnG1.length, 3);
        publicKeysOnG1[0] = abi.encode(BLS.G1Point(BLS.Unit({upper: 0, lower: 0}), BLS.Unit({upper: 0, lower: 0})));
        publicKeysOnG1[1] = abi.encode(BLS.G1Point(BLS.Unit({upper: 0, lower: 0}), BLS.Unit({upper: 0, lower: 0})));
        publicKeysOnG1[2] = abi.encode(BLS.G1Point(BLS.Unit({upper: 0, lower: 0}), BLS.Unit({upper: 0, lower: 0})));
        vm.expectRevert(
            abi.encodeWithSelector(
                ThresholdWallet.InvalidSignature.selector, "Member ID does not match public key on G1"
            )
        );
        _deployer.deployThresholdWallet(
            _owner, ThresholdWallet.WalletMode.PUBLIC_KEY_ON_G1, THRESHOLD, publicKeysOnG1, _memberIDsOnG2
        );
        publicKeysOnG2 = _publicKeysOnG2;
        assertEq(publicKeysOnG2.length, 3);
        publicKeysOnG2[0] = abi.encode(
            BLS.G2Point(
                BLS.Unit({upper: 0, lower: 0}),
                BLS.Unit({upper: 0, lower: 0}),
                BLS.Unit({upper: 0, lower: 0}),
                BLS.Unit({upper: 0, lower: 0})
            )
        );
        publicKeysOnG2[1] = abi.encode(
            BLS.G2Point(
                BLS.Unit({upper: 0, lower: 0}),
                BLS.Unit({upper: 0, lower: 0}),
                BLS.Unit({upper: 0, lower: 0}),
                BLS.Unit({upper: 0, lower: 0})
            )
        );
        publicKeysOnG2[2] = abi.encode(
            BLS.G2Point(
                BLS.Unit({upper: 0, lower: 0}),
                BLS.Unit({upper: 0, lower: 0}),
                BLS.Unit({upper: 0, lower: 0}),
                BLS.Unit({upper: 0, lower: 0})
            )
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                ThresholdWallet.InvalidSignature.selector, "Member ID does not match public key on G2"
            )
        );
        _deployer.deployThresholdWallet(
            _owner, ThresholdWallet.WalletMode.PUBLIC_KEY_ON_G2, THRESHOLD, publicKeysOnG2, _memberIDsOnG1
        );

        vm.expectRevert(abi.encodeWithSelector(ThresholdWallet.UnsupportedWalletMode.selector, 0));
        _deployer.deployThresholdWallet(
            _owner, ThresholdWallet.WalletMode.UNKNOWN, THRESHOLD, publicKeysOnG1, _memberIDsOnG2
        );
    }

    function testSubmitInvalidOperations() public {
        console.log("case1: empty operations");
        vm.expectRevert(ThresholdWallet.EmptyOperations.selector);
        _thresholdWalletPKOnG1.submitOperations(new ThresholdWallet.Operation[](0));
        vm.expectRevert(ThresholdWallet.EmptyOperations.selector);
        _thresholdWalletPKOnG2.submitOperations(new ThresholdWallet.Operation[](0));

        ThresholdWallet.Operation[] memory operationsG1;
        bytes32 operationHashG1;
        ThresholdWallet.Operation[] memory operationsG2;
        bytes32 operationHashG2;

        console.log("case2: target is zero address");
        (operationsG1, operationHashG1) = _operations(_thresholdWalletPKOnG1);
        operationsG1[0].target = address(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "Operation.target"));
        _thresholdWalletPKOnG1.submitOperations(operationsG1);
        (operationsG2, operationHashG2) = _operations(_thresholdWalletPKOnG2);
        operationsG2[0].target = address(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "Operation.target"));
        _thresholdWalletPKOnG2.submitOperations(operationsG2);

        console.log("case3: Operation.expirationTime earlier than Operation.effectiveTime");
        (operationsG1, operationHashG1) = _operations(_thresholdWalletPKOnG1);
        operationsG1[0].expirationTime = operationsG1[0].effectiveTime - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidValue.selector, "Operation.expirationTime earlier than Operation.effectiveTime"
            )
        );
        _thresholdWalletPKOnG1.submitOperations(operationsG1);
        (operationsG2, operationHashG2) = _operations(_thresholdWalletPKOnG2);
        operationsG2[0].expirationTime = operationsG2[0].effectiveTime - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidValue.selector, "Operation.expirationTime earlier than Operation.effectiveTime"
            )
        );
        _thresholdWalletPKOnG2.submitOperations(operationsG2);

        console.log("case4: Operation.expirationTime earlier than current time");
        (operationsG1, operationHashG1) = _operations(_thresholdWalletPKOnG1);
        vm.warp(block.timestamp + 30 days + 1 minutes);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.expirationTime earlier than current time")
        );
        _thresholdWalletPKOnG1.submitOperations(operationsG1);
        (operationsG2, operationHashG2) = _operations(_thresholdWalletPKOnG2);
        vm.warp(block.timestamp + 30 days + 1 minutes);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.expirationTime earlier than current time")
        );
        _thresholdWalletPKOnG2.submitOperations(operationsG2);

        console.log("case5: Operation.gasLimit too low");
        (operationsG1, operationHashG1) = _operations(_thresholdWalletPKOnG1);
        operationsG1[0].gasLimit = 21000 - 1;
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.gasLimit too low"));
        _thresholdWalletPKOnG1.submitOperations(operationsG1);
        (operationsG2, operationHashG2) = _operations(_thresholdWalletPKOnG2);
        operationsG2[0].gasLimit = 21000 - 1;
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.gasLimit too low"));
        _thresholdWalletPKOnG2.submitOperations(operationsG2);

        console.log("case6: Operation.nonce invalid");
        (operationsG1, operationHashG1) = _operations(_thresholdWalletPKOnG1);
        operationsG1[0].nonce = operationsG1[0].nonce + 1;
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.nonce invalid"));
        _thresholdWalletPKOnG1.submitOperations(operationsG1);
        (operationsG2, operationHashG2) = _operations(_thresholdWalletPKOnG2);
        operationsG2[0].nonce = operationsG2[0].nonce + 1;
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.nonce invalid"));
        _thresholdWalletPKOnG2.submitOperations(operationsG2);

        console.log("case7: Operation.hashCheckCode invalid");
        (operationsG1, operationHashG1) = _operations(_thresholdWalletPKOnG1);
        operationsG1[0].hashCheckCode = bytes8(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.hashCheckCode invalid"));
        _thresholdWalletPKOnG1.submitOperations(operationsG1);
        (operationsG2, operationHashG2) = _operations(_thresholdWalletPKOnG2);
        operationsG2[0].hashCheckCode = bytes8(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.hashCheckCode invalid"));
        _thresholdWalletPKOnG2.submitOperations(operationsG2);

        console.log("case8: Operation.data too short");
        (operationsG1, operationHashG1) = _operations(_thresholdWalletPKOnG1);
        operationsG1[0].data = new bytes(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.data too short"));
        _thresholdWalletPKOnG1.submitOperations(operationsG1);
        (operationsG2, operationHashG2) = _operations(_thresholdWalletPKOnG2);
        operationsG2[0].data = new bytes(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.data too short"));
        _thresholdWalletPKOnG2.submitOperations(operationsG2);

        console.log("case9: Operation.aggregatedSignature invalid");
        (operationsG1, operationHashG1) = _operations(_thresholdWalletPKOnG1);
        operationsG1[0].aggregatedSignature = abi.encodePacked("0xff");
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.aggregatedSignature invalid"));
        _thresholdWalletPKOnG1.submitOperations(operationsG1);
        (operationsG2, operationHashG2) = _operations(_thresholdWalletPKOnG2);
        operationsG2[0].aggregatedSignature = abi.encodePacked("0xff");
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.aggregatedSignature invalid"));
        _thresholdWalletPKOnG2.submitOperations(operationsG2);

        console.log("case10: Signers not enough");
        (operationsG1, operationHashG1) = _operations(_thresholdWalletPKOnG1);
        operationsG1[0].signers = new bytes[](1);
        vm.expectRevert(ThresholdWallet.SignersNotEnough.selector);
        _thresholdWalletPKOnG1.submitOperations(operationsG1);
        (operationsG2, operationHashG2) = _operations(_thresholdWalletPKOnG2);
        operationsG2[0].signers = new bytes[](1);
        vm.expectRevert(ThresholdWallet.SignersNotEnough.selector);
        _thresholdWalletPKOnG2.submitOperations(operationsG2);

        console.log("case11: Operation.hashCheckCode mismatch");
        (operationsG1, operationHashG1) = _operations(_thresholdWalletPKOnG1);
        operationsG1[0].hashCheckCode = bytes8(keccak256(abi.encodePacked("mismatch")));
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.hashCheckCode mismatch"));
        _thresholdWalletPKOnG1.submitOperations(operationsG1);
        (operationsG2, operationHashG2) = _operations(_thresholdWalletPKOnG2);
        operationsG2[0].hashCheckCode = bytes8(keccak256(abi.encodePacked("mismatch")));
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "Operation.hashCheckCode mismatch"));
        _thresholdWalletPKOnG2.submitOperations(operationsG2);

        console.log("case12: Operation already exists (impossible)");

        /*
        // This is impossible to happen based on current protocol design, so comment it out.
        console.log("case11: Operation already exists");
        (operationsG1, operationHashG1) = _operations(_thresholdWalletPKOnG1);
        _thresholdWalletPKOnG1.submitOperations(operationsG1);
        operationsG1[0].nonce = operationsG1[0].nonce + 1;
        vm.expectRevert(ThresholdWallet.OperationExists.selector);
        _thresholdWalletPKOnG1.submitOperations(operationsG1);
        (operationsG2, operationHashG2) = _operations(_thresholdWalletPKOnG2);
        _thresholdWalletPKOnG2.submitOperations(operationsG2);
        operationsG2[0].nonce = operationsG2[0].nonce + 1;
        vm.expectRevert(ThresholdWallet.OperationExists.selector);
        _thresholdWalletPKOnG2.submitOperations(operationsG2);
        */

        (operationsG1, operationHashG1) = _operations(_thresholdWalletPKOnG1);
        (operationsG1[0].aggregatedSignature, operationsG1[0].signers) = _signOnG2(operationHashG1);
        _thresholdWalletPKOnG1.submitOperations(operationsG1);
        (operationsG2, operationHashG2) = _operations(_thresholdWalletPKOnG2);
        (operationsG2[0].aggregatedSignature, operationsG2[0].signers) = _signOnG1(operationHashG2);
        _thresholdWalletPKOnG2.submitOperations(operationsG2);

        console.log("case13: Aggregated signature not match public keys");
        bytes memory invalidAggregatedSignatureG2 = operationsG1[0].aggregatedSignature;
        (operationsG1, operationHashG1) = _operations(_thresholdWalletPKOnG1);
        (operationsG1[0].aggregatedSignature, operationsG1[0].signers) = _signOnG2(operationHashG1);
        operationsG1[0].aggregatedSignature = invalidAggregatedSignatureG2;
        vm.expectRevert(abi.encodeWithSelector(ThresholdWallet.AggregatedSignatureNotMatchPublicKeys.selector, 0));
        _thresholdWalletPKOnG1.submitOperations(operationsG1);
        bytes memory invalidAggregatedSignatureG1 = operationsG2[0].aggregatedSignature;
        (operationsG2, operationHashG2) = _operations(_thresholdWalletPKOnG2);
        (operationsG2[0].aggregatedSignature, operationsG2[0].signers) = _signOnG1(operationHashG2);
        operationsG2[0].aggregatedSignature = invalidAggregatedSignatureG1;
        vm.expectRevert(abi.encodeWithSelector(ThresholdWallet.AggregatedSignatureNotMatchPublicKeys.selector, 0));
        _thresholdWalletPKOnG2.submitOperations(operationsG2);
    }

    function testVerifyInvalidOperations() public {
        console.log("case1: empty operations");
        vm.expectRevert(ThresholdWallet.EmptyOperations.selector);
        _thresholdWalletPKOnG1.verifyOperations(new bytes32[](0), new bytes[](0), new bytes[][](0));
        vm.expectRevert(ThresholdWallet.EmptyOperations.selector);
        _thresholdWalletPKOnG2.verifyOperations(new bytes32[](0), new bytes[](0), new bytes[][](0));

        console.log("case2: operationsHash_ and aggregatedSignatures_ length mismatch");
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidValue.selector, "operationsHash_ and aggregatedSignatures_ length mismatch"
            )
        );
        _thresholdWalletPKOnG1.verifyOperations(new bytes32[](1), new bytes[](0), new bytes[][](0));
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.InvalidValue.selector, "operationsHash_ and aggregatedSignatures_ length mismatch"
            )
        );
        _thresholdWalletPKOnG2.verifyOperations(new bytes32[](1), new bytes[](0), new bytes[][](0));

        console.log("case3: operationsHash_ and signers_ length mismatch");
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidValue.selector, "operationsHash_ and signers_ length mismatch")
        );
        _thresholdWalletPKOnG1.verifyOperations(new bytes32[](1), new bytes[](1), new bytes[][](0));
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidValue.selector, "operationsHash_ and signers_ length mismatch")
        );
        _thresholdWalletPKOnG2.verifyOperations(new bytes32[](1), new bytes[](1), new bytes[][](0));

        console.log("case4: invalid aggregated signature length");
        ThresholdWallet.Operation[] memory operationsG1;
        bytes32[] memory operationHashG1;
        bytes[][] memory signersG1 = new bytes[][](1);
        ThresholdWallet.Operation[] memory operationsG2;
        bytes32[] memory operationHashG2;
        bytes[][] memory signersG2 = new bytes[][](1);
        bytes[] memory aggregatedSignaturesG1 = new bytes[](1);
        bytes[] memory aggregatedSignaturesG2 = new bytes[](1);
        aggregatedSignaturesG1[0] = abi.encodePacked("0xff");
        aggregatedSignaturesG2[0] = abi.encodePacked("0xff");
        bytes32 validOpHashG1;
        (operationsG1, validOpHashG1) = _operations(_thresholdWalletPKOnG1);
        operationHashG1 = _thresholdWalletPKOnG1.submitOperations(operationsG1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ThresholdWallet.InvalidSignature.selector, "Invalid aggregated signature length for G1"
            )
        );
        _thresholdWalletPKOnG1.verifyOperations(operationHashG1, aggregatedSignaturesG2, signersG1);
        bytes32 validOpHashG2;
        (operationsG2, validOpHashG2) = _operations(_thresholdWalletPKOnG2);
        operationHashG2 = _thresholdWalletPKOnG2.submitOperations(operationsG2);
        vm.expectRevert(
            abi.encodeWithSelector(
                ThresholdWallet.InvalidSignature.selector, "Invalid aggregated signature length for G2"
            )
        );
        _thresholdWalletPKOnG2.verifyOperations(operationHashG2, aggregatedSignaturesG1, signersG2);

        console.log("case5: unrecognized signers");
        operationHashG1[0] = testSubmitOperationsWithoutSIGToWalletPKOnG1();
        (aggregatedSignaturesG2[0], signersG1[0]) = _signOnG2(operationHashG1[0]);
        signersG1[0][0] = bytes.concat(bytes1(0xff), signersG1[0][0].slice(1));
        operationHashG2[0] = testSubmitOperationsWithoutSIGToWalletPKOnG2();
        (aggregatedSignaturesG1[0], signersG2[0]) = _signOnG1(operationHashG2[0]);
        signersG2[0][0] = bytes.concat(bytes1(0xff), signersG2[0][0].slice(1));
        vm.expectRevert(abi.encodeWithSelector(ThresholdWallet.UnrecognizedSigner.selector, keccak256(signersG1[0][0])));
        _thresholdWalletPKOnG1.verifyOperations(operationHashG1, aggregatedSignaturesG2, signersG1);
        vm.expectRevert(abi.encodeWithSelector(ThresholdWallet.UnrecognizedSigner.selector, keccak256(signersG2[0][0])));
        _thresholdWalletPKOnG2.verifyOperations(operationHashG2, aggregatedSignaturesG1, signersG2);

        console.log("case6: unsupported wallet mode(impossible)");
        /*
        operationHashG1[0] = testSubmitOperationsWithoutSIGToWalletPKOnG1();
        (aggregatedSignaturesG2[0], signersG1[0]) = _signOnG2(operationHashG1[0]);
        operationHashG2[0] = testSubmitOperationsWithoutSIGToWalletPKOnG2();
        (aggregatedSignaturesG1[0], signersG2[0]) = _signOnG1(operationHashG2[0]);
        console.log("debug: find wallet mode storage slot on G1");
        uint256 slotOnG1 =
            stdstore.target(address(_thresholdWalletPKOnG1)).sig(ThresholdWallet.readWalletMode.selector).find();
        console.log("slotOnG1: %s", slotOnG1);
        stdstore.target(address(_thresholdWalletPKOnG1)).sig(ThresholdWallet.readWalletMode.selector).checked_write(
            uint256(uint8(ThresholdWallet.WalletMode.UNKNOWN))
        );
        vm.expectRevert(
            abi.encodeWithSelector(ThresholdWallet.UnsupportedWalletMode.selector, ThresholdWallet.WalletMode.UNKNOWN)
        );
        _thresholdWalletPKOnG1.verifyOperations(operationHashG1, aggregatedSignaturesG2, signersG1);
        stdstore.target(address(_thresholdWalletPKOnG1)).sig(ThresholdWallet.readWalletMode.selector).checked_write(
            uint256(uint8(ThresholdWallet.WalletMode.PUBLIC_KEY_ON_G1))
        );
        console.log("debug: find wallet mode storage slot on G1");
        uint256 slotOnG2 =
            stdstore.target(address(_thresholdWalletPKOnG2)).sig(ThresholdWallet.readWalletMode.selector).find();
        console.log("slotOnG2: %s", slotOnG2);
        stdstore.target(address(_thresholdWalletPKOnG2)).sig(ThresholdWallet.readWalletMode.selector).checked_write(
            uint256(uint8(ThresholdWallet.WalletMode.UNKNOWN))
        );
        vm.expectRevert(
            abi.encodeWithSelector(ThresholdWallet.UnsupportedWalletMode.selector, ThresholdWallet.WalletMode.UNKNOWN)
        );
        _thresholdWalletPKOnG2.verifyOperations(operationHashG2, aggregatedSignaturesG1, signersG2);
        stdstore.target(address(_thresholdWalletPKOnG2)).sig(ThresholdWallet.readWalletMode.selector).checked_write(
            uint256(uint8(ThresholdWallet.WalletMode.PUBLIC_KEY_ON_G2))
        );*/

        operationHashG1 = new bytes32[](5);
        operationHashG2 = new bytes32[](5);
        aggregatedSignaturesG1 = new bytes[](5);
        aggregatedSignaturesG2 = new bytes[](5);
        signersG1 = new bytes[][](5);
        signersG2 = new bytes[][](5);

        /// @dev op1: unexisting operation
        console.log("case6: five different situations");
        operationHashG1[0] = keccak256(abi.encodePacked("unexisting operation for wallet PK on G1"));
        (aggregatedSignaturesG2[0], signersG1[0]) = _signOnG2(operationHashG1[0]);
        operationHashG2[0] = keccak256(abi.encodePacked("unexisting operation for wallet PK on G2"));
        (aggregatedSignaturesG1[0], signersG2[0]) = _signOnG1(operationHashG2[0]);
        /// @dev op2: no aggregated signature
        operationHashG1[1] = validOpHashG1;
        aggregatedSignaturesG2[1] = abi.encodePacked("");
        signersG1[1] = new bytes[](0);
        operationHashG2[1] = validOpHashG2;
        aggregatedSignaturesG1[1] = abi.encodePacked("");
        signersG2[1] = new bytes[](0);
        /// @dev op3: not pending operation
        (operationHashG1[2], aggregatedSignaturesG2[2], signersG1[2]) = testSubmitOperationsWithSIGToWalletPKOnG1();
        (operationHashG2[2], aggregatedSignaturesG1[2], signersG2[2]) = testSubmitOperationsWithSIGToWalletPKOnG2();
        /// @dev op4: valid but not match aggregated signature
        operationHashG1[3] = testSubmitOperationsWithoutSIGToWalletPKOnG1();
        aggregatedSignaturesG2[3] = aggregatedSignaturesG2[2];
        signersG1[3] = signersG1[2];
        operationHashG2[3] = testSubmitOperationsWithoutSIGToWalletPKOnG2();
        aggregatedSignaturesG1[3] = aggregatedSignaturesG1[2];
        signersG2[3] = signersG2[2];
        /// @dev op5: valid and match aggregated signature
        operationHashG1[4] = testSubmitOperationsWithoutSIGToWalletPKOnG1();
        (aggregatedSignaturesG2[4], signersG1[4]) = _signOnG2(operationHashG1[4]);
        operationHashG2[4] = testSubmitOperationsWithoutSIGToWalletPKOnG2();
        (aggregatedSignaturesG1[4], signersG2[4]) = _signOnG1(operationHashG2[4]);

        bool[] memory resultsG1 =
            _thresholdWalletPKOnG1.verifyOperations(operationHashG1, aggregatedSignaturesG2, signersG1);
        assertFalse(resultsG1[0]);
        assertFalse(resultsG1[1]);
        assertFalse(resultsG1[2]);
        assertFalse(resultsG1[3]);
        assertTrue(resultsG1[4]);
        bool[] memory resultsG2 =
            _thresholdWalletPKOnG2.verifyOperations(operationHashG2, aggregatedSignaturesG1, signersG2);
        assertFalse(resultsG2[0]);
        assertFalse(resultsG2[1]);
        assertFalse(resultsG2[2]);
        assertFalse(resultsG2[3]);
        assertTrue(resultsG2[4]);
    }

    function testExecuteInvalidOperations() public {
        vm.expectRevert(ThresholdWallet.EmptyOperations.selector);
        _thresholdWalletPKOnG1.executeOperations(new bytes32[](0));
        vm.expectRevert(ThresholdWallet.EmptyOperations.selector);
        _thresholdWalletPKOnG2.executeOperations(new bytes32[](0));

        ThresholdWallet.Operation[] memory operationsG1;
        bytes32[] memory operationHashG1;
        ThresholdWallet.Operation[] memory operationsG2;
        bytes32[] memory operationHashG2;

        (operationsG1,) = _operations(_thresholdWalletPKOnG1);
        operationHashG1 = _thresholdWalletPKOnG1.submitOperations(operationsG1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ThresholdWallet.ExecuteUnapprovedOperation.selector, ThresholdWallet.OperationStatus.PENDING
            )
        );
        _thresholdWalletPKOnG1.executeOperations(operationHashG1);
        (operationsG2,) = _operations(_thresholdWalletPKOnG2);
        operationHashG2 = _thresholdWalletPKOnG2.submitOperations(operationsG2);
        vm.expectRevert(
            abi.encodeWithSelector(
                ThresholdWallet.ExecuteUnapprovedOperation.selector, ThresholdWallet.OperationStatus.PENDING
            )
        );
        _thresholdWalletPKOnG2.executeOperations(operationHashG2);

        bytes32 operationHash;
        (operationsG1, operationHash) = _operations(_thresholdWalletPKOnG1);
        (operationsG1[0].aggregatedSignature, operationsG1[0].signers) = _signOnG2(operationHash);
        operationHashG1 = _thresholdWalletPKOnG1.submitOperations(operationsG1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ThresholdWallet.ExecuteUneffectiveOperation.selector,
                operationsG1[0].effectiveTime,
                uint32(block.timestamp)
            )
        );
        _thresholdWalletPKOnG1.executeOperations(operationHashG1);
        (operationsG2, operationHash) = _operations(_thresholdWalletPKOnG2);
        (operationsG2[0].aggregatedSignature, operationsG2[0].signers) = _signOnG1(operationHash);
        operationHashG2 = _thresholdWalletPKOnG2.submitOperations(operationsG2);
        vm.expectRevert(
            abi.encodeWithSelector(
                ThresholdWallet.ExecuteUneffectiveOperation.selector,
                operationsG2[0].effectiveTime,
                uint32(block.timestamp)
            )
        );
        _thresholdWalletPKOnG2.executeOperations(operationHashG2);

        uint256 currentTime = block.timestamp + 31 days;
        vm.warp(currentTime);
        vm.expectRevert(
            abi.encodeWithSelector(
                ThresholdWallet.ExecuteExpiredOperation.selector, operationsG1[0].expirationTime, uint32(currentTime)
            )
        );
        _thresholdWalletPKOnG1.executeOperations(operationHashG1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ThresholdWallet.ExecuteExpiredOperation.selector, operationsG2[0].expirationTime, uint32(currentTime)
            )
        );
        _thresholdWalletPKOnG2.executeOperations(operationHashG2);

        vm.mockCallRevert(operationsG1[0].target, operationsG1[0].data, abi.encode(uint256(0)));
        vm.mockCallRevert(operationsG2[0].target, operationsG2[0].data, abi.encode(uint256(0)));
        vm.warp(block.timestamp - 2 days);
        _thresholdWalletPKOnG1.executeOperations(operationHashG1);
        (,,,,,, ThresholdWallet.OperationStatus statusG1,,,) = _thresholdWalletPKOnG1._operations(operationHashG1[0]);
        assertTrue(statusG1 == ThresholdWallet.OperationStatus.FAILED);
        _thresholdWalletPKOnG2.executeOperations(operationHashG2);
        (,,,,,, ThresholdWallet.OperationStatus statusG2,,,) = _thresholdWalletPKOnG2._operations(operationHashG2[0]);
        assertTrue(statusG2 == ThresholdWallet.OperationStatus.FAILED);
        vm.clearMockedCalls();
    }

    function testReadWalletMode() public view {
        ThresholdWallet.WalletMode modeOnG1 = _thresholdWalletPKOnG1.readWalletMode();
        assertEq(uint8(modeOnG1), uint8(ThresholdWallet.WalletMode.PUBLIC_KEY_ON_G1));
        ThresholdWallet.WalletMode modeOnG2 = _thresholdWalletPKOnG2.readWalletMode();
        assertEq(uint8(modeOnG2), uint8(ThresholdWallet.WalletMode.PUBLIC_KEY_ON_G2));
    }

    /// @notice Concatenate an array of bytes into a single bytes array
    /// @param bytesArray_ The array of bytes to concatenate
    /// @return bytesSingle_ The concatenated bytes array
    function _concatBytes(bytes[] memory bytesArray_) internal pure returns (bytes memory bytesSingle_) {
        for (uint256 i = 0; i < bytesArray_.length; ++i) {
            bytesSingle_ = abi.encodePacked(bytesSingle_, bytesArray_[i]);
        }
    }

    function _signMemberIDsOnG1(
        uint256[] memory thresholdFromPublicKeysOnG2_,
        uint256[] memory privateKeys_,
        BLS.G1Point memory thresholdPointOnG1_
    ) internal view returns (BLS.G1Point memory memberIDOnG1_) {
        uint256 len = privateKeys_.length;
        if (len == 0) {
            revert EmptySigners();
        }
        if (thresholdFromPublicKeysOnG2_.length != len) {
            revert SignersShouldMatchThresholdFromPublicKeys();
        }
        BLS.G1Point[] memory pointsOnG1 = new BLS.G1Point[](len);

        for (uint256 i = 0; i < len; ++i) {
            pointsOnG1[i] = thresholdPointOnG1_.scalarMulPointOnG1(privateKeys_[i]).scalarMulPointOnG1(
                thresholdFromPublicKeysOnG2_[i]
            );
        }

        memberIDOnG1_ = pointsOnG1.sumPointsOnG1();
    }

    function _signMemberIDsOnG2(
        uint256[] memory thresholdFromPublicKeysOnG1_,
        uint256[] memory privateKeys_,
        BLS.G2Point memory thresholdPointOnG2_
    ) internal view returns (BLS.G2Point memory memberIDOnG2_) {
        uint256 len = privateKeys_.length;
        if (len == 0) {
            revert EmptySigners();
        }
        if (thresholdFromPublicKeysOnG1_.length != len) {
            revert SignersShouldMatchThresholdFromPublicKeys();
        }
        BLS.G2Point[] memory pointsOnG2 = new BLS.G2Point[](len);

        for (uint256 i = 0; i < len; ++i) {
            pointsOnG2[i] = thresholdPointOnG2_.scalarMulPointOnG2(privateKeys_[i]).scalarMulPointOnG2(
                thresholdFromPublicKeysOnG1_[i]
            );
        }

        memberIDOnG2_ = pointsOnG2.sumPointsOnG2();
    }

    function _calculateSinglePKOnG1(uint256 privateKey_) internal view returns (BLS.G1Point memory pkOnG1_) {
        uint256[] memory privateKeyArray = new uint256[](1);
        privateKeyArray[0] = privateKey_;
        return BLSTool.calculatePKsOnG1(privateKeyArray);
    }

    function _calculateSinglePKOnG2(uint256 privateKey_) internal view returns (BLS.G2Point memory pkOnG2_) {
        uint256[] memory privateKeyArray = new uint256[](1);
        privateKeyArray[0] = privateKey_;
        return BLSTool.calculatePKsOnG2(privateKeyArray);
    }

    function _operations(ThresholdWallet thresholdWallet_)
        internal
        view
        returns (ThresholdWallet.Operation[] memory operations_, bytes32 operationHash_)
    {
        operations_ = new ThresholdWallet.Operation[](1);
        operations_[0].target = address(_depositAsset);
        operations_[0].value = 0;
        operations_[0].effectiveTime = uint32(block.timestamp + 1 days);
        operations_[0].expirationTime = uint32(block.timestamp + 30 days);
        operations_[0].gasLimit = uint32(gasleft());
        operations_[0].nonce = thresholdWallet_._nonce();
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

    function _signOnG2(bytes32 operationHash_)
        internal
        view
        returns (bytes memory aggregatedSignature_, bytes[] memory signers_)
    {
        uint256[] memory sks = new uint256[](2);
        bytes[] memory pks = new bytes[](2);
        BLS.G2Point[] memory memberIDs = new BLS.G2Point[](2);
        BLS.G2Point[] memory messages = new BLS.G2Point[](2);

        sks[0] = _privateKeys[0];
        sks[1] = _privateKeys[1];
        pks[0] = _publicKeysOnG1[0];
        pks[1] = _publicKeysOnG1[1];
        memberIDs[0] = abi.decode(_memberIDsOnG2[0], (BLS.G2Point));
        memberIDs[1] = abi.decode(_memberIDsOnG2[1], (BLS.G2Point));
        messages[0] = BLS.hashToG2(BLS.BLS_DOMAIN, abi.encode(operationHash_));
        messages[1] = BLS.hashToG2(BLS.BLS_DOMAIN, abi.encode(operationHash_));

        aggregatedSignature_ = abi.encode(
            messages[0].scalarMulPointOnG2(sks[0]).add(memberIDs[0]).add(
                messages[1].scalarMulPointOnG2(sks[1]).add(memberIDs[1])
            )
        );
        signers_ = pks;
    }

    function _signOnG1(bytes32 operationHash_)
        internal
        view
        returns (bytes memory aggregatedSignature_, bytes[] memory signers_)
    {
        uint256[] memory sks = new uint256[](2);
        bytes[] memory pks = new bytes[](2);
        BLS.G1Point[] memory memberIDs = new BLS.G1Point[](2);
        BLS.G1Point[] memory messages = new BLS.G1Point[](2);

        sks[0] = _privateKeys[0];
        sks[1] = _privateKeys[1];
        pks[0] = _publicKeysOnG2[0];
        pks[1] = _publicKeysOnG2[1];
        memberIDs[0] = abi.decode(_memberIDsOnG1[0], (BLS.G1Point));
        memberIDs[1] = abi.decode(_memberIDsOnG1[1], (BLS.G1Point));
        messages[0] = BLS.hashToG1(BLS.BLS_DOMAIN, abi.encode(operationHash_));
        messages[1] = BLS.hashToG1(BLS.BLS_DOMAIN, abi.encode(operationHash_));

        aggregatedSignature_ = abi.encode(
            messages[0].scalarMulPointOnG1(sks[0]).add(memberIDs[0]).add(
                messages[1].scalarMulPointOnG1(sks[1]).add(memberIDs[1])
            )
        );
        signers_ = pks;
    }

    function _calldata() internal view returns (bytes memory calldata_) {
        calldata_ = abi.encodeWithSelector(ERC20.balanceOf.selector, _owner);
    }
}
