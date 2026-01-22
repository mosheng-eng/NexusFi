// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {Roles} from "../../common/Roles.sol";
import {Errors} from "../../common/Errors.sol";

import {BLS} from "../utils/BLS.sol";

contract MultisigWallet is
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

    /// @notice Error reverted if a public key is invalid when initializing
    /// @param why The reason why the public key is invalid
    error InvalidPublicKey(string why);

    /// @notice Error reverted if a signature is invalid when verifying or aggregating
    /// @param why The reason why the signature is invalid
    error InvalidSignature(string why);

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
    }

    /// @notice Current mode of the wallet
    WalletMode private _walletMode;

    /// @notice Aggregated public key on G1 curve
    /// @notice Require wallet mode to be PUBLIC_KEY_ON_G1
    /// @notice Must be empty if wallet mode is PUBLIC_KEY_ON_G2
    BLS.G1Point private _aggregatedPublicKeyOnG1;

    /// @notice Aggregated public key on G2 curve
    /// @notice Require wallet mode to be PUBLIC_KEY_ON_G2
    /// @notice Must be empty if wallet mode is PUBLIC_KEY_ON_G1
    BLS.G2Point private _aggregatedPublicKeyOnG2;

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

    /// @notice Initialize the multisig wallet with the given wallet mode and aggregated public key
    /// @param walletMode_ The mode of the wallet, either PUBLIC_KEY_ON_G1 or PUBLIC_KEY_ON_G2
    /// @param publicKey_ The aggregated public key, format depends on the wallet mode
    function initialize(WalletMode walletMode_, bytes calldata publicKey_) public initializer {
        if (publicKey_.length == 0) {
            revert EmptyPublicKey();
        }

        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __Ownable_init(msg.sender);

        if (walletMode_ == WalletMode.PUBLIC_KEY_ON_G1) {
            if (publicKey_.length != 4 * 32) {
                revert InvalidPublicKey("Invalid public key length for G1");
            }
            _aggregatedPublicKeyOnG1 = BLS.G1Point(
                BLS.Unit(uint256(bytes32(publicKey_[0:32])), uint256(bytes32(publicKey_[32:64]))),
                BLS.Unit(uint256(bytes32(publicKey_[64:96])), uint256(bytes32(publicKey_[96:128])))
            );
        } else if (walletMode_ == WalletMode.PUBLIC_KEY_ON_G2) {
            if (publicKey_.length != 8 * 32) {
                revert InvalidPublicKey("Invalid public key length for G2");
            }
            _aggregatedPublicKeyOnG2 = BLS.G2Point(
                BLS.Unit(uint256(bytes32(publicKey_[0:32])), uint256(bytes32(publicKey_[32:64]))),
                BLS.Unit(uint256(bytes32(publicKey_[64:96])), uint256(bytes32(publicKey_[96:128]))),
                BLS.Unit(uint256(bytes32(publicKey_[128:160])), uint256(bytes32(publicKey_[160:192]))),
                BLS.Unit(uint256(bytes32(publicKey_[192:224])), uint256(bytes32(publicKey_[224:256])))
            );
        } else {
            revert UnsupportedWalletMode(uint8(walletMode_));
        }

        _walletMode = walletMode_;

        _grantRole(Roles.OWNER_ROLE, msg.sender);
        _setRoleAdmin(Roles.OPERATOR_ROLE, Roles.OWNER_ROLE);
    }

    /// @notice Submit a batch of operations to the multisig wallet
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

            operationsHash_[i] = _getOperationHash(operations_[i]);

            if (uint64(operations_[i].hashCheckCode) != uint64(bytes8(operationsHash_[i]))) {
                revert Errors.InvalidValue("Operation.hashCheckCode mismatch");
            }

            if (_operations[operationsHash_[i]].status != OperationStatus.NONE) {
                revert OperationExists();
            }

            if (operations_[i].aggregatedSignature.length != 0) {
                if (!_verifySignatures(operations_[i].aggregatedSignature, abi.encode(operationsHash_[i]))) {
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
                aggregatedSignature: operations_[i].aggregatedSignature
            });
        }
    }

    /// @notice Verify a batch of operations with their aggregated signatures
    /// @param operationsHash_ The array of operation hashes to be verified
    /// @param aggregatedSignatures_ The array of aggregated signatures corresponding to the operation hashes
    /// @return results_ The array of boolean results indicating whether each operation is approved or not
    /// @dev Each operation must be in PENDING status to be verified
    /// @dev Only one chance to verify each operation.
    /// @dev After verification, the operation status will be updated to APPROVED or REJECTED
    function verifyOperations(bytes32[] calldata operationsHash_, bytes[] calldata aggregatedSignatures_)
        public
        nonReentrant
        whenNotPaused
        initialized
        returns (bool[] memory results_)
    {
        uint256 operationNumber = operationsHash_.length;

        if (operationNumber == 0) {
            revert EmptyOperations();
        }
        if (operationNumber != aggregatedSignatures_.length) {
            revert Errors.InvalidValue("operationsHash_ and aggregatedSignatures_ length mismatch");
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

            results_[i] = _verifySignatures(aggregatedSignatures_[i], abi.encode(operationsHash_[i]));

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
    function _verifySignatures(bytes memory aggregatedSignature_, bytes memory message_) internal view returns (bool) {
        if (_walletMode == WalletMode.PUBLIC_KEY_ON_G1) {
            return _verifySignaturesWithPublicKeyOnG1(aggregatedSignature_, message_);
        } else if (_walletMode == WalletMode.PUBLIC_KEY_ON_G2) {
            return _verifySignaturesWithPublicKeyOnG2(aggregatedSignature_, message_);
        } else {
            revert UnsupportedWalletMode(uint8(_walletMode));
        }
    }

    /// @notice Verify aggregated signatures with public key on G1 curve
    /// @param aggregatedSignature_ The aggregated signature to be verified
    /// @param message_ The message that was signed
    /// @return True if the aggregated signature is valid, false otherwise
    function _verifySignaturesWithPublicKeyOnG1(bytes memory aggregatedSignature_, bytes memory message_)
        internal
        view
        returns (bool)
    {
        if (aggregatedSignature_.length != 256) {
            revert InvalidSignature("Invalid aggregated signature length for G1");
        }

        BLS.G2Point memory sigOnG2 = abi.decode(aggregatedSignature_, (BLS.G2Point));

        BLS.G2Point memory hashToG2 = BLS.hashToG2(BLS.BLS_DOMAIN, message_);

        return sigOnG2.pairWhenPKOnG1(_aggregatedPublicKeyOnG1, hashToG2);
    }

    /// @notice Verify aggregated signatures with public key on G2 curve
    /// @param aggregatedSignature_ The aggregated signature to be verified
    /// @param message_ The message that was signed
    /// @return True if the aggregated signature is valid, false otherwise
    function _verifySignaturesWithPublicKeyOnG2(bytes memory aggregatedSignature_, bytes memory message_)
        internal
        view
        returns (bool)
    {
        if (aggregatedSignature_.length != 128) {
            revert InvalidSignature("Invalid aggregated signature length for G2");
        }

        BLS.G1Point memory sigOnG1 = abi.decode(aggregatedSignature_, (BLS.G1Point));

        BLS.G1Point memory hashToG1 = BLS.hashToG1(BLS.BLS_DOMAIN, message_);

        return sigOnG1.pairWhenPKOnG2(_aggregatedPublicKeyOnG2, hashToG1);
    }

    /// @notice Calculate the operation hash
    /// @param op The operation to calculate the hash for
    /// @return The hash of the operation
    function _getOperationHash(Operation memory op) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(op.target, op.value, op.effectiveTime, op.expirationTime, op.gasLimit, op.nonce, op.data)
        );
    }
}
