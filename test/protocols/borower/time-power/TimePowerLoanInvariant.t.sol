// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {TimePowerLoan} from "src/protocols/borrower/time-power/TimePowerLoan.sol";
import {TimePowerLoanHandler} from "test/protocols/borower/time-power/handler/TimePowerLoanHandler.sol";

contract TimePowerLoanInvariant is Test {
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

    function testDebug() public {
        _timePowerLoanHandler.unionHandler5(
            address(0xae0ec28d16b76a2dF98AC70100453A6066Bf6900), 18762, 4067, 14327, 2276, 17252, 3478257374079577870
        );
    }

    function invariantTotalDebtAlwayEqualBetweenBorrowersAndVaults() public {
        uint256 totalBorrowers = _timePowerLoan.getTotalTrustedBorrowers();
        uint256 totalVaults = _timePowerLoan.getTotalTrustedVaults();
        uint256 totalDebtOfBorrowers = 0;
        uint256 totalDebtOfVaults = 0;
        for (uint64 i = 0; i < totalBorrowers; i++) {
            totalDebtOfBorrowers += _timePowerLoan.totalDebtOfBorrower(_timePowerLoan.getBorrowerAtIndex(i));
        }
        for (uint64 j = 0; j < totalVaults; j++) {
            totalDebtOfVaults += _timePowerLoan.totalDebtOfVault(_timePowerLoan.getVaultAtIndex(j));
        }
        console.log("Total Debt of Borrowers: ", totalDebtOfBorrowers);
        console.log("Total Debt of Vaults   : ", totalDebtOfVaults);
        /// @dev Assert that the total debt difference between borrowers and vaults is less than 256 (to account for any minor precision loss)
        assertLt(_abs(totalDebtOfBorrowers, totalDebtOfVaults), 256);
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
}
