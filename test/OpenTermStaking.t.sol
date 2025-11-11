// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {stdStorage, StdStorage, Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {OpenTermStaking} from "src/protocols/open-term/OpenTermStaking.sol";
import {OpenTermToken} from "src/protocols/open-term/OpenTermToken.sol";
import {UnderlyingToken} from "src/underlying/UnderlyingToken.sol";
import {IWhitelist} from "src/whitelist/IWhitelist.sol";
import {Whitelist} from "src/whitelist/Whitelist.sol";
import {Roles} from "src/common/Roles.sol";
import {Errors} from "src/common/Errors.sol";
import {UnderlyingTokenExchanger} from "src/underlying/UnderlyingTokenExchanger.sol";

import {AssetVault} from "test/mock/AssetVault.sol";
import {DepositAsset} from "test/mock/DepositAsset.sol";

import {DeployContractSuit} from "script/DeployContractSuit.s.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract OpenTermStakingTest is Test {
    using stdStorage for StdStorage;

    DeployContractSuit internal _deployer = new DeployContractSuit();
    OpenTermStaking internal _openTermStaking;
    UnderlyingToken internal _underlyingToken;
    Whitelist internal _whitelist;
    OpenTermStaking.AssetInfo[] internal _assetsInfoBasket;
    DepositAsset internal _depositToken;
    UnderlyingTokenExchanger internal _exchanger;

    address internal _owner = makeAddr("owner");
    address internal _whitelistedUser1 = makeAddr("whitelistedUser1");
    address internal _whitelistedUser2 = makeAddr("whitelistedUser2");
    address internal _nonWhitelistedUser1 = makeAddr("nonWhitelistedUser1");
    address internal _nonWhitelistedUser2 = makeAddr("nonWhitelistedUser2");

    uint64 internal _stakeFeeRate = 1_000; // in base points, 0.1%
    uint64 internal _unstakeFeeRate = 1_000; // in base points, 0.2%
    uint64 internal _startFeedTime = 1759301999; // 2025-10-01 14:59:59 UTC+8
    uint64 internal _currentTime = _startFeedTime - 1 days; // 2025-09-30 14:59:59 UTC+8
    uint128 internal _dustBalance = 1_000 * 10 ** 6; // 1,000 USDC
    uint128 internal _maxSupply = 1_000_000_000 * 10 ** 6; // 1 billion USDC

    modifier timeBegin() {
        vm.warp(_currentTime);
        _;
    }

    modifier oneDayPassed() {
        vm.warp(_currentTime += 1 days);
        _;
    }

    modifier deployUnderlyingToken() {
        vm.startPrank(_owner);

        _underlyingToken = UnderlyingToken(_deployer.deployUnderlyingToken(_owner, "lbUSD", "lbUSD"));

        _underlyingToken.grantRole(Roles.OPERATOR_ROLE, address(_owner));

        vm.stopPrank();

        vm.label(address(_underlyingToken), "lbUSD");

        _;
    }

    modifier deployWhitelist() {
        vm.startPrank(_owner);

        _whitelist = Whitelist(_deployer.deployWhitelist(_owner, true));

        _whitelist.grantRole(Roles.OPERATOR_ROLE, address(_owner));

        _whitelist.add(_whitelistedUser1);
        _whitelist.add(_whitelistedUser2);

        vm.stopPrank();

        vm.label(address(_whitelist), "Whitelist");
        vm.label(_whitelistedUser1, "whitelistedUser1");
        vm.label(_whitelistedUser2, "whitelistedUser2");
        vm.label(_nonWhitelistedUser1, "nonWhitelistedUser1");
        vm.label(_nonWhitelistedUser2, "nonWhitelistedUser2");

        _;
    }

    modifier deployOpenTermStaking() {
        _assetsInfoBasket.push(
            OpenTermStaking.AssetInfo({
                targetVault: address(new AssetVault(IERC20(address(_depositToken)), "MMF@lbUSD", "MMF@lbUSD")),
                weight: 500_000 // 50%
            })
        );

        _assetsInfoBasket.push(
            OpenTermStaking.AssetInfo({
                targetVault: address(new AssetVault(IERC20(address(_depositToken)), "RWA@lbUSD", "RWA@lbUSD")),
                weight: 500_000 // 50%
            })
        );

        vm.startPrank(_owner);

        _openTermStaking = OpenTermStaking(
            _deployer.deployOpenTermStaking(
                [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
                ((uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128) | (uint256(_startFeedTime) << 192)),
                (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
                "lbUSD+",
                "lbUSD+",
                _assetsInfoBasket
            )
        );

        _openTermStaking.grantRole(Roles.OPERATOR_ROLE, _owner);

        vm.stopPrank();

        vm.label(address(_openTermStaking), "lbUSD+");
        vm.label(address(_assetsInfoBasket[0].targetVault), "MMF@lbUSD");
        vm.label(address(_assetsInfoBasket[1].targetVault), "RWA@lbUSD");

        _;
    }

    modifier deployDepositToken() {
        _depositToken = new DepositAsset("USD Coin", "USDC");

        _depositToken.mint(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _depositToken.mint(_whitelistedUser2, 1_000_000 * 10 ** 6);
        _depositToken.mint(_nonWhitelistedUser1, 1_000_000 * 10 ** 6);
        _depositToken.mint(_nonWhitelistedUser2, 1_000_000 * 10 ** 6);
        _depositToken.mint(_owner, 1_000_000_000_000_000 * 10 ** 6);

        vm.label(address(_depositToken), "USDC");

        _;
    }

    modifier deployExchanger() {
        address[4] memory addrs = [address(_underlyingToken), address(_depositToken), address(_whitelist), _owner];
        uint256 properties = (uint256(1e6) | (uint256(1e6) << 64) | (uint256(1e6) << 128));

        vm.startPrank(_owner);

        _exchanger = UnderlyingTokenExchanger(_deployer.deployExchanger(addrs, properties));

        _exchanger.grantRole(Roles.OPERATOR_ROLE, address(_owner));

        vm.stopPrank();

        vm.label(address(_exchanger), "Exchanger");

        _;
    }

    modifier setContractDependencies() {
        vm.startPrank(_owner);

        _underlyingToken.grantRole(Roles.OPERATOR_ROLE, address(_openTermStaking));
        _underlyingToken.grantRole(Roles.OPERATOR_ROLE, address(_exchanger));

        _exchanger.grantRole(Roles.INVESTMENT_MANAGER_ROLE, address(_openTermStaking));

        vm.stopPrank();

        _;
    }

    function setUp()
        public
        timeBegin
        deployDepositToken
        deployUnderlyingToken
        deployWhitelist
        deployExchanger
        deployOpenTermStaking
        setContractDependencies
        oneDayPassed
    {
        vm.label(_owner, "owner");
    }

    function testNull() public pure {
        assertTrue(true);
    }

    function testFuzzStake(uint128 amountToStake_) public {
        amountToStake_ = uint128(bound(amountToStake_, 10 ** 6, 1_000_000_000 * 10 ** 6));
        address someone = makeAddr("someone");
        _fundUser(someone, amountToStake_);
        _whitelistUser(someone);
        _stake(someone, amountToStake_, false);
    }

    function testFuzeeStakeFrom(uint128 amountToStake_) public {
        amountToStake_ = uint128(bound(amountToStake_, 10 ** 6, 1_000_000_000 * 10 ** 6));
        address someone = makeAddr("someone");
        _fundUser(someone, amountToStake_);
        _whitelistUser(someone);
        _stake(someone, amountToStake_, true);
    }

    function testFuzzUnstake(uint128 amountToStake_, uint128 amountToUnstake_, uint128 days_, uint128 interest_)
        public
    {
        amountToStake_ = uint128(bound(amountToStake_, 10 ** 6, 1_000_000_000 * 10 ** 6));
        amountToUnstake_ = uint128(bound(amountToUnstake_, amountToStake_ / 10, amountToStake_));
        days_ = uint128(bound(days_, 10, 30));
        interest_ = uint128(bound(interest_, amountToStake_ / 10000, amountToStake_ / 1000));

        address someone = makeAddr("someone");
        _fundUser(someone, amountToStake_);
        _whitelistUser(someone);
        _stake(someone, amountToStake_, false);

        for (uint128 i = 0; i < days_; i++) {
            if (i % 2 == 0) {
                _depositToken.mint(_assetsInfoBasket[i % _assetsInfoBasket.length].targetVault, interest_);
            } else {
                _depositToken.burn(_assetsInfoBasket[i % _assetsInfoBasket.length].targetVault, interest_ / 10);
            }

            vm.warp((_currentTime += 1 days) + 1 minutes);
            _openTermStaking.feed(_currentTime);
        }

        vm.prank(_owner);
        _openTermStaking.feedForce(_currentTime);

        vm.prank(someone);
        _openTermStaking.unstake(amountToUnstake_);
    }

    function testFuzzUnstakeFrom(uint128 amountToStake_, uint128 amountToUnstake_, uint128 days_, uint128 interest_)
        public
    {
        amountToStake_ = uint128(bound(amountToStake_, 10 ** 6, 1_000_000_000 * 10 ** 6));
        amountToUnstake_ = uint128(bound(amountToUnstake_, amountToStake_ / 10, amountToStake_));
        days_ = uint128(bound(days_, 10, 30));
        interest_ = uint128(bound(interest_, amountToStake_ / 10000, amountToStake_ / 1000));

        address someone = makeAddr("someone");
        _fundUser(someone, amountToStake_);
        _whitelistUser(someone);
        _stake(someone, amountToStake_, true);

        for (uint128 i = 0; i < days_; i++) {
            if (i % 2 == 0) {
                _depositToken.mint(_assetsInfoBasket[i % _assetsInfoBasket.length].targetVault, interest_);
            } else {
                _depositToken.burn(_assetsInfoBasket[i % _assetsInfoBasket.length].targetVault, interest_ / 10);
            }

            vm.warp((_currentTime += 1 days) + 1 minutes);
            _openTermStaking.feed(_currentTime);
        }

        vm.prank(_owner);
        _openTermStaking.feedForce(_currentTime);

        vm.prank(_owner);
        _openTermStaking.unstakeFrom(amountToUnstake_, someone);
    }

    function testIntegration() public {
        address someone = makeAddr("someone");
        _whitelistUser(someone);

        for (uint256 i = 0; i < 60; ++i) {
            vm.warp(_currentTime += 1 days);

            uint128 amountToStake = uint128((_randomUint256() % 1_000 + 1) * 10 ** 6);
            uint128 amountToUnstake = amountToStake / uint128(_randomUint256() % 5 + 2);
            uint128 interest = uint128(_randomUint256() % 1_000_000 * amountToStake / 1_000_000 / 365);

            _depositToken.mint(_assetsInfoBasket[_randomUint256() % _assetsInfoBasket.length].targetVault, interest / 4);

            _fundUser(someone, amountToStake);

            _stake(someone, amountToStake / 2, false);

            _depositToken.mint(_assetsInfoBasket[_randomUint256() % _assetsInfoBasket.length].targetVault, interest / 4);

            vm.warp(_currentTime + 1 minutes);

            if (_randomUint256() % 2 == 0) {
                vm.prank(someone);
                _openTermStaking.unstake(amountToUnstake / 5);
            }

            _depositToken.mint(_assetsInfoBasket[_randomUint256() % _assetsInfoBasket.length].targetVault, interest / 4);

            _stake(someone, amountToStake / 2, false);

            if (_randomUint256() % 2 == 0) {
                vm.prank(someone);
                _openTermStaking.unstake(amountToUnstake / 5);
            }

            _depositToken.mint(_assetsInfoBasket[_randomUint256() % _assetsInfoBasket.length].targetVault, interest / 4);

            if (_randomUint256() % 2 == 0) {
                vm.prank(someone);
                _openTermStaking.unstake(amountToUnstake / 5);
            }

            vm.warp(_currentTime + 1 minutes);

            if (_randomUint256() % 2 == 0) {
                vm.prank(someone);
                _openTermStaking.unstake(amountToUnstake / 5);
            }

            _openTermStaking.feed(_currentTime);

            if (_randomUint256() % 2 == 0) {
                vm.prank(someone);
                _openTermStaking.unstake(amountToUnstake / 5);
            }
        }
    }

    function testUpdateStakeFeeRate() public {
        vm.prank(_owner);
        _openTermStaking.updateStakeFeeRate(_stakeFeeRate * 2);
        assertEq(_openTermStaking._stakeFeeRate(), _stakeFeeRate * 2);
    }

    function testUpdateMaxStakeFeeRate() public {
        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.InvalidFeeRate.selector, 50_001));
        _openTermStaking.updateStakeFeeRate(50_001);
    }

    function testUpdateUnstakeFeeRate() public {
        vm.prank(_owner);
        _openTermStaking.updateUnstakeFeeRate(_unstakeFeeRate * 2);
        assertEq(_openTermStaking._unstakeFeeRate(), _unstakeFeeRate * 2);
    }

    function testUpdateMaxUnstakeFeeRate() public {
        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.InvalidFeeRate.selector, 50_001));
        _openTermStaking.updateUnstakeFeeRate(50_001);
    }

    function testUpdateDustBalance() public {
        vm.prank(_owner);
        _openTermStaking.updateDustBalance(_dustBalance * 2);
        assertEq(_openTermStaking._dustBalance(), _dustBalance * 2);

        uint128 maxSupply = _openTermStaking._maxSupply();
        uint128 totalInterestBearing = _openTermStaking._totalInterestBearing();
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.InvalidValue.selector, "dustBalance"));
        vm.prank(_owner);
        _openTermStaking.updateDustBalance(maxSupply - totalInterestBearing + 1);
    }

    function testUpdateMaxSupply() public {
        vm.prank(_owner);
        _openTermStaking.updateMaxSupply(_maxSupply * 2);
        assertEq(_openTermStaking._maxSupply(), _maxSupply * 2);

        _stake(_whitelistedUser1, 100_000 * 10 ** 6, false);

        uint128 totalInterestBearing = _openTermStaking._totalInterestBearing();
        uint128 dustBalance = _openTermStaking._dustBalance();
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.InvalidValue.selector, "newMaxSupply"));
        vm.prank(_owner);
        _openTermStaking.updateMaxSupply(totalInterestBearing - 1);
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.InvalidValue.selector, "newMaxSupply"));
        vm.prank(_owner);
        _openTermStaking.updateMaxSupply(totalInterestBearing + dustBalance - 1);
    }

    function testPauseWhenUnpaused() public {
        vm.prank(_owner);
        _openTermStaking.pause();
        assertTrue(_openTermStaking.paused());
    }

    function testPauseWhenPaused() public {
        vm.prank(_owner);
        _openTermStaking.pause();
        assertTrue(_openTermStaking.paused());
        vm.prank(_whitelistedUser1);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        _openTermStaking.stake(1_000 * 10 ** 6);

        vm.prank(_owner);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        _openTermStaking.pause();
    }

    function testUnpauseWhenPaused() public {
        vm.prank(_owner);
        _openTermStaking.pause();
        assertTrue(_openTermStaking.paused());
        vm.prank(_owner);
        _openTermStaking.unpause();
        assertTrue(!_openTermStaking.paused());
    }

    function testUnpauseWhenUnpaused() public {
        vm.prank(_owner);
        vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
        _openTermStaking.unpause();
    }

    function testContractName() public view {
        assertEq(_openTermStaking.contractName(), "OpenTermStaking");
    }

    function testBalanceOf() public {
        address someone = makeAddr("someone");
        _fundUser(someone, 1_000_000 * 10 ** 6);
        _whitelistUser(someone);
        (uint128 sharesAmount, uint128 stakedAmount) = _stake(someone, 1_000_000 * 10 ** 6, false);
        assertEq(_openTermStaking.balanceOf(someone), stakedAmount);
        assertEq(_openTermStaking.sharesOf(someone), sharesAmount);
    }

    function testDecimals() public view {
        assertEq(_openTermStaking.decimals(), 6);
    }

    function testUnwhitelistedStake() public {
        address someone = makeAddr("someone");
        _fundUser(someone, 1_000_000 * 10 ** 6);
        vm.prank(someone);
        vm.expectRevert(abi.encodeWithSelector(IWhitelist.NotWhitelisted.selector, someone));
        _openTermStaking.stake(1_000_000 * 10 ** 6);
    }

    function testInvalidStake() public {
        console.log("case1: zero whitelist!");
        OpenTermStaking uninitializedStaking = new OpenTermStaking();
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.ZeroAddress.selector, "whitelist"));
        vm.prank(address(0x0));
        uninitializedStaking.stake(1_000 * 10 ** 6);

        console.log("case2: zero user!");
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.ZeroAddress.selector, "user"));
        vm.prank(address(0x0));
        _openTermStaking.stake(1_000 * 10 ** 6);

        console.log("case3: stakeAmount is zero!");
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.InvalidValue.selector, "stakeAmount"));
        vm.prank(_whitelistedUser1);
        _openTermStaking.stake(0);

        console.log("case4: insufficient allowance!");
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.InsufficientAllowance.selector, 0, 1));
        vm.prank(_whitelistedUser1);
        _openTermStaking.stake(1);

        console.log("case5: insufficient balance!");
        vm.prank(_whitelistedUser1);
        _underlyingToken.approve(address(_openTermStaking), 1);
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.InsufficientBalance.selector, 0, 1));
        vm.prank(_whitelistedUser1);
        _openTermStaking.stake(1);

        console.log("case6: exceed max supply!");
        uint256 amountToStake = (_maxSupply + 1) * 10 ** 6 / (10 ** 6 - _stakeFeeRate);
        _depositToken.mint(_whitelistedUser1, amountToStake);
        vm.prank(_whitelistedUser1);
        _depositToken.approve(address(_exchanger), amountToStake);
        vm.prank(_whitelistedUser1);
        _exchanger.exchange(uint128(amountToStake), true);
        assertEq(_underlyingToken.balanceOf(_whitelistedUser1), amountToStake);

        vm.prank(_whitelistedUser1);
        _underlyingToken.approve(address(_openTermStaking), amountToStake);

        vm.expectRevert(
            abi.encodeWithSelector(
                OpenTermStaking.ExceedMaxSupply.selector,
                _maxSupply,
                _openTermStaking._totalInterestBearing(),
                _openTermStaking._maxSupply()
            )
        );
        vm.prank(_whitelistedUser1);
        _openTermStaking.stake(uint128(amountToStake));

        console.log("case7: below dust balance!");
        amountToStake = (_maxSupply - 1) * 10 ** 6 / (10 ** 6 - _stakeFeeRate);
        vm.expectRevert(
            abi.encodeWithSelector(OpenTermStaking.BelowDustBalance.selector, _maxSupply - 1, 0, _dustBalance)
        );
        vm.prank(_whitelistedUser1);
        _openTermStaking.stake(uint128(amountToStake));

        console.log("case8: deposit to vault failed!");
        vm.mockCall(
            _assetsInfoBasket[0].targetVault, abi.encodeWithSelector(IERC4626.deposit.selector), abi.encode(uint256(0))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                OpenTermStaking.DepositFailed.selector, 499500000, 0, _assetsInfoBasket[0].targetVault
            )
        );
        vm.prank(_whitelistedUser1);
        _openTermStaking.stake(1_000 * 10 ** 6);
        vm.clearMockedCalls();
    }

    function testUnstakeOverBalance() public {
        _stake(_whitelistedUser1, 1_000_000 * 10 ** 6, false);

        uint256 sharesOwned = _openTermStaking.sharesOf(_whitelistedUser1);

        vm.prank(_whitelistedUser1);
        _openTermStaking.approve(address(_openTermStaking), type(uint256).max);
        vm.prank(_whitelistedUser1);
        (uint128 sharesBurned,) = _openTermStaking.unstake(1_000_001 * 10 ** 6);

        assertEq(sharesBurned, sharesOwned);
    }

    function testInvalidUnstake() public {
        _stake(_whitelistedUser1, 1_000_000 * 10 ** 6, false);

        console.log("case1: unstakeAmount is zero!");
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.InvalidValue.selector, "unstakeAmount"));
        vm.prank(_whitelistedUser1);
        _openTermStaking.unstake(0);

        console.log("case2: withdraw from vault failed!");
        vm.mockCall(
            _assetsInfoBasket[0].targetVault, abi.encodeWithSelector(IERC4626.withdraw.selector), abi.encode(uint256(0))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                OpenTermStaking.WithdrawFailed.selector, 250000000000, 0, _assetsInfoBasket[0].targetVault
            )
        );
        vm.prank(_whitelistedUser1);
        _openTermStaking.unstake(500_000 * 10 ** 6);
        vm.clearMockedCalls();
    }

    function testUnwhitelistedUnstake() public {
        address someone = makeAddr("someone");
        _fundUser(someone, 1_000_000 * 10 ** 6);
        _whitelistUser(someone);
        _stake(someone, 1_000_000 * 10 ** 6, false);
        vm.prank(_owner);
        _whitelist.remove(someone);
        vm.prank(someone);
        vm.expectRevert(abi.encodeWithSelector(IWhitelist.NotWhitelisted.selector, someone));
        _openTermStaking.unstake(500_000 * 10 ** 6);
    }

    function testInitializeException() public {
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.ZeroAddress.selector, "owner"));
        _openTermStaking = OpenTermStaking(
            _deployer.deployOpenTermStaking(
                [address(0x0), address(_underlyingToken), address(_whitelist), address(_exchanger)],
                ((uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128) | (uint256(_startFeedTime) << 192)),
                (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
                "lbUSD+",
                "lbUSD+",
                _assetsInfoBasket
            )
        );

        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.ZeroAddress.selector, "underlyingToken"));
        _openTermStaking = OpenTermStaking(
            _deployer.deployOpenTermStaking(
                [_owner, address(0x0), address(_whitelist), address(_exchanger)],
                ((uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128) | (uint256(_startFeedTime) << 192)),
                (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
                "lbUSD+",
                "lbUSD+",
                _assetsInfoBasket
            )
        );

        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.ZeroAddress.selector, "whitelist"));
        _openTermStaking = OpenTermStaking(
            _deployer.deployOpenTermStaking(
                [_owner, address(_underlyingToken), address(0x0), address(_exchanger)],
                ((uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128) | (uint256(_startFeedTime) << 192)),
                (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
                "lbUSD+",
                "lbUSD+",
                _assetsInfoBasket
            )
        );

        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.ZeroAddress.selector, "underlyingTokenExchanger"));
        _openTermStaking = OpenTermStaking(
            _deployer.deployOpenTermStaking(
                [_owner, address(_underlyingToken), address(_whitelist), address(0x0)],
                ((uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128) | (uint256(_startFeedTime) << 192)),
                (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
                "lbUSD+",
                "lbUSD+",
                _assetsInfoBasket
            )
        );

        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.InvalidValue.selector, "stakeFeeRate"));
        _openTermStaking = OpenTermStaking(
            _deployer.deployOpenTermStaking(
                [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
                ((uint256(50_001) << 64) | (uint256(_unstakeFeeRate) << 128) | (uint256(_startFeedTime) << 192)),
                (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
                "lbUSD+",
                "lbUSD+",
                _assetsInfoBasket
            )
        );

        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.InvalidValue.selector, "unstakeFeeRate"));
        _openTermStaking = OpenTermStaking(
            _deployer.deployOpenTermStaking(
                [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
                ((uint256(_stakeFeeRate) << 64) | (uint256(50_001) << 128) | (uint256(_startFeedTime) << 192)),
                (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
                "lbUSD+",
                "lbUSD+",
                _assetsInfoBasket
            )
        );

        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.InvalidValue.selector, "startFeedTime"));
        _openTermStaking = OpenTermStaking(
            _deployer.deployOpenTermStaking(
                [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
                ((uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128) | (uint256(0) << 192)),
                (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
                "lbUSD+",
                "lbUSD+",
                _assetsInfoBasket
            )
        );

        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.InvalidValue.selector, "name"));
        _openTermStaking = OpenTermStaking(
            _deployer.deployOpenTermStaking(
                [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
                ((uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128) | (uint256(_startFeedTime) << 192)),
                (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
                "",
                "lbUSD+",
                _assetsInfoBasket
            )
        );

        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.InvalidValue.selector, "symbol"));
        _openTermStaking = OpenTermStaking(
            _deployer.deployOpenTermStaking(
                [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
                ((uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128) | (uint256(_startFeedTime) << 192)),
                (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
                "lbUSD+",
                "",
                _assetsInfoBasket
            )
        );

        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.InvalidValue.selector, "assetsInfoBasket"));
        _openTermStaking = OpenTermStaking(
            _deployer.deployOpenTermStaking(
                [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
                ((uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128) | (uint256(_startFeedTime) << 192)),
                (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
                "lbUSD+",
                "lbUSD+",
                new OpenTermStaking.AssetInfo[](0)
            )
        );

        address originalTargetVault = _assetsInfoBasket[0].targetVault;
        _assetsInfoBasket[0].targetVault = address(0x0);
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.ZeroAddress.selector, "asset vault"));
        _openTermStaking = OpenTermStaking(
            _deployer.deployOpenTermStaking(
                [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
                ((uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128) | (uint256(_startFeedTime) << 192)),
                (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
                "lbUSD+",
                "lbUSD+",
                _assetsInfoBasket
            )
        );
        _assetsInfoBasket[0].targetVault = originalTargetVault;

        uint64 originalWeight = _assetsInfoBasket[0].weight;
        _assetsInfoBasket[0].weight = 0;
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.InvalidValue.selector, "weight of asset in basket"));
        _openTermStaking = OpenTermStaking(
            _deployer.deployOpenTermStaking(
                [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
                ((uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128) | (uint256(_startFeedTime) << 192)),
                (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
                "lbUSD+",
                "lbUSD+",
                _assetsInfoBasket
            )
        );
        _assetsInfoBasket[0].weight = originalWeight;

        uint64 originalWeight0 = _assetsInfoBasket[0].weight;
        uint64 originalWeight1 = _assetsInfoBasket[1].weight;
        _assetsInfoBasket[0].weight = 500_001;
        _assetsInfoBasket[1].weight = 500_001;
        vm.expectRevert(
            abi.encodeWithSelector(OpenTermStaking.InvalidValue.selector, "total weight of assets in basket")
        );
        _openTermStaking = OpenTermStaking(
            _deployer.deployOpenTermStaking(
                [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
                ((uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128) | (uint256(_startFeedTime) << 192)),
                (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
                "lbUSD+",
                "lbUSD+",
                _assetsInfoBasket
            )
        );
        _assetsInfoBasket[0].weight = originalWeight0;
        _assetsInfoBasket[1].weight = originalWeight1;

        OpenTermStaking.AssetInfo memory originalAssetInfo = _assetsInfoBasket[0];
        _assetsInfoBasket[0] = OpenTermStaking.AssetInfo({
            targetVault: address(
                new AssetVault(IERC20(address(new DepositAsset("USD Token", "USDT"))), "MMF@lbUSD", "MMF@lbUSD")
            ),
            weight: 500_000 // 50%
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                OpenTermStaking.VaultAssetNotEqualExchangerToken1.selector,
                IERC4626(_assetsInfoBasket[0].targetVault).asset(),
                _exchanger._token1()
            )
        );
        _openTermStaking = OpenTermStaking(
            _deployer.deployOpenTermStaking(
                [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
                ((uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128) | (uint256(_startFeedTime) << 192)),
                (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
                "lbUSD+",
                "lbUSD+",
                _assetsInfoBasket
            )
        );
        _assetsInfoBasket[0] = originalAssetInfo;

        vm.expectRevert(
            abi.encodeWithSelector(
                OpenTermStaking.ExchangerToken0NotEqualUnderlyingToken.selector, _exchanger._token0(), address(0x1234)
            )
        );
        _openTermStaking = OpenTermStaking(
            _deployer.deployOpenTermStaking(
                [_owner, address(0x1234), address(_whitelist), address(_exchanger)],
                ((uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128) | (uint256(_startFeedTime) << 192)),
                (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
                "lbUSD+",
                "lbUSD+",
                _assetsInfoBasket
            )
        );
    }

    function testInvalidFeed() public {
        console.log("case 1: zero principal feed");
        vm.warp((_currentTime += 1 days) + 1 minutes);
        _depositToken.mint(address(_openTermStaking), 1);
        vm.startPrank(address(_openTermStaking));
        _depositToken.approve(_assetsInfoBasket[0].targetVault, 1);
        IERC4626(_assetsInfoBasket[0].targetVault).deposit(1, address(_openTermStaking));
        vm.stopPrank();
        assertFalse(_openTermStaking.feed(_currentTime));

        console.log("case 2: negative interest feed");
        vm.warp((_currentTime += 1 days) + 1 minutes);
        _depositToken.mint(_assetsInfoBasket[0].targetVault, 1_000 * 10 ** 6);
        _depositToken.mint(_assetsInfoBasket[1].targetVault, 1_000 * 10 ** 6);
        vm.startPrank(_whitelistedUser1);
        _depositToken.approve(address(_exchanger), 300_000 * 10 ** 6);
        _exchanger.exchange(300_000 * 10 ** 6, true);
        assertEq(_underlyingToken.balanceOf(_whitelistedUser1), 300_000 * 10 ** 6);
        _underlyingToken.approve(address(_openTermStaking), 300_000 * 10 ** 6);
        _openTermStaking.stake(300_000 * 10 ** 6);
        vm.stopPrank();
        assertTrue(_openTermStaking.feed(_currentTime));
        vm.warp((_currentTime += 1 days) + 1 minutes);
        _depositToken.burn(_assetsInfoBasket[0].targetVault, 500 * 10 ** 6);
        _depositToken.burn(_assetsInfoBasket[1].targetVault, 500 * 10 ** 6);
        assertTrue(_openTermStaking.feed(_currentTime));

        console.log("case 3: AncientFeedTimeUpdateIsNotAllowed");
        vm.expectRevert(
            abi.encodeWithSelector(
                OpenTermStaking.AncientFeedTimeUpdateIsNotAllowed.selector,
                _normalizeTimestamp(_currentTime - 1 days),
                _openTermStaking._lastFeedTime(),
                uint64(block.timestamp)
            )
        );
        _openTermStaking.feed(_currentTime - 1 days);

        console.log("case 4: LastFeedTimeUpdateRequireForce");
        vm.expectRevert(
            abi.encodeWithSelector(
                OpenTermStaking.LastFeedTimeUpdateRequireForce.selector,
                _normalizeTimestamp(_currentTime),
                _openTermStaking._lastFeedTime(),
                uint64(block.timestamp)
            )
        );
        _openTermStaking.feed(_currentTime);

        console.log("case 5: FutureFeedTimeIsNotAllowed");
        vm.expectRevert(
            abi.encodeWithSelector(
                OpenTermStaking.FutureFeedTimeUpdateIsNotAllowed.selector,
                _normalizeTimestamp(_currentTime + 1 days + 1 minutes),
                _openTermStaking._lastFeedTime(),
                uint64(block.timestamp)
            )
        );
        _openTermStaking.feed(_currentTime + 1 days + 1 minutes);
    }

    function testPoolBankrupt() public {
        vm.prank(_owner);
        _whitelist.add(address(_openTermStaking));
        vm.prank(address(_openTermStaking));
        _openTermStaking.unstake(1);
        assertEq(_openTermStaking.sharesOf(address(_openTermStaking)), 0);
        vm.startPrank(_whitelistedUser1);
        _depositToken.approve(address(_exchanger), 1_000_000 * 10 ** 6);
        _exchanger.exchange(1_000_000 * 10 ** 6, true);
        assertEq(_underlyingToken.balanceOf(_whitelistedUser1), 1_000_000 * 10 ** 6);
        _underlyingToken.approve(address(_openTermStaking), 1_000_000 * 10 ** 6);
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.PoolBankrupt.selector));
        _openTermStaking.stake(1_000_000 * 10 ** 6);
        vm.stopPrank();
    }

    function testLostPartOfInterestBearing() public {
        vm.warp((_currentTime += 1 days) + 1 minutes);
        _stake(_whitelistedUser1, 1_000_000 * 10 ** 6, false);
        _depositToken.mint(
            _assetsInfoBasket[0].targetVault, IERC4626(_assetsInfoBasket[0].targetVault).totalAssets() * 5 / 100 / 365
        );
        _depositToken.mint(
            _assetsInfoBasket[1].targetVault, IERC4626(_assetsInfoBasket[1].targetVault).totalAssets() * 5 / 100 / 365
        );
        _openTermStaking.feed(_currentTime);

        vm.warp((_currentTime += 1 days) + 1 minutes);
        _stake(_whitelistedUser2, 1_000_000 * 10 ** 6, false);
        _depositToken.mint(
            _assetsInfoBasket[0].targetVault, IERC4626(_assetsInfoBasket[0].targetVault).totalAssets() * 10 / 100 / 365
        );
        _depositToken.mint(
            _assetsInfoBasket[1].targetVault, IERC4626(_assetsInfoBasket[1].targetVault).totalAssets() * 10 / 100 / 365
        );
        _openTermStaking.feed(_currentTime);

        vm.warp((_currentTime += 1 days) + 1 minutes);
        // Simulate loss of part assets in vaults
        _depositToken.burn(
            _assetsInfoBasket[0].targetVault, IERC4626(_assetsInfoBasket[0].targetVault).totalAssets() - 1
        );
        _depositToken.burn(
            _assetsInfoBasket[1].targetVault, IERC4626(_assetsInfoBasket[1].targetVault).totalAssets() - 1
        );
        _openTermStaking.feed(_currentTime);
    }

    function testInterestOverPoolBalance() public {
        vm.warp((_currentTime += 1 days) + 1 minutes);
        _stake(_whitelistedUser1, 1_000_000 * 10 ** 6, false);
        _depositToken.mint(
            _assetsInfoBasket[0].targetVault, IERC4626(_assetsInfoBasket[0].targetVault).totalAssets() * 5 / 100 / 365
        );
        _depositToken.mint(
            _assetsInfoBasket[1].targetVault, IERC4626(_assetsInfoBasket[1].targetVault).totalAssets() * 5 / 100 / 365
        );
        _openTermStaking.feed(_currentTime);

        vm.warp((_currentTime += 1 days) + 1 minutes);
        _depositToken.mint(
            _assetsInfoBasket[0].targetVault, IERC4626(_assetsInfoBasket[0].targetVault).totalAssets() * 10 / 100 / 365
        );
        _depositToken.mint(
            _assetsInfoBasket[1].targetVault, IERC4626(_assetsInfoBasket[1].targetVault).totalAssets() * 10 / 100 / 365
        );
        _openTermStaking.feed(_currentTime);

        vm.warp((_currentTime += 1 days) + 1 minutes);
        // Simulate loss of part assets in vaults
        _depositToken.burn(
            _assetsInfoBasket[0].targetVault, IERC4626(_assetsInfoBasket[0].targetVault).totalAssets() - 1
        );
        _depositToken.burn(
            _assetsInfoBasket[1].targetVault, IERC4626(_assetsInfoBasket[1].targetVault).totalAssets() - 1
        );
        vm.startPrank(address(_openTermStaking));
        _underlyingToken.burn(_underlyingToken.balanceOf(address(_openTermStaking)) / 2);
        vm.stopPrank();

        _openTermStaking.feed(_currentTime);
    }

    function testBoringOpenTermStakingOnlyInitialized() public {
        BoringOpenTermStaking boringOpenTermStaking = new BoringOpenTermStaking();

        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.Uninitialized.selector, "underlyingToken"));
        boringOpenTermStaking.boringTestOnlyInitialized();

        stdstore.target(address(boringOpenTermStaking)).sig(OpenTermStaking.underlyingToken.selector).checked_write(
            address(_underlyingToken)
        );
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.Uninitialized.selector, "whitelist"));
        boringOpenTermStaking.boringTestOnlyInitialized();

        stdstore.target(address(boringOpenTermStaking)).sig(OpenTermStaking.whitelist.selector).checked_write(
            address(_whitelist)
        );
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.Uninitialized.selector, "exchanger"));
        boringOpenTermStaking.boringTestOnlyInitialized();

        stdstore.target(address(boringOpenTermStaking)).sig(OpenTermStaking.exchanger.selector).checked_write(
            address(_exchanger)
        );
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.Uninitialized.selector, "maxSupply"));
        boringOpenTermStaking.boringTestOnlyInitialized();

        stdstore.enable_packed_slots().target(address(boringOpenTermStaking)).sig(OpenTermStaking.maxSupply.selector)
            .checked_write(_maxSupply);
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.Uninitialized.selector, "lastFeedTime"));
        boringOpenTermStaking.boringTestOnlyInitialized();

        stdstore.enable_packed_slots().target(address(boringOpenTermStaking)).sig(OpenTermStaking.lastFeedTime.selector)
            .checked_write(_normalizeTimestamp(_startFeedTime));
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.Uninitialized.selector, "assetsInfoBasket"));
        boringOpenTermStaking.boringTestOnlyInitialized();
    }

    function testBoringOpenTermStakingOnlyWhitelist() public {
        BoringOpenTermStaking boringOpenTermStaking = new BoringOpenTermStaking();

        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.ZeroAddress.selector, "whitelist"));
        boringOpenTermStaking.boringTestOnlyWhitelist();

        stdstore.target(address(boringOpenTermStaking)).sig(OpenTermStaking.whitelist.selector).checked_write(
            address(_whitelist)
        );
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.ZeroAddress.selector, "user"));
        vm.prank(address(0x0));
        boringOpenTermStaking.boringTestOnlyWhitelist();
        vm.expectRevert(abi.encodeWithSelector(IWhitelist.NotWhitelisted.selector, _nonWhitelistedUser1));
        vm.prank(_nonWhitelistedUser1);
        boringOpenTermStaking.boringTestOnlyWhitelist();
    }

    function testBoringOpenTermStake() public {
        BoringOpenTermStaking boringOpenTermStaking = new BoringOpenTermStaking();

        stdstore.target(address(boringOpenTermStaking)).sig(OpenTermStaking.underlyingToken.selector).checked_write(
            address(_underlyingToken)
        );
        stdstore.target(address(boringOpenTermStaking)).sig(OpenTermStaking.whitelist.selector).checked_write(
            address(_whitelist)
        );
        stdstore.target(address(boringOpenTermStaking)).sig(OpenTermStaking.exchanger.selector).checked_write(
            address(_exchanger)
        );
        stdstore.enable_packed_slots().target(address(boringOpenTermStaking)).sig(OpenTermStaking.maxSupply.selector)
            .checked_write(_maxSupply);
        stdstore.enable_packed_slots().target(address(boringOpenTermStaking)).sig(OpenTermStaking.lastFeedTime.selector)
            .checked_write(_normalizeTimestamp(_startFeedTime));

        address operator = makeAddr("operator");
        stdstore.target(address(boringOpenTermStaking)).sig(AccessControlUpgradeable.hasRole.selector).with_key(
            Roles.OPERATOR_ROLE
        ).with_key(operator).checked_write(true);
        vm.prank(operator);
        boringOpenTermStaking.addNewAssetIntoBasket(_assetsInfoBasket);

        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.ZeroAddress.selector, "from"));
        boringOpenTermStaking.boringTestStake(1000, address(0), address(0x01));
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.ZeroAddress.selector, "to"));
        boringOpenTermStaking.boringTestStake(1000, address(0x01), address(0));
    }

    function testBoringOpenTermUnstake() public {
        BoringOpenTermStaking boringOpenTermStaking = new BoringOpenTermStaking();

        stdstore.target(address(boringOpenTermStaking)).sig(OpenTermStaking.underlyingToken.selector).checked_write(
            address(_underlyingToken)
        );
        stdstore.target(address(boringOpenTermStaking)).sig(OpenTermStaking.whitelist.selector).checked_write(
            address(_whitelist)
        );
        stdstore.target(address(boringOpenTermStaking)).sig(OpenTermStaking.exchanger.selector).checked_write(
            address(_exchanger)
        );
        stdstore.enable_packed_slots().target(address(boringOpenTermStaking)).sig(OpenTermStaking.maxSupply.selector)
            .checked_write(_maxSupply);
        stdstore.enable_packed_slots().target(address(boringOpenTermStaking)).sig(OpenTermStaking.lastFeedTime.selector)
            .checked_write(_normalizeTimestamp(_startFeedTime));

        address operator = makeAddr("operator");
        stdstore.target(address(boringOpenTermStaking)).sig(AccessControlUpgradeable.hasRole.selector).with_key(
            Roles.OPERATOR_ROLE
        ).with_key(operator).checked_write(true);
        vm.prank(operator);
        boringOpenTermStaking.addNewAssetIntoBasket(_assetsInfoBasket);

        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.ZeroAddress.selector, "from"));
        boringOpenTermStaking.boringTestUnstake(1000, address(0), address(0x01));
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.ZeroAddress.selector, "to"));
        boringOpenTermStaking.boringTestUnstake(1000, address(0x01), address(0));
    }

    function testUnderlyingToken() public view {
        assertEq(address(_openTermStaking.underlyingToken()), address(_underlyingToken));
    }

    function testWhitelist() public view {
        assertEq(address(_openTermStaking.whitelist()), address(_whitelist));
    }

    function testExchanger() public view {
        assertEq(address(_openTermStaking.exchanger()), address(_exchanger));
    }

    function testTotalInterestBearing() public view {
        assertEq(_openTermStaking.totalInterestBearing(), 1);
    }

    function testTotalFee() public view {
        assertEq(_openTermStaking.totalFee(), 0);
    }

    function testDustBalance() public view {
        assertEq(_openTermStaking.dustBalance(), _dustBalance);
    }

    function testMaxSupply() public view {
        assertEq(_openTermStaking.maxSupply(), _maxSupply);
    }

    function testStakeFeeRate() public view {
        assertEq(_openTermStaking.stakeFeeRate(), _stakeFeeRate);
    }

    function testUnstakeFeeRate() public view {
        assertEq(_openTermStaking.unstakeFeeRate(), _unstakeFeeRate);
    }

    function testLastFeedTime() public view {
        assertEq(_openTermStaking.lastFeedTime(), _normalizeTimestamp(_startFeedTime));
    }

    function testAssetsInfoBasket() public view {
        OpenTermStaking.AssetInfo[] memory assetsInfoBasket = _openTermStaking.assetsInfoBasket();
        assertEq(assetsInfoBasket.length, _assetsInfoBasket.length);
        for (uint256 i = 0; i < assetsInfoBasket.length; i++) {
            assertEq(assetsInfoBasket[i].targetVault, _assetsInfoBasket[i].targetVault);
            assertEq(assetsInfoBasket[i].weight, _assetsInfoBasket[i].weight);
        }
    }

    function testAssetInfoAt() public view {
        for (uint256 i = 0; i < _assetsInfoBasket.length; i++) {
            OpenTermStaking.AssetInfo memory assetInfo = _openTermStaking.assetInfoAt(i);
            assertEq(assetInfo.targetVault, _assetsInfoBasket[i].targetVault);
            assertEq(assetInfo.weight, _assetsInfoBasket[i].weight);
        }
    }

    function testAddNewAssetIntoBasket() public {
        OpenTermStaking.AssetInfo[] memory assetsIntoBasket = new OpenTermStaking.AssetInfo[](2);
        assetsIntoBasket[0] = OpenTermStaking.AssetInfo({
            targetVault: address(new AssetVault(IERC20(address(_depositToken)), "MMF@lbUSD", "MMF@lbUSD")),
            weight: 250_000 // 25%
        });
        assetsIntoBasket[1] = OpenTermStaking.AssetInfo({
            targetVault: address(new AssetVault(IERC20(address(_depositToken)), "RWA@lbUSD", "RWA@lbUSD")),
            weight: 250_000 // 25%
        });

        OpenTermStaking.AssetInfo[] memory newAssetsIntoBasket = new OpenTermStaking.AssetInfo[](2);
        newAssetsIntoBasket[0] = OpenTermStaking.AssetInfo({
            targetVault: address(new AssetVault(IERC20(address(_depositToken)), "BTC@lbUSD", "BTC@lbUSD")),
            weight: 300_000 // 30%
        });
        newAssetsIntoBasket[1] = OpenTermStaking.AssetInfo({
            targetVault: address(new AssetVault(IERC20(address(_depositToken)), "ETH@lbUSD", "ETH@lbUSD")),
            weight: 300_000 // 30%
        });

        vm.startPrank(_owner);

        OpenTermStaking openTermStaking = OpenTermStaking(
            _deployer.deployOpenTermStaking(
                [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
                ((uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128) | (uint256(_startFeedTime) << 192)),
                (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
                "lbUSD+",
                "lbUSD+",
                assetsIntoBasket
            )
        );

        openTermStaking.grantRole(Roles.OPERATOR_ROLE, _owner);

        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.InvalidValue.selector, "empty newAssetInfo"));
        vm.prank(_owner);
        openTermStaking.addNewAssetIntoBasket(new OpenTermStaking.AssetInfo[](0));

        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.ZeroAddress.selector, "new asset's vault"));
        vm.prank(_owner);
        openTermStaking.addNewAssetIntoBasket(new OpenTermStaking.AssetInfo[](1));

        newAssetsIntoBasket[0].weight = 0;
        vm.expectRevert(abi.encodeWithSelector(OpenTermStaking.InvalidValue.selector, "weight of new asset in basket"));
        vm.prank(_owner);
        openTermStaking.addNewAssetIntoBasket(newAssetsIntoBasket);

        newAssetsIntoBasket[0].weight = 300_000;
        vm.expectRevert(
            abi.encodeWithSelector(
                OpenTermStaking.InvalidValue.selector, "total weight of assets in basket and new assets"
            )
        );
        vm.prank(_owner);
        openTermStaking.addNewAssetIntoBasket(newAssetsIntoBasket);

        newAssetsIntoBasket[0] = OpenTermStaking.AssetInfo({
            targetVault: address(new AssetVault(IERC20(address(0xdeadbeef)), "BTC@lbUSD", "BTC@lbUSD")),
            weight: 200_000 // 20%
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                OpenTermStaking.VaultAssetNotEqualExchangerToken1.selector, address(0xdeadbeef), address(_depositToken)
            )
        );
        vm.prank(_owner);
        openTermStaking.addNewAssetIntoBasket(newAssetsIntoBasket);

        newAssetsIntoBasket[0] = OpenTermStaking.AssetInfo({
            targetVault: address(new AssetVault(IERC20(address(_depositToken)), "BTC@lbUSD", "BTC@lbUSD")),
            weight: 200_000 // 20%
        });
        vm.prank(_owner);
        openTermStaking.addNewAssetIntoBasket(newAssetsIntoBasket);
    }

    function _stake(address user_, uint128 amountToStake_, bool stakeFrom_)
        internal
        returns (uint128 sharesAmount_, uint128 stakedAmount__)
    {
        vm.startPrank(user_);

        _depositToken.approve(address(_exchanger), amountToStake_);
        _exchanger.exchange(amountToStake_, true);

        uint128 userBalanceBeforeStake = uint128(_underlyingToken.balanceOf(user_));
        uint128 poolBalanceBeforeStake = uint128(_underlyingToken.balanceOf(address(_openTermStaking)));

        assertGe(userBalanceBeforeStake, amountToStake_);

        _underlyingToken.approve(address(_openTermStaking), uint256(amountToStake_));

        vm.stopPrank();

        if (stakeFrom_) {
            vm.prank(_owner);
            (sharesAmount_, stakedAmount__) = _openTermStaking.stakeFrom(amountToStake_, user_);
        } else {
            vm.prank(user_);
            (sharesAmount_, stakedAmount__) = _openTermStaking.stake(amountToStake_);
        }

        uint128 userBalanceAfterStake = uint128(_underlyingToken.balanceOf(user_));
        uint128 poolBalanceAfterStake = uint128(_underlyingToken.balanceOf(address(_openTermStaking)));

        uint128 totalFee = _openTermStaking._totalFee();
        uint128 totalInterestBearing = _openTermStaking._totalInterestBearing();

        assertEq(userBalanceBeforeStake - userBalanceAfterStake, amountToStake_);
        assertEq(poolBalanceAfterStake - poolBalanceBeforeStake, amountToStake_);
        assertEq(int128(poolBalanceAfterStake), int128(totalFee) + int128(totalInterestBearing) - 1);
    }

    function _fundUser(address user_, uint128 amount_) internal {
        _depositToken.mint(user_, amount_);
    }

    function _whitelistUser(address user_) internal {
        vm.prank(_owner);
        _whitelist.add(user_);
    }

    function _randomUint256() internal returns (uint256 randomWord) {
        string[] memory command = new string[](4);
        command[0] = "openssl";
        command[1] = "rand";
        command[2] = "-hex";
        command[3] = "32";

        randomWord = uint256(bytes32(vm.ffi(command)));
    }

    function _normalizeTimestamp(uint64 timestamp_) internal pure returns (uint64 normalizedTimestamp_) {
        normalizedTimestamp_ = uint64(((timestamp_ + 17 hours) / 1 days) * 1 days + 7 hours);
    }
}

contract BoringOpenTermStaking is OpenTermStaking {
    function boringTestOnlyInitialized() public view onlyInitialized returns (bool) {
        return true;
    }

    function boringTestOnlyWhitelist() public view onlyWhitelist(msg.sender) returns (bool) {
        return true;
    }

    function boringTestStake(uint128 stakeAmount_, address from_, address to_)
        public
        returns (uint128 sharesAmount_, uint128 stakedAmount_)
    {
        return _stake(stakeAmount_, from_, to_);
    }

    function boringTestUnstake(uint128 unstakeAmount_, address from_, address to_)
        public
        returns (uint128 sharesBurned_, uint128 unstakedAmount_)
    {
        return _unstake(unstakeAmount_, from_, to_);
    }
}
