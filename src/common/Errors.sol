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

    /// @dev Reverted when allowance is not enough for a transfer.
    /// @param allowance The current allowance.
    /// @param required The required allowance for the transfer.
    error InsufficientAllowance(uint256 allowance, uint256 required);

    /// @dev Reverted when owner does not approve the spender for a token.
    /// @param owner The owner of the token.
    /// @param spender The address trying to spend the token.
    /// @param tokenId The ID of the token being spent.
    error NotApproved(address owner, address spender, uint256 tokenId);
}
