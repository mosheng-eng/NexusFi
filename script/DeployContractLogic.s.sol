// SPDX-Licensed-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";

import {Whitelist} from "src/whitelist/Whitelist.sol";
import {Blacklist} from "src/blacklist/Blacklist.sol";
import {UnderlyingToken} from "src/underlying/UnderlyingToken.sol";
import {ValueInflationVault} from "src/vault/ValueInflationVault.sol";
import {MultisigWallet} from "src/wallet/multisig/MultisigWallet.sol";
import {ThresholdWallet} from "src/wallet/threshold/ThresholdWallet.sol";
import {TimePowerLoan} from "src/protocols/borrower/time-power/TimePowerLoan.sol";
import {OpenTermStaking} from "src/protocols/lender/open-term/OpenTermStaking.sol";
import {TimeLinearLoan} from "src/protocols/borrower/time-linear/TimeLinearLoan.sol";
import {UnderlyingTokenExchanger} from "src/underlying/UnderlyingTokenExchanger.sol";
import {FixedTermStaking} from "src/protocols/lender/fixed-term/FixedTermStaking.sol";

contract DeployContractLogic is Script {
    /**
     * 1 - Whitelist
     * 2 - Blacklist
     * 3 - UnderlyingToken
     * 4 - UnderlyingTokenExchanger
     * 5 - FixedTermStaking
     * 6 - OpenTermStaking
     * 7 - ValueInflationVault
     * 8 - TimePowerLoan
     * 9 - TimeLinearLoan
     * 10 - MultisigWallet
     * 11 - ThresholdWallet
     */
    function run() external returns (address logic_) {
        uint256 logicIndex = vm.envUint("LOGIC_INDEX");
        console.log(logicIndex);

        vm.startBroadcast();

        if (logicIndex == 1) {
            logic_ = address(new Whitelist());
        } else if (logicIndex == 2) {
            logic_ = address(new Blacklist());
        } else if (logicIndex == 3) {
            logic_ = address(new UnderlyingToken());
        } else if (logicIndex == 4) {
            logic_ = address(new UnderlyingTokenExchanger());
        } else if (logicIndex == 5) {
            logic_ = address(new FixedTermStaking());
        } else if (logicIndex == 6) {
            logic_ = address(new OpenTermStaking());
        } else if (logicIndex == 7) {
            logic_ = address(new ValueInflationVault());
        } else if (logicIndex == 8) {
            logic_ = address(new TimePowerLoan());
        } else if (logicIndex == 9) {
            logic_ = address(new TimeLinearLoan());
        } else if (logicIndex == 10) {
            logic_ = address(new MultisigWallet());
        } else if (logicIndex == 11) {
            logic_ = address(new ThresholdWallet());
        } else {
            revert("Invalid logic index");
        }

        vm.stopBroadcast();
    }
}
