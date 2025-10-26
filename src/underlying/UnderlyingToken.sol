// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";

import {Roles} from "src/common/Roles.sol";
import {Errors} from "src/common/Errors.sol";

contract UnderlyingToken is Initializable, EIP712Upgradeable, AccessControlUpgradeable, ERC20BurnableUpgradeable {
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract, this function can only be called once.
    /// @param owner_ The address to be granted the owner role.
    /// @param name_ The name of the token.
    /// @param symbol_ The symbol of the token.
    function initialize(address owner_, string calldata name_, string calldata symbol_) external initializer {
        if (owner_ == address(0)) {
            revert Errors.ZeroAddress("owner");
        }

        __ERC20_init_unchained(name_, symbol_);
        __ERC20Burnable_init_unchained();
        __AccessControl_init_unchained();

        _grantRole(Roles.OWNER_ROLE, owner_);
        _setRoleAdmin(Roles.OPERATOR_ROLE, Roles.OWNER_ROLE);
    }

    /// @dev Mint new tokens to a specified address.
    /// @param to_ The address to receive the newly minted tokens.
    /// @param amount_ The amount of tokens to be minted.
    /// @notice This function can only be called by an account with the operator role.
    function mint(address to_, uint256 amount_) external onlyRole(Roles.OPERATOR_ROLE) {
        _mint(to_, amount_);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function contractName() external pure returns (string memory) {
        return "UnderlyingToken";
    }

    uint256[10] private __gap;
}
