// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Roles} from "../../../common/Roles.sol";
import {Errors} from "../../../common/Errors.sol";

import {BLS} from "../../utils/BLS.sol";
import {ThresholdWalletLibs} from "../utils/ThresholdWalletLibs.sol";

library ThresholdWalletPKOnG1 {
    using BLS for BLS.G1Point;
    using BLS for BLS.G2Point;
    using BLS for BLS.G1Point[];
    using BLS for BLS.G2Point[];
    using ThresholdWalletLibs for bytes[];

    function initialize(
        mapping(bytes32 => ThresholdWalletLibs.MemberOnG2) storage publicKeyToMemberOnG2_,
        bytes[] memory publicKeys_,
        bytes[] memory memberIDs_
    ) public returns (BLS.G1Point memory aggregatedPublicKeyOnG1_) {
        uint256 publicKeysNum = publicKeys_.length;

        uint256[] memory thresholdOfPublicKeys = new uint256[](publicKeysNum);
        bytes memory publicKeysInLine = publicKeys_.concatBytes();

        BLS.G1Point[] memory publicKeysOnG1 = new BLS.G1Point[](publicKeysNum);

        for (uint256 i = 0; i < publicKeysNum; ++i) {
            if (publicKeys_[i].length != 128) {
                revert ThresholdWalletLibs.InvalidPublicKey("Invalid public key length for G1");
            }
            thresholdOfPublicKeys[i] = uint256(keccak256(bytes.concat(publicKeys_[i], publicKeysInLine)));
            publicKeysOnG1[i] = abi.decode(publicKeys_[i], (BLS.G1Point));
            publicKeyToMemberOnG2_[keccak256(publicKeys_[i])] = ThresholdWalletLibs.MemberOnG2({
                threshold: thresholdOfPublicKeys[i],
                thresholdPointOnG2: BLS.hashToG2(BLS.BLS_DOMAIN, abi.encodePacked(thresholdOfPublicKeys[i])),
                memberIDPointOnG2: abi.decode(memberIDs_[i], (BLS.G2Point))
            });
        }
        aggregatedPublicKeyOnG1_ = publicKeysOnG1.scalarsMulPointsOnG1(thresholdOfPublicKeys);
        for (uint256 i = 0; i < publicKeysNum; ++i) {
            ThresholdWalletLibs.MemberOnG2 memory memberOnG2 = publicKeyToMemberOnG2_[keccak256(publicKeys_[i])];
            if (
                !BLS.pairWhenPKOnG1(
                    memberOnG2.memberIDPointOnG2, aggregatedPublicKeyOnG1_, memberOnG2.thresholdPointOnG2
                )
            ) {
                revert ThresholdWalletLibs.InvalidSignature("Member ID does not match public key on G1");
            }
        }
    }

    /// @notice Check if the aggregated public key on G1 curve is empty
    /// @return True if the aggregated public key on G1 curve is empty, false otherwise
    function publicKeyOnG1IsEmpty(BLS.G1Point storage aggregatedPublicKeyOnG1_) public view returns (bool) {
        return aggregatedPublicKeyOnG1_.X.upper == 0 && aggregatedPublicKeyOnG1_.X.lower == 0
            && aggregatedPublicKeyOnG1_.Y.upper == 0 && aggregatedPublicKeyOnG1_.Y.lower == 0;
    }
}
