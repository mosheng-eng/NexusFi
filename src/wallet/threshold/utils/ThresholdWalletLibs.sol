// SPDX-Licensed-Identifier: MIT

pragma solidity ^0.8.24;

import {BLS} from "../../utils/BLS.sol";

library ThresholdWalletLibs {
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

    /// @notice Verify aggregated signatures with public key on G1 curve
    /// @param aggregatedSignature_ The aggregated signature to be verified
    /// @param message_ The message that was signed
    /// @return True if the aggregated signature is valid, false otherwise
    function verifySignaturesWithPublicKeyOnG1(
        mapping(bytes32 => MemberOnG2) storage publicKeyToMemberOnG2_,
        BLS.G1Point memory aggregatedPublicKeyOnG1_,
        bytes memory aggregatedSignature_,
        bytes memory message_,
        bytes[] memory signers_
    ) public view returns (bool) {
        if (aggregatedSignature_.length != 256) {
            revert ThresholdWalletLibs.InvalidSignature("Invalid aggregated signature length for G1");
        }

        uint256 signersNum = signers_.length;
        BLS.G1Point[] memory signerPKsOnG1 = new BLS.G1Point[](signersNum);
        BLS.G2Point[] memory signerMemberIDsOnG2 = new BLS.G2Point[](signersNum);

        for (uint256 i = 0; i < signersNum; ++i) {
            bytes32 signerPKHash = keccak256(signers_[i]);
            if (publicKeyToMemberOnG2_[signerPKHash].threshold == 0) {
                revert ThresholdWalletLibs.UnrecognizedSigner(signerPKHash);
            }
            signerPKsOnG1[i] = abi.decode(signers_[i], (BLS.G1Point));
            signerMemberIDsOnG2[i] = publicKeyToMemberOnG2_[signerPKHash].thresholdPointOnG2;
        }

        BLS.G1Point[] memory g1Points = new BLS.G1Point[](3);
        BLS.G2Point[] memory g2Points = new BLS.G2Point[](3);

        g1Points[0] = BLS.negGeneratorG1();
        g1Points[1] = signerPKsOnG1.sumPointsOnG1();
        g1Points[2] = aggregatedPublicKeyOnG1_;

        g2Points[0] = abi.decode(aggregatedSignature_, (BLS.G2Point));
        g2Points[1] = BLS.hashToG2(BLS.BLS_DOMAIN, message_);
        g2Points[2] = signerMemberIDsOnG2.sumPointsOnG2();

        return BLS.generalPairing(g1Points, g2Points);
    }

    /// @notice Verify aggregated signatures with public key on G2 curve
    /// @param aggregatedSignature_ The aggregated signature to be verified
    /// @param message_ The message that was signed
    /// @return True if the aggregated signature is valid, false otherwise
    function verifySignaturesWithPublicKeyOnG2(
        mapping(bytes32 => MemberOnG1) storage publicKeyToMemberOnG1_,
        BLS.G2Point memory aggregatedPublicKeyOnG2_,
        bytes memory aggregatedSignature_,
        bytes memory message_,
        bytes[] memory signers_
    ) public view returns (bool) {
        if (aggregatedSignature_.length != 128) {
            revert ThresholdWalletLibs.InvalidSignature("Invalid aggregated signature length for G2");
        }

        uint256 signersNum = signers_.length;
        BLS.G2Point[] memory signerPKsOnG2 = new BLS.G2Point[](signersNum);
        BLS.G1Point[] memory signerMemberIDsOnG1 = new BLS.G1Point[](signersNum);

        for (uint256 i = 0; i < signersNum; ++i) {
            bytes32 signerPKHash = keccak256(signers_[i]);
            if (publicKeyToMemberOnG1_[signerPKHash].threshold == 0) {
                revert ThresholdWalletLibs.UnrecognizedSigner(signerPKHash);
            }
            signerPKsOnG2[i] = abi.decode(signers_[i], (BLS.G2Point));
            signerMemberIDsOnG1[i] = publicKeyToMemberOnG1_[signerPKHash].thresholdPointOnG1;
        }

        BLS.G1Point[] memory g1Points = new BLS.G1Point[](3);
        BLS.G2Point[] memory g2Points = new BLS.G2Point[](3);

        g1Points[0] = abi.decode(aggregatedSignature_, (BLS.G1Point));
        g1Points[1] = BLS.hashToG1(BLS.BLS_DOMAIN, message_);
        g1Points[2] = signerMemberIDsOnG1.sumPointsOnG1();

        g2Points[0] = BLS.negGeneratorG2();
        g2Points[1] = signerPKsOnG2.sumPointsOnG2();
        g2Points[2] = aggregatedPublicKeyOnG2_;

        return BLS.generalPairing(g1Points, g2Points);
    }

    /// @notice Concatenate an array of bytes into a single bytes array
    /// @param bytesArray_ The array of bytes to concatenate
    /// @return bytesSingle_ The concatenated bytes array
    function concatBytes(bytes[] memory bytesArray_) public pure returns (bytes memory bytesSingle_) {
        for (uint256 i = 0; i < bytesArray_.length; ++i) {
            bytesSingle_ = abi.encodePacked(bytesSingle_, bytesArray_[i]);
        }
    }

    /// @notice Calculate the operation hash
    /// @param op The operation to calculate the hash for
    /// @return The hash of the operation
    function getOperationHash(ThresholdWalletLibs.Operation memory op) public pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(op.target, op.value, op.effectiveTime, op.expirationTime, op.gasLimit, op.nonce, op.data)
        );
    }
}
