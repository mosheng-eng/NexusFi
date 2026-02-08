// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {Roles} from "src/common/Roles.sol";
import {Whitelist} from "src/whitelist/Whitelist.sol";
import {Blacklist} from "src/blacklist/Blacklist.sol";
import {UnderlyingToken} from "src/underlying/UnderlyingToken.sol";
import {UnderlyingTokenExchanger} from "src/underlying/UnderlyingTokenExchanger.sol";
import {ValueInflationVault} from "src/vault/ValueInflationVault.sol";
import {FixedTermStaking} from "src/protocols/lender/fixed-term/FixedTermStaking.sol";
import {OpenTermStaking} from "src/protocols/lender/open-term/OpenTermStaking.sol";
import {TimePowerLoan} from "src/protocols/borrower/time-power/TimePowerLoan.sol";
import {TimeLinearLoan} from "src/protocols/borrower/time-linear/TimeLinearLoan.sol";
import {MultisigWallet} from "src/wallet/multisig/MultisigWallet.sol";
import {ThresholdWallet} from "src/wallet/threshold/ThresholdWallet.sol";

contract ContractDependencyScript is Script {
    address owner_ = vm.envAddress("NEXUSFI_OWNER");
    Whitelist whitelist_ = Whitelist(vm.envAddress("WHITELIST"));
    Blacklist blacklist_ = Blacklist(vm.envAddress("BLACKLIST"));
    UnderlyingToken underlyingToken_ = UnderlyingToken(vm.envAddress("UNDERLYING_TOKEN"));
    UnderlyingTokenExchanger underlyingTokenExchanger_ =
        UnderlyingTokenExchanger(vm.envAddress("UNDERLYING_TOKEN_EXCHANGER"));
    ValueInflationVault vault1_ = ValueInflationVault(vm.envAddress("VAULT_1"));
    ValueInflationVault vault2_ = ValueInflationVault(vm.envAddress("VAULT_2"));
    FixedTermStaking fixedTermStaking_ = FixedTermStaking(vm.envAddress("FIXED_TERM_STAKING"));
    OpenTermStaking openTermStaking_ = OpenTermStaking(vm.envAddress("OPEN_TERM_STAKING"));
    TimePowerLoan timePowerLoan_ = TimePowerLoan(vm.envAddress("TIME_POWER_LOAN"));
    TimeLinearLoan timeLinearLoan_ = TimeLinearLoan(vm.envAddress("TIME_LINEAR_LOAN"));
    MultisigWallet multisigWallet_ = MultisigWallet(vm.envAddress("MULTISIG_WALLET"));
    ThresholdWallet thresholdWallet_ = ThresholdWallet(vm.envAddress("THRESHOLD_WALLET"));

    function run() external {
        vm.label(owner_, "Owner");
        vm.label(address(whitelist_), "Whitelist");
        vm.label(address(blacklist_), "Blacklist");
        vm.label(address(underlyingToken_), "Underlying Token");
        vm.label(address(underlyingTokenExchanger_), "Underlying Token Exchanger");
        vm.label(address(vault1_), "Value Inflation Vault 1");
        vm.label(address(vault2_), "Value Inflation Vault 2");
        vm.label(address(fixedTermStaking_), "Fixed Term Staking");
        vm.label(address(openTermStaking_), "Open Term Staking");
        vm.label(address(timePowerLoan_), "Time Power Loan");
        vm.label(address(timeLinearLoan_), "Time Linear Loan");
        vm.label(address(multisigWallet_), "Multisig Wallet");
        vm.label(address(thresholdWallet_), "Threshold Wallet");
        /**
         * whitelist.grantRole(_owner, operator_role)
         * blacklist.grantRole(_owner, operator_role)
         * underlyingToken.grantRole(_underlyingTokenExchanger, operator_role)
         * underlyingToken.grantRole(_fixedTermStaking, operator_role)
         * underlyingToken.grantRole(_openTermStaking, operator_role)
         * underlyingTokenExchanger.grantRole(_fixedTermStaking, investment_manager_role)
         * underlyingTokenExchanger.grantRole(_openTermStaking, investment_manager_role)
         * _valueInflationVault1.grantRole(_owner, operator_role)
         * _valueInfaltionVault1.addTrustedLender(_fixedTermStaking)
         * _valueInfaltionVault1.addTrustedLender(_openTermStaking)
         * _valueInflationVault1.addTrustedBorrower(_timeLinearLoan)
         * _valueInflationVault1.approveTrustedBorrower(_timeLinearLoan, allowance)
         * _valueInflationVault1.addTrustedBorrower(_timePowerLoan)
         * _valueInflationVault1.approveTrustedBorrower(_timePowerLoan, allowance)
         * _valueInflationVault2.grantRole(_owner, operator_role)
         * _valueInfaltionVault2.addTrustedLender(_fixedTermStaking)
         * _valueInfaltionVault2..addTrustedLender(_openTermStaking)
         * _valueInflationVault2.addTrustedBorrower(_timeLinearLoan)
         * _valueInflationVault2.approveTrustedBorrower(_timeLinearLoan, allowance)
         * _valudInflationVault2.addTrustedBorrower(_timeLinearLoan)
         * _valueInflationVault2.approveTrustedBorrower(_timePowerLoan, allowance)
         * _timePowerLoan.grantRole(_owner, operator_role)
         * _timeLinearLoan.grantRole(_owner, operator_role)
         */
        vm.startBroadcast();

        AccessControlUpgradeable(address(whitelist_)).grantRole(Roles.OPERATOR_ROLE, owner_);
        AccessControlUpgradeable(address(blacklist_)).grantRole(Roles.OPERATOR_ROLE, owner_);

        AccessControlUpgradeable(address(underlyingToken_)).grantRole(
            Roles.OPERATOR_ROLE, address(underlyingTokenExchanger_)
        );
        AccessControlUpgradeable(address(underlyingToken_)).grantRole(Roles.OPERATOR_ROLE, address(fixedTermStaking_));
        AccessControlUpgradeable(address(underlyingToken_)).grantRole(Roles.OPERATOR_ROLE, address(openTermStaking_));

        AccessControlUpgradeable(address(underlyingTokenExchanger_)).grantRole(
            Roles.INVESTMENT_MANAGER_ROLE, address(fixedTermStaking_)
        );
        AccessControlUpgradeable(address(underlyingTokenExchanger_)).grantRole(
            Roles.INVESTMENT_MANAGER_ROLE, address(openTermStaking_)
        );

        AccessControlUpgradeable(address(vault1_)).grantRole(Roles.OPERATOR_ROLE, owner_);
        vault1_.addTrustedLender(address(fixedTermStaking_));
        vault1_.addTrustedLender(address(openTermStaking_));
        vault1_.addTrustedBorrower(address(timeLinearLoan_));
        vault1_.approveTrustedBorrower(address(timeLinearLoan_), 10_000_000_000); // 10,000 USDC
        vault1_.addTrustedBorrower(address(timePowerLoan_));
        vault1_.approveTrustedBorrower(address(timePowerLoan_), 10_000_000_000); // 10,000 USDC

        AccessControlUpgradeable(address(vault2_)).grantRole(Roles.OPERATOR_ROLE, owner_);
        vault2_.addTrustedLender(address(fixedTermStaking_));
        vault2_.addTrustedLender(address(openTermStaking_));
        vault2_.addTrustedBorrower(address(timeLinearLoan_));
        vault2_.approveTrustedBorrower(address(timeLinearLoan_), 10_000_000_000); // 10,000 USDC
        vault2_.addTrustedBorrower(address(timePowerLoan_));
        vault2_.approveTrustedBorrower(address(timePowerLoan_), 10_000_000_000); // 10,000 USDC

        AccessControlUpgradeable(address(timePowerLoan_)).grantRole(Roles.OPERATOR_ROLE, owner_);
        AccessControlUpgradeable(address(timeLinearLoan_)).grantRole(Roles.OPERATOR_ROLE, owner_);

        AccessControlUpgradeable(address(multisigWallet_)).grantRole(Roles.OPERATOR_ROLE, owner_);
        AccessControlUpgradeable(address(thresholdWallet_)).grantRole(Roles.OPERATOR_ROLE, owner_);
        AccessControlUpgradeable(address(fixedTermStaking_)).grantRole(Roles.OPERATOR_ROLE, owner_);
        AccessControlUpgradeable(address(openTermStaking_)).grantRole(Roles.OPERATOR_ROLE, owner_);

        vm.stopBroadcast();
    }
}
