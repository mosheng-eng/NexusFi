// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

/// @title Errors
/// @author Mr.Silent
/// @notice Library defining common error types for the NexusFi protocol.
library Errors {
    /// @dev Reverted when an address is zero.
    /// @param name The name of the address variable that is zero.
    error ZeroAddress(string name);
    /// @dev Reverted when a value is invalid.
    /// @param name The name of the value variable that is invalid.
    error InvalidValue(string name);
    /// @dev Reverted when contract is not fully initialized.
    /// @param name The field name of the contract that is uninitialized.
    error Uninitialized(string name);
    /// @dev Reverted when balance is not enough for a transfer.
    /// @param balance The current balance.
    /// @param transfer The amount to be transferred.
    error InsufficientBalance(uint256 balance, uint256 transfer);
}
