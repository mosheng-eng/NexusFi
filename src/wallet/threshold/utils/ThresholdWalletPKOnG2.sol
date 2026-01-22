// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Roles} from "../../../common/Roles.sol";
import {Errors} from "../../../common/Errors.sol";

import {BLS} from "../../utils/BLS.sol";
import {ThresholdWalletLibs} from "../utils/ThresholdWalletLibs.sol";

library ThresholdWalletPKOnG2 {
    using BLS for BLS.G1Point;
    using BLS for BLS.G2Point;
    using BLS for BLS.G1Point[];
    using BLS for BLS.G2Point[];
    using ThresholdWalletLibs for bytes[];

    function initialize(
        mapping(bytes32 => ThresholdWalletLibs.MemberOnG1) storage publicKeyToMemberOnG1_,
        bytes[] memory publicKeys_,
        bytes[] memory memberIDs_
    ) public returns (BLS.G2Point memory aggregatedPublicKeyOnG2_) {
        uint256 publicKeysNum = publicKeys_.length;

        uint256[] memory thresholdOfPublicKeys = new uint256[](publicKeysNum);
        bytes memory publicKeysInLine = publicKeys_.concatBytes();

        BLS.G2Point[] memory publicKeysOnG2 = new BLS.G2Point[](publicKeysNum);

        for (uint256 i = 0; i < publicKeysNum; ++i) {
            if (publicKeys_[i].length != 256) {
                revert ThresholdWalletLibs.InvalidPublicKey("Invalid public key length for G2");
            }
            thresholdOfPublicKeys[i] = uint256(keccak256(bytes.concat(publicKeys_[i], publicKeysInLine)));
            publicKeysOnG2[i] = abi.decode(publicKeys_[i], (BLS.G2Point));
            publicKeyToMemberOnG1_[keccak256(publicKeys_[i])] = ThresholdWalletLibs.MemberOnG1({
                threshold: thresholdOfPublicKeys[i],
                thresholdPointOnG1: BLS.hashToG1(BLS.BLS_DOMAIN, abi.encodePacked(thresholdOfPublicKeys[i])),
                memberIDPointOnG1: abi.decode(memberIDs_[i], (BLS.G1Point))
            });
        }
        aggregatedPublicKeyOnG2_ = publicKeysOnG2.scalarsMulPointsOnG2(thresholdOfPublicKeys);
        for (uint256 i = 0; i < publicKeysNum; ++i) {
            ThresholdWalletLibs.MemberOnG1 memory memberOnG1 = publicKeyToMemberOnG1_[keccak256(publicKeys_[i])];
            if (
                !BLS.pairWhenPKOnG2(
                    memberOnG1.memberIDPointOnG1, aggregatedPublicKeyOnG2_, memberOnG1.thresholdPointOnG1
                )
            ) {
                revert ThresholdWalletLibs.InvalidSignature("Member ID does not match public key on G2");
            }
        }
    }

    /// @notice Check if the aggregated public key on G2 curve is empty
    /// @return True if the aggregated public key on G2 curve is empty, false otherwise
    function publicKeyOnG2IsEmpty(BLS.G2Point storage aggregatedPublicKeyOnG2_) public view returns (bool) {
        return aggregatedPublicKeyOnG2_.X0.upper == 0 && aggregatedPublicKeyOnG2_.X0.lower == 0
            && aggregatedPublicKeyOnG2_.X1.upper == 0 && aggregatedPublicKeyOnG2_.X1.lower == 0
            && aggregatedPublicKeyOnG2_.Y0.upper == 0 && aggregatedPublicKeyOnG2_.Y0.lower == 0
            && aggregatedPublicKeyOnG2_.Y1.upper == 0 && aggregatedPublicKeyOnG2_.Y1.lower == 0;
    }
}
