// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

interface IVaultBorrower {
    function totalDebtOfVault(address vault_) external view returns (uint256 totalDebt_);
}
