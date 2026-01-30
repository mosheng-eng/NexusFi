// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Errors} from "src/common/Errors.sol";
import {TimePowerLoanDefs} from "src/protocols/borrower/time-power/utils/TimePowerLoanDefs.sol";

library TimePowerLoanCore {
    using Math for uint256;
    using SafeERC20 for IERC20;

    function initialize(
        TimePowerLoanDefs.TrustedVault[] storage trustedVaults_,
        mapping(address => uint64) storage vaultToIndex_,
        uint256[] storage secondInterestRates_,
        uint256[] storage accumulatedInterestRates_,
        /**
         * 0: address owner_,
         * 1: address whitelist_,
         * 2: address blacklist_,
         * 3: address loanToken_,
         */
        address[4] memory addrs_,
        /**
         * annual interest rates sorted in ascending order
         */
        uint64[] memory newSecondInterestRates_,
        /**
         * vaults that are allowed to lend to borrowers
         */
        TimePowerLoanDefs.TrustedVault[] memory newTrustedVaults_
    ) public {
        if (addrs_[0] == address(0)) {
            revert Errors.ZeroAddress("owner");
        }
        if (addrs_[1] == address(0)) {
            revert Errors.ZeroAddress("whitelist");
        }
        if (addrs_[2] == address(0)) {
            revert Errors.ZeroAddress("blacklist");
        }
        if (addrs_[3] == address(0)) {
            revert Errors.ZeroAddress("loanToken");
        }
        if (newSecondInterestRates_.length == 0) {
            revert Errors.InvalidValue("second interest rates length is zero");
        }
        for (uint256 i = 0; i < newSecondInterestRates_.length; i++) {
            if (
                newSecondInterestRates_[i] == 0
                    || newSecondInterestRates_[i] > TimePowerLoanDefs.MAX_SECOND_INTEREST_RATE
            ) {
                revert Errors.InvalidValue("second interest rates value invalid");
            }
            if (i > 0 && newSecondInterestRates_[i] <= newSecondInterestRates_[i - 1]) {
                revert Errors.InvalidValue("second interest rates not sorted or duplicated");
            }
            secondInterestRates_.push(newSecondInterestRates_[i]);
            accumulatedInterestRates_.push(TimePowerLoanDefs.FIXED18);
        }
        if (newTrustedVaults_.length == 0) {
            revert Errors.InvalidValue("trusted vaults length is zero");
        }
        for (uint256 i = 0; i < newTrustedVaults_.length; i++) {
            if (newTrustedVaults_[i].vault == address(0)) {
                revert Errors.ZeroAddress("trusted vault address");
            }
            if (IERC4626(newTrustedVaults_[i].vault).asset() != addrs_[3]) {
                revert Errors.InvalidValue("trusted vault asset and loan token mismatch");
            }
            if (newTrustedVaults_[i].minimumPercentage > newTrustedVaults_[i].maximumPercentage) {
                revert Errors.InvalidValue("trusted vault percentage");
            }
            if (newTrustedVaults_[i].maximumPercentage > TimePowerLoanDefs.PRECISION) {
                revert Errors.InvalidValue("trusted vault maximum percentage exceeds 100%");
            }
            trustedVaults_.push(newTrustedVaults_[i]);
            vaultToIndex_[newTrustedVaults_[i].vault] = uint64(trustedVaults_.length - 1);
        }
    }

    function join(
        TimePowerLoanDefs.TrustedBorrower[] storage trustedBorrowers_,
        mapping(address => uint64) storage borrowerToIndex_
    ) public returns (uint64 borrowerIndex_) {
        for (uint256 i = 0; i < trustedBorrowers_.length; i++) {
            if (trustedBorrowers_[i].borrower == msg.sender) {
                revert TimePowerLoanDefs.BorrowerAlreadyExists(msg.sender, uint64(i));
            }
        }

        trustedBorrowers_.push(
            TimePowerLoanDefs.TrustedBorrower({borrower: msg.sender, ceilingLimit: 0, remainingLimit: 0})
        );
        borrowerIndex_ = uint64(trustedBorrowers_.length - 1);
        borrowerToIndex_[msg.sender] = borrowerIndex_;

        emit TimePowerLoanDefs.TrustedBorrowerAdded(msg.sender, borrowerIndex_);
    }

    function agree(
        TimePowerLoanDefs.TrustedBorrower[] storage trustedBorrowers_,
        mapping(address => uint64) storage borrowerToIndex_,
        address borrower_,
        uint128 newCeilingLimit_
    ) public {
        if (newCeilingLimit_ == 0) {
            revert TimePowerLoanDefs.AgreeJoinRequestShouldHaveNonZeroCeilingLimit(borrower_);
        }

        if (trustedBorrowers_[borrowerToIndex_[borrower_]].ceilingLimit != 0) {
            revert TimePowerLoanDefs.UpdateCeilingLimitDirectly(borrower_);
        }

        updateBorrowerLimit(trustedBorrowers_, borrowerToIndex_, borrower_, newCeilingLimit_);

        emit TimePowerLoanDefs.AgreeJoinRequest(borrower_, newCeilingLimit_);
    }

    function updateBorrowerLimit(
        TimePowerLoanDefs.TrustedBorrower[] storage trustedBorrowers_,
        mapping(address => uint64) storage borrowerToIndex_,
        address borrower_,
        uint128 newCeilingLimit_
    ) public {
        uint64 borrowerIndex = borrowerToIndex_[borrower_];
        TimePowerLoanDefs.TrustedBorrower memory trustedBorrower = trustedBorrowers_[borrowerIndex];

        uint128 remainingLimit = trustedBorrower.remainingLimit;
        uint128 ceilingLimit = trustedBorrower.ceilingLimit;

        if (ceilingLimit < remainingLimit) {
            revert TimePowerLoanDefs.CeilingLimitBelowRemainingLimit(ceilingLimit, remainingLimit);
        }

        uint128 usedLimit = ceilingLimit - remainingLimit;

        if (newCeilingLimit_ < usedLimit) {
            revert TimePowerLoanDefs.CeilingLimitBelowUsedLimit(newCeilingLimit_, usedLimit);
        }

        trustedBorrowers_[borrowerIndex].ceilingLimit = newCeilingLimit_;
        trustedBorrowers_[borrowerIndex].remainingLimit = newCeilingLimit_ - usedLimit;

        emit TimePowerLoanDefs.BorrowerCeilingLimitUpdated(ceilingLimit, newCeilingLimit_);
    }

    function request(
        TimePowerLoanDefs.TrustedBorrower[] storage trustedBorrowers_,
        mapping(address => uint64) storage borrowerToIndex_,
        TimePowerLoanDefs.LoanInfo[] storage allLoans_,
        mapping(uint64 => uint64[]) storage loansInfoGroupedByBorrower_,
        uint128 amount_
    ) public returns (uint64 loanIndex_) {
        uint64 borrowerIndex = borrowerToIndex_[msg.sender];
        uint128 borrowerRemainingLimit = trustedBorrowers_[borrowerIndex].remainingLimit;

        if (amount_ > borrowerRemainingLimit) {
            revert TimePowerLoanDefs.LoanCeilingLimitExceedsBorrowerRemainingLimit(amount_, borrowerRemainingLimit);
        }

        trustedBorrowers_[borrowerIndex].remainingLimit = borrowerRemainingLimit - amount_;

        allLoans_.push(
            TimePowerLoanDefs.LoanInfo({
                ceilingLimit: amount_,
                remainingLimit: amount_,
                normalizedPrincipal: 0,
                interestRateIndex: 0,
                borrowerIndex: borrowerIndex,
                status: TimePowerLoanDefs.LoanStatus.PENDING
            })
        );

        loanIndex_ = uint64(allLoans_.length - 1);

        loansInfoGroupedByBorrower_[borrowerIndex].push(loanIndex_);

        emit TimePowerLoanDefs.ReceiveLoanRequest(msg.sender, loanIndex_, amount_);
    }

    function approve(
        TimePowerLoanDefs.TrustedBorrower[] storage trustedBorrowers_,
        TimePowerLoanDefs.LoanInfo[] storage allLoans_,
        uint64 loanIndex_,
        uint128 ceilingLimit_,
        uint64 interestRateIndex_
    ) public {
        TimePowerLoanDefs.LoanInfo memory loan = allLoans_[loanIndex_];

        uint64 borrowerIndex = loan.borrowerIndex;
        uint128 requestCeilingLimit = loan.ceilingLimit;

        if (ceilingLimit_ < requestCeilingLimit) {
            uint128 diffCeilingLimit = requestCeilingLimit - ceilingLimit_;

            trustedBorrowers_[borrowerIndex].remainingLimit += diffCeilingLimit;
            loan.ceilingLimit = ceilingLimit_;
            loan.remainingLimit -= diffCeilingLimit;
        }

        loan.interestRateIndex = interestRateIndex_;
        loan.status = TimePowerLoanDefs.LoanStatus.APPROVED;

        allLoans_[loanIndex_] = loan;

        emit TimePowerLoanDefs.ApproveLoanRequest(
            trustedBorrowers_[borrowerIndex].borrower, loanIndex_, ceilingLimit_, interestRateIndex_
        );
    }

    function prepareFunds(TimePowerLoanDefs.TrustedVault[] storage trustedVaults_, address loanToken_, uint256 amount_)
        public
        returns (uint256[] memory trancheAmounts_, uint256 availableAmount_)
    {
        uint256 vaultNumber = trustedVaults_.length;

        /// @dev store tranche amounts for this debt from each vault
        /// @dev default lend value is zero
        trancheAmounts_ = new uint256[](vaultNumber);

        for (uint256 i = 0; i < vaultNumber; ++i) {
            uint256 minimumLendAmount = amount_.mulDiv(
                uint256(trustedVaults_[i].minimumPercentage), uint256(TimePowerLoanDefs.PRECISION), Math.Rounding.Floor
            );
            uint256 maximumLendAmount = amount_.mulDiv(
                uint256(trustedVaults_[i].maximumPercentage), uint256(TimePowerLoanDefs.PRECISION), Math.Rounding.Ceil
            );
            uint256 vaultTotalAssets = IERC4626(trustedVaults_[i].vault).totalAssets();
            uint256 vaultLendAmount;

            /// @dev vault cannot provide minimum lend amount for this debt
            if (vaultTotalAssets < minimumLendAmount) {
                vaultLendAmount = 0;
            }
            /// @dev vault can provide between minimum and maximum lend amount for this debt
            /// @dev vault provides all its assets
            else if (vaultTotalAssets < maximumLendAmount) {
                vaultLendAmount = vaultTotalAssets;
            }
            /// @dev vault can provide maximum lend amount for this debt
            else {
                vaultLendAmount = maximumLendAmount;
            }

            /// @dev not enough funds collected yet, continue to collect from next vault
            if (availableAmount_ + vaultLendAmount <= amount_) {
                trancheAmounts_[i] = vaultLendAmount;
                availableAmount_ += vaultLendAmount;
                IERC20(loanToken_).safeTransferFrom(trustedVaults_[i].vault, address(this), vaultLendAmount);
                continue;
            }
            /// @dev enough funds collected, finalize tranche amounts and break
            else {
                vaultLendAmount = amount_ - availableAmount_;
                trancheAmounts_[i] = vaultLendAmount;
                availableAmount_ += vaultLendAmount;
                IERC20(loanToken_).safeTransferFrom(trustedVaults_[i].vault, address(this), vaultLendAmount);
                break;
            }
        }
    }

    function distributeFunds(
        TimePowerLoanDefs.TrustedVault[] storage trustedVaults_,
        TimePowerLoanDefs.LoanInfo[] storage allLoans_,
        TimePowerLoanDefs.TrancheInfo[] storage allTranches_,
        mapping(uint64 => uint64[]) storage tranchesInfoGroupedByDebt_,
        uint256[] storage accumulatedInterestRates_,
        address loanToken_,
        uint64 debtIndex_,
        uint128 oldDebtNormalizedPrincipal_,
        uint128 newDebtNormalizedPrincipal_,
        uint256 amount_
    ) public {
        uint64[] memory tranchesIndex = tranchesInfoGroupedByDebt_[debtIndex_];
        uint256 totalRepaidAmount = 0;
        uint128 totalNormalizedPrincipal = 0;
        uint256 trancheNumber = tranchesIndex.length;
        for (uint256 i = 0; i < trancheNumber; ++i) {
            TimePowerLoanDefs.TrancheInfo memory tranche = allTranches_[tranchesIndex[i]];
            uint256 accumulatedInterestRate = accumulatedInterestRates_[allLoans_[tranche.loanIndex].interestRateIndex];

            if (i == trancheNumber - 1) {
                /// @dev last tranche takes the remaining amount to avoid rounding issues
                uint256 lastTrancheRepayAmount = amount_ - totalRepaidAmount;

                IERC20(loanToken_).safeTransfer(trustedVaults_[tranche.vaultIndex].vault, lastTrancheRepayAmount);

                allTranches_[tranchesIndex[i]].normalizedPrincipal =
                    newDebtNormalizedPrincipal_ - totalNormalizedPrincipal;
            } else {
                /// @dev calculate repay amount for each tranche based on their normalized principal
                uint256 trancheRepayAmount = uint256(tranche.normalizedPrincipal).mulDiv(
                    amount_, oldDebtNormalizedPrincipal_, Math.Rounding.Floor
                );
                totalRepaidAmount += trancheRepayAmount;

                IERC20(loanToken_).safeTransfer(trustedVaults_[tranche.vaultIndex].vault, trancheRepayAmount);

                uint128 newTrancheNormalizedPrincipal = uint128(
                    (
                        uint256(tranche.normalizedPrincipal).mulDiv(
                            accumulatedInterestRate, TimePowerLoanDefs.FIXED18, Math.Rounding.Ceil
                        ) - trancheRepayAmount
                    ).mulDiv(TimePowerLoanDefs.FIXED18, accumulatedInterestRate, Math.Rounding.Floor)
                );

                allTranches_[tranchesIndex[i]].normalizedPrincipal = newTrancheNormalizedPrincipal;
                totalNormalizedPrincipal += newTrancheNormalizedPrincipal;
            }
        }
    }
}
