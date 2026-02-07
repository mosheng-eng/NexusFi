// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

/// @title Roles
/// @author Mr.Silent
/// @notice Library defining role constants for access control.
library Roles {
    /// @dev 0xb19546dff01e856fb3f010c267a7b1c60363cf8a4664e21cc89c26224620214e
    bytes32 public constant OWNER_ROLE = keccak256(abi.encodePacked("OWNER_ROLE"));
    /// @dev 0x97667070c54ef182b0f5858b034beac1b6f3089aa2d3188bb1e8929f4fa9b929
    bytes32 public constant OPERATOR_ROLE = keccak256(abi.encodePacked("OPERATOR_ROLE"));
    /// @dev 0x189ab7a9244df0848122154315af71fe140f3db0fe014031783b0946b8c9d2e3
    bytes32 public constant UPGRADER_ROLE = keccak256(abi.encodePacked("UPGRADER_ROLE"));
    /// @dev 0xbaa42688efd68ad7551eb3356f98d93887878ab0c9b9212d12cee7725992818d
    bytes32 public constant INVESTMENT_MANAGER_ROLE = keccak256(abi.encodePacked("INVESTMENT_MANAGER_ROLE"));
}
