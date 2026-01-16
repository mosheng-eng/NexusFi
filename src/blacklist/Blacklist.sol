// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {IBlacklist} from "src/blacklist/IBlacklist.sol";
import {Errors} from "src/common/Errors.sol";
import {Roles} from "src/common/Roles.sol";

/// @title Blacklist
/// @author Mr.Silent
/// @notice Contract implementing a blacklist mechanism for access control.
/// @notice Allows adding, removing, enabling, and disabling blacklist functionality.
contract Blacklist is Initializable, AccessControlUpgradeable, IBlacklist {
    /// @notice special address address(uint160(uint256(keccak256(abi.encodePacked("Blacklist Enabled")&&bytes1(0xff)))) is used to indicate whether the blacklist is enabled or not
    address private constant BLACK_LIST_ENABLED_FLAG =
        address(uint160(uint256(keccak256(abi.encodePacked("Blacklist Enabled")) & ~bytes32(uint256(0xff)))));

    /// @dev true if address in the blacklist, false otherwise
    mapping(address => bool) internal blacklist;

    modifier onlyNotBlacklisted(address addr) {
        if (blacklist[BLACK_LIST_ENABLED_FLAG] && blacklist[addr]) {
            revert Blacklisted(addr);
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address owner_, bool blacklistEnabled_) external initializer {
        if (owner_ == address(0x0)) {
            revert Errors.ZeroAddress("owner");
        }

        __AccessControl_init();

        _grantRole(Roles.OWNER_ROLE, owner_);
        _setRoleAdmin(Roles.OPERATOR_ROLE, Roles.OWNER_ROLE);

        blacklist[BLACK_LIST_ENABLED_FLAG] = blacklistEnabled_;
    }

    function add(address addr_) external onlyRole(Roles.OPERATOR_ROLE) {
        if (addr_ == address(0x0)) {
            revert Errors.ZeroAddress("addr");
        }
        blacklist[addr_] = true;
        emit BlacklistAdded(addr_);
    }

    function remove(address addr_) external onlyRole(Roles.OPERATOR_ROLE) {
        if (addr_ == address(0x0)) {
            revert Errors.ZeroAddress("addr");
        }
        blacklist[addr_] = false;
        emit BlacklistRemoved(addr_);
    }

    function enable() external onlyRole(Roles.OWNER_ROLE) {
        blacklist[BLACK_LIST_ENABLED_FLAG] = true;
        emit BlacklistEnabled();
    }

    function disable() external onlyRole(Roles.OWNER_ROLE) {
        blacklist[BLACK_LIST_ENABLED_FLAG] = false;
        emit BlacklistDisabled();
    }

    function isBlacklisted(address addr_) external view returns (bool) {
        return blacklist[addr_];
    }

    function blacklistEnabled() external view returns (bool) {
        return blacklist[BLACK_LIST_ENABLED_FLAG];
    }
}
