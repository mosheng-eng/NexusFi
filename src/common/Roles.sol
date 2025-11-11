// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

/// @title Roles
/// @author Mr.Silent
/// @notice Library defining role constants for access control.
library Roles {
    bytes32 public constant OWNER_ROLE = keccak256(abi.encodePacked("OWNER_ROLE"));
    bytes32 public constant OPERATOR_ROLE = keccak256(abi.encodePacked("OPERATOR_ROLE"));
    bytes32 public constant UPGRADER_ROLE = keccak256(abi.encodePacked("UPGRADER_ROLE"));
    bytes32 public constant INVESTMENT_MANAGER_ROLE = keccak256(abi.encodePacked("INVESTMENT_MANAGER_ROLE"));
}
