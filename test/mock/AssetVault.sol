// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AssetVault is ERC20, ERC4626 {
    constructor(IERC20 underlyingAsset_, string memory name_, string memory symbol_)
        ERC4626(underlyingAsset_)
        ERC20(name_, symbol_)
    {}

    function decimals() public view virtual override(ERC4626, ERC20) returns (uint8) {
        return ERC4626.decimals();
    }
}
