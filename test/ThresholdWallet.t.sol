// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ThresholdWallet} from "src/multisig/ThresholdWallet.sol";
import {BLS} from "../src/multisig/utils/BLS.sol";
import {BLSTool} from "../src/multisig/utils/BLSTool.sol";
import {BLSHelper} from "../src/multisig/utils/BLSHelper.sol";
import {DeployContractSuit} from "../script/DeployContractSuit.s.sol";

import {DepositAsset} from "./mock/DepositAsset.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract ThresholdWalletTest is Test {
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

    function testSubmitOperationsWithoutSIGToWalletPKOnG1() public {
        (ThresholdWallet.Operation[] memory operations, bytes32 operationHash) = _operations(_thresholdWalletPKOnG1);

        bytes32[] memory operationsHash = _thresholdWalletPKOnG1.submitOperations(operations);

        assertEq(operationsHash.length, 1);
        assertEq(operationsHash[0], operationHash);
        (,,,,,, ThresholdWallet.OperationStatus status,,,) = _thresholdWalletPKOnG1._operations(operationHash);
        assertEq(uint8(status), uint8(ThresholdWallet.OperationStatus.PENDING));
    }

    function testSubmitOperationsWithoutSIGToWalletPKOnG2() public {
        (ThresholdWallet.Operation[] memory operations, bytes32 operationHash) = _operations(_thresholdWalletPKOnG2);

        bytes32[] memory operationsHash = _thresholdWalletPKOnG2.submitOperations(operations);

        assertEq(operationsHash.length, 1);
        assertEq(operationsHash[0], operationHash);
        (,,,,,, ThresholdWallet.OperationStatus status,,,) = _thresholdWalletPKOnG2._operations(operationHash);
        assertEq(uint8(status), uint8(ThresholdWallet.OperationStatus.PENDING));
    }

    function testSubmitOperationsWithSIGToWalletPKOnG1() public {
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
    }

    function testSubmitOperationsWithSIGToWalletPKOnG2() public {
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

    function _calldata() internal view returns (bytes memory calldata_) {
        calldata_ = abi.encodeWithSelector(ERC20.balanceOf.selector, _owner);
    }
}
