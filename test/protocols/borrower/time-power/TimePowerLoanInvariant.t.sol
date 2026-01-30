// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {TimePowerLoan} from "src/protocols/borrower/time-power/TimePowerLoan.sol";
import {TimePowerLoanDefs} from "src/protocols/borrower/time-power/utils/TimePowerLoanDefs.sol";
import {TimePowerLoanHandler} from "test/protocols/borrower/time-power/handler/TimePowerLoanHandler.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract TimePowerLoanInvariant is Test {
    using Math for uint256;

    TimePowerLoanHandler internal _timePowerLoanHandler;
    TimePowerLoan internal _timePowerLoan;

    function setUp() public {
        _timePowerLoanHandler = new TimePowerLoanHandler();
        vm.label(address(_timePowerLoanHandler), "TimePowerLoanHandler");

        _timePowerLoan = _timePowerLoanHandler.getTimePowerLoan();
        vm.label(address(_timePowerLoan), "TimePowerLoan");

        bytes4[] memory targetSelectors = new bytes4[](10);
        targetSelectors[0] = TimePowerLoanHandler.unionHandler1.selector;
        targetSelectors[1] = TimePowerLoanHandler.unionHandler2.selector;
        targetSelectors[2] = TimePowerLoanHandler.unionHandler3.selector;
        targetSelectors[3] = TimePowerLoanHandler.unionHandler4.selector;
        targetSelectors[4] = TimePowerLoanHandler.unionHandler5.selector;
        targetSelectors[5] = TimePowerLoanHandler.timeHandler.selector;
        targetSelectors[6] = TimePowerLoanHandler.repayHandler.selector;
        targetSelectors[7] = TimePowerLoanHandler.defaultHandler.selector;
        targetSelectors[8] = TimePowerLoanHandler.recoveryHandler.selector;
        targetSelectors[9] = TimePowerLoanHandler.closeHandler.selector;
        targetSelector(StdInvariant.FuzzSelector({addr: address(_timePowerLoanHandler), selectors: targetSelectors}));
        targetContract(address(_timePowerLoanHandler));
    }

    function testDebug() public {}

    function invariantTotalDebtAlwayEqualBetweenBorrowersAndVaults() public {
        uint256 totalBorrowers = _timePowerLoan.getTotalTrustedBorrowers();
        uint256 totalVaults = _timePowerLoan.getTotalTrustedVaults();
        uint256 totalDebtOfBorrowers = 0;
        uint256 totalDebtOfVaults = 0;
        for (uint64 i = 0; i < totalBorrowers; i++) {
            (address borrower,,) = _timePowerLoan._trustedBorrowers(i);
            totalDebtOfBorrowers += _timePowerLoan.totalDebtOfBorrower(borrower);
        }
        for (uint64 j = 0; j < totalVaults; j++) {
            (address vault,,) = _timePowerLoan._trustedVaults(j);
            totalDebtOfVaults += _timePowerLoan.totalDebtOfVault(vault);
        }
        console.log("Total Debt of Borrowers: ", totalDebtOfBorrowers);
        console.log("Total Debt of Vaults   : ", totalDebtOfVaults);
        /// @dev Assert that the total debt difference between borrowers and vaults is less than 256 (to account for any minor precision loss)
        assertLt(_abs(totalDebtOfBorrowers, totalDebtOfVaults), 256);
    }

    function invariantDebtAlwaysEqualInLoansDebtsTranches() public {
        _timePowerLoan.pile();

        uint256[] memory loans_debts_tranches_number = new uint256[](3);
        loans_debts_tranches_number[0] = _timePowerLoan.getTotalLoans();
        loans_debts_tranches_number[1] = _timePowerLoan.getTotalDebts();
        loans_debts_tranches_number[2] = _timePowerLoan.getTotalTranches();
        uint256[] memory loans_debts_tranches_amount = new uint256[](3);
        uint64 index;
        for (index = 0; index < loans_debts_tranches_number[0]; index++) {
            TimePowerLoanDefs.LoanInfo memory loanInfo = _getLoanInfoAtIndex(index);
            loans_debts_tranches_amount[0] += uint256(loanInfo.normalizedPrincipal).mulDiv(
                _timePowerLoan._accumulatedInterestRates(loanInfo.interestRateIndex), 1e18, Math.Rounding.Ceil
            );
        }
        for (index = 0; index < loans_debts_tranches_number[1]; index++) {
            TimePowerLoanDefs.DebtInfo memory debtInfo = _getDebtInfoAtIndex(index);
            TimePowerLoanDefs.LoanInfo memory loanInfo = _getLoanInfoAtIndex(debtInfo.loanIndex);
            loans_debts_tranches_amount[1] += uint256(debtInfo.normalizedPrincipal).mulDiv(
                _timePowerLoan._accumulatedInterestRates(loanInfo.interestRateIndex), 1e18, Math.Rounding.Ceil
            );
        }
        for (index = 0; index < loans_debts_tranches_number[2]; index++) {
            TimePowerLoanDefs.TrancheInfo memory trancheInfo = _getTrancheInfoAtIndex(index);
            TimePowerLoanDefs.LoanInfo memory loanInfo = _getLoanInfoAtIndex(trancheInfo.loanIndex);
            loans_debts_tranches_amount[2] += uint256(trancheInfo.normalizedPrincipal).mulDiv(
                _timePowerLoan._accumulatedInterestRates(loanInfo.interestRateIndex), 1e18, Math.Rounding.Ceil
            );
        }
        console.log("Total Amount of Loans   : ", loans_debts_tranches_amount[0]);
        console.log("Total Amount of Debts   : ", loans_debts_tranches_amount[1]);
        console.log("Total Amount of Tranches: ", loans_debts_tranches_amount[2]);
        /// @dev Assert that the total amount difference between loans, debts and tranches is less than 256 (to account for any minor precision loss)
        assertLt(_abs(loans_debts_tranches_amount[0], loans_debts_tranches_amount[1]), 256);
        assertLt(_abs(loans_debts_tranches_amount[1], loans_debts_tranches_amount[2]), 256);
        assertLt(_abs(loans_debts_tranches_amount[2], loans_debts_tranches_amount[0]), 256);
    }

    function afterInvariant() public view {
        console.log("----- TimePowerLoan Handler Counts -----");
        console.log(
            "Union    enters:         ",
            _timePowerLoanHandler.getHandlerEnterCount(TimePowerLoanHandler.HandlerType.UNION)
        );
        console.log(
            "Union    exits(over):    ",
            _timePowerLoanHandler.getHandlerExitCount(TimePowerLoanHandler.HandlerType.UNIN_OVER)
        );
        console.log(
            "Join     enters:         ",
            _timePowerLoanHandler.getHandlerEnterCount(TimePowerLoanHandler.HandlerType.JOIN)
        );
        console.log(
            "Join     exits(over):    ",
            _timePowerLoanHandler.getHandlerExitCount(TimePowerLoanHandler.HandlerType.JOIN_OVER)
        );
        console.log(
            "Request  enters:         ",
            _timePowerLoanHandler.getHandlerEnterCount(TimePowerLoanHandler.HandlerType.REQUEST)
        );
        console.log(
            "Request  exits(borrower):",
            _timePowerLoanHandler.getHandlerExitCount(TimePowerLoanHandler.HandlerType.REQUEST_NO_BORROWER)
        );
        console.log(
            "Request  exits(limit):   ",
            _timePowerLoanHandler.getHandlerExitCount(TimePowerLoanHandler.HandlerType.REQUEST_NO_LIMIT)
        );
        console.log(
            "Request  exits(amount):  ",
            _timePowerLoanHandler.getHandlerExitCount(TimePowerLoanHandler.HandlerType.REQUEST_NO_AMOUNT)
        );
        console.log(
            "Request  exits(over):    ",
            _timePowerLoanHandler.getHandlerExitCount(TimePowerLoanHandler.HandlerType.REQUEST_OVER)
        );
        console.log(
            "Borrow   enters:         ",
            _timePowerLoanHandler.getHandlerEnterCount(TimePowerLoanHandler.HandlerType.BORROW)
        );
        console.log(
            "Borrow   exits(loan):    ",
            _timePowerLoanHandler.getHandlerExitCount(TimePowerLoanHandler.HandlerType.BORROW_NO_LOAN)
        );
        console.log(
            "Borrow   exits(limit):   ",
            _timePowerLoanHandler.getHandlerExitCount(TimePowerLoanHandler.HandlerType.BORROW_NO_LIMIT)
        );
        console.log(
            "Borrow   exits(over):    ",
            _timePowerLoanHandler.getHandlerExitCount(TimePowerLoanHandler.HandlerType.BORROW_OVER)
        );
        console.log(
            "Repay    enters:         ",
            _timePowerLoanHandler.getHandlerEnterCount(TimePowerLoanHandler.HandlerType.REPAY)
        );
        console.log(
            "Repay    exits(no debt): ",
            _timePowerLoanHandler.getHandlerExitCount(TimePowerLoanHandler.HandlerType.REPAY_NO_DEBT)
        );
        console.log(
            "Repay    exits(status):  ",
            _timePowerLoanHandler.getHandlerExitCount(TimePowerLoanHandler.HandlerType.REPAY_STATUS)
        );
        console.log(
            "Repay    exits(over):    ",
            _timePowerLoanHandler.getHandlerExitCount(TimePowerLoanHandler.HandlerType.REPAY_OVER)
        );
        console.log(
            "Default  enters:         ",
            _timePowerLoanHandler.getHandlerEnterCount(TimePowerLoanHandler.HandlerType.DEFAULT)
        );
        console.log(
            "Default  exits(no debt): ",
            _timePowerLoanHandler.getHandlerExitCount(TimePowerLoanHandler.HandlerType.DEFAULT_NO_DEBT)
        );
        console.log(
            "Default  exits(status):  ",
            _timePowerLoanHandler.getHandlerExitCount(TimePowerLoanHandler.HandlerType.DEFAULT_STATUS)
        );
        console.log(
            "Default  exits(over):    ",
            _timePowerLoanHandler.getHandlerExitCount(TimePowerLoanHandler.HandlerType.DEFAULT_OVER)
        );
        console.log(
            "Recovery enters:         ",
            _timePowerLoanHandler.getHandlerEnterCount(TimePowerLoanHandler.HandlerType.RECOVERY)
        );
        console.log(
            "Recovery exits(no debt): ",
            _timePowerLoanHandler.getHandlerExitCount(TimePowerLoanHandler.HandlerType.RECOVERY_NO_DEBT)
        );
        console.log(
            "Recovery exits(status):  ",
            _timePowerLoanHandler.getHandlerExitCount(TimePowerLoanHandler.HandlerType.RECOVERY_STATUS)
        );
        console.log(
            "Recovery exits(over):    ",
            _timePowerLoanHandler.getHandlerExitCount(TimePowerLoanHandler.HandlerType.RECOVERY_OVER)
        );
        console.log(
            "Close    enters:         ",
            _timePowerLoanHandler.getHandlerEnterCount(TimePowerLoanHandler.HandlerType.CLOSE)
        );
        console.log(
            "Close    exits(no debt): ",
            _timePowerLoanHandler.getHandlerExitCount(TimePowerLoanHandler.HandlerType.CLOSE_NO_DEBT)
        );
        console.log(
            "Close    exits(status):  ",
            _timePowerLoanHandler.getHandlerExitCount(TimePowerLoanHandler.HandlerType.CLOSE_STATUS)
        );
        console.log(
            "Close    exits(over):    ",
            _timePowerLoanHandler.getHandlerExitCount(TimePowerLoanHandler.HandlerType.CLOSE_OVER)
        );
        console.log(
            "Time     enters:         ",
            _timePowerLoanHandler.getHandlerEnterCount(TimePowerLoanHandler.HandlerType.TIME)
        );
        console.log(
            "Time     exits(over):    ",
            _timePowerLoanHandler.getHandlerExitCount(TimePowerLoanHandler.HandlerType.TIME_OVER)
        );
    }

    function _abs(uint256 a_, uint256 b_) internal pure returns (uint256) {
        return a_ >= b_ ? a_ - b_ : b_ - a_;
    }

    function _getLoanInfoAtIndex(uint256 loanIndex_)
        internal
        view
        returns (TimePowerLoanDefs.LoanInfo memory loanInfo_)
    {
        (
            loanInfo_.ceilingLimit,
            loanInfo_.remainingLimit,
            loanInfo_.normalizedPrincipal,
            loanInfo_.interestRateIndex,
            loanInfo_.borrowerIndex,
            loanInfo_.status
        ) = _timePowerLoan._allLoans(loanIndex_);
    }

    function _getDebtInfoAtIndex(uint256 debtIndex_)
        internal
        view
        returns (TimePowerLoanDefs.DebtInfo memory debtInfo_)
    {
        (
            debtInfo_.startTime,
            debtInfo_.maturityTime,
            debtInfo_.principal,
            debtInfo_.normalizedPrincipal,
            debtInfo_.loanIndex,
            debtInfo_.status
        ) = _timePowerLoan._allDebts(debtIndex_);
    }

    function _getTrancheInfoAtIndex(uint256 trancheIndex_)
        internal
        view
        returns (TimePowerLoanDefs.TrancheInfo memory trancheInfo_)
    {
        (
            trancheInfo_.vaultIndex,
            trancheInfo_.debtIndex,
            trancheInfo_.loanIndex,
            trancheInfo_.borrowerIndex,
            trancheInfo_.normalizedPrincipal
        ) = _timePowerLoan._allTranches(trancheIndex_);
    }
}
