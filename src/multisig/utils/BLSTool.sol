// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {BLS} from "./BLS.sol";

library BLSTool {
    using BLS for BLS.G1Point;
    using BLS for BLS.G2Point;
    using BLS for BLS.G1Point[];
    using BLS for BLS.G2Point[];

    /// @notice Error reverted if the number of secret keys does not match the number of messages
    error SecretKeysNotMatchMessagesLength();

    /// @notice Aggregate public keys on G1 curve
    /// @param pksOnG1_ The array of public keys on G1 curve
    /// @return aggregatedPKOnG1_ The aggregated public key on G1 curve
    /// @dev This can also be done off-chain.
    /// @dev You can refer to https://crates.io/crates/bls12_381 for Rust implementation details
    function aggregatePKsOnG1(BLS.G1Point[] memory pksOnG1_)
        public
        view
        returns (BLS.G1Point memory aggregatedPKOnG1_)
    {
        aggregatedPKOnG1_ = pksOnG1_.sumPointsOnG1();
    }

    /// @notice Aggregate signatures on G1 curve
    /// @param sigsOnG1_ The array of signatures on G1 curve
    /// @return aggregatedSIGOnG1_ The aggregated signature on G1 curve
    /// @dev This can also be done off-chain.
    /// @dev You can refer to https://crates.io/crates/bls12_381 for Rust implementation details
    function aggregateSIGsOnG1(BLS.G1Point[] memory sigsOnG1_)
        public
        view
        returns (BLS.G1Point memory aggregatedSIGOnG1_)
    {
        aggregatedSIGOnG1_ = sigsOnG1_.sumPointsOnG1();
    }

    /// @notice Build signatures on G1 curve
    /// @param sks_ The array of secret keys
    /// @param messages_ The array of messages to be signed
    /// @return aggregatedSigsOnG1_ The aggregated signature on G1 curve
    /// @dev If you just input one secret key and one message, the output is the corresponding signature.
    /// @dev This can also be done off-chain.
    /// @dev You can refer to https://crates.io/crates/bls12_381 for Rust implementation details
    function buildSIGsOnG1(uint256[] memory sks_, bytes[] memory messages_)
        public
        view
        returns (BLS.G1Point memory aggregatedSigsOnG1_)
    {
        uint256 sksLen = sks_.length;

        if (messages_.length != sksLen) {
            revert SecretKeysNotMatchMessagesLength();
        }

        BLS.G1Point[] memory msgToPointsOnG1 = new BLS.G1Point[](sksLen);
        for (uint256 i = 0; i < sksLen; ++i) {
            msgToPointsOnG1[i] = BLS.hashToG1(BLS.BLS_DOMAIN, messages_[i]);
        }

        aggregatedSigsOnG1_ = msgToPointsOnG1.scalarsMulPointsOnG1(sks_);
    }

    /// @notice Calculate public keys on G1 curve
    /// @param sks_ The array of secret keys
    /// @return aggregatedPKsOnG1_ The aggregated public key on G1 curve
    /// @dev If you just input one secret key, the output is the corresponding public key.
    /// @dev This can also be done off-chain.
    /// @dev You can refer to https://crates.io/crates/bls12_381 for Rust implementation details
    function calculatePKsOnG1(uint256[] memory sks_) public view returns (BLS.G1Point memory aggregatedPKsOnG1_) {
        uint256 sksLen = sks_.length;

        BLS.G1Point[] memory generatorsOnG1 = new BLS.G1Point[](sksLen);
        for (uint256 i = 0; i < sksLen; ++i) {
            generatorsOnG1[i] = BLS.generatorG1();
        }

        aggregatedPKsOnG1_ = generatorsOnG1.scalarsMulPointsOnG1(sks_);
    }

    /// @notice Aggregate public keys on G2 curve
    /// @param pksOnG2_ The array of public keys on G2 curve
    /// @return aggregatedPKOnG2_ The aggregated public key on G2 curve
    /// @dev This can also be done off-chain.
    /// @dev You can refer to https://crates.io/crates/bls12_381 for Rust implementation details
    function aggregatePKsOnG2(BLS.G2Point[] memory pksOnG2_)
        public
        view
        returns (BLS.G2Point memory aggregatedPKOnG2_)
    {
        aggregatedPKOnG2_ = pksOnG2_.sumPointsOnG2();
    }

    /// @notice Aggregate signatures on G2 curve
    /// @param sigsOnG2_ The array of signatures on G2 curve
    /// @return aggregatedSIGOnG2_ The aggregated signature on G2 curve
    /// @dev This can also be done off-chain.
    /// @dev You can refer to https://crates.io/crates/bls12_381 for Rust implementation details
    function aggregateSIGsOnG2(BLS.G2Point[] memory sigsOnG2_)
        public
        view
        returns (BLS.G2Point memory aggregatedSIGOnG2_)
    {
        aggregatedSIGOnG2_ = sigsOnG2_.sumPointsOnG2();
    }

    /// @notice Build signatures on G2 curve
    /// @param sks_ The array of secret keys
    /// @param messages_ The array of messages to be signed
    /// @return aggregatedSigsOnG2_ The aggregated signature on G2 curve
    /// @dev If you just input one secret key and one message, the output is the corresponding signature.
    /// @dev This can also be done off-chain.
    /// @dev You can refer to https://crates.io/crates/bls12_381 for Rust implementation details
    function buildSIGsOnG2(uint256[] memory sks_, bytes[] memory messages_)
        public
        view
        returns (BLS.G2Point memory aggregatedSigsOnG2_)
    {
        uint256 sksLen = sks_.length;

        if (messages_.length != sksLen) {
            revert SecretKeysNotMatchMessagesLength();
        }

        BLS.G2Point[] memory msgToPointsOnG2 = new BLS.G2Point[](sksLen);
        for (uint256 i = 0; i < sksLen; ++i) {
            msgToPointsOnG2[i] = BLS.hashToG2(BLS.BLS_DOMAIN, messages_[i]);
        }

        aggregatedSigsOnG2_ = msgToPointsOnG2.scalarsMulPointsOnG2(sks_);
    }

    /// @notice Calculate public keys on G2 curve
    /// @param sks_ The array of secret keys
    /// @return aggregatedPKsOnG2_ The aggregated public key on G2 curve
    /// @dev If you just input one secret key, the output is the corresponding public key.
    /// @dev This can also be done off-chain.
    /// @dev You can refer to https://crates.io/crates/bls12_381 for Rust implementation details
    function calculatePKsOnG2(uint256[] memory sks_) public view returns (BLS.G2Point memory aggregatedPKsOnG2_) {
        uint256 sksLen = sks_.length;

        BLS.G2Point[] memory generatorsOnG2 = new BLS.G2Point[](sksLen);
        for (uint256 i = 0; i < sksLen; ++i) {
            generatorsOnG2[i] = BLS.generatorG2();
        }

        aggregatedPKsOnG2_ = generatorsOnG2.scalarsMulPointsOnG2(sks_);
    }
}
