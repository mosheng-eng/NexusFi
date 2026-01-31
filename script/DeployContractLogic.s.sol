// SPDX-Licensed-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

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
    function run(uint256 logicIndex_) external returns (address) {
        if (logicIndex_ == 1) {
            Whitelist whitelist = new Whitelist();
            return address(whitelist);
        } else if (logicIndex_ == 2) {
            Blacklist blacklist = new Blacklist();
            return address(blacklist);
        } else if (logicIndex_ == 3) {
            UnderlyingToken underlyingToken = new UnderlyingToken();
            return address(underlyingToken);
        } else if (logicIndex_ == 4) {
            UnderlyingTokenExchanger exchanger = new UnderlyingTokenExchanger();
            return address(exchanger);
        } else if (logicIndex_ == 5) {
            FixedTermStaking fixedTermStaking = new FixedTermStaking();
            return address(fixedTermStaking);
        } else if (logicIndex_ == 6) {
            OpenTermStaking openTermStaking = new OpenTermStaking();
            return address(openTermStaking);
        } else if (logicIndex_ == 7) {
            ValueInflationVault vault = new ValueInflationVault();
            return address(vault);
        } else if (logicIndex_ == 8) {
            TimePowerLoan timePowerLoan = new TimePowerLoan();
            return address(timePowerLoan);
        } else if (logicIndex_ == 9) {
            TimeLinearLoan timeLinearLoan = new TimeLinearLoan();
            return address(timeLinearLoan);
        } else if (logicIndex_ == 10) {
            MultisigWallet multisigWallet = new MultisigWallet();
            return address(multisigWallet);
        } else if (logicIndex_ == 11) {
            ThresholdWallet thresholdWallet = new ThresholdWallet();
            return address(thresholdWallet);
        } else {
            revert("Invalid logic index");
        }
    }
}
