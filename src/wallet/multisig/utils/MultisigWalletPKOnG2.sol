// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Roles} from "../../../common/Roles.sol";
import {Errors} from "../../../common/Errors.sol";

import {BLS} from "../../utils/BLS.sol";
import {MultisigWalletLibs} from "./MultisigWalletLibs.sol";

library MultisigWalletPKOnG2 {
    using BLS for BLS.G1Point;
    using BLS for BLS.G2Point;
    using BLS for BLS.G1Point[];
    using BLS for BLS.G2Point[];

    function initialize(bytes calldata publicKey_) public pure returns (BLS.G2Point memory aggregatedPublicKeyOnG2_) {
        if (publicKey_.length != 8 * 32) {
            revert MultisigWalletLibs.InvalidPublicKey("Invalid public key length for G2");
        }
        aggregatedPublicKeyOnG2_ = BLS.G2Point(
            BLS.Unit(uint256(bytes32(publicKey_[0:32])), uint256(bytes32(publicKey_[32:64]))),
            BLS.Unit(uint256(bytes32(publicKey_[64:96])), uint256(bytes32(publicKey_[96:128]))),
            BLS.Unit(uint256(bytes32(publicKey_[128:160])), uint256(bytes32(publicKey_[160:192]))),
            BLS.Unit(uint256(bytes32(publicKey_[192:224])), uint256(bytes32(publicKey_[224:256])))
        );
    }
}
