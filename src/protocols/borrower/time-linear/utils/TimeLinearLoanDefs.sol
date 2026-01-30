// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

library TimeLinearLoanDefs {
    /// @dev error thrown when an address is not a trusted borrower
    /// @param borrower_ address of the borrower
    error NotTrustedBorrower(address borrower_);

    /// @dev error thrown when a borrower is not valid
    /// @param borrowerIndex_ index of the borrower
    error NotValidBorrower(uint64 borrowerIndex_);

    /// @dev error thrown when a loan is not valid
    /// @param loanIndex_ index of the loan
    error NotValidLoan(uint64 loanIndex_);

    /// @dev error thrown when borrower is not the owner of the loan
    /// @param loanIndex_ index of the loan
    /// @param loanOwner_ address of the loan owner
    /// @param borrower_ address of the borrower
    error NotLoanOwner(uint64 loanIndex_, address loanOwner_, address borrower_);

    /// @dev error thrown when a loan is not pending
    /// @param loanIndex_ index of the loan
    error NotPendingLoan(uint64 loanIndex_);

    /// @dev error thrown when a debt is not valid
    /// @param debtIndex_ index of the debt
    error NotValidDebt(uint64 debtIndex_);

    /// @dev error thrown when a debt is not defaulted
    /// @param debtIndex_ index of the debt
    error NotDefaultedDebt(uint64 debtIndex_);

    /// @dev error thrown when a debt is not matured
    /// @param debtIndex_ index of the debt
    error NotMaturedDebt(uint64 debtIndex_);

    /// @dev error thrown when a tranche is not valid
    /// @param trancheIndex_ index of the tranche
    error NotValidTranche(uint64 trancheIndex_);

    /// @dev error thrown when an address is not a trusted vault
    /// @param vault_ address of the vault
    error NotTrustedVault(address vault_);

    /// @dev error thrown when a vault is not valid
    /// @param vaultIndex_ index of the vault
    error NotValidVault(uint64 vaultIndex_);

    /// @dev error thrown when an interest rate index is not valid
    /// @param interestRateIndex_ index of the interest rate
    error NotValidInterestRate(uint64 interestRateIndex_);

    /// @dev error thrown when ceiling limit below remaining limit
    /// @param ceilingLimit_ ceiling limit
    /// @param remainingLimit_ remaining limit
    error CeilingLimitBelowRemainingLimit(uint128 ceilingLimit_, uint128 remainingLimit_);

    /// @dev error thrown when ceiling limit below used limit which is caculated by ceiling limit substract remaining limit
    /// @param ceilingLimit_ ceiling limit
    /// @param usedLimit_ difference of ceiling limit and remaining limit
    error CeilingLimitBelowUsedLimit(uint128 ceilingLimit_, uint128 usedLimit_);

    /// @dev error thrown when loan ceiling limit exceeds borrower's remaining limit
    /// @param loanCeilingLimit_ loan ceiling limit
    /// @param borrowerRemainingLimit_ borrower's remaining limit
    error LoanCeilingLimitExceedsBorrowerRemainingLimit(uint128 loanCeilingLimit_, uint128 borrowerRemainingLimit_);

    /// @dev error thrown when borrower already exists
    /// @param borrower_ address of the borrower
    /// @param borrowerIndex_ index of the borrower
    error BorrowerAlreadyExists(address borrower_, uint64 borrowerIndex_);

    /// @dev error thrown when agree join request but ceiling limit is zero
    /// @param borrower_ address of the borrower
    error AgreeJoinRequestShouldHaveNonZeroCeilingLimit(address borrower_);

    /// @dev error thrown when duplicated agree join request
    /// @param borrower_ address of the borrower
    error UpdateCeilingLimitDirectly(address borrower_);

    /// @dev error thrown when borrow amount exceeds loan remaining limit
    /// @param borrowAmount_ amount of the borrow
    /// @param loanRemainingLimit_ remaining limit of the loan
    /// @param loanIndex_ index of the loan
    error BorrowAmountOverLoanRemainingLimit(uint128 borrowAmount_, uint128 loanRemainingLimit_, uint64 loanIndex_);

    /// @dev error thrown when maturity time is before or at block timestamp
    /// @param maturityTime_ maturity time
    /// @param blockTimestamp_ block timestamp
    error MaturityTimeShouldAfterBlockTimestamp(uint64 maturityTime_, uint64 blockTimestamp_);

    /// @dev event emitted when borrower ceiling limit is updated
    /// @param oldCeilingLimit_ old ceiling limit
    /// @param newCeilingLimit_ new ceiling limit
    event BorrowerCeilingLimitUpdated(uint128 oldCeilingLimit_, uint128 newCeilingLimit_);

    /// @dev event emitted when loan ceiling limit is updated
    /// @param oldCeilingLimit_ old ceiling limit
    /// @param newCeilingLimit_ new ceiling limit
    event LoanCeilingLimitUpdated(uint128 oldCeilingLimit_, uint128 newCeilingLimit_);

    /// @dev event emitted when interest rate index is updated
    /// @param loanIndex_ index of the loan
    /// @param oldInterestRateIndex_ old interest rate index
    /// @param newInterestRateIndex_ new interest rate index
    event LoanInterestRateUpdated(uint64 loanIndex_, uint64 oldInterestRateIndex_, uint64 newInterestRateIndex_);

    /// @dev event emitted when trusted vault is updated
    /// @param oldVault_ address of the old trusted vault
    /// @param oldMinimumPercentage_ minimum percentage of the old trusted vault
    /// @param oldMaximumPercentage_ maximum percentage of the old trusted vault
    /// @param newVault_ address of the new trusted vault
    /// @param newMinimumPercentage_ minimum percentage of the new trusted vault
    /// @param newMaximumPercentage_ maximum percentage of the new trusted vault
    /// @param vaultIndex_ index of the trusted vault
    event TrustedVaultUpdated(
        address oldVault_,
        uint48 oldMinimumPercentage_,
        uint48 oldMaximumPercentage_,
        address newVault_,
        uint48 newMinimumPercentage_,
        uint48 newMaximumPercentage_,
        uint256 vaultIndex_
    );

    /// @dev event emitted when trusted vault is added
    /// @param vault_ address of the trusted vault
    /// @param minimumPercentage_ minimum percentage
    /// @param maximumPercentage_ maximum percentage
    event TrustedVaultAdded(address vault_, uint48 minimumPercentage_, uint48 maximumPercentage_, uint256 vaultIndex_);

    /// @dev event emitted when trusted borrower is added
    /// @param borrower_ address of the trusted borrower
    /// @param borrowerIndex_ index of the trusted borrower
    event TrustedBorrowerAdded(address borrower_, uint64 borrowerIndex_);

    /// @dev event emitted when a borrower join request is agreed
    /// @param borrower_ address of the borrower
    /// @param newCeilingLimit_ new ceiling limit of the borrower
    event AgreeJoinRequest(address borrower_, uint128 newCeilingLimit_);

    /// @dev event emitted when a loan request is received
    /// @param borrower_ address of the borrower
    /// @param loanIndex_ index of the loan
    /// @param amount_ amount of the loan request
    event ReceiveLoanRequest(address borrower_, uint64 loanIndex_, uint128 amount_);

    /// @dev event emitted when a loan request is approved
    /// @param borrower_ address of the borrower
    /// @param loanIndex_ index of the loan
    /// @param ceilingLimit_ ceiling limit of the approved loan
    /// @param interestRateIndex_ interest rate index of the approved loan
    event ApproveLoanRequest(address borrower_, uint64 loanIndex_, uint128 ceilingLimit_, uint64 interestRateIndex_);

    /// @dev event emitted when a new debt is borrowed
    /// @param borrower_ address of the borrower
    /// @param loanIndex_ index of the loan
    /// @param amount_ amount of the borrowed debt
    /// @param isAllSatisfied_ whether the borrowed debt is fully satisfied
    /// @param debtIndex_ index of the new debt
    event Borrowed(address borrower_, uint64 loanIndex_, uint128 amount_, bool isAllSatisfied_, uint64 debtIndex_);

    /// @dev event emitted when a debt is repaid
    /// @param borrower_ address of the borrower
    /// @param debtIndex_ index of the debt
    /// @param amount_ amount of the repaid debt
    /// @param isAllRepaid_ whether the debt is fully repaid
    event Repaid(address borrower_, uint64 debtIndex_, uint128 amount_, bool isAllRepaid_);

    /// @dev event emitted when a debt is defaulted
    /// @param borrower_ address of the borrower
    /// @param debtIndex_ index of the debt
    /// @param remainingDebt_ amount of the remaining debt
    /// @param defaultedInterestRateIndex_ interest rate index at the time of default
    event Defaulted(address borrower_, uint64 debtIndex_, uint128 remainingDebt_, uint64 defaultedInterestRateIndex_);

    /// @dev event emitted when a defaulted debt is recovered
    /// @param borrower_ address of the borrower
    /// @param debtIndex_ index of the debt
    /// @param recoveredAmount_ amount of the recovered debt
    /// @param remainingDebt_ amount of the remaining debt after recovery
    event Recovery(address borrower_, uint64 debtIndex_, uint128 recoveredAmount_, uint128 remainingDebt_);

    /// @dev event emitted when a defaulted debt is closed
    /// @param borrower_ address of the borrower
    /// @param debtIndex_ index of the debt
    /// @param lossDebt_ amount of the loss debt
    event Closed(address borrower_, uint64 debtIndex_, uint128 lossDebt_);

    /// @dev status of a debt
    enum DebtStatus {
        /// @dev default value, not existed debt
        NOT_EXISTED,
        /// @dev debt is approved and time is before or at maturity date
        ACTIVE,
        /// @dev debt is zero after maturity date
        REPAID,
        /// @dev debt is not zero after maturity date
        DEFAULTED,
        /// @dev debt is closed by operator after default
        CLOSED
    }

    /// @dev status of a loan
    enum LoanStatus {
        /// @dev default value, not existed loan
        NOT_EXISTED,
        /// @dev loan is not approved by operator yet
        PENDING,
        /// @dev loan is approved by operator
        APPROVED,
        /// @dev loan is rejected by operator
        REJECTED
    }

    /// @dev trusted vault information
    struct TrustedVault {
        /// @dev address of the trusted vault
        address vault;
        /// @dev minimum percentage of each loan that borrow from this vault in million (1_000_000 = 100%)
        uint48 minimumPercentage;
        /// @dev maximum percentage of each loan that borrow from this vault in million (1_000_000 = 100%)
        uint48 maximumPercentage;
    }

    /// @dev trusted borrower information
    struct TrustedBorrower {
        /// @dev address of the trusted borrower
        address borrower;
        /// @dev ceiling limit for the trusted borrower
        uint128 ceilingLimit;
        /// @dev remaining limit for the trusted borrower, decreased when new loan is approved
        uint128 remainingLimit;
    }

    /// @dev loan information
    struct LoanInfo {
        /// @dev maximum limit for the loan
        uint128 ceilingLimit;
        /// @dev remaining limit for the loan, decreased when new debt is borrowed
        uint128 remainingLimit;
        /// @dev interest rate index for the loan
        uint64 interestRateIndex;
        /// @dev address of the borrower
        uint64 borrowerIndex;
        /// @dev status of the loan
        LoanStatus status;
    }

    /// @dev debt information
    struct DebtInfo {
        /// @dev loan index for the debt
        uint64 loanIndex;
        /// @dev start time of the debt
        uint64 startTime;
        /// @dev maturity time of the debt
        uint64 maturityTime;
        /// @dev last update time of the debt
        uint64 lastUpdateTime;
        /// @dev principal amount of the debt
        uint128 principal;
        /// @dev net remaining debt amount of the debt
        uint128 netRemainingDebt;
        /// @dev interest bearing amount of the debt
        uint128 interestBearingAmount;
        /// @dev net remaining interest amount of the debt
        uint128 netRemainingInterest;
        /// @dev status of the debt
        DebtStatus status;
    }

    /// @dev tranche information
    struct TrancheInfo {
        /// @dev vault index for the tranche
        uint64 vaultIndex;
        /// @dev debt index for the tranche
        uint64 debtIndex;
        /// @dev loan index for the tranche
        uint64 loanIndex;
        /// @dev borrower index for the tranche
        uint64 borrowerIndex;
        /// @dev principal amount for the tranche
        uint128 principal;
    }

    /// @dev fixed point 18 precision
    /// @notice constant, not stored in storage
    uint256 public constant FIXED18 = 1_000_000_000_000_000_000;

    /// @dev precision in million (1_000_000 = 100%)
    /// @notice constant, not stored in storage
    uint256 public constant PRECISION = 1_000_000;

    /// @dev maximum second interest rate in FIXED18 : 36% / (365 * 24 * 60 * 60)
    /// @notice constant, not stored in storage
    uint256 public constant MAX_SECOND_INTEREST_RATE = 11415525114;
}
