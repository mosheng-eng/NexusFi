// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Errors} from "src/common/Errors.sol";
import {TimeLinearLoanLibs} from "src/protocols/borrower/time-linear/utils/TimeLinearLoanLibs.sol";
import {TimeLinearLoanDefs} from "src/protocols/borrower/time-linear/utils/TimeLinearLoanDefs.sol";

library TimeLinearLoanCore {
    using Math for uint256;
    using SafeERC20 for IERC20;
    using TimeLinearLoanLibs for TimeLinearLoanDefs.TrustedBorrower[];

    function initialize(
        TimeLinearLoanDefs.TrustedVault[] storage trustedVaults_,
        mapping(address => uint64) storage vaultToIndex_,
        uint256[] storage secondInterestRates_,
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
        TimeLinearLoanDefs.TrustedVault[] memory newTrustedVaults_
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
                    || newSecondInterestRates_[i] > TimeLinearLoanDefs.MAX_SECOND_INTEREST_RATE
            ) {
                revert Errors.InvalidValue("second interest rates value invalid");
            }
            if (i > 0 && newSecondInterestRates_[i] <= newSecondInterestRates_[i - 1]) {
                revert Errors.InvalidValue("second interest rates not sorted or duplicated");
            }
            secondInterestRates_.push(newSecondInterestRates_[i]);
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
            if (newTrustedVaults_[i].maximumPercentage > TimeLinearLoanDefs.PRECISION) {
                revert Errors.InvalidValue("trusted vault maximum percentage exceeds 100%");
            }
            trustedVaults_.push(newTrustedVaults_[i]);
            vaultToIndex_[newTrustedVaults_[i].vault] = uint64(trustedVaults_.length - 1);
        }
    }

    function join(
        TimeLinearLoanDefs.TrustedBorrower[] storage trustedBorrowers_,
        mapping(address => uint64) storage borrowerToIndex_
    ) public returns (uint64 borrowerIndex_) {
        for (uint256 i = 0; i < trustedBorrowers_.length; i++) {
            if (trustedBorrowers_[i].borrower == msg.sender) {
                revert TimeLinearLoanDefs.BorrowerAlreadyExists(msg.sender, uint64(i));
            }
        }

        trustedBorrowers_.push(
            TimeLinearLoanDefs.TrustedBorrower({borrower: msg.sender, ceilingLimit: 0, remainingLimit: 0})
        );
        borrowerIndex_ = uint64(trustedBorrowers_.length - 1);
        borrowerToIndex_[msg.sender] = borrowerIndex_;
        emit TimeLinearLoanDefs.TrustedBorrowerAdded(msg.sender, borrowerIndex_);
    }

    function agree(
        TimeLinearLoanDefs.TrustedBorrower[] storage trustedBorrowers_,
        mapping(address => uint64) storage borrowerToIndex_,
        address borrower_,
        uint128 newCeilingLimit_
    ) public {
        if (newCeilingLimit_ == 0) {
            revert TimeLinearLoanDefs.AgreeJoinRequestShouldHaveNonZeroCeilingLimit(borrower_);
        }

        if (trustedBorrowers_[borrowerToIndex_[borrower_]].ceilingLimit != 0) {
            revert TimeLinearLoanDefs.UpdateCeilingLimitDirectly(borrower_);
        }

        trustedBorrowers_.updateBorrowerLimit(borrowerToIndex_, borrower_, newCeilingLimit_);

        emit TimeLinearLoanDefs.AgreeJoinRequest(borrower_, newCeilingLimit_);
    }

    function request(
        TimeLinearLoanDefs.TrustedBorrower[] storage trustedBorrowers_,
        mapping(address => uint64) storage borrowerToIndex_,
        TimeLinearLoanDefs.LoanInfo[] storage allLoans_,
        mapping(uint64 => uint64[]) storage loansInfoGroupedByBorrower_,
        uint128 amount_
    ) public returns (uint64 loanIndex_) {
        uint64 borrowerIndex = borrowerToIndex_[msg.sender];
        uint128 borrowerRemainingLimit = trustedBorrowers_[borrowerIndex].remainingLimit;

        if (amount_ > borrowerRemainingLimit) {
            revert TimeLinearLoanDefs.LoanCeilingLimitExceedsBorrowerRemainingLimit(amount_, borrowerRemainingLimit);
        }

        trustedBorrowers_[borrowerIndex].remainingLimit = borrowerRemainingLimit - amount_;

        allLoans_.push(
            TimeLinearLoanDefs.LoanInfo({
                ceilingLimit: amount_,
                remainingLimit: amount_,
                interestRateIndex: 0,
                borrowerIndex: borrowerIndex,
                status: TimeLinearLoanDefs.LoanStatus.PENDING
            })
        );

        loanIndex_ = uint64(allLoans_.length - 1);

        loansInfoGroupedByBorrower_[borrowerIndex].push(loanIndex_);

        emit TimeLinearLoanDefs.ReceiveLoanRequest(msg.sender, loanIndex_, amount_);
    }

    function approve(
        TimeLinearLoanDefs.TrustedBorrower[] storage trustedBorrowers_,
        TimeLinearLoanDefs.LoanInfo[] storage allLoans_,
        uint64 loanIndex_,
        uint128 ceilingLimit_,
        uint64 interestRateIndex_
    ) public {
        TimeLinearLoanDefs.LoanInfo memory loan = allLoans_[loanIndex_];

        uint64 borrowerIndex = loan.borrowerIndex;
        uint128 requestCeilingLimit = loan.ceilingLimit;

        if (ceilingLimit_ < requestCeilingLimit) {
            uint128 diffCeilingLimit = requestCeilingLimit - ceilingLimit_;

            trustedBorrowers_[borrowerIndex].remainingLimit += diffCeilingLimit;
            loan.ceilingLimit = ceilingLimit_;
            loan.remainingLimit -= diffCeilingLimit;
        }

        loan.interestRateIndex = interestRateIndex_;
        loan.status = TimeLinearLoanDefs.LoanStatus.APPROVED;

        allLoans_[loanIndex_] = loan;

        emit TimeLinearLoanDefs.ApproveLoanRequest(
            trustedBorrowers_[borrowerIndex].borrower, loanIndex_, ceilingLimit_, interestRateIndex_
        );
    }

    function close(
        TimeLinearLoanDefs.DebtInfo[] storage allDebts_,
        address borrower_,
        uint64 debtIndex_,
        TimeLinearLoanDefs.LoanInfo[] storage allLoans_,
        uint256[] storage secondInterestRates_
    ) public returns (uint128 lossDebt_) {
        TimeLinearLoanDefs.DebtInfo memory debtInfo = allDebts_[debtIndex_];
        TimeLinearLoanDefs.LoanInfo memory loanInfo = allLoans_[debtInfo.loanIndex];

        loanInfo.remainingLimit += (debtInfo.netRemainingDebt - debtInfo.netRemainingInterest);

        lossDebt_ = debtInfo.netRemainingDebt;

        if (debtInfo.lastUpdateTime < block.timestamp) {
            lossDebt_ += uint128(
                uint256(debtInfo.interestBearingAmount * (block.timestamp - debtInfo.lastUpdateTime)).mulDiv(
                    secondInterestRates_[loanInfo.interestRateIndex], TimeLinearLoanDefs.FIXED18, Math.Rounding.Ceil
                )
            );
        }

        debtInfo.status = TimeLinearLoanDefs.DebtStatus.CLOSED;
        debtInfo.netRemainingDebt = 0;
        debtInfo.netRemainingInterest = 0;
        debtInfo.interestBearingAmount = 0;
        debtInfo.lastUpdateTime = uint64(block.timestamp);

        allDebts_[debtIndex_] = debtInfo;
        allLoans_[debtInfo.loanIndex] = loanInfo;

        emit TimeLinearLoanDefs.Closed(borrower_, debtIndex_, lossDebt_);
    }

    function distributeFunds(
        TimeLinearLoanDefs.TrustedVault[] storage trustedVaults_,
        TimeLinearLoanDefs.TrancheInfo[] storage allTranches_,
        mapping(uint64 => uint64[]) storage tranchesInfoGroupedByDebt_,
        address loanToken_,
        uint64 debtIndex_,
        uint128 principal_,
        uint256 amount_
    ) public {
        uint64[] memory tranchesIndex = tranchesInfoGroupedByDebt_[debtIndex_];
        uint256 totalRepaidAmount = 0;
        uint256 trancheNumber = tranchesIndex.length;
        for (uint256 i = 0; i < trancheNumber; ++i) {
            TimeLinearLoanDefs.TrancheInfo memory tranche = allTranches_[tranchesIndex[i]];
            if (i == trancheNumber - 1) {
                /// @dev last tranche takes the remaining amount to avoid rounding issues
                uint256 lastTrancheRepayAmount = amount_ - totalRepaidAmount;

                IERC20(loanToken_).safeTransfer(trustedVaults_[tranche.vaultIndex].vault, lastTrancheRepayAmount);
            } else {
                /// @dev calculate repay amount for each tranche based on their principal
                uint256 trancheRepayAmount = amount_.mulDiv(tranche.principal, principal_, Math.Rounding.Floor);
                totalRepaidAmount += trancheRepayAmount;

                IERC20(loanToken_).safeTransfer(trustedVaults_[tranche.vaultIndex].vault, trancheRepayAmount);
            }
        }
    }

    function prepareFunds(TimeLinearLoanDefs.TrustedVault[] storage trustedVaults_, address loanToken_, uint256 amount_)
        public
        returns (uint256[] memory trancheAmounts_, uint256 availableAmount_)
    {
        uint256 vaultNumber = trustedVaults_.length;

        /// @dev store tranche amounts for this debt from each vault
        /// @dev default lend value is zero
        trancheAmounts_ = new uint256[](vaultNumber);

        for (uint256 i = 0; i < vaultNumber; ++i) {
            uint256 minimumLendAmount = amount_.mulDiv(
                uint256(trustedVaults_[i].minimumPercentage), uint256(TimeLinearLoanDefs.PRECISION), Math.Rounding.Floor
            );
            uint256 maximumLendAmount = amount_.mulDiv(
                uint256(trustedVaults_[i].maximumPercentage), uint256(TimeLinearLoanDefs.PRECISION), Math.Rounding.Ceil
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
}
