// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {UnderlyingToken} from "src/underlying/UnderlyingToken.sol";
import {Whitelist} from "src/whitelist/Whitelist.sol";
import {Blacklist} from "src/blacklist/Blacklist.sol";
import {FixedTermStaking} from "src/protocols/lender/fixed-term/FixedTermStaking.sol";
import {OpenTermStaking} from "src/protocols/lender/open-term/OpenTermStaking.sol";
import {TimePowerLoan} from "src/protocols/borrower/time-power/TimePowerLoan.sol";
import {UnderlyingTokenExchanger} from "src/underlying/UnderlyingTokenExchanger.sol";
import {MultisigWallet} from "src/multisig/MultisigWallet.sol";
import {ThresholdWallet} from "src/multisig/ThresholdWallet.sol";

import {AssetVault} from "test/mock/AssetVault.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployContractSuit is Script {
    function run() external {
        vm.startBroadcast();

        vm.stopBroadcast();
    }

    function deployUnderlyingToken(address owner_, string memory name_, string memory symbol_)
        external
        returns (address)
    {
        return address(
            new TransparentUpgradeableProxy(
                address(new UnderlyingToken()),
                owner_,
                abi.encodeWithSelector(UnderlyingToken.initialize.selector, owner_, name_, symbol_)
            )
        );
    }

    function deployWhitelist(address owner_, bool whitelistEnabled_) external returns (address) {
        return address(
            new TransparentUpgradeableProxy(
                address(new Whitelist()),
                owner_,
                abi.encodeWithSelector(Whitelist.initialize.selector, owner_, whitelistEnabled_)
            )
        );
    }

    function deployBlacklist(address owner_, bool blacklistEnabled_) external returns (address) {
        return address(
            new TransparentUpgradeableProxy(
                address(new Blacklist()),
                owner_,
                abi.encodeWithSelector(Blacklist.initialize.selector, owner_, blacklistEnabled_)
            )
        );
    }

    function deployFixedTermStaking(
        /**
         * 0: address owner_,
         * 1: address underlyingToken_,
         * 2: address whitelist_,
         * 3: address exchanger_,
         */
        address[4] calldata addrs_,
        /**
         * [0~63]: uint64 lockPeriod_,
         * [64~127]: uint64 stakeFeeRate_,
         * [128~191]: uint64 unstakeFeeRate_,
         * [192~255]: uint64 startFeedTime_
         */
        uint256 properties_,
        /**
         * [0~127]: uint128 dustBalance_,
         * [128~255]: uint128 maxSupply_,
         */
        uint256 limits_,
        string calldata name_,
        string calldata symbol_,
        FixedTermStaking.AssetInfo[] calldata assetsInfoBasket_
    ) external returns (address) {
        return address(
            new TransparentUpgradeableProxy(
                address(new FixedTermStaking()),
                addrs_[0],
                abi.encodeWithSelector(
                    FixedTermStaking.initialize.selector,
                    addrs_,
                    properties_,
                    limits_,
                    name_,
                    symbol_,
                    assetsInfoBasket_
                )
            )
        );
    }

    function deployOpenTermStaking(
        /**
         * 0: address owner_,
         * 1: address underlyingToken_,
         * 2: address whitelist_,
         * 3: address exchanger_,
         */
        address[4] calldata addrs_,
        /**
         * [0~63]: uint64 reserveField_,
         * [64~127]: uint64 stakeFeeRate_,
         * [128~191]: uint64 unstakeFeeRate_,
         * [192~255]: uint64 startFeedTime_
         */
        uint256 properties_,
        /**
         * [0~127]: uint128 dustBalance_,
         * [128~255]: uint128 maxSupply_,
         */
        uint256 limits_,
        string calldata name_,
        string calldata symbol_,
        OpenTermStaking.AssetInfo[] calldata assetsInfoBasket_
    ) external returns (address) {
        return address(
            new TransparentUpgradeableProxy(
                address(new OpenTermStaking()),
                addrs_[0],
                abi.encodeWithSelector(
                    OpenTermStaking.initialize.selector, addrs_, properties_, limits_, name_, symbol_, assetsInfoBasket_
                )
            )
        );
    }

    function deployExchanger(
        /**
         * 0: address token0_,
         * 1: address token1_,
         * 2: address whitelist_,
         * 3: address owner_,
         */
        address[4] calldata addrs_,
        /**
         * [0~63]: uint64 precision_,
         * [64~127]: uint64 token0_2_token1_rate_,
         * [128~191]: uint64 token1_2_token0_rate_,
         */
        uint256 properties_
    ) external returns (address) {
        return address(
            new TransparentUpgradeableProxy(
                address(new UnderlyingTokenExchanger()),
                addrs_[3],
                abi.encodeWithSelector(UnderlyingTokenExchanger.initialize.selector, addrs_, properties_)
            )
        );
    }

    function deployMultisigWallet(address owner_, MultisigWallet.WalletMode walletMode_, bytes calldata publicKey_)
        external
        returns (address)
    {
        return address(
            new TransparentUpgradeableProxy(
                address(new MultisigWallet()),
                owner_,
                abi.encodeWithSelector(MultisigWallet.initialize.selector, walletMode_, publicKey_)
            )
        );
    }

    function deployThresholdWallet(
        address owner_,
        ThresholdWallet.WalletMode walletMode_,
        uint128 threshold_,
        bytes[] calldata publicKeys_,
        bytes[] calldata memberIDs_
    ) external returns (address) {
        return address(
            new TransparentUpgradeableProxy(
                address(new ThresholdWallet()),
                owner_,
                abi.encodeWithSelector(
                    ThresholdWallet.initialize.selector, walletMode_, threshold_, publicKeys_, memberIDs_
                )
            )
        );
    }

    function deployAssetVault(address underlyingToken_, string calldata name_, string calldata symbol_)
        external
        returns (address)
    {
        return address(new AssetVault(IERC20(underlyingToken_), name_, symbol_));
    }

    function deployTimePowerLoan(
        /**
         * 0: address owner_,
         * 1: address whitelist_,
         * 2: address blacklist_,
         * 3: address loanToken_,
         */
        address[] memory addrs_,
        /**
         * annual interest rates sorted in ascending order
         */
        uint64[] memory secondInterestRates_,
        /**
         * vaults that are allowed to lend to borrowers
         */
        TimePowerLoan.TrustedVault[] memory trustedVaults_
    ) external returns (address) {
        return address(
            new TransparentUpgradeableProxy(
                address(new TimePowerLoan()),
                addrs_[0],
                abi.encodeWithSelector(TimePowerLoan.initialize.selector, addrs_, secondInterestRates_, trustedVaults_)
            )
        );
    }
}
