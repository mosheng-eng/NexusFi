// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Errors} from "@nexusfi/contracts/common/Errors.sol";
import {TimePowerLoanDefs} from "@nexusfi/contracts/protocols/borrower/time-power/utils/TimePowerLoanDefs.sol";
import {TimePowerLoanLibs} from "@nexusfi/contracts/protocols/borrower/time-power/utils/TimePowerLoanLibs.sol";

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
        mapping(address => uint64) storage borrowerToIndex_,
        address borrower_
    ) public returns (uint64 borrowerIndex_) {
        for (uint256 i = 0; i < trustedBorrowers_.length; i++) {
            if (trustedBorrowers_[i].borrower == borrower_) {
                revert TimePowerLoanDefs.BorrowerAlreadyExists(borrower_, uint64(i));
            }
        }

        trustedBorrowers_.push(
            TimePowerLoanDefs.TrustedBorrower({borrower: borrower_, ceilingLimit: 0, remainingLimit: 0})
        );
        borrowerIndex_ = uint64(trustedBorrowers_.length - 1);
        borrowerToIndex_[borrower_] = borrowerIndex_;

        emit TimePowerLoanDefs.TrustedBorrowerAdded(borrower_, borrowerIndex_);
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
        uint128 amount_,
        address borrower_
    ) public returns (uint64 loanIndex_) {
        uint64 borrowerIndex = borrowerToIndex_[borrower_];
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

        emit TimePowerLoanDefs.ReceiveLoanRequest(borrower_, loanIndex_, amount_);
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
            uint256 vaultRemainingBalance = IERC20(loanToken_).balanceOf(trustedVaults_[i].vault);
            uint256 vaultLendAmount;

            /// @dev vault cannot provide minimum lend amount for this debt
            if (vaultRemainingBalance < minimumLendAmount) {
                vaultLendAmount = 0;
            }
            /// @dev vault can provide between minimum and maximum lend amount for this debt
            /// @dev vault provides all its assets
            else if (vaultRemainingBalance < maximumLendAmount) {
                vaultLendAmount = vaultRemainingBalance;
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

    function accumulateInterest(
        uint256[] storage accumulatedInterestRates_,
        uint256[] storage secondInterestRates_,
        uint64 lastAccumulateInterestTime_
    ) public returns (uint64) {
        uint64 currentTime = uint64(block.timestamp);
        if (currentTime > lastAccumulateInterestTime_) {
            uint64 timePeriod = currentTime - lastAccumulateInterestTime_;
            for (uint256 i = 0; i < secondInterestRates_.length; i++) {
                accumulatedInterestRates_[i] = accumulatedInterestRates_[i].mulDiv(
                    TimePowerLoanLibs.rpow(secondInterestRates_[i], timePeriod, TimePowerLoanDefs.FIXED18),
                    TimePowerLoanDefs.FIXED18,
                    Math.Rounding.Ceil
                );
            }
            lastAccumulateInterestTime_ = currentTime;

            emit TimePowerLoanDefs.AccumulatedInterestUpdated(currentTime);
        }
        return lastAccumulateInterestTime_;
    }

    function dryrunAccumulatedInterest(
        uint256[] storage accumulatedInterestRates_,
        uint256[] storage secondInterestRates_,
        uint64 lastAccumulateInterestTime_
    ) public view returns (uint256[] memory updatedAccumulatedInterestRates_) {
        uint64 currentTime = uint64(block.timestamp);
        if (currentTime > lastAccumulateInterestTime_) {
            uint64 timePeriod = currentTime - lastAccumulateInterestTime_;
            updatedAccumulatedInterestRates_ = new uint256[](secondInterestRates_.length);
            for (uint256 i = 0; i < secondInterestRates_.length; i++) {
                updatedAccumulatedInterestRates_[i] = accumulatedInterestRates_[i].mulDiv(
                    TimePowerLoanLibs.rpow(secondInterestRates_[i], timePeriod, TimePowerLoanDefs.FIXED18),
                    TimePowerLoanDefs.FIXED18,
                    Math.Rounding.Ceil
                );
            }
        } else {
            updatedAccumulatedInterestRates_ = accumulatedInterestRates_;
        }
    }

    function borrow(
        TimePowerLoanDefs.LoanInfo[] storage allLoans_,
        TimePowerLoanDefs.TrancheInfo[] storage allTranches_,
        TimePowerLoanDefs.DebtInfo[] storage allDebts_,
        TimePowerLoanDefs.TrustedVault[] storage trustedVaults_,
        mapping(uint64 => uint64[]) storage debtsInfoGroupedByLoan_,
        mapping(uint64 => uint64[]) storage debtsInfoGroupedByBorrower_,
        mapping(uint64 => uint64[]) storage tranchesInfoGroupedByDebt_,
        mapping(uint64 => uint64[]) storage tranchesInfoGroupedByLoan_,
        mapping(uint64 => uint64[]) storage tranchesInfoGroupedByBorrower_,
        mapping(uint64 => uint64[]) storage tranchesInfoGroupedByVault_,
        uint256[] storage accumulatedInterestRates_,
        uint64 loanIndex_,
        uint128 amount_,
        uint64 maturityTime_,
        address loanToken_,
        address receiver_
    ) public returns (bool isAllSatisfied_, uint64 debtIndex_) {
        if (maturityTime_ <= uint64(block.timestamp)) {
            revert TimePowerLoanDefs.MaturityTimeShouldAfterBlockTimestamp(maturityTime_, uint64(block.timestamp));
        }

        TimePowerLoanDefs.LoanInfo memory loan = allLoans_[loanIndex_];

        if (amount_ > loan.remainingLimit) {
            revert TimePowerLoanDefs.BorrowAmountOverLoanRemainingLimit(amount_, loan.remainingLimit, loanIndex_);
        }

        (uint256[] memory trancheAmounts, uint256 availableAmount) = prepareFunds(trustedVaults_, loanToken_, amount_);

        isAllSatisfied_ = availableAmount == uint256(amount_);

        uint256 accumulatedInterestRate = accumulatedInterestRates_[loan.interestRateIndex];
        uint128 normalizedPrincipal = 0;

        for (uint256 i = 0; i < trancheAmounts.length; ++i) {
            if (trancheAmounts[i] == 0) {
                continue;
            }

            uint256 normalizedPrincipalForTranche =
                trancheAmounts[i].mulDiv(TimePowerLoanDefs.FIXED18, accumulatedInterestRate, Math.Rounding.Ceil);

            normalizedPrincipal += uint128(normalizedPrincipalForTranche);

            allTranches_.push(
                TimePowerLoanDefs.TrancheInfo({
                    vaultIndex: uint64(i),
                    debtIndex: uint64(allDebts_.length),
                    loanIndex: loanIndex_,
                    borrowerIndex: loan.borrowerIndex,
                    normalizedPrincipal: uint128(normalizedPrincipalForTranche)
                })
            );

            uint64 trancheIndex = uint64(allTranches_.length - 1);

            tranchesInfoGroupedByDebt_[uint64(allDebts_.length)].push(trancheIndex);
            tranchesInfoGroupedByLoan_[loanIndex_].push(trancheIndex);
            tranchesInfoGroupedByBorrower_[loan.borrowerIndex].push(trancheIndex);
            tranchesInfoGroupedByVault_[uint64(i)].push(trancheIndex);
        }

        loan.remainingLimit -= uint128(availableAmount);

        loan.normalizedPrincipal += normalizedPrincipal;

        allLoans_[loanIndex_] = loan;

        allDebts_.push(
            TimePowerLoanDefs.DebtInfo({
                startTime: uint64(block.timestamp),
                maturityTime: maturityTime_,
                principal: uint128(availableAmount),
                normalizedPrincipal: normalizedPrincipal,
                loanIndex: loanIndex_,
                status: TimePowerLoanDefs.DebtStatus.ACTIVE
            })
        );

        debtIndex_ = uint64(allDebts_.length - 1);

        debtsInfoGroupedByLoan_[loanIndex_].push(debtIndex_);
        debtsInfoGroupedByBorrower_[loan.borrowerIndex].push(debtIndex_);

        IERC20(loanToken_).safeTransfer(receiver_, availableAmount);

        emit TimePowerLoanDefs.Borrowed(receiver_, loanIndex_, uint128(availableAmount), isAllSatisfied_, debtIndex_);
    }

    function repay(
        TimePowerLoanDefs.LoanInfo[] storage allLoans_,
        TimePowerLoanDefs.TrancheInfo[] storage allTranches_,
        TimePowerLoanDefs.DebtInfo[] storage allDebts_,
        TimePowerLoanDefs.TrustedVault[] storage trustedVaults_,
        mapping(uint64 => uint64[]) storage tranchesInfoGroupedByDebt_,
        uint256[] storage accumulatedInterestRates_,
        address borrower_,
        uint64 debtIndex_,
        uint128 amount_,
        address loanToken_
    ) public returns (bool isAllRepaid_, uint128 remainingDebt_) {
        TimePowerLoanDefs.DebtInfo memory debt = allDebts_[debtIndex_];
        TimePowerLoanDefs.LoanInfo memory loan = allLoans_[debt.loanIndex];

        /// @dev layoff temporary variables
        /// @dev params[0]: accumulatedInterestRate
        /// @dev params[1]: debtNormalizedPrincipal
        /// @dev params[2]: totalDebt
        /// @dev params[3]: remainingNormalizedPrincipal
        uint256[] memory params = new uint256[](4);
        /* uint256 accumulatedInterestRate */
        params[0] = accumulatedInterestRates_[loan.interestRateIndex];
        /* uint128 debtNormalizedPrincipal */
        params[1] = debt.normalizedPrincipal;
        /* uint256 totalDebt */
        params[2] = uint256(params[1]).mulDiv(params[0], TimePowerLoanDefs.FIXED18, Math.Rounding.Ceil);

        if (amount_ >= params[2]) {
            amount_ = uint128(params[2]);
            isAllRepaid_ = true;
            debt.status = TimePowerLoanDefs.DebtStatus.REPAID;
        } else {
            isAllRepaid_ = false;
        }

        remainingDebt_ = uint128(params[2] - uint256(amount_));

        /// @dev ramining normalized principal maybe over than debt normalized principal if repay amount is below debt interest
        /* uint128 remainingNormalizedPrincipal */
        params[3] = uint256(remainingDebt_).mulDiv(TimePowerLoanDefs.FIXED18, params[0], Math.Rounding.Ceil);

        /// @dev loan normalized principal should decrease if repay amount is over debt interest
        /// @dev loan normalized principal should increase if repay amount is below debt interest
        loan.normalizedPrincipal = loan.normalizedPrincipal + uint128(params[3]) - uint128(params[1]);

        /// @dev repay amount is greater than or equal to debt total interest
        /// @dev loan remaining limit is impossible to decrease in this case
        if (amount_ + debt.principal >= params[2]) {
            loan.remainingLimit += (amount_ + debt.principal - uint128(params[2]));
        } else {
            uint128 decreasedLimit = uint128(params[2]) - (amount_ + debt.principal);
            /// @dev repay amount is not enough to cover debt interest
            /// @dev loan limit will decrease in this case
            /// @dev meaning that unrepaid interest become new debt principal and reduce loan limit
            if (loan.remainingLimit > decreasedLimit) {
                loan.remainingLimit -= decreasedLimit;
            }
            /// @dev if loan remaining limit is not enough to cover the decreased limit, revert TimePowerLoanDefs.the transaction
            /// @dev borrower should repay more to cover the decreased limit
            else {
                revert TimePowerLoanDefs.RepayTooLittle(
                    borrower_, debtIndex_, uint128(params[2]) - debt.principal - loan.remainingLimit, amount_
                );
            }
        }

        /// @dev debt normalized principal should decrease if repay amount is over debt interest
        /// @dev debt normalized principal should increase if repay amount is below debt interest
        debt.normalizedPrincipal = uint128(params[3]);
        /// @dev debt principal should decrease if repay amount is over debt interest
        /// @dev debt principal should remain the same if repay amount is below debt interest
        debt.principal = remainingDebt_;

        allDebts_[debtIndex_] = debt;
        allLoans_[debt.loanIndex] = loan;

        IERC20(loanToken_).safeTransferFrom(borrower_, address(this), uint256(amount_));

        distributeFunds(
            trustedVaults_,
            allLoans_,
            allTranches_,
            tranchesInfoGroupedByDebt_,
            accumulatedInterestRates_,
            loanToken_,
            debtIndex_,
            uint128(params[1]),
            uint128(params[3]),
            uint256(amount_)
        );

        emit TimePowerLoanDefs.Repaid(borrower_, debtIndex_, amount_, isAllRepaid_);
    }
}
