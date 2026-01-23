// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {Roles} from "../../common/Roles.sol";
import {Errors} from "../../common/Errors.sol";

import {MultisigWalletLibs} from "./utils/MultisigWalletLibs.sol";
import {MultisigWalletPKOnG1} from "./utils/MultisigWalletPKOnG1.sol";
import {MultisigWalletPKOnG2} from "./utils/MultisigWalletPKOnG2.sol";

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
    using MultisigWalletLibs for BLS.G1Point;
    using MultisigWalletLibs for BLS.G2Point;
    using MultisigWalletLibs for MultisigWalletLibs.Operation;

    /// @notice Current mode of the wallet
    MultisigWalletLibs.WalletMode private _walletMode;

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
    mapping(bytes32 => MultisigWalletLibs.Operation) public _operations;

    /// @notice Modifier to check if the wallet has been initialized
    modifier initialized() {
        if (
            _walletMode == MultisigWalletLibs.WalletMode.UNKNOWN
                || (_aggregatedPublicKeyOnG1.publicKeyOnG1IsEmpty() && _aggregatedPublicKeyOnG2.publicKeyOnG2IsEmpty())
        ) {
            revert Errors.Uninitialized("Mode or PK is not set");
        }

        _;
    }

    /// @notice Can not be called directly, use proxy and initialize instead
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the multisig wallet with the given wallet mode and aggregated public key
    /// @param walletMode_ The mode of the wallet, either PUBLIC_KEY_ON_G1 or PUBLIC_KEY_ON_G2
    /// @param publicKey_ The aggregated public key, format depends on the wallet mode
    function initialize(MultisigWalletLibs.WalletMode walletMode_, bytes calldata publicKey_) public initializer {
        if (publicKey_.length == 0) {
            revert MultisigWalletLibs.EmptyPublicKey();
        }

        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __Ownable_init(msg.sender);

        if (walletMode_ == MultisigWalletLibs.WalletMode.PUBLIC_KEY_ON_G1) {
            _aggregatedPublicKeyOnG1 = MultisigWalletPKOnG1.initialize(publicKey_);
        } else if (walletMode_ == MultisigWalletLibs.WalletMode.PUBLIC_KEY_ON_G2) {
            _aggregatedPublicKeyOnG2 = MultisigWalletPKOnG2.initialize(publicKey_);
        } else {
            revert MultisigWalletLibs.UnsupportedWalletMode(uint8(walletMode_));
        }

        _walletMode = walletMode_;

        _grantRole(Roles.OWNER_ROLE, msg.sender);
        _setRoleAdmin(Roles.OPERATOR_ROLE, Roles.OWNER_ROLE);
    }

    /// @notice Submit a batch of operations to the multisig wallet
    /// @param operations_ The array of operations to be submitted
    /// @return operationsHash_ The array of operation hashes corresponding to the submitted operations
    /// @dev Each operation's nonce must be unique and sequentially increasing as the order in the array
    function submitOperations(MultisigWalletLibs.Operation[] memory operations_)
        public
        nonReentrant
        whenNotPaused
        initialized
        returns (bytes32[] memory operationsHash_)
    {
        uint256 operationNumber = operations_.length;

        if (operationNumber == 0) {
            revert MultisigWalletLibs.EmptyOperations();
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
                        (
                            _walletMode == MultisigWalletLibs.WalletMode.PUBLIC_KEY_ON_G1
                                && operations_[i].aggregatedSignature.length != 256
                        )
                            || (
                                _walletMode == MultisigWalletLibs.WalletMode.PUBLIC_KEY_ON_G2
                                    && operations_[i].aggregatedSignature.length != 128
                            )
                    )
            ) {
                revert Errors.InvalidValue("Operation.aggregatedSignature invalid");
            }

            operationsHash_[i] = operations_[i].getOperationHash();

            if (uint64(operations_[i].hashCheckCode) != uint64(bytes8(operationsHash_[i]))) {
                revert Errors.InvalidValue("Operation.hashCheckCode mismatch");
            }

            if (_operations[operationsHash_[i]].status != MultisigWalletLibs.OperationStatus.NONE) {
                revert MultisigWalletLibs.OperationExists();
            }

            if (operations_[i].aggregatedSignature.length != 0) {
                if (!_verifySignatures(operations_[i].aggregatedSignature, abi.encode(operationsHash_[i]))) {
                    revert MultisigWalletLibs.AggregatedSignatureNotMatchPublicKeys(i);
                } else {
                    operations_[i].status = MultisigWalletLibs.OperationStatus.APPROVED;
                    emit MultisigWalletLibs.OperationStatusChanged(
                        operationsHash_[i],
                        MultisigWalletLibs.OperationStatus.NONE,
                        MultisigWalletLibs.OperationStatus.APPROVED
                    );
                }
            } else {
                operations_[i].status = MultisigWalletLibs.OperationStatus.PENDING;
                emit MultisigWalletLibs.OperationStatusChanged(
                    operationsHash_[i],
                    MultisigWalletLibs.OperationStatus.NONE,
                    MultisigWalletLibs.OperationStatus.PENDING
                );
            }

            _nonce += 1;

            _operations[operationsHash_[i]] = MultisigWalletLibs.Operation({
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
            revert MultisigWalletLibs.EmptyOperations();
        }
        if (operationNumber != aggregatedSignatures_.length) {
            revert Errors.InvalidValue("operationsHash_ and aggregatedSignatures_ length mismatch");
        }

        results_ = new bool[](operationNumber);

        for (uint256 i = 0; i < operationNumber; ++i) {
            MultisigWalletLibs.Operation storage op = _operations[operationsHash_[i]];

            if (op.status == MultisigWalletLibs.OperationStatus.NONE) {
                results_[i] = false;
                continue;
            }

            if (aggregatedSignatures_[i].length == 0) {
                results_[i] = false;
                continue;
            }

            if (op.status != MultisigWalletLibs.OperationStatus.PENDING) {
                results_[i] = false;
                emit MultisigWalletLibs.OperationStatusNotMatch(
                    operationsHash_[i], MultisigWalletLibs.OperationStatus.PENDING, op.status
                );
                continue;
            }

            results_[i] = _verifySignatures(aggregatedSignatures_[i], abi.encode(operationsHash_[i]));

            op.aggregatedSignature = aggregatedSignatures_[i];

            if (results_[i]) {
                op.status = MultisigWalletLibs.OperationStatus.APPROVED;
                emit MultisigWalletLibs.OperationStatusChanged(
                    operationsHash_[i],
                    MultisigWalletLibs.OperationStatus.PENDING,
                    MultisigWalletLibs.OperationStatus.APPROVED
                );
            } else {
                op.status = MultisigWalletLibs.OperationStatus.REJECTED;
                emit MultisigWalletLibs.OperationStatusChanged(
                    operationsHash_[i],
                    MultisigWalletLibs.OperationStatus.PENDING,
                    MultisigWalletLibs.OperationStatus.REJECTED
                );
            }
        }
    }

    /// @notice Execute a batch of approved operations
    /// @param operationsHash_ The array of operation hashes to be executed
    /// @dev Each operation must be approved, effective, and not expired
    function executeOperations(bytes32[] calldata operationsHash_) public nonReentrant whenNotPaused initialized {
        uint256 operationNumber = operationsHash_.length;

        if (operationNumber == 0) {
            revert MultisigWalletLibs.EmptyOperations();
        }

        for (uint256 i = 0; i < operationNumber; i++) {
            MultisigWalletLibs.Operation storage op = _operations[operationsHash_[i]];

            if (op.status != MultisigWalletLibs.OperationStatus.APPROVED) {
                revert MultisigWalletLibs.ExecuteUnapprovedOperation(op.status);
            }
            if (block.timestamp < op.effectiveTime) {
                revert MultisigWalletLibs.ExecuteUneffectiveOperation(op.effectiveTime, uint32(block.timestamp));
            }
            if (block.timestamp >= op.expirationTime) {
                op.status = MultisigWalletLibs.OperationStatus.EXPIRED;
                revert MultisigWalletLibs.ExecuteExpiredOperation(op.expirationTime, uint32(block.timestamp));
            }

            op.status = MultisigWalletLibs.OperationStatus.EXECUTING;
            emit MultisigWalletLibs.OperationStatusChanged(
                operationsHash_[i],
                MultisigWalletLibs.OperationStatus.APPROVED,
                MultisigWalletLibs.OperationStatus.EXECUTING
            );
            (bool success,) = op.target.call{value: op.value, gas: op.gasLimit}(op.data);

            if (success) {
                op.status = MultisigWalletLibs.OperationStatus.EXECUTED;
                emit MultisigWalletLibs.OperationStatusChanged(
                    operationsHash_[i],
                    MultisigWalletLibs.OperationStatus.EXECUTING,
                    MultisigWalletLibs.OperationStatus.EXECUTED
                );
            } else {
                op.status = MultisigWalletLibs.OperationStatus.FAILED;
                emit MultisigWalletLibs.OperationStatusChanged(
                    operationsHash_[i],
                    MultisigWalletLibs.OperationStatus.EXECUTING,
                    MultisigWalletLibs.OperationStatus.FAILED
                );
            }
        }
    }

    /// @notice Verify aggregated signatures against the aggregated public key
    /// @param aggregatedSignature_ The aggregated signature to be verified
    /// @param message_ The message that was signed
    /// @return True if the aggregated signature is valid, false otherwise
    /// @dev The verification method depends on the wallet mode
    function _verifySignatures(bytes memory aggregatedSignature_, bytes memory message_) internal view returns (bool) {
        if (_walletMode == MultisigWalletLibs.WalletMode.PUBLIC_KEY_ON_G1) {
            return _aggregatedPublicKeyOnG1.verifySignaturesWithPublicKeyOnG1(aggregatedSignature_, message_);
        } else if (_walletMode == MultisigWalletLibs.WalletMode.PUBLIC_KEY_ON_G2) {
            return _aggregatedPublicKeyOnG2.verifySignaturesWithPublicKeyOnG2(aggregatedSignature_, message_);
        } else {
            revert MultisigWalletLibs.UnsupportedWalletMode(uint8(_walletMode));
        }
    }
}
