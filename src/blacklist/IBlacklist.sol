// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IBlacklist
/// @author Mr.Silent
/// @notice Interface for a blacklist contract to manage access control.
/// @notice Allows adding, removing, enabling, and disabling blacklist functionality.
interface IBlacklist {
    /// @dev Emitted when addr is added to the blacklist.
    event BlacklistAdded(address indexed addr);

    /// @dev Emitted when addr is removed from the blacklist.
    event BlacklistRemoved(address indexed addr);

    /// @dev Emitted when the blacklist is disabled.
    event BlacklistDisabled();

    /// @dev Emitted when the blacklist is enabled.
    event BlacklistEnabled();

    /// @dev Reverted when addr is in the blacklist.
    error Blacklisted(address addr);

    /// @dev Initialize the blacklist contract.
    /// @param owner_ The owner of the blacklist contract.
    /// @param blacklistEnabled_ True if the blacklist is enabled, false otherwise.
    function initialize(address owner_, bool blacklistEnabled_) external;

    /// @dev Add an address to the blacklist.
    /// @param addr_ The address to be added to the blacklist.
    function add(address addr_) external;

    /// @dev Remove an address from the blacklist.
    /// @param addr_ The address to be removed from the blacklist.
    function remove(address addr_) external;

    /// @dev Enable the blacklist.
    function enable() external;

    /// @notice Disable the blacklist.
    function disable() external;

    /// @dev Check if an address is in the blacklist.
    /// @param addr_ The address to be checked.
    /// @return True if the address is in the blacklist, false otherwise.
    function isBlacklisted(address addr_) external view returns (bool);

    /// @dev Check if the blacklist is enabled.
    /// @return True if the blacklist is enabled, false otherwise.
    function blacklistEnabled() external view returns (bool);
}
