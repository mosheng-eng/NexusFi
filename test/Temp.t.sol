// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {FixedTermStaking} from "src/protocols/lender/fixed-term/FixedTermStaking.sol";
import {OpenTermStaking} from "src/protocols/lender/open-term/OpenTermStaking.sol";
import {TimeLinearLoan} from "src/protocols/borrower/time-linear/TimeLinearLoan.sol";
import {TimePowerLoan} from "src/protocols/borrower/time-power/TimePowerLoan.sol";

contract TempTest is Test {
    address internal _investor;
    address internal _borrower;
    OpenTermStaking internal _openTermStaking;
    FixedTermStaking internal _fixedTermStaking;
    TimeLinearLoan internal _timeLinearLoan;
    TimePowerLoan internal _timePowerLoan;

    function setUp() public {
        _investor = vm.envAddress("NEXUSFI_OWNER");
        _borrower = vm.envAddress("NEXUSFI_BORROWER");
        _openTermStaking = OpenTermStaking(vm.envAddress("OPEN_TERM_STAKING"));
        _fixedTermStaking = FixedTermStaking(vm.envAddress("FIXED_TERM_STAKING"));
        _timeLinearLoan = TimeLinearLoan(vm.envAddress("TIME_LINEAR_LOAN"));
        _timePowerLoan = TimePowerLoan(vm.envAddress("TIME_POWER_LOAN"));

        vm.label(_investor, "Investor");
        vm.label(_borrower, "Borrower");
        vm.label(address(_openTermStaking), "OpenTermStaking");
        vm.label(address(_fixedTermStaking), "FixedTermStaking");
        vm.label(address(_timeLinearLoan), "TimeLinearLoan");
        vm.label(address(_timePowerLoan), "TimePowerLoan");
    }

    function testTemp() public {
        vm.prank(_borrower);
        _timeLinearLoan.repay(0, 1500000);
    }
}
