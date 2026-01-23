// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Roles} from "../../../common/Roles.sol";
import {Errors} from "../../../common/Errors.sol";

import {BLS} from "../../utils/BLS.sol";

library MultisigWalletLibs {
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

    /// @notice Check if the aggregated public key on G1 curve is empty
    /// @return True if the aggregated public key on G1 curve is empty, false otherwise
    function publicKeyOnG1IsEmpty(BLS.G1Point storage aggregatedPublicKeyOnG1_) public view returns (bool) {
        return aggregatedPublicKeyOnG1_.X.upper == 0 && aggregatedPublicKeyOnG1_.X.lower == 0
            && aggregatedPublicKeyOnG1_.Y.upper == 0 && aggregatedPublicKeyOnG1_.Y.lower == 0;
    }

    /// @notice Check if the aggregated public key on G2 curve is empty
    /// @return True if the aggregated public key on G2 curve is empty, false otherwise
    function publicKeyOnG2IsEmpty(BLS.G2Point storage aggregatedPublicKeyOnG2_) public view returns (bool) {
        return aggregatedPublicKeyOnG2_.X0.upper == 0 && aggregatedPublicKeyOnG2_.X0.lower == 0
            && aggregatedPublicKeyOnG2_.X1.upper == 0 && aggregatedPublicKeyOnG2_.X1.lower == 0
            && aggregatedPublicKeyOnG2_.Y0.upper == 0 && aggregatedPublicKeyOnG2_.Y0.lower == 0
            && aggregatedPublicKeyOnG2_.Y1.upper == 0 && aggregatedPublicKeyOnG2_.Y1.lower == 0;
    }

    /// @notice Verify aggregated signatures with public key on G1 curve
    /// @param aggregatedSignature_ The aggregated signature to be verified
    /// @param message_ The message that was signed
    /// @return True if the aggregated signature is valid, false otherwise
    function verifySignaturesWithPublicKeyOnG1(
        BLS.G1Point storage aggregatedPublicKeyOnG1_,
        bytes memory aggregatedSignature_,
        bytes memory message_
    ) public view returns (bool) {
        if (aggregatedSignature_.length != 256) {
            revert InvalidSignature("Invalid aggregated signature length for G1");
        }

        BLS.G2Point memory sigOnG2 = abi.decode(aggregatedSignature_, (BLS.G2Point));

        BLS.G2Point memory hashToG2 = BLS.hashToG2(BLS.BLS_DOMAIN, message_);

        return sigOnG2.pairWhenPKOnG1(aggregatedPublicKeyOnG1_, hashToG2);
    }

    /// @notice Verify aggregated signatures with public key on G2 curve
    /// @param aggregatedSignature_ The aggregated signature to be verified
    /// @param message_ The message that was signed
    /// @return True if the aggregated signature is valid, false otherwise
    function verifySignaturesWithPublicKeyOnG2(
        BLS.G2Point storage aggregatedPublicKeyOnG2_,
        bytes memory aggregatedSignature_,
        bytes memory message_
    ) public view returns (bool) {
        if (aggregatedSignature_.length != 128) {
            revert InvalidSignature("Invalid aggregated signature length for G2");
        }

        BLS.G1Point memory sigOnG1 = abi.decode(aggregatedSignature_, (BLS.G1Point));

        BLS.G1Point memory hashToG1 = BLS.hashToG1(BLS.BLS_DOMAIN, message_);

        return sigOnG1.pairWhenPKOnG2(aggregatedPublicKeyOnG2_, hashToG1);
    }

    /// @notice Calculate the operation hash
    /// @param op The operation to calculate the hash for
    /// @return The hash of the operation
    function getOperationHash(Operation memory op) public pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(op.target, op.value, op.effectiveTime, op.expirationTime, op.gasLimit, op.nonce, op.data)
        );
    }
}
