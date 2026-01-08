// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {TimeLinearLoan} from "src/protocols/borrower/time-linear/TimeLinearLoan.sol";
import {TimeLinearLoanHandler} from "test/protocols/borrower/time-linear/handler/TimeLinearLoanHandler.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract TimeLinearLoanInvariant is Test {
    using Math for uint256;

    TimeLinearLoanHandler internal _timeLinearLoanHandler;
    TimeLinearLoan internal _timeLinearLoan;

    function setUp() public {
        _timeLinearLoanHandler = new TimeLinearLoanHandler();
        vm.label(address(_timeLinearLoanHandler), "TimeLinearLoanHandler");

        _timeLinearLoan = _timeLinearLoanHandler.getTimeLinearLoan();
        vm.label(address(_timeLinearLoan), "TimeLinearLoan");

        bytes4[] memory targetSelectors = new bytes4[](10);
        targetSelectors[0] = TimeLinearLoanHandler.unionHandler1.selector;
        targetSelectors[1] = TimeLinearLoanHandler.unionHandler2.selector;
        targetSelectors[2] = TimeLinearLoanHandler.unionHandler3.selector;
        targetSelectors[3] = TimeLinearLoanHandler.unionHandler4.selector;
        targetSelectors[4] = TimeLinearLoanHandler.unionHandler5.selector;
        targetSelectors[5] = TimeLinearLoanHandler.timeHandler.selector;
        targetSelectors[6] = TimeLinearLoanHandler.repayHandler.selector;
        targetSelectors[7] = TimeLinearLoanHandler.defaultHandler.selector;
        targetSelectors[8] = TimeLinearLoanHandler.recoveryHandler.selector;
        targetSelectors[9] = TimeLinearLoanHandler.closeHandler.selector;
        targetSelector(StdInvariant.FuzzSelector({addr: address(_timeLinearLoanHandler), selectors: targetSelectors}));
        targetContract(address(_timeLinearLoanHandler));
    }

    function testDebug() public {}

    function invariantTotalDebtAlwayEqualBetweenBorrowersAndVaults() public {
        uint256 totalBorrowers = _timeLinearLoan.getTotalTrustedBorrowers();
        uint256 totalVaults = _timeLinearLoan.getTotalTrustedVaults();
        uint256 totalDebtOfBorrowers = 0;
        uint256 totalDebtOfVaults = 0;
        for (uint64 i = 0; i < totalBorrowers; i++) {
            totalDebtOfBorrowers += _timeLinearLoan.totalDebtOfBorrower(_timeLinearLoan.getBorrowerAtIndex(i));
        }
        for (uint64 j = 0; j < totalVaults; j++) {
            totalDebtOfVaults += _timeLinearLoan.totalDebtOfVault(_timeLinearLoan.getVaultAtIndex(j));
        }
        console.log("Total Debt of Borrowers: ", totalDebtOfBorrowers);
        console.log("Total Debt of Vaults   : ", totalDebtOfVaults);
        /// @dev Assert that the total debt difference between borrowers and vaults is less than 256 (to account for any minor precision loss)
        assertLt(_abs(totalDebtOfBorrowers, totalDebtOfVaults), 512);
    }

    function afterInvariant() public view {
        console.log("----- TimeLinearLoan Handler Counts -----");
        console.log(
            "Union    enters:         ",
            _timeLinearLoanHandler.getHandlerEnterCount(TimeLinearLoanHandler.HandlerType.UNION)
        );
        console.log(
            "Union    exits(over):    ",
            _timeLinearLoanHandler.getHandlerExitCount(TimeLinearLoanHandler.HandlerType.UNIN_OVER)
        );
        console.log(
            "Join     enters:         ",
            _timeLinearLoanHandler.getHandlerEnterCount(TimeLinearLoanHandler.HandlerType.JOIN)
        );
        console.log(
            "Join     exits(over):    ",
            _timeLinearLoanHandler.getHandlerExitCount(TimeLinearLoanHandler.HandlerType.JOIN_OVER)
        );
        console.log(
            "Request  enters:         ",
            _timeLinearLoanHandler.getHandlerEnterCount(TimeLinearLoanHandler.HandlerType.REQUEST)
        );
        console.log(
            "Request  exits(borrower):",
            _timeLinearLoanHandler.getHandlerExitCount(TimeLinearLoanHandler.HandlerType.REQUEST_NO_BORROWER)
        );
        console.log(
            "Request  exits(limit):   ",
            _timeLinearLoanHandler.getHandlerExitCount(TimeLinearLoanHandler.HandlerType.REQUEST_NO_LIMIT)
        );
        console.log(
            "Request  exits(amount):  ",
            _timeLinearLoanHandler.getHandlerExitCount(TimeLinearLoanHandler.HandlerType.REQUEST_NO_AMOUNT)
        );
        console.log(
            "Request  exits(over):    ",
            _timeLinearLoanHandler.getHandlerExitCount(TimeLinearLoanHandler.HandlerType.REQUEST_OVER)
        );
        console.log(
            "Borrow   enters:         ",
            _timeLinearLoanHandler.getHandlerEnterCount(TimeLinearLoanHandler.HandlerType.BORROW)
        );
        console.log(
            "Borrow   exits(loan):    ",
            _timeLinearLoanHandler.getHandlerExitCount(TimeLinearLoanHandler.HandlerType.BORROW_NO_LOAN)
        );
        console.log(
            "Borrow   exits(limit):   ",
            _timeLinearLoanHandler.getHandlerExitCount(TimeLinearLoanHandler.HandlerType.BORROW_NO_LIMIT)
        );
        console.log(
            "Borrow   exits(over):    ",
            _timeLinearLoanHandler.getHandlerExitCount(TimeLinearLoanHandler.HandlerType.BORROW_OVER)
        );
        console.log(
            "Repay    enters:         ",
            _timeLinearLoanHandler.getHandlerEnterCount(TimeLinearLoanHandler.HandlerType.REPAY)
        );
        console.log(
            "Repay    exits(no debt): ",
            _timeLinearLoanHandler.getHandlerExitCount(TimeLinearLoanHandler.HandlerType.REPAY_NO_DEBT)
        );
        console.log(
            "Repay    exits(status):  ",
            _timeLinearLoanHandler.getHandlerExitCount(TimeLinearLoanHandler.HandlerType.REPAY_STATUS)
        );
        console.log(
            "Repay    exits(over):    ",
            _timeLinearLoanHandler.getHandlerExitCount(TimeLinearLoanHandler.HandlerType.REPAY_OVER)
        );
        console.log(
            "Default  enters:         ",
            _timeLinearLoanHandler.getHandlerEnterCount(TimeLinearLoanHandler.HandlerType.DEFAULT)
        );
        console.log(
            "Default  exits(no debt): ",
            _timeLinearLoanHandler.getHandlerExitCount(TimeLinearLoanHandler.HandlerType.DEFAULT_NO_DEBT)
        );
        console.log(
            "Default  exits(status):  ",
            _timeLinearLoanHandler.getHandlerExitCount(TimeLinearLoanHandler.HandlerType.DEFAULT_STATUS)
        );
        console.log(
            "Default  exits(over):    ",
            _timeLinearLoanHandler.getHandlerExitCount(TimeLinearLoanHandler.HandlerType.DEFAULT_OVER)
        );
        console.log(
            "Recovery enters:         ",
            _timeLinearLoanHandler.getHandlerEnterCount(TimeLinearLoanHandler.HandlerType.RECOVERY)
        );
        console.log(
            "Recovery exits(no debt): ",
            _timeLinearLoanHandler.getHandlerExitCount(TimeLinearLoanHandler.HandlerType.RECOVERY_NO_DEBT)
        );
        console.log(
            "Recovery exits(status):  ",
            _timeLinearLoanHandler.getHandlerExitCount(TimeLinearLoanHandler.HandlerType.RECOVERY_STATUS)
        );
        console.log(
            "Recovery exits(over):    ",
            _timeLinearLoanHandler.getHandlerExitCount(TimeLinearLoanHandler.HandlerType.RECOVERY_OVER)
        );
        console.log(
            "Close    enters:         ",
            _timeLinearLoanHandler.getHandlerEnterCount(TimeLinearLoanHandler.HandlerType.CLOSE)
        );
        console.log(
            "Close    exits(no debt): ",
            _timeLinearLoanHandler.getHandlerExitCount(TimeLinearLoanHandler.HandlerType.CLOSE_NO_DEBT)
        );
        console.log(
            "Close    exits(status):  ",
            _timeLinearLoanHandler.getHandlerExitCount(TimeLinearLoanHandler.HandlerType.CLOSE_STATUS)
        );
        console.log(
            "Close    exits(over):    ",
            _timeLinearLoanHandler.getHandlerExitCount(TimeLinearLoanHandler.HandlerType.CLOSE_OVER)
        );
        console.log(
            "Time     enters:         ",
            _timeLinearLoanHandler.getHandlerEnterCount(TimeLinearLoanHandler.HandlerType.TIME)
        );
        console.log(
            "Time     exits(over):    ",
            _timeLinearLoanHandler.getHandlerExitCount(TimeLinearLoanHandler.HandlerType.TIME_OVER)
        );
    }

    function _abs(uint256 a_, uint256 b_) internal pure returns (uint256) {
        return a_ >= b_ ? a_ - b_ : b_ - a_;
    }
}
