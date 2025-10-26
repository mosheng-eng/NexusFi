// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library BLSHelper {
    error EllTooLarge(uint256 ell);
    error LengthTooLarge(uint256 len_in_bytes);
    error DSTTooLong(uint256 dst_length);

    uint256 constant B_IN_BYTES = 32; // SHA-256 output size in bytes
    uint256 constant S_IN_BYTES = 64; // SHA-256 block size in bytes

    // L = ceil((ceil(log2(p)) + k) / 8), where k is the security parameter
    // ceil(log2(p)) = 381, k = 128
    // ceil((381 + 128) / 8) = 64
    uint256 constant L = 64;
    // BLS12-381 base field prime
    bytes constant P =
        hex"1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab";

    /// @notice Hashes an arbitrary input to one or more field elements in the base field Fp of BLS12-381
    /// @param input_ The input bytes to hash
    /// @param dst_ The domain separation tag to prevent collisions between different hash usages
    /// @param count_ The number of field elements to generate
    /// @return result_ An array of count field elements in Fp
    function hashToFp(bytes memory input_, string memory dst_, uint256 count_)
        public
        view
        returns (bytes[] memory result_)
    {
        result_ = new bytes[](count_);
        uint16 length_in_bytes = uint16(count_ * L);
        bytes memory uniform_bytes = expandMessageXMD(input_, dst_, length_in_bytes);
        for (uint256 i = 0; i < count_; i++) {
            // m - 1 = 0, so no loop
            // L * (j + i * m), m = 1, j = 0 => L * i
            uint256 elm_offset = L * i;
            bytes memory slice = new bytes(L);
            assembly {
                mcopy(add(slice, 0x20), add(add(uniform_bytes, 0x20), elm_offset), L)
            }
            // We need to sanitize the Fp elements to be represented with 64 byte arrays
            bytes memory slice_mod_p = Math.modExp(slice, hex"01", P);
            uint256 pad = L - slice_mod_p.length;
            bytes memory fp_bytes = new bytes(L);
            assembly {
                mcopy(add(add(fp_bytes, 0x20), pad), add(slice_mod_p, 0x20), L)
            }
            result_[i] = fp_bytes;
        }
    }

    /// @notice Hashes an arbitrary input to one or more field elements in the extension field Fp2 of BLS12-381
    /// @param input_ The input bytes to hash
    /// @param dst_ The domain separation tag to prevent collisions between different hash usages
    /// @param count_ The number of field elements to generate
    /// @return result_ An array of count field elements in Fp2
    function hashToFp2(bytes memory input_, string memory dst_, uint256 count_)
        public
        view
        returns (bytes[] memory result_)
    {
        result_ = new bytes[](count_);
        uint16 length_in_bytes = uint16(count_ * L * 2);
        bytes memory uniform_bytes = expandMessageXMD(input_, dst_, length_in_bytes);
        for (uint256 i = 0; i < count_; i++) {
            // m - 1 = 1, so 2 iterations
            // L * (j + i * m), m = 2, j = 0 => L * 2i
            // L * (j + i * m), m = 2, j = 1 => L * (2i + 1)
            bytes memory result_i_bytes = new bytes(L * 2);
            for (uint256 j = 0; j < 2; j++) {
                uint256 elm_offset = L * (j + i * 2);
                bytes memory slice = new bytes(L);
                assembly {
                    mcopy(add(slice, 0x20), add(add(uniform_bytes, 0x20), elm_offset), L)
                }
                // The mod operation removes trailing zeros, so we need to pad the results
                // such that in the end we have a 128 byte array for each Fp2 element
                bytes memory slice_mod_p = Math.modExp(slice, hex"01", P);
                uint256 pad = L - slice_mod_p.length;
                bytes memory slice_sanitized = new bytes(L);
                // NOTE: this can be optimized to a single copy
                assembly {
                    // copy slice_mod_p to slice_sanitized
                    mcopy(add(add(slice_sanitized, 0x20), pad), add(slice_mod_p, 0x20), L)
                    // copy slice_sanitized to result_i_bytes[64j:64(j+1)]
                    mcopy(add(add(result_i_bytes, 0x20), mul(j, L)), add(slice_sanitized, 0x20), L)
                }
            }
            result_[i] = result_i_bytes;
        }
    }

    /// @notice Expands a message using the expand_message_xmd method as per RFC9380.
    /// @param message_ The input message as bytes.
    /// @param dst_ The domain separation tag as a string.
    /// @param len_in_bytes_ The desired length of the output in bytes.
    /// @return result The expanded message as a byte array.
    function expandMessageXMD(bytes memory message_, string memory dst_, uint16 len_in_bytes_)
        public
        pure
        returns (bytes memory result)
    {
        // Step 1: Calculate ell
        uint256 ell = (len_in_bytes_ + B_IN_BYTES - 1) / B_IN_BYTES;

        // Step 2: Perform checks
        if (ell > 255) revert EllTooLarge(ell);
        if (len_in_bytes_ > 65535) revert LengthTooLarge(len_in_bytes_);
        if (bytes(dst_).length > 255) revert DSTTooLong(bytes(dst_).length);

        // Step 3: Construct DST_prime
        bytes memory DST_bytes = bytes(dst_);
        bytes memory DST_prime = abi.encodePacked(DST_bytes, I2OSP(uint256(DST_bytes.length), 1));

        // Step 4: Create Z_pad
        bytes memory Z_pad = I2OSP(0, S_IN_BYTES);

        // Step 5: Encode len_in_bytes
        bytes memory l_i_b_str = I2OSP(uint256(len_in_bytes_), 2);

        // Step 6: Construct msg_prime
        bytes memory msg_prime = abi.encodePacked(Z_pad, message_, l_i_b_str, I2OSP(0, 1), DST_prime);

        // Step 7: Compute b_0
        bytes32 b0 = sha256(msg_prime);

        // Step 8: Compute b_1
        bytes memory b0_bytes = abi.encodePacked(b0);
        bytes memory b1_input = abi.encodePacked(b0_bytes, I2OSP(1, 1), DST_prime);
        bytes32 b1 = sha256(b1_input);

        // Initialize array to hold b_i values
        bytes memory uniform_bytes = abi.encodePacked(b1);

        // Initialize previous block
        bytes32 prev_block = b1;

        // Step 9: Compute b_i for i = 2 to ell
        for (uint256 i = 2; i <= ell; i++) {
            // strxor(b0, b_{i-1})
            bytes32 xor_input = b0 ^ prev_block;

            // I2OSP(i, 1)
            bytes memory i_bytes = I2OSP(i, 1);

            // Construct input for hashing
            bytes memory bi_input = abi.encodePacked(xor_input, i_bytes, DST_prime);

            // Compute b_i
            bytes32 bi = sha256(bi_input);

            // Append b_i to uniform_bytes
            uniform_bytes = abi.encodePacked(uniform_bytes, bi);

            // Update previous block
            prev_block = bi;
        }

        // Step 11: Truncate to desired length
        assembly {
            result := uniform_bytes
            mstore(result, len_in_bytes_)
        }
    }

    /// @dev Converts a non-negative integer to its big-endian byte representation.
    /// @param x_ The integer to convert.
    /// @param length_ The desired length of the output byte array.
    /// @return o_ The resulting byte array.
    function I2OSP(uint256 x_, uint256 length_) internal pure returns (bytes memory o_) {
        o_ = new bytes(length_);
        for (uint256 i = 0; i < length_; i++) {
            o_[length_ - 1 - i] = bytes1(uint8(x_ >> (8 * i)));
        }
        return o_;
    }
}
