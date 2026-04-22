// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {FixedTermStakingDefs} from "src/protocols/lender/fixed-term/utils/FixedTermStakingDefs.sol";
import {FixedTermStaking} from "src/protocols/lender/fixed-term/FixedTermStaking.sol";
import {OpenTermStaking} from "src/protocols/lender/open-term/OpenTermStaking.sol";
import {TimeLinearLoan} from "src/protocols/borrower/time-linear/TimeLinearLoan.sol";
import {TimePowerLoan} from "src/protocols/borrower/time-power/TimePowerLoan.sol";

contract TempTest is Test {
    using Strings for uint256;
    using Strings for int256;

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
        uint256 timestamp = 1774508400;
        for (uint256 i = 0; i < 26; i++) {
            console.log(
                string.concat(
                    timestamp.toString(),
                    " | ",
                    int256(_fixedTermStaking._accumulatedInterestRate(uint64(timestamp))).toStringSigned()
                )
            );
            timestamp += 1 days;
        }

        FixedTermStakingDefs.StakeInfo[] memory stakeInfos = new FixedTermStakingDefs.StakeInfo[](2);
        (stakeInfos[0].principal, stakeInfos[0].startDate, stakeInfos[0].maturityDate, stakeInfos[0].status) =
            _fixedTermStaking._tokenId_stakeInfo(6);
        (stakeInfos[1].principal, stakeInfos[1].startDate, stakeInfos[1].maturityDate, stakeInfos[1].status) =
            _fixedTermStaking._tokenId_stakeInfo(7);

        vm.startPrank(_investor);
        console.log("TokenId: 6");
        console.log("Principal:", stakeInfos[0].principal);
        console.log("Maturity Date:", stakeInfos[0].maturityDate);
        console.log(
            "accumulatedInterestRateOnMaturityDate:",
            _fixedTermStaking._accumulatedInterestRate(stakeInfos[0].maturityDate)
        );
        console.log("Start Date:", stakeInfos[0].startDate);
        console.log(
            "accumulatedInterestRateOnStartDate:", _fixedTermStaking._accumulatedInterestRate(stakeInfos[0].startDate)
        );
        _fixedTermStaking.unstake(6);

        console.log("TokenId: 7");
        console.log("Principal:", stakeInfos[1].principal);
        console.log("Maturity Date:", stakeInfos[1].maturityDate);
        console.log(
            "accumulatedInterestRateOnMaturityDate:",
            _fixedTermStaking._accumulatedInterestRate(stakeInfos[1].maturityDate)
        );
        console.log("Start Date:", stakeInfos[1].startDate);
        console.log(
            "accumulatedInterestRateOnStartDate:", _fixedTermStaking._accumulatedInterestRate(stakeInfos[1].startDate)
        );
        _fixedTermStaking.unstake(7);
        vm.stopPrank();
    }
}
