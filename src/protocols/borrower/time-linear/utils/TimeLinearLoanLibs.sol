// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {Errors} from "src/common/Errors.sol";
import {TimeLinearLoanDefs} from "src/protocols/borrower/time-linear/utils/TimeLinearLoanDefs.sol";

library TimeLinearLoanLibs {
    using Math for uint256;

    function updateBorrowerLimit(
        TimeLinearLoanDefs.TrustedBorrower[] storage trustedBorrowers_,
        mapping(address => uint64) storage borrowerToIndex_,
        address borrower_,
        uint128 newCeilingLimit_
    ) public {
        TimeLinearLoanDefs.TrustedBorrower memory trustedBorrower = trustedBorrowers_[borrowerToIndex_[borrower_]];
        uint128 remainingLimit = trustedBorrower.remainingLimit;
        uint128 ceilingLimit = trustedBorrower.ceilingLimit;

        if (ceilingLimit < remainingLimit) {
            revert TimeLinearLoanDefs.CeilingLimitBelowRemainingLimit(ceilingLimit, remainingLimit);
        }

        uint128 usedLimit = ceilingLimit - remainingLimit;

        if (newCeilingLimit_ < usedLimit) {
            revert TimeLinearLoanDefs.CeilingLimitBelowUsedLimit(newCeilingLimit_, usedLimit);
        }

        trustedBorrowers_[borrowerToIndex_[borrower_]].ceilingLimit = newCeilingLimit_;
        trustedBorrowers_[borrowerToIndex_[borrower_]].remainingLimit = newCeilingLimit_ - usedLimit;

        emit TimeLinearLoanDefs.BorrowerCeilingLimitUpdated(ceilingLimit, newCeilingLimit_);
    }

    function updateLoanInterestRate(
        TimeLinearLoanDefs.LoanInfo[] storage allLoans_,
        uint64 loanIndex_,
        uint64 newInterestRateIndex_,
        TimeLinearLoanDefs.DebtInfo[] storage allDebts_,
        uint256[] storage secondInterestRates_,
        mapping(uint64 => uint64[]) storage debtsInfoGroupedByLoan_,
        bool dryrun_
    ) public returns (uint128 remainingDebt_) {
        TimeLinearLoanDefs.LoanInfo memory loanInfo = allLoans_[loanIndex_];
        uint64[] memory debtsIndex = debtsInfoGroupedByLoan_[loanIndex_];
        for (uint256 i = 0; i < debtsIndex.length; i++) {
            remainingDebt_ += updateDebt(allDebts_, debtsIndex[i], allLoans_, secondInterestRates_, dryrun_);
        }

        if (!dryrun_) {
            allLoans_[loanIndex_].interestRateIndex = newInterestRateIndex_;
            emit TimeLinearLoanDefs.LoanInterestRateUpdated(
                loanIndex_, loanInfo.interestRateIndex, newInterestRateIndex_
            );
        }
    }

    function updateDebt(
        TimeLinearLoanDefs.DebtInfo[] storage allDebts_,
        uint64 debtIndex_,
        TimeLinearLoanDefs.LoanInfo[] storage allLoans_,
        uint256[] storage secondInterestRates_,
        bool dryrun_
    ) public returns (uint128 remainingDebt_) {
        TimeLinearLoanDefs.DebtInfo memory debtInfo = allDebts_[debtIndex_];
        TimeLinearLoanDefs.LoanInfo memory loanInfo = allLoans_[debtInfo.loanIndex];
        if (
            (
                debtInfo.status == TimeLinearLoanDefs.DebtStatus.ACTIVE
                    || debtInfo.status == TimeLinearLoanDefs.DebtStatus.DEFAULTED
            ) && debtInfo.lastUpdateTime < block.timestamp
        ) {
            uint128 interestIncrement = uint128(
                uint256(debtInfo.interestBearingAmount * (block.timestamp - debtInfo.lastUpdateTime)).mulDiv(
                    secondInterestRates_[loanInfo.interestRateIndex], TimeLinearLoanDefs.FIXED18, Math.Rounding.Ceil
                )
            );

            debtInfo.netRemainingDebt += interestIncrement;
            debtInfo.netRemainingInterest += interestIncrement;
            debtInfo.lastUpdateTime = uint64(block.timestamp);

            if (!dryrun_) {
                allDebts_[debtIndex_] = debtInfo;
            }
        }
        remainingDebt_ = debtInfo.netRemainingDebt;
    }

    function updateLoanLimit(
        TimeLinearLoanDefs.LoanInfo[] storage allLoans_,
        uint64 loanIndex_,
        uint128 newCeilingLimit,
        TimeLinearLoanDefs.TrustedBorrower[] storage trustedBorrowers_
    ) public {
        uint128 remainingLimit = allLoans_[loanIndex_].remainingLimit;
        uint128 ceilingLimit = allLoans_[loanIndex_].ceilingLimit;

        if (ceilingLimit < remainingLimit) {
            revert TimeLinearLoanDefs.CeilingLimitBelowRemainingLimit(ceilingLimit, remainingLimit);
        }

        uint128 usedLimit = ceilingLimit - remainingLimit;

        if (newCeilingLimit < usedLimit) {
            revert TimeLinearLoanDefs.CeilingLimitBelowUsedLimit(newCeilingLimit, usedLimit);
        }

        if (newCeilingLimit > ceilingLimit) {
            uint128 increasedLimit = newCeilingLimit - ceilingLimit;
            uint128 borrowerRemainingLimit = trustedBorrowers_[allLoans_[loanIndex_].borrowerIndex].remainingLimit;
            if (borrowerRemainingLimit < increasedLimit) {
                revert TimeLinearLoanDefs.LoanCeilingLimitExceedsBorrowerRemainingLimit(
                    newCeilingLimit, borrowerRemainingLimit
                );
            }
            trustedBorrowers_[allLoans_[loanIndex_].borrowerIndex].remainingLimit =
                borrowerRemainingLimit - increasedLimit;
        }

        allLoans_[loanIndex_].ceilingLimit = newCeilingLimit;
        allLoans_[loanIndex_].remainingLimit = newCeilingLimit - usedLimit;

        emit TimeLinearLoanDefs.LoanCeilingLimitUpdated(newCeilingLimit, ceilingLimit);
    }

    function updateTrustedVaults(
        TimeLinearLoanDefs.TrustedVault[] storage trustedVaults_,
        TimeLinearLoanDefs.TrustedVault memory newTrustedVault_,
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
        if (newTrustedVault_.maximumPercentage > TimeLinearLoanDefs.PRECISION) {
            revert Errors.InvalidValue("trusted vault maximum percentage exceeds 100%");
        }
        if (vaultIndex_ >= trustedVaults_.length) {
            trustedVaults_.push(newTrustedVault_);
            vaultIndex_ = trustedVaults_.length - 1;
            emit TimeLinearLoanDefs.TrustedVaultAdded(
                newTrustedVault_.vault,
                newTrustedVault_.minimumPercentage,
                newTrustedVault_.maximumPercentage,
                vaultIndex_
            );
            isUpdated_ = false;
        } else {
            TimeLinearLoanDefs.TrustedVault memory oldVault = trustedVaults_[vaultIndex_];
            trustedVaults_[vaultIndex_] = newTrustedVault_;

            emit TimeLinearLoanDefs.TrustedVaultUpdated(
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
