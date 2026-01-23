// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {Whitelist} from "src/whitelist/Whitelist.sol";
import {Blacklist} from "src/blacklist/Blacklist.sol";
import {MultisigWallet} from "src/wallet/multisig/MultisigWallet.sol";
import {MultisigWalletLibs} from "src/wallet/multisig/utils/MultisigWalletLibs.sol";
import {ThresholdWallet} from "src/wallet/threshold/ThresholdWallet.sol";
import {ThresholdWalletLibs} from "src/wallet/threshold/utils/ThresholdWalletLibs.sol";
import {UnderlyingToken} from "src/underlying/UnderlyingToken.sol";
import {ValueInflationVault} from "src/vault/ValueInflationVault.sol";
import {TimePowerLoan} from "src/protocols/borrower/time-power/TimePowerLoan.sol";
import {OpenTermStaking} from "src/protocols/lender/open-term/OpenTermStaking.sol";
import {TimeLinearLoan} from "src/protocols/borrower/time-linear/TimeLinearLoan.sol";
import {UnderlyingTokenExchanger} from "src/underlying/UnderlyingTokenExchanger.sol";
import {FixedTermStaking} from "src/protocols/lender/fixed-term/FixedTermStaking.sol";

import {AssetVault} from "test/mock/AssetVault.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployContractSuit is Script {
    address internal _owner;
    string internal _underlyingTokenName;
    string internal _underlyingTokenSymbol;
    bool internal _enableWhitelist;
    bool internal _enableBlacklist;
    address internal _underlyingAsset;
    string internal _vault1Name;
    string internal _vault1Symbol;
    uint48 internal _vault1MinimumPercentageInALoan;
    uint48 internal _vault1MaximumPercentageInALoan;
    uint64 internal _vault1WeightInAStake;
    string internal _vault2Name;
    string internal _vault2Symbol;
    uint48 internal _vault2MinimumPercentageInALoan;
    uint48 internal _vault2MaximumPercentageInALoan;
    uint64 internal _vault2WeightInAStake;
    uint256 internal _timePowerLoanAllowance;
    uint256 internal _timeLinearLoanAllowance;
    uint64[] internal _timePowerLoanInterestRates;
    uint64[] internal _timeLinearLoanInterestRates;
    uint256 internal _fixedTermLockPeriod;
    uint256 internal _fixedTermStakeFeeRate;
    uint256 internal _fixedTermUnstakeFeeRate;
    uint256 internal _fixedTermStartFeedTime;
    uint256 internal _fixedTermDustBalance;
    uint256 internal _fixedTermMaxSupply;
    string internal _fixedTermTokenName;
    string internal _fixedTermTokenSymbol;
    uint256 internal _openTermStakeFeeRate;
    uint256 internal _openTermUnstakeFeeRate;
    uint256 internal _openTermStartFeedTime;
    uint256 internal _openTermDustBalance;
    uint256 internal _openTermMaxSupply;
    string internal _openTermTokenName;
    string internal _openTermTokenSymbol;
    MultisigWalletLibs.WalletMode internal _multisigWalletMode;
    bytes internal _multisigWalletPublicKey;
    ThresholdWalletLibs.WalletMode internal _thresholdWalletMode;
    bytes[] internal _thresholdWalletPublicKeys;
    bytes[] internal _thresholdWalletMemberIDs;
    uint128 internal _thresholdWalletN;
    uint128 internal _thresholdWalletM;

    Whitelist internal _whitelist;
    Blacklist internal _blacklist;
    UnderlyingToken internal _underlyingToken;
    UnderlyingTokenExchanger internal _underlyingTokenExchanger;
    MultisigWallet internal _multisigWallet;
    ThresholdWallet internal _thresholdWallet;
    FixedTermStaking internal _fixedTermStaking;
    OpenTermStaking internal _openTermStaking;
    TimePowerLoan internal _timePowerLoan;
    TimeLinearLoan internal _timeLinearLoan;
    ValueInflationVault internal _vault1;
    ValueInflationVault internal _vault2;

    function run() external {
        _owner = vm.envAddress("NEXUSFI_OWNER");
        vm.label(_owner, "owner");
        _underlyingTokenName = vm.envString("NEXUSFI_UNDERLYING_TOKEN_NAME");
        _underlyingTokenSymbol = vm.envString("NEXUSFI_UNDERLYING_TOKEN_SYMBOL");
        _enableWhitelist = vm.envBool("NEXUSFI_ENABLE_WHITELIST");
        _enableBlacklist = vm.envBool("NEXUSFI_ENABLE_BLACKLIST");
        _underlyingAsset = vm.envAddress("NEXUSFI_UNDERLYING_ASSET");
        vm.label(_underlyingAsset, "underlyingAsset");
        _vault1Name = vm.envString("NEXUSFI_VAULT_1_NAME");
        _vault1Symbol = vm.envString("NEXUSFI_VAULT_1_SYMBOL");
        _vault1MinimumPercentageInALoan = uint48(vm.envUint("NEXUSFI_VAULT_1_MINIMUM_PERCENTAGE_IN_A_LOAN"));
        _vault1MaximumPercentageInALoan = uint48(vm.envUint("NEXUSFI_VAULT_1_MAXIMUM_PERCENTAGE_IN_A_LOAN"));
        _vault1WeightInAStake = uint64(vm.envUint("NEXUSFI_VAULT_1_WEIGHT_IN_A_STAKE"));
        _vault2Name = vm.envString("NEXUSFI_VAULT_2_NAME");
        _vault2Symbol = vm.envString("NEXUSFI_VAULT_2_SYMBOL");
        _vault2MinimumPercentageInALoan = uint48(vm.envUint("NEXUSFI_VAULT_2_MINIMUM_PERCENTAGE_IN_A_LOAN"));
        _vault2MaximumPercentageInALoan = uint48(vm.envUint("NEXUSFI_VAULT_2_MAXIMUM_PERCENTAGE_IN_A_LOAN"));
        _vault2WeightInAStake = uint64(vm.envUint("NEXUSFI_VAULT_2_WEIGHT_IN_A_STAKE"));
        _timePowerLoanAllowance = vm.envUint("NEXUSFI_TIME_POWER_LOAN_ALLOWANCE");
        _timeLinearLoanAllowance = vm.envUint("NEXUSFI_TIME_LINEAR_LOAN_ALLOWANCE");
        uint256[] memory timePowerLoanInterestRates = vm.envUint("NEXUSFI_TIME_POWER_LOAN_INTEREST_RATES", ",");
        for (uint256 i = 0; i < timePowerLoanInterestRates.length; i++) {
            _timePowerLoanInterestRates.push(uint64(timePowerLoanInterestRates[i]));
        }
        uint256[] memory timeLinearLoanInterestRates = vm.envUint("NEXUSFI_TIME_LINEAR_LOAN_INTEREST_RATES", ",");
        for (uint256 i = 0; i < timeLinearLoanInterestRates.length; i++) {
            _timeLinearLoanInterestRates.push(uint64(timeLinearLoanInterestRates[i]));
        }
        _fixedTermLockPeriod = vm.envUint("NEXUSFI_FIXED_TERM_LOCK_PERIOD");
        _fixedTermStakeFeeRate = vm.envUint("NEXUSFI_FIXED_TERM_STAKE_FEE_RATE");
        _fixedTermUnstakeFeeRate = vm.envUint("NEXUSFI_FIXED_TERM_UNSTAKE_FEE_RATE");
        _fixedTermStartFeedTime = vm.envUint("NEXUSFI_FIXED_TERM_START_FEED_TIME");
        _fixedTermDustBalance = vm.envUint("NEXUSFI_FIXED_TERM_DUST_BALANCE");
        _fixedTermMaxSupply = vm.envUint("NEXUSFI_FIXED_TERM_MAX_SUPPLY");
        _fixedTermTokenName = vm.envString("NEXUSFI_FIXED_TERM_TOKEN_NAME");
        _fixedTermTokenSymbol = vm.envString("NEXUSFI_FIXED_TERM_TOKEN_SYMBOL");
        _openTermStakeFeeRate = vm.envUint("NEXUSFI_OPEN_TERM_STAKE_FEE_RATE");
        _openTermUnstakeFeeRate = vm.envUint("NEXUSFI_OPEN_TERM_UNSTAKE_FEE_RATE");
        _openTermStartFeedTime = vm.envUint("NEXUSFI_OPEN_TERM_START_FEED_TIME");
        _openTermDustBalance = vm.envUint("NEXUSFI_OPEN_TERM_DUST_BALANCE");
        _openTermMaxSupply = vm.envUint("NEXUSFI_OPEN_TERM_MAX_SUPPLY");
        _openTermTokenName = vm.envString("NEXUSFI_OPEN_TERM_TOKEN_NAME");
        _openTermTokenSymbol = vm.envString("NEXUSFI_OPEN_TERM_TOKEN_SYMBOL");
        _multisigWalletMode = MultisigWalletLibs.WalletMode(uint8(vm.envUint("NEXUSFI_MULTISIG_WALLET_PK_ON_G")));
        _multisigWalletPublicKey = vm.envBytes("NEXUSFI_MULTISIG_WALLET_PUBLIC_KEY");
        _thresholdWalletMode = ThresholdWalletLibs.WalletMode(uint8(vm.envUint("NEXUSFI_THRESHOLD_WALLET_PK_ON_G")));
        _thresholdWalletPublicKeys = vm.envBytes("NEXUSFI_THRESHOLD_WALLET_PUBLIC_KEYS", ",");
        _thresholdWalletMemberIDs = vm.envBytes("NEXUSFI_THRESHOLD_WALLET_MEMBER_IDS", ",");
        _thresholdWalletN = uint128(vm.envUint("NEXUSFI_THRESHOLD_WALLET_N"));
        _thresholdWalletM = uint128(vm.envUint("NEXUSFI_THRESHOLD_WALLET_M"));

        vm.startBroadcast();

        _whitelist = Whitelist(deployWhitelist(_owner, _enableWhitelist));
        _blacklist = Blacklist(deployBlacklist(_owner, _enableBlacklist));
        _underlyingToken = UnderlyingToken(deployUnderlyingToken(_owner, _underlyingTokenName, _underlyingTokenSymbol));
        _underlyingTokenExchanger = UnderlyingTokenExchanger(
            deployExchanger(
                [address(_underlyingToken), _underlyingAsset, address(_whitelist), _owner],
                (uint256(1e6) | (uint256(1e6) << 64) | (uint256(1e6) << 128))
            )
        );
        _multisigWallet = MultisigWallet(deployMultisigWallet(_owner, _multisigWalletMode, _multisigWalletPublicKey));
        _thresholdWallet = ThresholdWallet(
            deployThresholdWallet(
                _owner, _thresholdWalletMode, _thresholdWalletM, _thresholdWalletPublicKeys, _thresholdWalletMemberIDs
            )
        );

        /// @dev no trusted borrowers and lenders for vaults
        /// @dev should set them later via governance process
        _vault1 = ValueInflationVault(
            deployValueInflationVault(
                _vault1Name,
                _vault1Symbol,
                [_owner, _underlyingAsset],
                new address[](0),
                new uint256[](0),
                new address[](0)
            )
        );
        /// @dev no trusted borrowers and lenders for vaults
        /// @dev should set them later via governance process
        _vault2 = ValueInflationVault(
            deployValueInflationVault(
                _vault2Name,
                _vault2Symbol,
                [_owner, _underlyingAsset],
                new address[](0),
                new uint256[](0),
                new address[](0)
            )
        );
        FixedTermStaking.AssetInfo[] memory fixedTermAssetsInfoBasket = new FixedTermStaking.AssetInfo[](2);
        fixedTermAssetsInfoBasket[0] =
            FixedTermStaking.AssetInfo({targetVault: address(_vault1), weight: _vault1WeightInAStake});
        fixedTermAssetsInfoBasket[1] =
            FixedTermStaking.AssetInfo({targetVault: address(_vault2), weight: _vault2WeightInAStake});

        _fixedTermStaking = FixedTermStaking(
            deployFixedTermStaking(
                [_owner, address(_underlyingToken), address(_whitelist), address(_underlyingTokenExchanger)],
                (
                    _fixedTermLockPeriod * 1 days | (_fixedTermStakeFeeRate << 64) | (_fixedTermUnstakeFeeRate << 128)
                        | (_fixedTermStartFeedTime << 192)
                ),
                (_fixedTermDustBalance | (_fixedTermMaxSupply << 128)),
                _fixedTermTokenName,
                _fixedTermTokenSymbol,
                fixedTermAssetsInfoBasket
            )
        );
        OpenTermStaking.AssetInfo[] memory openTermAssetsInfoBasket = new OpenTermStaking.AssetInfo[](2);
        openTermAssetsInfoBasket[0] =
            OpenTermStaking.AssetInfo({targetVault: address(_vault1), weight: _vault1WeightInAStake});
        openTermAssetsInfoBasket[1] =
            OpenTermStaking.AssetInfo({targetVault: address(_vault2), weight: _vault2WeightInAStake});
        _openTermStaking = OpenTermStaking(
            deployOpenTermStaking(
                [_owner, address(_underlyingToken), address(_whitelist), address(_underlyingTokenExchanger)],
                ((_openTermStakeFeeRate << 64) | (_openTermUnstakeFeeRate << 128) | (_openTermStartFeedTime << 192)),
                (_openTermDustBalance | (_openTermMaxSupply << 128)),
                _openTermTokenName,
                _openTermTokenSymbol,
                openTermAssetsInfoBasket
            )
        );
        TimePowerLoan.TrustedVault[] memory timePowerLoanTrustedVaults = new TimePowerLoan.TrustedVault[](2);
        timePowerLoanTrustedVaults[0] = TimePowerLoan.TrustedVault({
            vault: address(_vault1),
            minimumPercentage: _vault1MinimumPercentageInALoan,
            maximumPercentage: _vault1MaximumPercentageInALoan
        });
        timePowerLoanTrustedVaults[1] = TimePowerLoan.TrustedVault({
            vault: address(_vault2),
            minimumPercentage: _vault2MinimumPercentageInALoan,
            maximumPercentage: _vault2MaximumPercentageInALoan
        });
        _timePowerLoan = TimePowerLoan(
            deployTimePowerLoan(
                [_owner, address(_whitelist), address(_blacklist), _underlyingAsset],
                _timePowerLoanInterestRates,
                timePowerLoanTrustedVaults
            )
        );
        TimeLinearLoan.TrustedVault[] memory timeLinearLoanTrustedVaults = new TimeLinearLoan.TrustedVault[](2);
        timeLinearLoanTrustedVaults[0] = TimeLinearLoan.TrustedVault({
            vault: address(_vault1),
            minimumPercentage: _vault1MinimumPercentageInALoan,
            maximumPercentage: _vault1MaximumPercentageInALoan
        });
        timeLinearLoanTrustedVaults[1] = TimeLinearLoan.TrustedVault({
            vault: address(_vault2),
            minimumPercentage: _vault2MinimumPercentageInALoan,
            maximumPercentage: _vault2MaximumPercentageInALoan
        });
        _timeLinearLoan = TimeLinearLoan(
            deployTimeLinearLoan(
                [_owner, address(_whitelist), address(_blacklist), _underlyingAsset],
                _timeLinearLoanInterestRates,
                timeLinearLoanTrustedVaults
            )
        );

        vm.stopBroadcast();
    }

    function deployUnderlyingToken(address owner_, string memory name_, string memory symbol_)
        public
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

    function deployWhitelist(address owner_, bool whitelistEnabled_) public returns (address) {
        return address(
            new TransparentUpgradeableProxy(
                address(new Whitelist()),
                owner_,
                abi.encodeWithSelector(Whitelist.initialize.selector, owner_, whitelistEnabled_)
            )
        );
    }

    function deployBlacklist(address owner_, bool blacklistEnabled_) public returns (address) {
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
        address[4] memory addrs_,
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
        string memory name_,
        string memory symbol_,
        FixedTermStaking.AssetInfo[] memory assetsInfoBasket_
    ) public returns (address) {
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
        address[4] memory addrs_,
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
        string memory name_,
        string memory symbol_,
        OpenTermStaking.AssetInfo[] memory assetsInfoBasket_
    ) public returns (address) {
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
        address[4] memory addrs_,
        /**
         * [0~63]: uint64 precision_,
         * [64~127]: uint64 token0_2_token1_rate_,
         * [128~191]: uint64 token1_2_token0_rate_,
         */
        uint256 properties_
    ) public returns (address) {
        return address(
            new TransparentUpgradeableProxy(
                address(new UnderlyingTokenExchanger()),
                addrs_[3],
                abi.encodeWithSelector(UnderlyingTokenExchanger.initialize.selector, addrs_, properties_)
            )
        );
    }

    function deployMultisigWallet(address owner_, MultisigWalletLibs.WalletMode walletMode_, bytes memory publicKey_)
        public
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
        ThresholdWalletLibs.WalletMode walletMode_,
        uint128 threshold_,
        bytes[] memory publicKeys_,
        bytes[] memory memberIDs_
    ) public returns (address) {
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

    function deployAssetVault(address underlyingToken_, string memory name_, string memory symbol_)
        public
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
        address[4] memory addrs_,
        /**
         * annual interest rates sorted in ascending order
         */
        uint64[] memory secondInterestRates_,
        /**
         * vaults that are allowed to lend to borrowers
         */
        TimePowerLoan.TrustedVault[] memory trustedVaults_
    ) public returns (address) {
        return address(
            new TransparentUpgradeableProxy(
                address(new TimePowerLoan()),
                addrs_[0],
                abi.encodeWithSelector(TimePowerLoan.initialize.selector, addrs_, secondInterestRates_, trustedVaults_)
            )
        );
    }

    function deployTimeLinearLoan(
        /**
         * 0: address owner_,
         * 1: address whitelist_,
         * 2: address blacklist_,
         * 3: address loanToken_,
         */
        address[4] memory addrs_,
        /**
         * annual interest rates sorted in ascending order
         */
        uint64[] memory secondInterestRates_,
        /**
         * vaults that are allowed to lend to borrowers
         */
        TimeLinearLoan.TrustedVault[] memory trustedVaults_
    ) public returns (address) {
        return address(
            new TransparentUpgradeableProxy(
                address(new TimeLinearLoan()),
                addrs_[0],
                abi.encodeWithSelector(TimeLinearLoan.initialize.selector, addrs_, secondInterestRates_, trustedVaults_)
            )
        );
    }

    function deployValueInflationVault(
        /**
         * vault token name
         */
        string memory name_,
        /**
         * vault token symbol
         */
        string memory symbol_,
        /**
         * 0: address owner_,
         * 1: address asset_,
         */
        address[2] memory addr_,
        /**
         * trusted borrowers addresses
         */
        address[] memory trustedBorrowers_,
        /**
         * trusted borrowers allowances
         */
        uint256[] memory trustedBorrowersAllowance_,
        /**
         * trusted lenders addresses
         */
        address[] memory trustedLenders
    ) public returns (address) {
        return address(
            new TransparentUpgradeableProxy(
                address(new ValueInflationVault()),
                addr_[0],
                abi.encodeWithSelector(
                    ValueInflationVault.initialize.selector,
                    name_,
                    symbol_,
                    addr_,
                    trustedBorrowers_,
                    trustedBorrowersAllowance_,
                    trustedLenders
                )
            )
        );
    }
}
