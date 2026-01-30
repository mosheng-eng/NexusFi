// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {Errors} from "src/common/Errors.sol";
import {TimePowerLoanDefs} from "src/protocols/borrower/time-power/utils/TimePowerLoanDefs.sol";

library TimePowerLoanLibs {
    using Math for uint256;

    function updateDebtInterestRate(
        TimePowerLoanDefs.DebtInfo[] storage allDebts_,
        uint64 debtIndex_,
        TimePowerLoanDefs.TrancheInfo[] storage allTranches_,
        mapping(uint64 => uint64[]) storage tranchesInfoGroupedByDebt_,
        uint256 oldAccumulatedInterestRate_,
        uint256 newAccumulatedInterestRate_
    ) public returns (uint128 newDebtNormalizedPrincipal_) {
        TimePowerLoanDefs.DebtInfo memory debtInfo = allDebts_[debtIndex_];
        if (
            debtInfo.status == TimePowerLoanDefs.DebtStatus.ACTIVE
                || debtInfo.status == TimePowerLoanDefs.DebtStatus.DEFAULTED
        ) {
            uint64[] memory tranchesIndex = tranchesInfoGroupedByDebt_[debtIndex_];
            for (uint256 j = 0; j < tranchesIndex.length; j++) {
                newDebtNormalizedPrincipal_ += updateTrancheInterestRate(
                    allTranches_, tranchesIndex[j], oldAccumulatedInterestRate_, newAccumulatedInterestRate_
                );
            }
            allDebts_[debtIndex_].normalizedPrincipal = newDebtNormalizedPrincipal_;
        }
    }

    function updateTrancheInterestRate(
        TimePowerLoanDefs.TrancheInfo[] storage allTranches_,
        uint64 trancheIndex_,
        uint256 oldAccumulatedInterestRate_,
        uint256 newAccumulatedInterestRate_
    ) public returns (uint128 newTrancheNormalizedPrincipal_) {
        newTrancheNormalizedPrincipal_ = uint128(
            uint256(allTranches_[trancheIndex_].normalizedPrincipal).mulDiv(
                oldAccumulatedInterestRate_, newAccumulatedInterestRate_, Math.Rounding.Ceil
            )
        );
        allTranches_[trancheIndex_].normalizedPrincipal = newTrancheNormalizedPrincipal_;
    }

    function updateLoanLimit(
        TimePowerLoanDefs.LoanInfo[] storage allLoans_,
        uint64 loanIndex_,
        uint128 newCeilingLimit_,
        TimePowerLoanDefs.TrustedBorrower[] storage trustedBorrowers_
    ) public {
        uint128 remainingLimit = allLoans_[loanIndex_].remainingLimit;
        uint128 ceilingLimit = allLoans_[loanIndex_].ceilingLimit;

        if (ceilingLimit < remainingLimit) {
            revert TimePowerLoanDefs.CeilingLimitBelowRemainingLimit(ceilingLimit, remainingLimit);
        }

        uint128 usedLimit = ceilingLimit - remainingLimit;

        if (newCeilingLimit_ < usedLimit) {
            revert TimePowerLoanDefs.CeilingLimitBelowUsedLimit(newCeilingLimit_, usedLimit);
        }

        if (newCeilingLimit_ > ceilingLimit) {
            uint128 increasedLimit = newCeilingLimit_ - ceilingLimit;
            uint128 borrowerRemainingLimit = trustedBorrowers_[allLoans_[loanIndex_].borrowerIndex].remainingLimit;
            if (borrowerRemainingLimit < increasedLimit) {
                revert TimePowerLoanDefs.LoanCeilingLimitExceedsBorrowerRemainingLimit(
                    newCeilingLimit_, borrowerRemainingLimit
                );
            }
            trustedBorrowers_[allLoans_[loanIndex_].borrowerIndex].remainingLimit =
                borrowerRemainingLimit - increasedLimit;
        }

        allLoans_[loanIndex_].ceilingLimit = newCeilingLimit_;
        allLoans_[loanIndex_].remainingLimit = newCeilingLimit_ - usedLimit;

        emit TimePowerLoanDefs.LoanCeilingLimitUpdated(newCeilingLimit_, ceilingLimit);
    }

    function updateTrustedVaults(
        TimePowerLoanDefs.TrustedVault[] storage trustedVaults_,
        TimePowerLoanDefs.TrustedVault memory newTrustedVault_,
        uint256 vaultIndex_,
        address loanToken_
    ) public returns (bool isUpdated_) {
        if (newTrustedVault_.vault == address(0)) {
            revert Errors.ZeroAddress("trusted vault address");
        }
        if (IERC4626(newTrustedVault_.vault).asset() != loanToken_) {
            revert Errors.InvalidValue("trusted vault asset and loan token mismatch");
        }
        if (newTrustedVault_.minimumPercentage > newTrustedVault_.maximumPercentage) {
            revert Errors.InvalidValue("trusted vault percentage");
        }
        if (newTrustedVault_.maximumPercentage > TimePowerLoanDefs.PRECISION) {
            revert Errors.InvalidValue("trusted vault maximum percentage exceeds 100%");
        }
        if (vaultIndex_ >= trustedVaults_.length) {
            trustedVaults_.push(newTrustedVault_);
            emit TimePowerLoanDefs.TrustedVaultAdded(
                newTrustedVault_.vault,
                newTrustedVault_.minimumPercentage,
                newTrustedVault_.maximumPercentage,
                trustedVaults_.length - 1
            );
            isUpdated_ = false;
            vaultIndex_ = trustedVaults_.length - 1;
        } else {
            TimePowerLoanDefs.TrustedVault memory oldVault = trustedVaults_[vaultIndex_];
            trustedVaults_[vaultIndex_] = newTrustedVault_;

            emit TimePowerLoanDefs.TrustedVaultUpdated(
                oldVault.vault,
                oldVault.minimumPercentage,
                oldVault.maximumPercentage,
                newTrustedVault_.vault,
                newTrustedVault_.minimumPercentage,
                newTrustedVault_.maximumPercentage,
                vaultIndex_
            );

            isUpdated_ = true;
        }
    }
}
