// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {BLSHelper} from "./BLSHelper.sol";

/// @title BLS library
/// @notice Provides functions for BLS signature scheme operations
/// @dev Precompiled contracts are used for elliptic curve operations
/// @dev please refer to https://www.evm.codes/precompiled for more details
library BLS {
    /// @notice Error reverted if trying to sum zero points
    error EmptyPointsToSum();

    /// @notice Error reverted if summing points failed
    error SumPointsFailed();

    /// @notice Error reverted if hashing to Fp failed
    error HashToFpFailed();

    /// @notice Error reverted if hashing to Fp2 failed
    error HashToFp2Failed();

    /// @notice Error reverted if scalars length does not match G1 points length
    error ScalarsLengthNotMatchG1PointsLength();

    /// @notice Error reverted if scalars length does not match G2 points length
    error ScalarsLengthNotMatchG2PointsLength();

    /// @notice Error reverted if scalar multiplication on G1 points failed
    error ScalarsMulPointsOnG1Failed();

    /// @notice Error reverted if scalar multiplication on G2 points failed
    error ScalarsMulPointsOnG2Failed();

    /// @notice Error reverted if pairing with public key on G1 failed
    error PairWhenPKOnG1Failed();

    /// @notice Error reverted if pairing with public key on G2 failed
    error PairWhenPKOnG2Failed();

    /// @notice Error reverted if G1 points do not match G2 points in general pairing
    error G1PointsShouldMatchG2PointsWhenGeneralPairing();

    /// @notice Error reverted if general pairing operation failed
    error GeneralPairingFailed();

    /// @notice Represents a uint of 384 bits (bytes48)
    /// @param upper The upper 256 bits (bytes32), zero padded in first 128 bits (bytes16)
    /// @param lower The lower 256 bits (bytes32)
    struct Unit {
        uint256 upper;
        uint256 lower;
    }

    /// @notice Represents a point in G1
    struct G1Point {
        /// @notice X is bytes48 and saved in two bytes32 (X.upper, X.lower)
        /// @notice X.upper has zero padding at lower bytes
        Unit X;
        /// @notice Y is bytes48 and saved in two bytes32 (Y.upper, Y.lower)
        /// @notice Y.upper has zero padding at lower bytes
        Unit Y;
    }

    /// @notice Represents a point in G2
    struct G2Point {
        /// @notice X0 is bytes48 and saved in two bytes32 (X0.upper, X0.lower)
        /// @notice X0.upper has zero padding at lower bytes
        Unit X0;
        /// @notice X1 is bytes48 and saved in two bytes32 (X1.upper, X1.lower)
        /// @notice X1.upper has zero padding at lower bytes
        Unit X1;
        /// @notice Y0 is bytes48 and saved in two bytes32 (Y0.upper, Y0.lower)
        /// @notice Y0.upper has zero padding at lower bytes
        Unit Y0;
        /// @notice Y1 is bytes48 and saved in two bytes32 (Y1.upper, Y1.lower)
        /// @notice Y1.upper has zero padding at lower bytes
        Unit Y1;
    }

    /// @notice BLS12-381 precompile addresses
    /// @dev Please refer to https://eips.ethereum.org/EIPS/eip-2537#precompiled-contracts
    address constant G1_ADD = address(0x0B);
    address constant G1_MSM = address(0x0C);
    address constant G2_ADD = address(0x0D);
    address constant G2_MSM = address(0x0E);
    address constant PAIRING = address(0x0F);
    address constant MAP_FP_TO_G1 = address(0x10);
    address constant MAP_FP2_TO_G2 = address(0x11);

    /// @notice Generator point on G1 curve
    /// @dev Please refer to https://eips.ethereum.org/EIPS/eip-2537#curve-parameters
    uint256 public constant G1_X_UPPER = 0x0000000000000000000000000000000017f1d3a73197d7942695638c4fa9ac0f;
    uint256 public constant G1_X_LOWER = 0xc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb;
    uint256 public constant G1_Y_UPPER = 0x0000000000000000000000000000000008b3f481e3aaa0f1a09e30ed741d8ae4;
    uint256 public constant G1_Y_LOWER = 0xfcf5e095d5d00af600db18cb2c04b3edd03cc744a2888ae40caa232946c5e7e1;

    /// @notice Negative of Generator point on G1 curve
    /// @dev Please refer to https://eips.ethereum.org/EIPS/eip-2537#curve-parameters
    uint256 public constant NEG_G1_X_UPPER = 0x0000000000000000000000000000000017f1d3a73197d7942695638c4fa9ac0f;
    uint256 public constant NEG_G1_X_LOWER = 0xc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb;
    uint256 public constant NEG_G1_Y_UPPER = 0x00000000000000000000000000000000114d1d6855d545a8aa7d76c8cf2e21f2;
    uint256 public constant NEG_G1_Y_LOWER = 0x67816aef1db507c96655b9d5caac42364e6f38ba0ecb751bad54dcd6b939c2ca;

    /// @notice Generator point on G2 curve
    /// @dev Please refer to https://eips.ethereum.org/EIPS/eip-2537#curve-parameters
    uint256 public constant G2_X0_UPPER = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 public constant G2_X0_LOWER = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 public constant G2_X1_UPPER = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 public constant G2_X1_LOWER = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 public constant G2_Y0_UPPER = 0x000000000000000000000000000000000ce5d527727d6e118cc9cdc6da2e351a;
    uint256 public constant G2_Y0_LOWER = 0xadfd9baa8cbdd3a76d429a695160d12c923ac9cc3baca289e193548608b82801;
    uint256 public constant G2_Y1_UPPER = 0x000000000000000000000000000000000606c4a02ea734cc32acd2b02bc28b99;
    uint256 public constant G2_Y1_LOWER = 0xcb3e287e85a763af267492ab572e99ab3f370d275cec1da1aaa9075ff05f79be;

    /// @notice Negative of Generator point on G2 curve
    /// @dev Please refer to https://eips.ethereum.org/EIPS/eip-2537#curve-parameters
    uint256 public constant NEG_G2_X0_UPPER = 0x00000000000000000000000000000000024aa2b2f08f0a91260805272dc51051;
    uint256 public constant NEG_G2_X0_LOWER = 0xc6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8;
    uint256 public constant NEG_G2_X1_UPPER = 0x0000000000000000000000000000000013e02b6052719f607dacd3a088274f65;
    uint256 public constant NEG_G2_X1_LOWER = 0x596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e;
    uint256 public constant NEG_G2_Y0_UPPER = 0x000000000000000000000000000000000d1b3cc2c7027888be51d9ef691d77bc;
    uint256 public constant NEG_G2_Y0_LOWER = 0xb679afda66c73f17f9ee3837a55024f78c71363275a75d75d86bab79f74782aa;
    uint256 public constant NEG_G2_Y1_UPPER = 0x0000000000000000000000000000000013fa4d4a0ad8b1ce186ed5061789213d;
    uint256 public constant NEG_G2_Y1_LOWER = 0x993923066dddaf1040bc3ff59f825c78df74f2d75467e25e0f55f8a00fa030ed;

    /// @notice Domain separation tag for BLS operations in Multisig Wallet
    /// @dev Domain can be any string you like, just make sure to keep it consistent across all operations
    string internal constant BLS_DOMAIN = "MULTISIG_WALLET_BLS_DOMAIN";

    /// @notice Returns the generator point on G1 curve
    /// @return pointOnG1_ The generator point on G1 curve
    function generatorG1() public pure returns (G1Point memory) {
        return G1Point(Unit(G1_X_UPPER, G1_X_LOWER), Unit(G1_Y_UPPER, G1_Y_LOWER));
    }

    /// @notice Returns the generator point on G2 curve
    /// @return pointOnG2_ The generator point on G2 curve
    function generatorG2() public pure returns (G2Point memory) {
        return G2Point(
            Unit(G2_X0_UPPER, G2_X0_LOWER),
            Unit(G2_X1_UPPER, G2_X1_LOWER),
            Unit(G2_Y0_UPPER, G2_Y0_LOWER),
            Unit(G2_Y1_UPPER, G2_Y1_LOWER)
        );
    }

    /// @notice Returns the negative of generator point on G1 curve
    /// @return pointOnG1_ The negative of generator point on G1 curve
    function negGeneratorG1() public pure returns (G1Point memory) {
        return G1Point(Unit(NEG_G1_X_UPPER, NEG_G1_X_LOWER), Unit(NEG_G1_Y_UPPER, NEG_G1_Y_LOWER));
    }

    /// @notice Returns the negative of generator point on G2 curve
    /// @return pointOnG2_ The negative of generator point on G2 curve
    function negGeneratorG2() public pure returns (G2Point memory) {
        return G2Point(
            Unit(NEG_G2_X0_UPPER, NEG_G2_X0_LOWER),
            Unit(NEG_G2_X1_UPPER, NEG_G2_X1_LOWER),
            Unit(NEG_G2_Y0_UPPER, NEG_G2_Y0_LOWER),
            Unit(NEG_G2_Y1_UPPER, NEG_G2_Y1_LOWER)
        );
    }

    /// @notice Sums an array of points on G1 curve
    /// @param pointsOnG1_ The array of points on G1 curve to be summed
    /// @return result_ The resulting point on G1 curve after summation
    /// @dev Uses the precompiled contract at address 0x0B for point addition
    /// @dev Usually used for aggregating public keys or signatures on G1 curve
    function sumPointsOnG1(G1Point[] memory pointsOnG1_) public view returns (G1Point memory result_) {
        if (pointsOnG1_.length == 0) {
            revert EmptyPointsToSum();
        } else {
            result_ = pointsOnG1_[0];
            uint256[8] memory input;
            for (uint256 i = 1; i < pointsOnG1_.length; ++i) {
                input[0] = result_.X.upper;
                input[1] = result_.X.lower;
                input[2] = result_.Y.upper;
                input[3] = result_.Y.lower;
                input[4] = pointsOnG1_[i].X.upper;
                input[5] = pointsOnG1_[i].X.lower;
                input[6] = pointsOnG1_[i].Y.upper;
                input[7] = pointsOnG1_[i].Y.lower;

                bool success;
                uint256[4] memory output;

                // solium-disable-next-line security/no-inline-assembly
                assembly {
                    success := staticcall(sub(gas(), 2000), 0x0B, input, 0x0100, output, 0x80)
                    // Use "invalid" to make gas estimation work
                    switch success
                    case 0 { invalid() }
                }

                if (!success) {
                    revert SumPointsFailed();
                }

                result_ = G1Point(Unit(output[0], output[1]), Unit(output[2], output[3]));
            }
        }
    }

    /// @notice Adds two points on G1 curve
    /// @param pointA_ The first point on G1 curve
    /// @param pointB_ The second point on G1 curve
    /// @return result_ The resulting point on G1 curve after addition
    function add(G1Point memory pointA_, G1Point memory pointB_) public view returns (G1Point memory result_) {
        G1Point[] memory pointsOnG1 = new G1Point[](2);
        pointsOnG1[0] = pointA_;
        pointsOnG1[1] = pointB_;
        result_ = sumPointsOnG1(pointsOnG1);
    }

    /// @notice Sums an array of points on G2 curve
    /// @param pointsOnG2_ The array of points on G2 curve to be summed
    /// @return result_ The resulting point on G2 curve after summation
    /// @dev Uses the precompiled contract at address 0x0D for point addition
    /// @dev Usually used for aggregating public keys or signatures on G2 curve
    function sumPointsOnG2(G2Point[] memory pointsOnG2_) public view returns (G2Point memory result_) {
        if (pointsOnG2_.length == 0) {
            revert EmptyPointsToSum();
        } else {
            result_ = pointsOnG2_[0];
            uint256[16] memory input;
            for (uint256 i = 1; i < pointsOnG2_.length; ++i) {
                input[0] = result_.X0.upper;
                input[1] = result_.X0.lower;
                input[2] = result_.X1.upper;
                input[3] = result_.X1.lower;
                input[4] = result_.Y0.upper;
                input[5] = result_.Y0.lower;
                input[6] = result_.Y1.upper;
                input[7] = result_.Y1.lower;
                input[8] = pointsOnG2_[i].X0.upper;
                input[9] = pointsOnG2_[i].X0.lower;
                input[10] = pointsOnG2_[i].X1.upper;
                input[11] = pointsOnG2_[i].X1.lower;
                input[12] = pointsOnG2_[i].Y0.upper;
                input[13] = pointsOnG2_[i].Y0.lower;
                input[14] = pointsOnG2_[i].Y1.upper;
                input[15] = pointsOnG2_[i].Y1.lower;

                bool success;
                uint256[8] memory output;

                // solium-disable-next-line security/no-inline-assembly
                assembly {
                    success := staticcall(sub(gas(), 2000), 0x0D, input, 0x0200, output, 0x0100)
                    // Use "invalid" to make gas estimation work
                    switch success
                    case 0 { invalid() }
                }

                if (!success) {
                    revert SumPointsFailed();
                }

                result_ = G2Point(
                    Unit(output[0], output[1]),
                    Unit(output[2], output[3]),
                    Unit(output[4], output[5]),
                    Unit(output[6], output[7])
                );
            }
        }
    }

    /// @notice Adds two points on G2 curve
    /// @param pointA_ The first point on G2 curve
    /// @param pointB_ The second point on G2 curve
    /// @return result_ The resulting point on G2 curve after addition
    function add(G2Point memory pointA_, G2Point memory pointB_) public view returns (G2Point memory result_) {
        G2Point[] memory pointsOnG2 = new G2Point[](2);
        pointsOnG2[0] = pointA_;
        pointsOnG2[1] = pointB_;
        result_ = sumPointsOnG2(pointsOnG2);
    }

    /// @notice Hashes a byte array to a point on G1 curve
    /// @param domain_ The domain separation tag
    /// @param hash_ The byte array to be hashed
    /// @return pointOnG1_ The resulting point on G1 curve
    /// @dev Uses the precompiled contract at address 0x10 for hashing to G1
    /// @dev Usually used for signing messages on G1 curve
    function hashToG1(string memory domain_, bytes memory hash_) public view returns (G1Point memory pointOnG1_) {
        bytes[] memory fp = BLSHelper.hashToFp(hash_, domain_, 2);

        if (fp.length != 2 || fp[0].length != 64 || fp[1].length != 64) {
            revert HashToFpFailed();
        }

        G1Point[] memory pointsOnG1 = new G1Point[](2);

        for (uint256 i = 0; i < 2; i++) {
            bool success;
            bytes memory input = fp[i];
            uint256[4] memory output;

            // solium-disable-next-line security/no-inline-assembly
            assembly {
                success := staticcall(sub(gas(), 2000), 0x10, add(input, 0x20), 0x40, output, 0x80)
                // Use "invalid" to make gas estimation work
                switch success
                case 0 { invalid() }
            }

            if (!success) {
                revert HashToFpFailed();
            }

            pointsOnG1[i] = G1Point(Unit(output[0], output[1]), Unit(output[2], output[3]));
        }

        pointOnG1_ = sumPointsOnG1(pointsOnG1);
    }

    /// @notice Hashes a byte array to a point on G2 curve
    /// @param domain_ The domain separation tag
    /// @param hash_ The byte array to be hashed
    /// @return pointOnG2_ The resulting point on G2 curve
    /// @dev Uses the precompiled contract at address 0x11 for hashing to G2
    /// @dev Usually used for signing messages on G2 curve
    function hashToG2(string memory domain_, bytes memory hash_) public view returns (G2Point memory pointOnG2_) {
        bytes[] memory fp2 = BLSHelper.hashToFp2(hash_, domain_, 2);

        if (fp2.length != 2 || fp2[0].length != 128 || fp2[1].length != 128) {
            revert HashToFp2Failed();
        }

        G2Point[] memory pointsOnG2 = new G2Point[](2);

        for (uint256 i = 0; i < 2; ++i) {
            bool success;
            bytes memory input = fp2[i];
            uint256[8] memory output;

            // solium-disable-next-line security/no-inline-assembly
            assembly {
                success := staticcall(sub(gas(), 2000), 0x11, add(input, 0x20), 0x80, output, 0x0100)
                // Use "invalid" to make gas estimation work
                switch success
                case 0 { invalid() }
            }

            if (!success) {
                revert HashToFp2Failed();
            }

            pointsOnG2[i] = G2Point(
                Unit(output[0], output[1]),
                Unit(output[2], output[3]),
                Unit(output[4], output[5]),
                Unit(output[6], output[7])
            );
        }

        pointOnG2_ = sumPointsOnG2(pointsOnG2);
    }

    /// @notice Multiplies an array of points on G1 curve by corresponding scalars
    /// @param srcPointsOnG1_ The array of points on G1 curve to be multiplied
    /// @param scalars_ The array of scalars for multiplication
    /// @return dstPointsOnG1_ The resulting array of points on G1 curve after multiplication
    /// @dev Uses the precompiled contract at address 0x0C for scalar multiplication
    /// @dev Usually used for calculating public key or signing a message on G1 curve
    function scalarsMulPointsOnG1(G1Point[] memory srcPointsOnG1_, uint256[] memory scalars_)
        public
        view
        returns (G1Point memory dstPointsOnG1_)
    {
        uint256 len = srcPointsOnG1_.length;

        if (scalars_.length != len) {
            revert ScalarsLengthNotMatchG1PointsLength();
        }

        uint256[] memory input = new uint256[](5 * len);
        for (uint256 i = 0; i < srcPointsOnG1_.length; ++i) {
            input[i * 5 + 0] = srcPointsOnG1_[i].X.upper;
            input[i * 5 + 1] = srcPointsOnG1_[i].X.lower;
            input[i * 5 + 2] = srcPointsOnG1_[i].Y.upper;
            input[i * 5 + 3] = srcPointsOnG1_[i].Y.lower;
            input[i * 5 + 4] = scalars_[i];
        }

        bool success;
        uint256[4] memory output;

        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(sub(gas(), 2000), 0x0C, add(input, 0x20), mul(len, 0xA0), output, 0x80)
            // Use "invalid" to make gas estimation work
            switch success
            case 0 { invalid() }
        }

        if (!success) {
            revert ScalarsMulPointsOnG1Failed();
        }

        dstPointsOnG1_ = G1Point(Unit(output[0], output[1]), Unit(output[2], output[3]));
    }

    /// @notice Multiplies a single point on G1 curve by a scalar
    /// @param srcPointOnG1_ The point on G1 curve to be multiplied
    /// @param scalar_ The scalar for multiplication
    /// @return dstPointOnG1_ The resulting point on G1 curve after multiplication
    function scalarMulPointOnG1(G1Point memory srcPointOnG1_, uint256 scalar_)
        public
        view
        returns (G1Point memory dstPointOnG1_)
    {
        G1Point[] memory srcPointsOnG1 = new G1Point[](1);
        uint256[] memory scalars = new uint256[](1);

        srcPointsOnG1[0] = srcPointOnG1_;
        scalars[0] = scalar_;

        dstPointOnG1_ = scalarsMulPointsOnG1(srcPointsOnG1, scalars);
    }

    /// @notice Multiplies an array of points on G2 curve by corresponding scalars
    /// @param srcPointOnG2_ The array of points on G2 curve to be multiplied
    /// @param scalar_ The array of scalars for multiplication
    /// @return dstPointOnG2_ The resulting array of points on G2 curve after multiplication
    /// @dev Uses the precompiled contract at address 0x0E for scalar multiplication
    /// @dev Usually used for calculating public key or signing a message on G2 curve
    function scalarsMulPointsOnG2(G2Point[] memory srcPointOnG2_, uint256[] memory scalar_)
        public
        view
        returns (G2Point memory dstPointOnG2_)
    {
        uint256 len = srcPointOnG2_.length;

        if (scalar_.length != len) {
            revert ScalarsLengthNotMatchG2PointsLength();
        }

        uint256[] memory input = new uint256[](9 * len);
        for (uint256 i = 0; i < len; ++i) {
            input[i * 9 + 0] = srcPointOnG2_[i].X0.upper;
            input[i * 9 + 1] = srcPointOnG2_[i].X0.lower;
            input[i * 9 + 2] = srcPointOnG2_[i].X1.upper;
            input[i * 9 + 3] = srcPointOnG2_[i].X1.lower;
            input[i * 9 + 4] = srcPointOnG2_[i].Y0.upper;
            input[i * 9 + 5] = srcPointOnG2_[i].Y0.lower;
            input[i * 9 + 6] = srcPointOnG2_[i].Y1.upper;
            input[i * 9 + 7] = srcPointOnG2_[i].Y1.lower;
            input[i * 9 + 8] = scalar_[i];
        }

        bool success;
        uint256[8] memory output;

        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(sub(gas(), 2000), 0x0E, add(input, 0x20), mul(len, 0x0120), output, 0x0100)
            // Use "invalid" to make gas estimation work
            switch success
            case 0 { invalid() }
        }

        if (!success) {
            revert ScalarsMulPointsOnG2Failed();
        }

        dstPointOnG2_ = G2Point(
            Unit(output[0], output[1]),
            Unit(output[2], output[3]),
            Unit(output[4], output[5]),
            Unit(output[6], output[7])
        );
    }

    /// @notice Multiplies a single point on G2 curve by a scalar
    /// @param srcPointOnG2_ The point on G2 curve to be multiplied
    /// @param scalar_ The scalar for multiplication
    /// @return dstPointOnG2_ The resulting point on G2 curve after multiplication
    function scalarMulPointOnG2(G2Point memory srcPointOnG2_, uint256 scalar_)
        public
        view
        returns (G2Point memory dstPointOnG2_)
    {
        G2Point[] memory srcPointsOnG2 = new G2Point[](1);
        uint256[] memory scalars = new uint256[](1);

        srcPointsOnG2[0] = srcPointOnG2_;
        scalars[0] = scalar_;

        dstPointOnG2_ = scalarsMulPointsOnG2(srcPointsOnG2, scalars);
    }

    /// @notice Performs pairing check when public key is on G1 curve
    /// @param sigOnG2_ The signature point on G2 curve
    /// @param pkOnG1_ The public key point on G1 curve
    /// @param hashToG2_ The hash point of the message on G2 curve
    /// @return pairResult_ The result of the pairing check
    /// @dev Uses the precompiled contract at address 0x0F for pairing check
    /// @dev Usually used for verifying signatures when public key is on G1 curve
    /// @dev Formula: e(generatorG1, sigOnG2) = e(pkOnG1, hashToG2)
    function pairWhenPKOnG1(G2Point memory sigOnG2_, G1Point memory pkOnG1_, G2Point memory hashToG2_)
        public
        view
        returns (bool pairResult_)
    {
        G1Point memory neg_g1 = negGeneratorG1();

        uint256[24] memory input;
        input[0] = neg_g1.X.upper;
        input[1] = neg_g1.X.lower;
        input[2] = neg_g1.Y.upper;
        input[3] = neg_g1.Y.lower;
        input[4] = sigOnG2_.X0.upper;
        input[5] = sigOnG2_.X0.lower;
        input[6] = sigOnG2_.X1.upper;
        input[7] = sigOnG2_.X1.lower;
        input[8] = sigOnG2_.Y0.upper;
        input[9] = sigOnG2_.Y0.lower;
        input[10] = sigOnG2_.Y1.upper;
        input[11] = sigOnG2_.Y1.lower;
        input[12] = pkOnG1_.X.upper;
        input[13] = pkOnG1_.X.lower;
        input[14] = pkOnG1_.Y.upper;
        input[15] = pkOnG1_.Y.lower;
        input[16] = hashToG2_.X0.upper;
        input[17] = hashToG2_.X0.lower;
        input[18] = hashToG2_.X1.upper;
        input[19] = hashToG2_.X1.lower;
        input[20] = hashToG2_.Y0.upper;
        input[21] = hashToG2_.Y0.lower;
        input[22] = hashToG2_.Y1.upper;
        input[23] = hashToG2_.Y1.lower;

        bool success;
        uint256[1] memory output;

        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(sub(gas(), 2000), 0x0F, input, 0x0300, output, 0x20)
            // Use "invalid" to make gas estimation work
            switch success
            case 0 { invalid() }
        }

        if (!success) {
            revert PairWhenPKOnG2Failed();
        }

        pairResult_ = (output[0] == 1);
    }

    /// @notice Performs pairing check when public key is on G2 curve
    /// @param sigOnG1_ The signature point on G1 curve
    /// @param pkOnG2_ The public key point on G2 curve
    /// @param hashToG1_ The hash point of the message on G1 curve
    /// @return pairResult_ The result of the pairing check
    /// @dev Uses the precompiled contract at address 0x0F for pairing check
    /// @dev Usually used for verifying signatures when public key is on G2 curve
    /// @dev Formula: e(sigOnG1, generatorG2) = e(hashToG1, pkOnG2)
    function pairWhenPKOnG2(G1Point memory sigOnG1_, G2Point memory pkOnG2_, G1Point memory hashToG1_)
        public
        view
        returns (bool pairResult_)
    {
        G2Point memory neg_g2 = negGeneratorG2();

        uint256[24] memory input;
        input[0] = sigOnG1_.X.upper;
        input[1] = sigOnG1_.X.lower;
        input[2] = sigOnG1_.Y.upper;
        input[3] = sigOnG1_.Y.lower;
        input[4] = neg_g2.X0.upper;
        input[5] = neg_g2.X0.lower;
        input[6] = neg_g2.X1.upper;
        input[7] = neg_g2.X1.lower;
        input[8] = neg_g2.Y0.upper;
        input[9] = neg_g2.Y0.lower;
        input[10] = neg_g2.Y1.upper;
        input[11] = neg_g2.Y1.lower;
        input[12] = hashToG1_.X.upper;
        input[13] = hashToG1_.X.lower;
        input[14] = hashToG1_.Y.upper;
        input[15] = hashToG1_.Y.lower;
        input[16] = pkOnG2_.X0.upper;
        input[17] = pkOnG2_.X0.lower;
        input[18] = pkOnG2_.X1.upper;
        input[19] = pkOnG2_.X1.lower;
        input[20] = pkOnG2_.Y0.upper;
        input[21] = pkOnG2_.Y0.lower;
        input[22] = pkOnG2_.Y1.upper;
        input[23] = pkOnG2_.Y1.lower;

        bool success;
        uint256[1] memory output;

        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(sub(gas(), 2000), 0x0F, input, 0x0300, output, 0x20)
            // Use "invalid" to make gas estimation work
            switch success
            case 0 { invalid() }
        }

        if (!success) {
            revert PairWhenPKOnG2Failed();
        }

        pairResult_ = (output[0] == 1);
    }

    /// @notice Performs general pairing check for multiple pairs of points
    /// @param g1Points_ The array of points on G1 curve
    /// @param g2Points_ The array of points on G2 curve
    /// @return pairResult_ The result of the general pairing check
    /// @dev Uses the precompiled contract at address 0x0F for pairing check
    /// @dev Usually used for m-n threshold pairing checks
    function generalPairing(G1Point[] memory g1Points_, G2Point[] memory g2Points_)
        public
        view
        returns (bool pairResult_)
    {
        uint256 len = g1Points_.length;

        if (g2Points_.length != len) {
            revert G1PointsShouldMatchG2PointsWhenGeneralPairing();
        }

        uint256[] memory input = new uint256[](12 * len);
        for (uint256 i = 0; i < len; ++i) {
            input[i * 12 + 0] = g1Points_[i].X.upper;
            input[i * 12 + 1] = g1Points_[i].X.lower;
            input[i * 12 + 2] = g1Points_[i].Y.upper;
            input[i * 12 + 3] = g1Points_[i].Y.lower;
            input[i * 12 + 4] = g2Points_[i].X0.upper;
            input[i * 12 + 5] = g2Points_[i].X0.lower;
            input[i * 12 + 6] = g2Points_[i].X1.upper;
            input[i * 12 + 7] = g2Points_[i].X1.lower;
            input[i * 12 + 8] = g2Points_[i].Y0.upper;
            input[i * 12 + 9] = g2Points_[i].Y0.lower;
            input[i * 12 + 10] = g2Points_[i].Y1.upper;
            input[i * 12 + 11] = g2Points_[i].Y1.lower;
        }

        bool success;
        uint256[1] memory output;

        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(sub(gas(), 2000), 0x0F, add(input, 0x20), mul(len, 0x0180), output, 0x20)
            // Use "invalid" to make gas estimation work
            switch success
            case 0 { invalid() }
        }

        if (!success) {
            revert PairWhenPKOnG2Failed();
        }

        pairResult_ = (output[0] == 1);
    }
}
