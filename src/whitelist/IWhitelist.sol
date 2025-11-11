// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IWhitelist
/// @author Mr.Silent
/// @notice Interface for a whitelist contract to manage access control.
/// @notice Allows adding, removing, enabling, and disabling whitelist functionality.
interface IWhitelist {
    /// @dev Emitted when addr is added to the whitelist.
    event WhitelistAdded(address indexed addr);

    /// @dev Emitted when addr is removed from the whitelist.
    event WhitelistRemoved(address indexed addr);

    /// @dev Emitted when the whitelist is disabled.
    event WhitelistDisabled();

    /// @dev Emitted when the whitelist is enabled.
    event WhitelistEnabled();

    /// @dev Reverted when addr is not in the whitelist.
    error NotWhitelisted(address addr);

    /// @dev Initialize the whitelist contract.
    /// @param owner_ The owner of the whitelist contract.
    /// @param whitelistEnabled_ True if the whitelist is enabled, false otherwise.
    function initialize(address owner_, bool whitelistEnabled_) external;

    /// @dev Add an address to the whitelist.
    /// @param addr_ The address to be added to the whitelist.
    function add(address addr_) external;

    /// @dev Remove an address from the whitelist.
    /// @param addr_ The address to be removed from the whitelist.
    function remove(address addr_) external;

    /// @dev Enable the whitelist.
    function enable() external;

    /// @notice Disable the whitelist.
    function disable() external;

    /// @dev Check if an address is in the whitelist.
    /// @param addr_ The address to be checked.
    /// @return True if the address is in the whitelist, false otherwise.
    function isWhitelisted(address addr_) external view returns (bool);

    /// @dev Check if the whitelist is enabled.
    /// @return True if the whitelist is enabled, false otherwise.
    function whitelistEnabled() external view returns (bool);
}
