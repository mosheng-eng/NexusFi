// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {Roles} from "../common/Roles.sol";
import {Errors} from "../common/Errors.sol";

import {BLS} from "./utils/BLS.sol";

contract ThresholdWallet is
    Initializable,
    OwnableUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using BLS for BLS.G1Point;
    using BLS for BLS.G2Point;
    using BLS for BLS.G1Point[];
    using BLS for BLS.G2Point[];

    /// @notice Emitted when the status of an operation changes
    /// @param operationHash The hash of the operation
    /// @param oldStatus The previous status of the operation
    /// @param newStatus The new status of the operation
    event OperationStatusChanged(bytes32 indexed operationHash, OperationStatus oldStatus, OperationStatus newStatus);

    /// @notice Error reverted if the operation status does not match the expected status
    /// @param operationHash The hash of the operation
    /// @param expectedStatus The expected status of the operation
    /// @param actualStatus The actual status of the operation
    event OperationStatusNotMatch(
        bytes32 indexed operationHash, OperationStatus expectedStatus, OperationStatus actualStatus
    );

    /// @notice Error reverted if the wallet mode is not supported
    error UnsupportedWalletMode(uint8 walletMode);

    /// @notice Error reverted if public keys are empty when initializing
    error EmptyPublicKey();

    /// @notice Error reverted if the number of signers is not enough to meet the threshold
    error SignersNotEnough();

    /// @notice Error reverted if the threshold is not between 1 and total number of signers
    error ThresholdShouldBetweenOneAndTotalSigners();

    /// @notice Error reverted if a public key is invalid when initializing
    /// @param why The reason why the public key is invalid
    error InvalidPublicKey(string why);

    /// @notice Error reverted if a signature is invalid when verifying or aggregating
    /// @param why The reason why the signature is invalid
    error InvalidSignature(string why);

    /// @notice Error reverted if a signer is not recognized
    /// @param signerPKHash The hash of the signer's public key
    error UnrecognizedSigner(bytes32 signerPKHash);

    /// @notice Error reverted if operations are empty when submitting
    error EmptyOperations();

    /// @notice Error reverted if an operation already exists when submitting
    error OperationExists();

    /// @notice Error reverted if aggregated signature does not match public keys
    error AggregatedSignatureNotMatchPublicKeys(uint256 operationIndex);

    /// @notice Error reverted if trying to execute an unapproved operation
    error ExecuteUnapprovedOperation(OperationStatus currentStatus);

    /// @notice Error reverted if trying to execute an operation that is effective in the future
    /// @param effectiveTime The time when the operation can be executed
    /// @param currentTime The current block timestamp
    error ExecuteUneffectiveOperation(uint32 effectiveTime, uint32 currentTime);

    /// @notice Error reverted if trying to execute an operation that has expired
    /// @param expirationTime The time when the operation expires
    /// @param currentTime The current block timestamp
    error ExecuteExpiredOperation(uint32 expirationTime, uint32 currentTime);

    /// @notice Enumeration of wallet modes
    enum WalletMode {
        /// @notice Unknown mode, default value when uninitialized
        UNKNOWN,
        /// @notice BLS public keys are on G1 curve
        PUBLIC_KEY_ON_G1,
        /// @notice BLS public keys are on G2 curve
        PUBLIC_KEY_ON_G2
    }

    /// @notice Enumeration of operation status
    enum OperationStatus {
        /// @notice Zero value means operation does not exist
        NONE,
        /// @notice Operation is submitted and waiting for approval
        PENDING,
        /// @notice Operation has been approved
        APPROVED,
        /// @notice Operation has been rejected
        REJECTED,
        /// @notice Operation is currently being executed
        EXECUTING,
        /// @notice Operation has been executed successfully
        EXECUTED,
        /// @notice Operation has been executed but failed
        FAILED,
        /// @notice Operation hasn't been executed before expiration time
        EXPIRED
    }

    /// @dev Operation structure to indicate a transaction operation
    /// @param target Target address
    /// @param value Ether value
    /// @param effectiveTime The time when the operation can be executed
    /// @param expirationTime The time when the operation expires
    /// @param gasLimit Gas limit for the operation execution
    /// @param nonce Nonce of the operation, should be unique for each operation
    /// @param status Status of the operation
    /// @param hashCheckCode First 8 bytes of the operation hash, used to prevent signature replay attacks
    /// @param data Data payload of the operation to be sent to the target address
    /// @param aggregatedSignature Aggregated signature of the operation hash : keccak256(target, value, effectiveTime, expirationTime, gasLimit, nonce, data)
    /// @param signers Array of signer public keys who signed the operation
    struct Operation {
        address target;
        uint32 value;
        uint32 effectiveTime;
        uint32 expirationTime;
        uint32 gasLimit;
        uint128 nonce;
        OperationStatus status;
        bytes8 hashCheckCode;
        bytes data;
        bytes aggregatedSignature;
        bytes[] signers;
    }

    struct MemberOnG1 {
        uint256 threshold;
        BLS.G1Point thresholdPointOnG1;
        BLS.G1Point memberIDPointOnG1;
    }

    struct MemberOnG2 {
        uint256 threshold;
        BLS.G2Point thresholdPointOnG2;
        BLS.G2Point memberIDPointOnG2;
    }

    /// @notice Current mode of the wallet
    WalletMode private _walletMode;

    /// @notice Aggregated public key on G1 curve
    /// @notice Require wallet mode to be PUBLIC_KEY_ON_G1
    /// @notice Must be empty if wallet mode is PUBLIC_KEY_ON_G2
    /// @dev Aggregated mechanism is different from multi-sig wallet
    BLS.G1Point private _aggregatedPublicKeyOnG1;

    /// @notice Mapping of member public keys hash to threshold points on G2 curve
    /// @notice Require wallet mode to be PUBLIC_KEY_ON_G1
    /// @notice Must be empty if wallet mode is PUBLIC_KEY_ON_G2
    /// @dev Used for threshold signature verification
    mapping(bytes32 => MemberOnG2) private _publicKeyToMemberOnG2;

    /// @notice Aggregated public key on G2 curve
    /// @notice Require wallet mode to be PUBLIC_KEY_ON_G2
    /// @notice Must be empty if wallet mode is PUBLIC_KEY_ON_G1
    BLS.G2Point private _aggregatedPublicKeyOnG2;

    /// @notice Mapping of member public keys hash to threshold points on G1 curve
    /// @notice Require wallet mode to be PUBLIC_KEY_ON_G2
    /// @notice Must be empty if wallet mode is PUBLIC_KEY_ON_G1
    /// @dev Used for threshold signature verification
    mapping(bytes32 => MemberOnG1) private _publicKeyToMemberOnG1;

    /// @notice Threshold number of signatures required to approve an operation
    /// @dev Must be less than or equal to the number of all signers
    uint128 private _threshold;

    /// @notice Record the operations number of the wallet
    /// @notice Incremented for each new operation
    uint128 public _nonce;

    /// @notice Records of all operations no matter what their status is
    mapping(bytes32 => Operation) public _operations;

    /// @notice Modifier to check if the wallet has been initialized
    modifier initialized() {
        if (_walletMode == WalletMode.UNKNOWN || (_publicKeyOnG1IsEmpty() && _publicKeyOnG2IsEmpty())) {
            revert Errors.Uninitialized("Mode or PK is not set");
        }

        _;
    }

    /// @notice Check if the aggregated public key on G1 curve is empty
    /// @return True if the aggregated public key on G1 curve is empty, false otherwise
    function _publicKeyOnG1IsEmpty() internal view returns (bool) {
        return _aggregatedPublicKeyOnG1.X.upper == 0 && _aggregatedPublicKeyOnG1.X.lower == 0
            && _aggregatedPublicKeyOnG1.Y.upper == 0 && _aggregatedPublicKeyOnG1.Y.lower == 0;
    }

    /// @notice Check if the aggregated public key on G2 curve is empty
    /// @return True if the aggregated public key on G2 curve is empty, false otherwise
    function _publicKeyOnG2IsEmpty() internal view returns (bool) {
        return _aggregatedPublicKeyOnG2.X0.upper == 0 && _aggregatedPublicKeyOnG2.X0.lower == 0
            && _aggregatedPublicKeyOnG2.X1.upper == 0 && _aggregatedPublicKeyOnG2.X1.lower == 0
            && _aggregatedPublicKeyOnG2.Y0.upper == 0 && _aggregatedPublicKeyOnG2.Y0.lower == 0
            && _aggregatedPublicKeyOnG2.Y1.upper == 0 && _aggregatedPublicKeyOnG2.Y1.lower == 0;
    }

    /// @notice Can not be called directly, use proxy and initialize instead
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the threshold wallet with the given wallet mode and aggregated public key
    /// @param walletMode_ The mode of the wallet, either PUBLIC_KEY_ON_G1 or PUBLIC_KEY_ON_G2
    /// @param threshold_ The threshold number of signatures required to approve an operation
    /// @param publicKeys_ The member public keys, format depends on the wallet mode
    /// @param memberIDs_ The member IDs that should be signed by all members' secret keys
    function initialize(
        WalletMode walletMode_,
        uint128 threshold_,
        bytes[] calldata publicKeys_,
        bytes[] calldata memberIDs_
    ) public initializer {
        if (publicKeys_.length == 0) {
            revert EmptyPublicKey();
        }

        if (publicKeys_.length != memberIDs_.length) {
            revert InvalidPublicKey("Public keys length mismatch with member IDs length");
        }

        if (threshold_ == 0 || threshold_ > publicKeys_.length) {
            revert ThresholdShouldBetweenOneAndTotalSigners();
        }

        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __Ownable_init(msg.sender);

        uint256 publicKeysNum = publicKeys_.length;
        uint256[] memory thresholdOfPublicKeys = new uint256[](publicKeysNum);
        bytes memory publicKeysInLine = _concatBytes(publicKeys_);

        if (walletMode_ == WalletMode.PUBLIC_KEY_ON_G1) {
            BLS.G1Point[] memory publicKeysOnG1 = new BLS.G1Point[](publicKeysNum);

            for (uint256 i = 0; i < publicKeysNum; ++i) {
                if (publicKeys_[i].length != 128) {
                    revert InvalidPublicKey("Invalid public key length for G1");
                }
                thresholdOfPublicKeys[i] = uint256(keccak256(bytes.concat(publicKeys_[i], publicKeysInLine)));
                publicKeysOnG1[i] = abi.decode(publicKeys_[i], (BLS.G1Point));
                _publicKeyToMemberOnG2[keccak256(publicKeys_[i])] = MemberOnG2({
                    threshold: thresholdOfPublicKeys[i],
                    thresholdPointOnG2: BLS.hashToG2(BLS.BLS_DOMAIN, abi.encodePacked(thresholdOfPublicKeys[i])),
                    memberIDPointOnG2: abi.decode(memberIDs_[i], (BLS.G2Point))
                });
            }
            _aggregatedPublicKeyOnG1 = publicKeysOnG1.scalarsMulPointsOnG1(thresholdOfPublicKeys);
            for (uint256 i = 0; i < publicKeysNum; ++i) {
                MemberOnG2 memory memberOnG2 = _publicKeyToMemberOnG2[keccak256(publicKeys_[i])];
                if (
                    !BLS.pairWhenPKOnG1(
                        memberOnG2.memberIDPointOnG2, _aggregatedPublicKeyOnG1, memberOnG2.thresholdPointOnG2
                    )
                ) {
                    revert InvalidSignature("Member ID does not match public key on G1");
                }
            }
        } else if (walletMode_ == WalletMode.PUBLIC_KEY_ON_G2) {
            BLS.G2Point[] memory publicKeysOnG2 = new BLS.G2Point[](publicKeysNum);

            for (uint256 i = 0; i < publicKeysNum; ++i) {
                if (publicKeys_[i].length != 256) {
                    revert InvalidPublicKey("Invalid public key length for G2");
                }
                thresholdOfPublicKeys[i] = uint256(keccak256(bytes.concat(publicKeys_[i], publicKeysInLine)));
                publicKeysOnG2[i] = abi.decode(publicKeys_[i], (BLS.G2Point));
                _publicKeyToMemberOnG1[keccak256(publicKeys_[i])] = MemberOnG1({
                    threshold: thresholdOfPublicKeys[i],
                    thresholdPointOnG1: BLS.hashToG1(BLS.BLS_DOMAIN, abi.encodePacked(thresholdOfPublicKeys[i])),
                    memberIDPointOnG1: abi.decode(memberIDs_[i], (BLS.G1Point))
                });
            }
            _aggregatedPublicKeyOnG2 = publicKeysOnG2.scalarsMulPointsOnG2(thresholdOfPublicKeys);
            for (uint256 i = 0; i < publicKeysNum; ++i) {
                MemberOnG1 memory memberOnG1 = _publicKeyToMemberOnG1[keccak256(publicKeys_[i])];
                if (
                    !BLS.pairWhenPKOnG2(
                        memberOnG1.memberIDPointOnG1, _aggregatedPublicKeyOnG2, memberOnG1.thresholdPointOnG1
                    )
                ) {
                    revert InvalidSignature("Member ID does not match public key on G2");
                }
            }
        } else {
            revert UnsupportedWalletMode(uint8(walletMode_));
        }

        _walletMode = walletMode_;
        _threshold = threshold_;

        _grantRole(Roles.OWNER_ROLE, msg.sender);
        _setRoleAdmin(Roles.OPERATOR_ROLE, Roles.OWNER_ROLE);
    }

    /// @notice Submit a batch of operations to the threshold wallet
    /// @param operations_ The array of operations to be submitted
    /// @return operationsHash_ The array of operation hashes corresponding to the submitted operations
    /// @dev Each operation's nonce must be unique and sequentially increasing as the order in the array
    function submitOperations(Operation[] memory operations_)
        public
        nonReentrant
        whenNotPaused
        initialized
        returns (bytes32[] memory operationsHash_)
    {
        uint256 operationNumber = operations_.length;

        if (operationNumber == 0) {
            revert EmptyOperations();
        }

        operationsHash_ = new bytes32[](operationNumber);

        for (uint256 i = 0; i < operationNumber; i++) {
            if (operations_[i].target == address(0)) {
                revert Errors.ZeroAddress("Operation.target");
            }
            if (operations_[i].expirationTime <= operations_[i].effectiveTime) {
                revert Errors.InvalidValue("Operation.expirationTime earlier than Operation.effectiveTime");
            }
            if (operations_[i].expirationTime <= block.timestamp) {
                revert Errors.InvalidValue("Operation.expirationTime earlier than current time");
            }
            if (operations_[i].gasLimit < 21000) {
                revert Errors.InvalidValue("Operation.gasLimit too low");
            }
            if (operations_[i].nonce != _nonce) {
                revert Errors.InvalidValue("Operation.nonce invalid");
            }
            if (operations_[i].hashCheckCode == bytes8(0)) {
                revert Errors.InvalidValue("Operation.hashCheckCode invalid");
            }
            if (operations_[i].data.length < 4) {
                revert Errors.InvalidValue("Operation.data too short");
            }
            if (
                operations_[i].aggregatedSignature.length != 0
                    && (
                        (_walletMode == WalletMode.PUBLIC_KEY_ON_G1 && operations_[i].aggregatedSignature.length != 256)
                            || (_walletMode == WalletMode.PUBLIC_KEY_ON_G2 && operations_[i].aggregatedSignature.length != 128)
                    )
            ) {
                revert Errors.InvalidValue("Operation.aggregatedSignature invalid");
            }

            if (operations_[i].signers.length != 0 && operations_[i].signers.length < _threshold) {
                revert SignersNotEnough();
            }

            operationsHash_[i] = _getOperationHash(operations_[i]);

            if (uint64(operations_[i].hashCheckCode) != uint64(bytes8(operationsHash_[i]))) {
                revert Errors.InvalidValue("Operation.hashCheckCode mismatch");
            }

            if (_operations[operationsHash_[i]].status != OperationStatus.NONE) {
                revert OperationExists();
            }

            if (operations_[i].aggregatedSignature.length != 0 && operations_[i].signers.length >= _threshold) {
                if (
                    !_verifySignatures(
                        operations_[i].aggregatedSignature, abi.encode(operationsHash_[i]), operations_[i].signers
                    )
                ) {
                    revert AggregatedSignatureNotMatchPublicKeys(i);
                } else {
                    operations_[i].status = OperationStatus.APPROVED;
                    emit OperationStatusChanged(operationsHash_[i], OperationStatus.NONE, OperationStatus.APPROVED);
                }
            } else {
                operations_[i].status = OperationStatus.PENDING;
                emit OperationStatusChanged(operationsHash_[i], OperationStatus.NONE, OperationStatus.PENDING);
            }

            _nonce += 1;

            _operations[operationsHash_[i]] = Operation({
                target: operations_[i].target,
                value: operations_[i].value,
                effectiveTime: operations_[i].effectiveTime,
                expirationTime: operations_[i].expirationTime,
                gasLimit: operations_[i].gasLimit,
                nonce: operations_[i].nonce,
                status: operations_[i].status,
                hashCheckCode: operations_[i].hashCheckCode,
                data: operations_[i].data,
                aggregatedSignature: operations_[i].aggregatedSignature,
                signers: operations_[i].signers
            });
        }
    }

    function verifyOperations(
        bytes32[] calldata operationsHash_,
        bytes[] calldata aggregatedSignatures_,
        bytes[][] calldata signers_
    ) public nonReentrant whenNotPaused initialized returns (bool[] memory results_) {
        uint256 operationNumber = operationsHash_.length;

        if (operationNumber == 0) {
            revert EmptyOperations();
        }
        if (operationNumber != aggregatedSignatures_.length) {
            revert Errors.InvalidValue("operationsHash_ and aggregatedSignatures_ length mismatch");
        }
        if (operationNumber != signers_.length) {
            revert Errors.InvalidValue("operationsHash_ and signers_ length mismatch");
        }

        results_ = new bool[](operationNumber);

        for (uint256 i = 0; i < operationNumber; ++i) {
            Operation storage op = _operations[operationsHash_[i]];

            if (op.status == OperationStatus.NONE) {
                results_[i] = false;
                continue;
            }

            if (aggregatedSignatures_[i].length == 0) {
                results_[i] = false;
                continue;
            }

            if (op.status != OperationStatus.PENDING) {
                results_[i] = false;
                emit OperationStatusNotMatch(operationsHash_[i], OperationStatus.PENDING, op.status);
                continue;
            }

            results_[i] = _verifySignatures(aggregatedSignatures_[i], abi.encode(operationsHash_[i]), signers_[i]);

            op.aggregatedSignature = aggregatedSignatures_[i];

            if (results_[i]) {
                op.status = OperationStatus.APPROVED;
                emit OperationStatusChanged(operationsHash_[i], OperationStatus.PENDING, OperationStatus.APPROVED);
            } else {
                op.status = OperationStatus.REJECTED;
                emit OperationStatusChanged(operationsHash_[i], OperationStatus.PENDING, OperationStatus.REJECTED);
            }
        }
    }

    /// @notice Execute a batch of approved operations
    /// @param operationsHash_ The array of operation hashes to be executed
    /// @dev Each operation must be approved, effective, and not expired
    function executeOperations(bytes32[] calldata operationsHash_) public nonReentrant whenNotPaused initialized {
        uint256 operationNumber = operationsHash_.length;

        if (operationNumber == 0) {
            revert EmptyOperations();
        }

        for (uint256 i = 0; i < operationNumber; i++) {
            Operation storage op = _operations[operationsHash_[i]];

            if (op.status != OperationStatus.APPROVED) {
                revert ExecuteUnapprovedOperation(op.status);
            }
            if (block.timestamp < op.effectiveTime) {
                revert ExecuteUneffectiveOperation(op.effectiveTime, uint32(block.timestamp));
            }
            if (block.timestamp >= op.expirationTime) {
                op.status = OperationStatus.EXPIRED;
                revert ExecuteExpiredOperation(op.expirationTime, uint32(block.timestamp));
            }

            op.status = OperationStatus.EXECUTING;
            emit OperationStatusChanged(operationsHash_[i], OperationStatus.APPROVED, OperationStatus.EXECUTING);

            (bool success,) = op.target.call{value: op.value, gas: op.gasLimit}(op.data);

            if (success) {
                op.status = OperationStatus.EXECUTED;
                emit OperationStatusChanged(operationsHash_[i], OperationStatus.EXECUTING, OperationStatus.EXECUTED);
            } else {
                op.status = OperationStatus.FAILED;
                emit OperationStatusChanged(operationsHash_[i], OperationStatus.EXECUTING, OperationStatus.FAILED);
            }
        }
    }

    /// @notice Verify aggregated signatures against the aggregated public key
    /// @param aggregatedSignature_ The aggregated signature to be verified
    /// @param message_ The message that was signed
    /// @return True if the aggregated signature is valid, false otherwise
    /// @dev The verification method depends on the wallet mode
    function _verifySignatures(bytes memory aggregatedSignature_, bytes memory message_, bytes[] memory signers_)
        internal
        view
        returns (bool)
    {
        if (_walletMode == WalletMode.PUBLIC_KEY_ON_G1) {
            return _verifySignaturesWithPublicKeyOnG1(aggregatedSignature_, message_, signers_);
        } else if (_walletMode == WalletMode.PUBLIC_KEY_ON_G2) {
            return _verifySignaturesWithPublicKeyOnG2(aggregatedSignature_, message_, signers_);
        } else {
            revert UnsupportedWalletMode(uint8(_walletMode));
        }
    }

    /// @notice Verify aggregated signatures with public key on G1 curve
    /// @param aggregatedSignature_ The aggregated signature to be verified
    /// @param message_ The message that was signed
    /// @return True if the aggregated signature is valid, false otherwise
    function _verifySignaturesWithPublicKeyOnG1(
        bytes memory aggregatedSignature_,
        bytes memory message_,
        bytes[] memory signers_
    ) internal view returns (bool) {
        if (aggregatedSignature_.length != 256) {
            revert InvalidSignature("Invalid aggregated signature length for G1");
        }

        uint256 signersNum = signers_.length;
        BLS.G1Point[] memory signerPKsOnG1 = new BLS.G1Point[](signersNum);
        BLS.G2Point[] memory signerMemberIDsOnG2 = new BLS.G2Point[](signersNum);

        for (uint256 i = 0; i < signersNum; ++i) {
            bytes32 signerPKHash = keccak256(signers_[i]);
            if (_publicKeyToMemberOnG2[signerPKHash].threshold == 0) {
                revert UnrecognizedSigner(signerPKHash);
            }
            signerPKsOnG1[i] = abi.decode(signers_[i], (BLS.G1Point));
            signerMemberIDsOnG2[i] = _publicKeyToMemberOnG2[signerPKHash].thresholdPointOnG2;
        }

        BLS.G1Point[] memory g1Points = new BLS.G1Point[](3);
        BLS.G2Point[] memory g2Points = new BLS.G2Point[](3);

        g1Points[0] = BLS.negGeneratorG1();
        g1Points[1] = signerPKsOnG1.sumPointsOnG1();
        g1Points[2] = _aggregatedPublicKeyOnG1;

        g2Points[0] = abi.decode(aggregatedSignature_, (BLS.G2Point));
        g2Points[1] = BLS.hashToG2(BLS.BLS_DOMAIN, message_);
        g2Points[2] = signerMemberIDsOnG2.sumPointsOnG2();

        return BLS.generalPairing(g1Points, g2Points);
    }

    /// @notice Verify aggregated signatures with public key on G2 curve
    /// @param aggregatedSignature_ The aggregated signature to be verified
    /// @param message_ The message that was signed
    /// @return True if the aggregated signature is valid, false otherwise
    function _verifySignaturesWithPublicKeyOnG2(
        bytes memory aggregatedSignature_,
        bytes memory message_,
        bytes[] memory signers_
    ) internal view returns (bool) {
        if (aggregatedSignature_.length != 128) {
            revert InvalidSignature("Invalid aggregated signature length for G2");
        }

        uint256 signersNum = signers_.length;
        BLS.G2Point[] memory signerPKsOnG2 = new BLS.G2Point[](signersNum);
        BLS.G1Point[] memory signerMemberIDsOnG1 = new BLS.G1Point[](signersNum);

        for (uint256 i = 0; i < signersNum; ++i) {
            bytes32 signerPKHash = keccak256(signers_[i]);
            if (_publicKeyToMemberOnG1[signerPKHash].threshold == 0) {
                revert UnrecognizedSigner(signerPKHash);
            }
            signerPKsOnG2[i] = abi.decode(signers_[i], (BLS.G2Point));
            signerMemberIDsOnG1[i] = _publicKeyToMemberOnG1[signerPKHash].thresholdPointOnG1;
        }

        BLS.G1Point[] memory g1Points = new BLS.G1Point[](3);
        BLS.G2Point[] memory g2Points = new BLS.G2Point[](3);

        g1Points[0] = abi.decode(aggregatedSignature_, (BLS.G1Point));
        g1Points[1] = BLS.hashToG1(BLS.BLS_DOMAIN, message_);
        g1Points[2] = signerMemberIDsOnG1.sumPointsOnG1();

        g2Points[0] = BLS.negGeneratorG2();
        g2Points[1] = signerPKsOnG2.sumPointsOnG2();
        g2Points[2] = _aggregatedPublicKeyOnG2;

        return BLS.generalPairing(g1Points, g2Points);
    }

    function readWalletMode() public view returns (WalletMode) {
        return _walletMode;
    }

    /// @notice Calculate the operation hash
    /// @param op The operation to calculate the hash for
    /// @return The hash of the operation
    function _getOperationHash(Operation memory op) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(op.target, op.value, op.effectiveTime, op.expirationTime, op.gasLimit, op.nonce, op.data)
        );
    }

    /// @notice Concatenate an array of bytes into a single bytes array
    /// @param bytesArray_ The array of bytes to concatenate
    /// @return bytesSingle_ The concatenated bytes array
    function _concatBytes(bytes[] memory bytesArray_) internal pure returns (bytes memory bytesSingle_) {
        for (uint256 i = 0; i < bytesArray_.length; ++i) {
            bytesSingle_ = abi.encodePacked(bytesSingle_, bytesArray_[i]);
        }
    }
}
