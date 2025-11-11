// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {IWhitelist} from "src/whitelist/IWhitelist.sol";
import {Errors} from "src/common/Errors.sol";
import {Roles} from "src/common/Roles.sol";

/// @title Whitelist
/// @author Mr.Silent
/// @notice Contract implementing a whitelist mechanism for access control.
/// @notice Allows adding, removing, enabling, and disabling whitelist functionality.
contract Whitelist is Initializable, AccessControlUpgradeable, IWhitelist {
    /// @notice special address address(uint160(uint256(keccak256(abi.encodePacked("Whitelist Enabled")&&bytes1(0xff)))) is used to indicate whether the whitelist is enabled or not
    address private constant WHITE_LIST_ENABLED_FLAG =
        address(uint160(uint256(keccak256(abi.encodePacked("Whitelist Enabled")) & ~bytes32(uint256(0xff)))));

    /// @dev true if address in the whitelist, false otherwise
    mapping(address => bool) internal whitelist;

    modifier onlyWhitelisted(address addr) {
        if (whitelist[WHITE_LIST_ENABLED_FLAG] && !whitelist[addr]) {
            revert NotWhitelisted(addr);
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address owner_, bool whitelistEnabled_) external initializer {
        if (owner_ == address(0x0)) {
            revert Errors.ZeroAddress("owner");
        }

        __AccessControl_init();

        _grantRole(Roles.OWNER_ROLE, owner_);
        _setRoleAdmin(Roles.OPERATOR_ROLE, Roles.OWNER_ROLE);

        whitelist[WHITE_LIST_ENABLED_FLAG] = whitelistEnabled_;
    }

    function add(address addr_) external onlyRole(Roles.OPERATOR_ROLE) {
        if (addr_ == address(0x0)) {
            revert Errors.ZeroAddress("addr");
        }
        whitelist[addr_] = true;
        emit WhitelistAdded(addr_);
    }

    function remove(address addr_) external onlyRole(Roles.OPERATOR_ROLE) {
        if (addr_ == address(0x0)) {
            revert Errors.ZeroAddress("addr");
        }
        whitelist[addr_] = false;
        emit WhitelistRemoved(addr_);
    }

    function enable() external onlyRole(Roles.OWNER_ROLE) {
        whitelist[WHITE_LIST_ENABLED_FLAG] = true;
        emit WhitelistEnabled();
    }

    function disable() external onlyRole(Roles.OWNER_ROLE) {
        whitelist[WHITE_LIST_ENABLED_FLAG] = false;
        emit WhitelistDisabled();
    }

    function isWhitelisted(address addr_) external view returns (bool) {
        return whitelist[addr_];
    }

    function whitelistEnabled() external view returns (bool) {
        return whitelist[WHITE_LIST_ENABLED_FLAG];
    }
}
