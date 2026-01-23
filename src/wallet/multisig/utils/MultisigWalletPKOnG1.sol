// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Roles} from "../../../common/Roles.sol";
import {Errors} from "../../../common/Errors.sol";

import {BLS} from "../../utils/BLS.sol";
import {MultisigWalletLibs} from "./MultisigWalletLibs.sol";

library MultisigWalletPKOnG1 {
    using BLS for BLS.G1Point;
    using BLS for BLS.G2Point;
    using BLS for BLS.G1Point[];
    using BLS for BLS.G2Point[];

    function initialize(bytes calldata publicKey_) public pure returns (BLS.G1Point memory aggregatedPublicKeyOnG1_) {
        if (publicKey_.length != 4 * 32) {
            revert MultisigWalletLibs.InvalidPublicKey("Invalid public key length for G1");
        }
        aggregatedPublicKeyOnG1_ = BLS.G1Point(
            BLS.Unit(uint256(bytes32(publicKey_[0:32])), uint256(bytes32(publicKey_[32:64]))),
            BLS.Unit(uint256(bytes32(publicKey_[64:96])), uint256(bytes32(publicKey_[96:128])))
        );
    }
}
