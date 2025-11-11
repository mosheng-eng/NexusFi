// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/// @title OpenTermToken
/// @author Mr.Silent
/// @notice ERC20 token representing open-term deposits.
/// @notice This contract is designed to be inherited by OpenTermStaking.
abstract contract OpenTermToken is ERC20Upgradeable {
    /// @notice Event emitted when tokens are minted
    event Mint(address indexed to, uint256 amount);
    /// @notice Event emitted when tokens are burned
    event Burn(address indexed from, uint256 amount);

    constructor() {
        _disableInitializers();
    }

    function __OpenTermToken_init(string memory name_, string memory symbol_) internal onlyInitializing {
        __ERC20_init(name_, symbol_);
    }

    function mint(address to_, uint256 amount_) internal {
        _mint(to_, amount_);

        emit Mint(to_, amount_);
    }

    function burn(address from_, uint256 amount_) internal {
        _burn(from_, amount_);

        emit Burn(from_, amount_);
    }

    function sharesOf(address account) public view returns (uint256) {
        return super.balanceOf(account);
    }

    /// @notice Must be overridden by the inheriting contract
    function balanceOf(address /* account */ ) public view virtual override(ERC20Upgradeable) returns (uint256) {
        revert("Must override!");
    }

    function decimals() public pure override(ERC20Upgradeable) returns (uint8) {
        return 6;
    }
}
