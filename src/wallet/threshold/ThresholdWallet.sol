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
import {ThresholdWalletLibs} from "./utils/ThresholdWalletLibs.sol";
import {ThresholdWalletPKOnG1} from "./utils/ThresholdWalletPKOnG1.sol";
import {ThresholdWalletPKOnG2} from "./utils/ThresholdWalletPKOnG2.sol";

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
    using ThresholdWalletLibs for BLS.G1Point;
    using ThresholdWalletLibs for BLS.G2Point;
    using ThresholdWalletLibs for ThresholdWalletLibs.Operation;
    using ThresholdWalletLibs for mapping(bytes32 => ThresholdWalletLibs.MemberOnG1);
    using ThresholdWalletLibs for mapping(bytes32 => ThresholdWalletLibs.MemberOnG2);

    /// @notice Current mode of the wallet
    ThresholdWalletLibs.WalletMode private _walletMode;

    /// @notice Aggregated public key on G1 curve
    /// @notice Require wallet mode to be PUBLIC_KEY_ON_G1
    /// @notice Must be empty if wallet mode is PUBLIC_KEY_ON_G2
    /// @dev Aggregated mechanism is different from multi-sig wallet
    BLS.G1Point private _aggregatedPublicKeyOnG1;

    /// @notice Mapping of member public keys hash to threshold points on G2 curve
    /// @notice Require wallet mode to be PUBLIC_KEY_ON_G1
    /// @notice Must be empty if wallet mode is PUBLIC_KEY_ON_G2
    /// @dev Used for threshold signature verification
    mapping(bytes32 => ThresholdWalletLibs.MemberOnG2) private _publicKeyToMemberOnG2;

    /// @notice Aggregated public key on G2 curve
    /// @notice Require wallet mode to be PUBLIC_KEY_ON_G2
    /// @notice Must be empty if wallet mode is PUBLIC_KEY_ON_G1
    BLS.G2Point private _aggregatedPublicKeyOnG2;

    /// @notice Mapping of member public keys hash to threshold points on G1 curve
    /// @notice Require wallet mode to be PUBLIC_KEY_ON_G2
    /// @notice Must be empty if wallet mode is PUBLIC_KEY_ON_G1
    /// @dev Used for threshold signature verification
    mapping(bytes32 => ThresholdWalletLibs.MemberOnG1) private _publicKeyToMemberOnG1;

    /// @notice Threshold number of signatures required to approve an operation
    /// @dev Must be less than or equal to the number of all signers
    uint128 private _threshold;

    /// @notice Record the operations number of the wallet
    /// @notice Incremented for each new operation
    uint128 public _nonce;

    /// @notice Records of all operations no matter what their status is
    mapping(bytes32 => ThresholdWalletLibs.Operation) public _operations;

    /// @notice Modifier to check if the wallet has been initialized
    modifier initialized() {
        if (
            _walletMode == ThresholdWalletLibs.WalletMode.UNKNOWN
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

    /// @notice Initialize the threshold wallet with the given wallet mode and aggregated public key
    /// @param walletMode_ The mode of the wallet, either PUBLIC_KEY_ON_G1 or PUBLIC_KEY_ON_G2
    /// @param threshold_ The threshold number of signatures required to approve an operation
    /// @param publicKeys_ The member public keys, format depends on the wallet mode
    /// @param memberIDs_ The member IDs that should be signed by all members' secret keys
    function initialize(
        ThresholdWalletLibs.WalletMode walletMode_,
        uint128 threshold_,
        bytes[] calldata publicKeys_,
        bytes[] calldata memberIDs_
    ) public initializer {
        if (publicKeys_.length == 0) {
            revert ThresholdWalletLibs.EmptyPublicKey();
        }

        if (publicKeys_.length != memberIDs_.length) {
            revert ThresholdWalletLibs.InvalidPublicKey("Public keys length mismatch with member IDs length");
        }

        if (threshold_ == 0 || threshold_ > publicKeys_.length) {
            revert ThresholdWalletLibs.ThresholdShouldBetweenOneAndTotalSigners();
        }

        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __Ownable_init(msg.sender);

        if (walletMode_ == ThresholdWalletLibs.WalletMode.PUBLIC_KEY_ON_G1) {
            _aggregatedPublicKeyOnG1 = ThresholdWalletPKOnG1.initialize(_publicKeyToMemberOnG2, publicKeys_, memberIDs_);
        } else if (walletMode_ == ThresholdWalletLibs.WalletMode.PUBLIC_KEY_ON_G2) {
            _aggregatedPublicKeyOnG2 = ThresholdWalletPKOnG2.initialize(_publicKeyToMemberOnG1, publicKeys_, memberIDs_);
        } else {
            revert ThresholdWalletLibs.UnsupportedWalletMode(uint8(walletMode_));
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
    function submitOperations(ThresholdWalletLibs.Operation[] memory operations_)
        public
        nonReentrant
        whenNotPaused
        initialized
        returns (bytes32[] memory operationsHash_)
    {
        uint256 operationNumber = operations_.length;

        if (operationNumber == 0) {
            revert ThresholdWalletLibs.EmptyOperations();
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
                            _walletMode == ThresholdWalletLibs.WalletMode.PUBLIC_KEY_ON_G1
                                && operations_[i].aggregatedSignature.length != 256
                        )
                            || (
                                _walletMode == ThresholdWalletLibs.WalletMode.PUBLIC_KEY_ON_G2
                                    && operations_[i].aggregatedSignature.length != 128
                            )
                    )
            ) {
                revert Errors.InvalidValue("Operation.aggregatedSignature invalid");
            }

            if (operations_[i].signers.length != 0 && operations_[i].signers.length < _threshold) {
                revert ThresholdWalletLibs.SignersNotEnough();
            }

            operationsHash_[i] = operations_[i].getOperationHash();

            if (uint64(operations_[i].hashCheckCode) != uint64(bytes8(operationsHash_[i]))) {
                revert Errors.InvalidValue("Operation.hashCheckCode mismatch");
            }

            if (_operations[operationsHash_[i]].status != ThresholdWalletLibs.OperationStatus.NONE) {
                revert ThresholdWalletLibs.OperationExists();
            }

            if (operations_[i].aggregatedSignature.length != 0 && operations_[i].signers.length >= _threshold) {
                if (
                    !_verifySignatures(
                        operations_[i].aggregatedSignature, abi.encode(operationsHash_[i]), operations_[i].signers
                    )
                ) {
                    revert ThresholdWalletLibs.AggregatedSignatureNotMatchPublicKeys(i);
                } else {
                    operations_[i].status = ThresholdWalletLibs.OperationStatus.APPROVED;
                    emit ThresholdWalletLibs.OperationStatusChanged(
                        operationsHash_[i],
                        ThresholdWalletLibs.OperationStatus.NONE,
                        ThresholdWalletLibs.OperationStatus.APPROVED
                    );
                }
            } else {
                operations_[i].status = ThresholdWalletLibs.OperationStatus.PENDING;
                emit ThresholdWalletLibs.OperationStatusChanged(
                    operationsHash_[i],
                    ThresholdWalletLibs.OperationStatus.NONE,
                    ThresholdWalletLibs.OperationStatus.PENDING
                );
            }

            _nonce += 1;

            _operations[operationsHash_[i]] = ThresholdWalletLibs.Operation({
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
            revert ThresholdWalletLibs.EmptyOperations();
        }
        if (operationNumber != aggregatedSignatures_.length) {
            revert Errors.InvalidValue("operationsHash_ and aggregatedSignatures_ length mismatch");
        }
        if (operationNumber != signers_.length) {
            revert Errors.InvalidValue("operationsHash_ and signers_ length mismatch");
        }

        results_ = new bool[](operationNumber);

        for (uint256 i = 0; i < operationNumber; ++i) {
            ThresholdWalletLibs.Operation storage op = _operations[operationsHash_[i]];

            if (op.status == ThresholdWalletLibs.OperationStatus.NONE) {
                results_[i] = false;
                continue;
            }

            if (aggregatedSignatures_[i].length == 0) {
                results_[i] = false;
                continue;
            }

            if (op.status != ThresholdWalletLibs.OperationStatus.PENDING) {
                results_[i] = false;
                emit ThresholdWalletLibs.OperationStatusNotMatch(
                    operationsHash_[i], ThresholdWalletLibs.OperationStatus.PENDING, op.status
                );
                continue;
            }

            results_[i] = _verifySignatures(aggregatedSignatures_[i], abi.encode(operationsHash_[i]), signers_[i]);

            op.aggregatedSignature = aggregatedSignatures_[i];

            if (results_[i]) {
                op.status = ThresholdWalletLibs.OperationStatus.APPROVED;
                emit ThresholdWalletLibs.OperationStatusChanged(
                    operationsHash_[i],
                    ThresholdWalletLibs.OperationStatus.PENDING,
                    ThresholdWalletLibs.OperationStatus.APPROVED
                );
            } else {
                op.status = ThresholdWalletLibs.OperationStatus.REJECTED;
                emit ThresholdWalletLibs.OperationStatusChanged(
                    operationsHash_[i],
                    ThresholdWalletLibs.OperationStatus.PENDING,
                    ThresholdWalletLibs.OperationStatus.REJECTED
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
            revert ThresholdWalletLibs.EmptyOperations();
        }

        for (uint256 i = 0; i < operationNumber; i++) {
            ThresholdWalletLibs.Operation storage op = _operations[operationsHash_[i]];

            if (op.status != ThresholdWalletLibs.OperationStatus.APPROVED) {
                revert ThresholdWalletLibs.ExecuteUnapprovedOperation(op.status);
            }
            if (block.timestamp < op.effectiveTime) {
                revert ThresholdWalletLibs.ExecuteUneffectiveOperation(op.effectiveTime, uint32(block.timestamp));
            }
            if (block.timestamp >= op.expirationTime) {
                op.status = ThresholdWalletLibs.OperationStatus.EXPIRED;
                revert ThresholdWalletLibs.ExecuteExpiredOperation(op.expirationTime, uint32(block.timestamp));
            }

            op.status = ThresholdWalletLibs.OperationStatus.EXECUTING;
            emit ThresholdWalletLibs.OperationStatusChanged(
                operationsHash_[i],
                ThresholdWalletLibs.OperationStatus.APPROVED,
                ThresholdWalletLibs.OperationStatus.EXECUTING
            );

            (bool success,) = op.target.call{value: op.value, gas: op.gasLimit}(op.data);

            if (success) {
                op.status = ThresholdWalletLibs.OperationStatus.EXECUTED;
                emit ThresholdWalletLibs.OperationStatusChanged(
                    operationsHash_[i],
                    ThresholdWalletLibs.OperationStatus.EXECUTING,
                    ThresholdWalletLibs.OperationStatus.EXECUTED
                );
            } else {
                op.status = ThresholdWalletLibs.OperationStatus.FAILED;
                emit ThresholdWalletLibs.OperationStatusChanged(
                    operationsHash_[i],
                    ThresholdWalletLibs.OperationStatus.EXECUTING,
                    ThresholdWalletLibs.OperationStatus.FAILED
                );
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
        if (_walletMode == ThresholdWalletLibs.WalletMode.PUBLIC_KEY_ON_G1) {
            return _publicKeyToMemberOnG2.verifySignaturesWithPublicKeyOnG1(
                _aggregatedPublicKeyOnG1, aggregatedSignature_, message_, signers_
            );
        } else if (_walletMode == ThresholdWalletLibs.WalletMode.PUBLIC_KEY_ON_G2) {
            return _publicKeyToMemberOnG1.verifySignaturesWithPublicKeyOnG2(
                _aggregatedPublicKeyOnG2, aggregatedSignature_, message_, signers_
            );
        } else {
            revert ThresholdWalletLibs.UnsupportedWalletMode(uint8(_walletMode));
        }
    }

    function readWalletMode() public view returns (ThresholdWalletLibs.WalletMode) {
        return _walletMode;
    }
}
