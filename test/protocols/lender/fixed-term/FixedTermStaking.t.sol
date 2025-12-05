// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {stdStorage, StdStorage, Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {FixedTermStaking} from "src/protocols/lender/fixed-term/FixedTermStaking.sol";
import {FixedTermToken} from "src/protocols/lender/fixed-term/FixedTermToken.sol";
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
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract FixedTermStakingTest is Test {
    using stdStorage for StdStorage;

    DeployContractSuit internal _deployer = new DeployContractSuit();
    FixedTermStaking internal _fixedTermStaking;
    UnderlyingToken internal _underlyingToken;
    Whitelist internal _whitelist;
    FixedTermStaking.AssetInfo[] internal _assetsInfoBasket;
    DepositAsset internal _depositToken;
    UnderlyingTokenExchanger internal _exchanger;

    address internal _owner = makeAddr("owner");
    address internal _whitelistedUser1 = makeAddr("whitelistedUser1");
    address internal _whitelistedUser2 = makeAddr("whitelistedUser2");
    address internal _nonWhitelistedUser1 = makeAddr("nonWhitelistedUser1");
    address internal _nonWhitelistedUser2 = makeAddr("nonWhitelistedUser2");

    uint64 internal _lockPeriod = 365 days;
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

        _underlyingToken = UnderlyingToken(_deployer.deployUnderlyingToken(_owner, "mosUSD", "mosUSD"));

        _underlyingToken.grantRole(Roles.OPERATOR_ROLE, address(_owner));

        vm.stopPrank();

        vm.label(address(_underlyingToken), "mosUSD");

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

    modifier deployFixedTermStaking() {
        _assetsInfoBasket.push(
            FixedTermStaking.AssetInfo({
                targetVault: address(new AssetVault(IERC20(address(_depositToken)), "MMF@mosUSD", "MMF@mosUSD")),
                weight: 500_000 // 50%
            })
        );

        _assetsInfoBasket.push(
            FixedTermStaking.AssetInfo({
                targetVault: address(new AssetVault(IERC20(address(_depositToken)), "RWA@mosUSD", "RWA@mosUSD")),
                weight: 500_000 // 50%
            })
        );

        vm.startPrank(_owner);

        _fixedTermStaking = FixedTermStaking(
            _deployer.deployFixedTermStaking(
                [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
                (
                    uint256(_lockPeriod) | (uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128)
                        | (uint256(_startFeedTime) << 192)
                ),
                (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
                "mosUSD12M+",
                "mosUSD12M+",
                _assetsInfoBasket
            )
        );

        _fixedTermStaking.grantRole(Roles.OPERATOR_ROLE, _owner);

        vm.stopPrank();

        vm.label(address(_fixedTermStaking), "mosUSD12M+");
        vm.label(address(_assetsInfoBasket[0].targetVault), "MMF@mosUSD");
        vm.label(address(_assetsInfoBasket[1].targetVault), "RWA@mosUSD");

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

        _underlyingToken.grantRole(Roles.OPERATOR_ROLE, address(_fixedTermStaking));
        _underlyingToken.grantRole(Roles.OPERATOR_ROLE, address(_exchanger));

        _exchanger.grantRole(Roles.INVESTMENT_MANAGER_ROLE, address(_fixedTermStaking));

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
        deployFixedTermStaking
        setContractDependencies
        oneDayPassed
    {
        vm.label(_owner, "owner");
    }

    function testNull() public pure {
        assertTrue(true);
    }

    function testStake() public {
        _stake(_whitelistedUser1, 1_000_000 * 10 ** 6, false);
    }

    function testFuzzStake(uint128 amountToStake_) public {
        amountToStake_ = uint128(bound(amountToStake_, 10 ** 6, 1_000 * 10 ** 6));
        address someone = makeAddr("someone");
        _fundUser(someone, amountToStake_);
        _whitelistUser(someone);
        _stake(someone, amountToStake_, false);
    }

    function testStakeThenFeedWithoutPriceFloating() public {
        _stake(_whitelistedUser1, 1_000_000 * 10 ** 6, false);

        int128 totalInterest = _fixedTermStaking._totalInterest();

        for (uint256 i = 0; i < 365; ++i) {
            vm.warp((_currentTime += 1 days) + 1 minutes);
            _fixedTermStaking.feed(_currentTime);
            assertEq(totalInterest, _fixedTermStaking._totalInterest());
        }
    }

    function testStakeThenFeedWithRandomPriceFloating() public {
        _stake(_whitelistedUser1, 1_000_000 * 10 ** 6, false);

        uint64[365] memory timepoints;

        for (uint256 i = 0; i < 365; ++i) {
            vm.warp((_currentTime += 1 days) + 1 minutes);
            _randomPriceFloating();
            if (_fixedTermStaking.feed(_currentTime)) {
                assertEq(
                    uint256(uint128(int128(_fixedTermStaking._totalPrincipal()) + _fixedTermStaking._totalInterest())),
                    _fixedTermStaking.getTotalAssetValueInBasket()
                );
                timepoints[i] = _currentTime;
            }
        }

        for (uint256 i = 0; i < 365; ++i) {
            console.log(_fixedTermStaking.getAccumulatedInterestRate(timepoints[i]));
        }
    }

    function testUnstakeWithoutPriceFloating() public {
        uint256 tokenId = _stake(_whitelistedUser1, 1_000_000 * 10 ** 6, true);

        int128 totalInterest = _fixedTermStaking._totalInterest();

        for (uint256 i = 0; i < 365; ++i) {
            vm.warp((_currentTime += 1 days) + 1 minutes);
            vm.prank(_owner);
            _fixedTermStaking.feedForce(_currentTime);
            assertEq(totalInterest, _fixedTermStaking._totalInterest());
        }

        vm.startPrank(_whitelistedUser1);

        _fixedTermStaking.approve(address(_fixedTermStaking), tokenId);
        _fixedTermStaking.unstake(tokenId);

        vm.stopPrank();
    }

    function testUnstakeWithRandomPriceFloating() public {
        uint256 tokenId = _stake(_whitelistedUser1, 1_000_000 * 10 ** 6, true);

        for (uint256 i = 0; i < 365; ++i) {
            vm.warp((_currentTime += 1 days) + 1 minutes);
            _randomPriceFloating();
            vm.prank(_owner);
            if (_fixedTermStaking.feedForce(_currentTime)) {
                assertEq(
                    uint256(uint128(int128(_fixedTermStaking._totalPrincipal()) + _fixedTermStaking._totalInterest())),
                    _fixedTermStaking.getTotalAssetValueInBasket()
                );
            }
        }

        vm.startPrank(_whitelistedUser1);

        _fixedTermStaking.approve(address(_fixedTermStaking), tokenId);
        _fixedTermStaking.unstake(tokenId);

        vm.stopPrank();
    }

    function testFuzzUnstake(uint128 amountToStake_) public {
        amountToStake_ = uint128(bound(amountToStake_, 10 ** 6, 1_000 * 10 ** 6));
        address someone = makeAddr("someone");
        _fundUser(someone, amountToStake_);
        _whitelistUser(someone);
        uint256 tokenId = _stake(someone, amountToStake_, false);

        for (uint256 i = 0; i < 365; ++i) {
            vm.warp((_currentTime += 1 days) + 1 minutes);
            _randomPriceFloating();
            vm.prank(_owner);
            if (_fixedTermStaking.feedForce(_currentTime)) {
                assertEq(
                    uint256(uint128(int128(_fixedTermStaking._totalPrincipal()) + _fixedTermStaking._totalInterest())),
                    _fixedTermStaking.getTotalAssetValueInBasket()
                );
            }
        }

        vm.prank(someone);

        _fixedTermStaking.approve(address(_fixedTermStaking), tokenId);

        vm.startPrank(_owner);

        _fixedTermStaking.unstakeFrom(tokenId, someone);

        vm.stopPrank();
    }

    function testUpdateStakeFeeRate() public {
        vm.prank(_owner);
        _fixedTermStaking.updateStakeFeeRate(_stakeFeeRate * 2);
        assertEq(_fixedTermStaking._stakeFeeRate(), _stakeFeeRate * 2);
    }

    function testUpdateMaxStakeFeeRate() public {
        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.InvalidFeeRate.selector, 50_001));
        _fixedTermStaking.updateStakeFeeRate(50_001);
    }

    function testUpdateUnstakeFeeRate() public {
        vm.prank(_owner);
        _fixedTermStaking.updateUnstakeFeeRate(_unstakeFeeRate * 2);
        assertEq(_fixedTermStaking._unstakeFeeRate(), _unstakeFeeRate * 2);
    }

    function testUpdateMaxUnstakeFeeRate() public {
        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.InvalidFeeRate.selector, 50_001));
        _fixedTermStaking.updateUnstakeFeeRate(50_001);
    }

    function testUpdateDustBalance() public {
        vm.prank(_owner);
        _fixedTermStaking.updateDustBalance(_dustBalance * 2);
        assertEq(_fixedTermStaking._dustBalance(), _dustBalance * 2);

        uint128 remainingBalance = _fixedTermStaking._remainingBalance();
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.InvalidValue.selector, "dustBalance"));
        vm.prank(_owner);
        _fixedTermStaking.updateDustBalance(remainingBalance + 1);
    }

    function testUpdateMaxSupply() public {
        vm.prank(_owner);
        _fixedTermStaking.updateMaxSupply(_maxSupply * 2);
        assertEq(_fixedTermStaking._maxSupply(), _maxSupply * 2);

        vm.startPrank(_whitelistedUser1);
        _depositToken.approve(address(_exchanger), 1_000_000 * 10 ** 6);
        _exchanger.exchange(1_000_000 * 10 ** 6, true);
        _underlyingToken.approve(address(_fixedTermStaking), 1_000_000 * 10 ** 6);
        _fixedTermStaking.stake(1_000_000 * 10 ** 6);
        vm.stopPrank();

        uint128 totalPrincipal = _fixedTermStaking._totalPrincipal();
        uint128 dustBalance = _fixedTermStaking._dustBalance();

        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.InvalidValue.selector, "newMaxSupply"));
        vm.prank(_owner);
        _fixedTermStaking.updateMaxSupply(totalPrincipal - 1);

        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.InvalidValue.selector, "newMaxSupply"));
        vm.prank(_owner);
        _fixedTermStaking.updateMaxSupply(totalPrincipal + dustBalance - 1);
    }

    function testPauseWhenUnpaused() public {
        vm.prank(_owner);
        _fixedTermStaking.pause();
        assertTrue(_fixedTermStaking.paused());
    }

    function testPauseWhenPaused() public {
        vm.prank(_owner);
        _fixedTermStaking.pause();
        assertTrue(_fixedTermStaking.paused());
        vm.prank(_whitelistedUser1);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        _fixedTermStaking.stake(1_000 * 10 ** 6);

        vm.prank(_owner);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        _fixedTermStaking.pause();
    }

    function testUnpauseWhenPaused() public {
        vm.prank(_owner);
        _fixedTermStaking.pause();
        assertTrue(_fixedTermStaking.paused());
        vm.prank(_owner);
        _fixedTermStaking.unpause();
        assertTrue(!_fixedTermStaking.paused());
    }

    function testUnpauseWhenUnpaused() public {
        vm.prank(_owner);
        vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
        _fixedTermStaking.unpause();
    }

    function testSupportsInterface() public view {
        assertTrue(_fixedTermStaking.supportsInterface(type(IERC721Enumerable).interfaceId));
        assertTrue(_fixedTermStaking.supportsInterface(type(IERC721Metadata).interfaceId));
        assertTrue(_fixedTermStaking.supportsInterface(type(IERC721).interfaceId));
        assertTrue(_fixedTermStaking.supportsInterface(type(IERC165).interfaceId));
    }

    function testContractName() public view {
        assertEq(_fixedTermStaking.contractName(), "FixedTermStaking");
    }

    function testReadFixedTermTokenDetails() public {
        uint256 tokenId = _stake(_whitelistedUser1, 1_000_000 * 10 ** 6, false);
        string memory tokenURI = _fixedTermStaking.tokenURI(tokenId);
        console.log(tokenURI);
    }

    function testDisableInitialize() public {
        vm.expectEmit(false, false, false, true);
        emit Initializable.Initialized(type(uint64).max);
        new FixedTermStaking();
    }

    function testInvalidStake() public {
        console.log("case1: zero address user stake");
        vm.prank(address(0x0));
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.ZeroAddress.selector, "user"));
        _fixedTermStaking.stake(1_000 * 10 ** 6);

        console.log("case2: unwhitelisted user stake");
        vm.prank(_nonWhitelistedUser1);
        vm.expectRevert(abi.encodeWithSelector(IWhitelist.NotWhitelisted.selector, _nonWhitelistedUser1));
        _fixedTermStaking.stake(1_000 * 10 ** 6);

        console.log("case3: stake amount is zero");
        vm.prank(_whitelistedUser1);
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.InvalidValue.selector, "stakeAmount"));
        _fixedTermStaking.stake(0);

        console.log("case4: insufficient allowance");
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.InsufficientAllowance.selector, 0, 1));
        vm.prank(_whitelistedUser1);
        _fixedTermStaking.stake(1);

        console.log("case5: insufficient balance");
        vm.prank(_whitelistedUser1);
        _underlyingToken.approve(address(_fixedTermStaking), 1);
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.InsufficientBalance.selector, 0, 1));
        vm.prank(_whitelistedUser1);
        _fixedTermStaking.stake(1);

        console.log("case6: exceed max supply");
        uint256 amountToStake = (_maxSupply + 2) * 10 ** 6 / (10 ** 6 - _stakeFeeRate);
        _depositToken.mint(_whitelistedUser1, amountToStake);
        vm.prank(_whitelistedUser1);
        _depositToken.approve(address(_exchanger), amountToStake);
        vm.prank(_whitelistedUser1);
        _exchanger.exchange(uint128(amountToStake), true);
        assertEq(_underlyingToken.balanceOf(_whitelistedUser1), amountToStake);

        vm.prank(_whitelistedUser1);
        _underlyingToken.approve(address(_fixedTermStaking), amountToStake);

        vm.expectRevert(
            abi.encodeWithSelector(
                FixedTermStaking.ExceedMaxSupply.selector,
                _maxSupply + 1,
                _fixedTermStaking._totalPrincipal(),
                _fixedTermStaking._maxSupply()
            )
        );
        vm.prank(_whitelistedUser1);
        _fixedTermStaking.stake(uint128(amountToStake));

        console.log("case7: below dust balance!");
        amountToStake = (_maxSupply - 1) * 10 ** 6 / (10 ** 6 - _stakeFeeRate);
        vm.prank(_whitelistedUser1);
        vm.expectRevert(
            abi.encodeWithSelector(FixedTermStaking.BelowDustBalance.selector, _maxSupply - 1, _maxSupply, _dustBalance)
        );
        _fixedTermStaking.stake(uint128(amountToStake));

        console.log("case8: deposit to vault failed!");
        vm.mockCall(
            _assetsInfoBasket[0].targetVault, abi.encodeWithSelector(IERC4626.deposit.selector), abi.encode(uint256(0))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                FixedTermStaking.DepositFailed.selector, 499500000, 0, _assetsInfoBasket[0].targetVault
            )
        );
        vm.prank(_whitelistedUser1);
        _fixedTermStaking.stake(1_000 * 10 ** 6);
        vm.clearMockedCalls();
    }

    function testInvalidUnstake() public {
        console.log("case1: invalid tokenId");
        vm.prank(_whitelistedUser1);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "tokenId"));
        _fixedTermStaking.unstake(0);

        console.log("case2: duplicate unstake");
        uint256 tokenId = _stake(_whitelistedUser1, 1_000_000 * 10 ** 6, true);
        for (uint256 i = 0; i < 365; ++i) {
            vm.warp((_currentTime += 1 days) + 1 minutes);
            _randomPriceFloating();
            vm.prank(_owner);
            if (_fixedTermStaking.feedForce(_currentTime)) {
                assertEq(
                    uint256(uint128(int128(_fixedTermStaking._totalPrincipal()) + _fixedTermStaking._totalInterest())),
                    _fixedTermStaking.getTotalAssetValueInBasket()
                );
            }
        }
        vm.startPrank(_whitelistedUser1);
        _fixedTermStaking.approve(address(_fixedTermStaking), tokenId);
        _fixedTermStaking.unstake(tokenId);
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.AlreadyUnstaked.selector, tokenId));
        _fixedTermStaking.unstake(tokenId);
        vm.stopPrank();

        console.log("case3: unstake not owned token");
        tokenId = _stake(_whitelistedUser2, 1_000_000 * 10 ** 6, true);
        for (uint256 i = 0; i < 360; ++i) {
            vm.warp((_currentTime += 1 days) + 1 minutes);
            _randomPriceFloating();
            vm.prank(_owner);
            if (_fixedTermStaking.feedForce(_currentTime)) {
                assertEq(
                    uint256(uint128(int128(_fixedTermStaking._totalPrincipal()) + _fixedTermStaking._totalInterest())),
                    _fixedTermStaking.getTotalAssetValueInBasket()
                );
            }
        }
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.NotTokenOwner.selector, _whitelistedUser1, tokenId));
        vm.prank(_whitelistedUser1);
        _fixedTermStaking.unstake(tokenId);

        console.log("case4: unstake not matured token");
        (,, uint64 maturityDate,) = _fixedTermStaking._tokenId_stakeInfo(tokenId);
        vm.expectRevert(
            abi.encodeWithSelector(
                FixedTermStaking.StakeNotMatured.selector, tokenId, maturityDate, uint64(block.timestamp)
            )
        );
        vm.prank(_whitelistedUser2);
        _fixedTermStaking.unstake(tokenId);

        console.log("case5: waiting for feed at maturity date");
        for (uint256 i = 0; i < 6; ++i) {
            vm.warp((_currentTime += 1 days) + 1 minutes);
            _randomPriceFloating();
            if (i != 5 && _fixedTermStaking.feed(_currentTime)) {
                assertEq(
                    uint256(uint128(int128(_fixedTermStaking._totalPrincipal()) + _fixedTermStaking._totalInterest())),
                    _fixedTermStaking.getTotalAssetValueInBasket()
                );
            }
        }
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.WaitingForMaturityDateFeed.selector));
        vm.prank(_whitelistedUser2);
        _fixedTermStaking.unstake(tokenId);

        console.log("case6: withdraw from vault failed");
        vm.prank(_whitelistedUser2);
        _fixedTermStaking.approve(address(_fixedTermStaking), tokenId);
        _fixedTermStaking.feed(_currentTime);
        vm.mockCall(
            _assetsInfoBasket[0].targetVault, abi.encodeWithSelector(IERC4626.withdraw.selector), abi.encode(uint256(0))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                FixedTermStaking.WithdrawFailed.selector, 499500000000, 0, _assetsInfoBasket[0].targetVault
            )
        );
        vm.prank(_whitelistedUser2);
        _fixedTermStaking.unstake(tokenId);
        vm.clearMockedCalls();
    }

    function testInitializeException() public {
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.ZeroAddress.selector, "owner"));
        _deployer.deployFixedTermStaking(
            [address(0x0), address(_underlyingToken), address(_whitelist), address(_exchanger)],
            (
                uint256(_lockPeriod) | (uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128)
                    | (uint256(_startFeedTime) << 192)
            ),
            (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
            "mosUSD12M+",
            "mosUSD12M+",
            _assetsInfoBasket
        );

        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.ZeroAddress.selector, "underlyingToken"));
        _deployer.deployFixedTermStaking(
            [_owner, address(0x0), address(_whitelist), address(_exchanger)],
            (
                uint256(_lockPeriod) | (uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128)
                    | (uint256(_startFeedTime) << 192)
            ),
            (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
            "mosUSD12M+",
            "mosUSD12M+",
            _assetsInfoBasket
        );

        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.ZeroAddress.selector, "whitelist"));
        _deployer.deployFixedTermStaking(
            [_owner, address(_underlyingToken), address(0x0), address(_exchanger)],
            (
                uint256(_lockPeriod) | (uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128)
                    | (uint256(_startFeedTime) << 192)
            ),
            (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
            "mosUSD12M+",
            "mosUSD12M+",
            _assetsInfoBasket
        );

        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.ZeroAddress.selector, "exchanger"));
        _deployer.deployFixedTermStaking(
            [_owner, address(_underlyingToken), address(_whitelist), address(0x0)],
            (
                uint256(_lockPeriod) | (uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128)
                    | (uint256(_startFeedTime) << 192)
            ),
            (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
            "mosUSD12M+",
            "mosUSD12M+",
            _assetsInfoBasket
        );

        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.InvalidValue.selector, "lockPeriod"));
        _deployer.deployFixedTermStaking(
            [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
            (
                uint256(0) | (uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128)
                    | (uint256(_startFeedTime) << 192)
            ),
            (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
            "mosUSD12M+",
            "mosUSD12M+",
            _assetsInfoBasket
        );

        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.InvalidValue.selector, "stakeFeeRate"));
        _deployer.deployFixedTermStaking(
            [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
            (
                uint256(_lockPeriod) | (uint256(50_001) << 64) | (uint256(_unstakeFeeRate) << 128)
                    | (uint256(_startFeedTime) << 192)
            ),
            (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
            "mosUSD12M+",
            "mosUSD12M+",
            _assetsInfoBasket
        );

        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.InvalidValue.selector, "unstakeFeeRate"));
        _deployer.deployFixedTermStaking(
            [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
            (
                uint256(_lockPeriod) | (uint256(_stakeFeeRate) << 64) | (uint256(50_001) << 128)
                    | (uint256(_startFeedTime) << 192)
            ),
            (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
            "mosUSD12M+",
            "mosUSD12M+",
            _assetsInfoBasket
        );

        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.InvalidValue.selector, "startFeedTime"));
        _deployer.deployFixedTermStaking(
            [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
            (
                uint256(_lockPeriod) | (uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128)
                    | (uint256(0) << 192)
            ),
            (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
            "mosUSD12M+",
            "mosUSD12M+",
            _assetsInfoBasket
        );

        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.InvalidValue.selector, "name"));
        _deployer.deployFixedTermStaking(
            [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
            (
                uint256(_lockPeriod) | (uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128)
                    | (uint256(_startFeedTime) << 192)
            ),
            (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
            "",
            "mosUSD12M+",
            _assetsInfoBasket
        );

        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.InvalidValue.selector, "symbol"));
        _deployer.deployFixedTermStaking(
            [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
            (
                uint256(_lockPeriod) | (uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128)
                    | (uint256(_startFeedTime) << 192)
            ),
            (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
            "mosUSD12M+",
            "",
            _assetsInfoBasket
        );

        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.InvalidValue.selector, "assetsInfoBasket"));
        _deployer.deployFixedTermStaking(
            [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
            (
                uint256(_lockPeriod) | (uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128)
                    | (uint256(_startFeedTime) << 192)
            ),
            (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
            "mosUSD12M+",
            "mosUSD12M+",
            new FixedTermStaking.AssetInfo[](0)
        );

        address originalTargetVault = _assetsInfoBasket[0].targetVault;
        _assetsInfoBasket[0].targetVault = address(0x0);
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.ZeroAddress.selector, "asset vault"));
        _deployer.deployFixedTermStaking(
            [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
            (
                uint256(_lockPeriod) | (uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128)
                    | (uint256(_startFeedTime) << 192)
            ),
            (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
            "mosUSD12M+",
            "mosUSD12M+",
            _assetsInfoBasket
        );
        _assetsInfoBasket[0].targetVault = originalTargetVault;

        uint64 originalWeight = _assetsInfoBasket[0].weight;
        _assetsInfoBasket[0].weight = 0;
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.InvalidValue.selector, "weight of asset in basket"));
        _deployer.deployFixedTermStaking(
            [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
            (
                uint256(_lockPeriod) | (uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128)
                    | (uint256(_startFeedTime) << 192)
            ),
            (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
            "mosUSD12M+",
            "mosUSD12M+",
            _assetsInfoBasket
        );
        _assetsInfoBasket[0].weight = originalWeight;

        uint64 originalWeight0 = _assetsInfoBasket[0].weight;
        uint64 originalWeight1 = _assetsInfoBasket[1].weight;
        _assetsInfoBasket[0].weight = 500_001;
        _assetsInfoBasket[1].weight = 500_001;
        vm.expectRevert(
            abi.encodeWithSelector(FixedTermStaking.InvalidValue.selector, "total weight of assets in basket")
        );
        _deployer.deployFixedTermStaking(
            [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
            (
                uint256(_lockPeriod) | (uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128)
                    | (uint256(_startFeedTime) << 192)
            ),
            (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
            "mosUSD12M+",
            "mosUSD12M+",
            _assetsInfoBasket
        );
        _assetsInfoBasket[0].weight = originalWeight0;
        _assetsInfoBasket[1].weight = originalWeight1;

        FixedTermStaking.AssetInfo memory originalAssetInfo = _assetsInfoBasket[0];
        _assetsInfoBasket[0] = FixedTermStaking.AssetInfo({
            targetVault: address(
                new AssetVault(IERC20(address(new DepositAsset("USD Token", "USDT"))), "MMF@mosUSD", "MMF@mosUSD")
            ),
            weight: 500_000 // 50%
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                FixedTermStaking.VaultAssetNotEqualExchangerToken1.selector,
                IERC4626(_assetsInfoBasket[0].targetVault).asset(),
                UnderlyingTokenExchanger(_exchanger)._token1()
            )
        );
        _deployer.deployFixedTermStaking(
            [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
            (
                uint256(_lockPeriod) | (uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128)
                    | (uint256(_startFeedTime) << 192)
            ),
            (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
            "mosUSD12M+",
            "mosUSD12M+",
            _assetsInfoBasket
        );
        _assetsInfoBasket[0] = originalAssetInfo;

        vm.expectRevert(
            abi.encodeWithSelector(
                FixedTermStaking.ExchangerToken0NotEqualUnderlyingToken.selector,
                UnderlyingTokenExchanger(_exchanger)._token0(),
                address(0x1234)
            )
        );
        _deployer.deployFixedTermStaking(
            [_owner, address(0x1234), address(_whitelist), address(_exchanger)],
            (
                uint256(_lockPeriod) | (uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128)
                    | (uint256(_startFeedTime) << 192)
            ),
            (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
            "mosUSD12M+",
            "mosUSD12M+",
            _assetsInfoBasket
        );
    }

    function testInvalidFeed() public {
        console.log("case 1: zero principal feed");
        vm.warp((_currentTime += 1 days) + 1 minutes);
        assertFalse(_fixedTermStaking.feed(_currentTime));

        console.log("case 2: unbelievable interest rate");
        vm.warp((_currentTime += 1 days) + 1 minutes);
        vm.startPrank(_whitelistedUser1);
        _depositToken.approve(address(_exchanger), 1_000 * 10 ** 6);
        _exchanger.exchange(1_000 * 10 ** 6, true);
        assertEq(_underlyingToken.balanceOf(_whitelistedUser1), 1_000 * 10 ** 6);
        _underlyingToken.approve(address(_fixedTermStaking), 1_000 * 10 ** 6);
        _fixedTermStaking.stake(1_000 * 10 ** 6);
        vm.stopPrank();
        vm.startPrank(_owner);
        _depositToken.transfer(_assetsInfoBasket[0].targetVault, 1_000 * 10 ** 6);
        _depositToken.transfer(_assetsInfoBasket[1].targetVault, 1_000 * 10 ** 6);
        vm.stopPrank();
        vm.expectRevert(
            abi.encodeWithSelector(FixedTermStaking.UnbelievableInterestRate.selector, 2_002_001, 10_000, -10_000)
        );
        _fixedTermStaking.feed(_currentTime);

        console.log("case 3: negative interest feed");
        vm.startPrank(_whitelistedUser1);
        _depositToken.approve(address(_exchanger), 300_000 * 10 ** 6);
        _exchanger.exchange(300_000 * 10 ** 6, true);
        assertEq(_underlyingToken.balanceOf(_whitelistedUser1), 300_000 * 10 ** 6);
        _underlyingToken.approve(address(_fixedTermStaking), 300_000 * 10 ** 6);
        _fixedTermStaking.stake(300_000 * 10 ** 6);
        vm.stopPrank();
        assertTrue(_fixedTermStaking.feed(_currentTime));
        vm.warp((_currentTime += 1 days) + 1 minutes);
        _depositToken.burn(_assetsInfoBasket[0].targetVault, 500 * 10 ** 6);
        _depositToken.burn(_assetsInfoBasket[1].targetVault, 500 * 10 ** 6);
        assertTrue(_fixedTermStaking.feed(_currentTime));

        console.log("case 4: AncientFeedTimeUpdateIsNotAllowed");
        vm.expectRevert(
            abi.encodeWithSelector(
                FixedTermStaking.AncientFeedTimeUpdateIsNotAllowed.selector,
                _normalizeTimestamp(_currentTime - 1 days),
                _fixedTermStaking._lastFeedTime(),
                uint64(block.timestamp)
            )
        );
        _fixedTermStaking.feed(_currentTime - 1 days);

        console.log("case 5: LastFeedTimeUpdateRequireForce");
        vm.expectRevert(
            abi.encodeWithSelector(
                FixedTermStaking.LastFeedTimeUpdateRequireForce.selector,
                _normalizeTimestamp(_currentTime),
                _fixedTermStaking._lastFeedTime(),
                uint64(block.timestamp)
            )
        );
        _fixedTermStaking.feed(_currentTime);

        console.log("case 6: FutureFeedTimeIsNotAllowed");
        vm.expectRevert(
            abi.encodeWithSelector(
                FixedTermStaking.FutureFeedTimeUpdateIsNotAllowed.selector,
                _normalizeTimestamp(_currentTime + 1 days + 1 minutes),
                _fixedTermStaking._lastFeedTime(),
                uint64(block.timestamp)
            )
        );
        _fixedTermStaking.feed(_currentTime + 1 days + 1 minutes);
    }

    /// @dev Certificats of Deposit (CoD)
    struct CoD {
        uint256 tokenId;
        address owner;
        uint128 principal;
    }

    /// @dev Organize CoDs by maturity date for unstaking later
    mapping(uint64 => CoD[]) cods;

    function testIntegration() public {
        for (uint256 dates = 0; dates < 365; ++dates) {
            vm.warp((_currentTime += 1 days) + 1 minutes);

            /// @dev Random number of stakes today (1-20)
            uint256 stakeTimesToday = bound(_randomUint256(), 1, 20);
            for (uint256 stake = 0; stake < stakeTimesToday; ++stake) {
                /// @dev Random amount to stake (1-1000 USDC)
                uint128 amountToStake = uint128(bound(_randomUint256(), 10 ** 6, 1_000 * 10 ** 6));
                /// @dev Unique address for each stake
                address someone = makeAddr(string(abi.encodePacked("someone", vm.toString(dates), vm.toString(stake))));
                /// @dev Fund, whitelist and stake
                _fundUser(someone, amountToStake);
                _whitelistUser(someone);
                uint256 tokenId = _stake(someone, amountToStake, false);
                (uint128 principal,, uint64 maturityDate,) = _fixedTermStaking._tokenId_stakeInfo(tokenId);
                cods[maturityDate].push(
                    CoD({tokenId: tokenId, owner: _fixedTermStaking.ownerOf(tokenId), principal: principal})
                );
            }

            /// @dev Random price floating
            _randomPriceFloating();
            /// @dev Feed
            if (_fixedTermStaking.feed(_currentTime)) {
                assertEq(
                    uint256(uint128(int128(_fixedTermStaking._totalPrincipal()) + _fixedTermStaking._totalInterest())),
                    _fixedTermStaking.getTotalAssetValueInBasket()
                );
            }
        }

        for (uint256 dates = 365; dates < 365 + 10; ++dates) {
            vm.warp((_currentTime += 1 days) + 1 minutes);

            uint256 stakeTimesToday = bound(_randomUint256(), 1, 20);
            for (uint256 stake = 0; stake < stakeTimesToday; ++stake) {
                /// @dev Random amount to stake (1-1000 USDC)
                uint128 amountToStake = uint128(bound(_randomUint256(), 10 ** 6, 1_000 * 10 ** 6));
                /// @dev Unique address for each stake
                address someone = makeAddr(string(abi.encodePacked("someone", vm.toString(dates), vm.toString(stake))));
                /// @dev Fund, whitelist and stake
                _fundUser(someone, amountToStake);
                _whitelistUser(someone);
                uint256 tokenId = _stake(someone, amountToStake, false);
                (uint128 principal,, uint64 maturityDate,) = _fixedTermStaking._tokenId_stakeInfo(tokenId);
                cods[maturityDate].push(
                    CoD({tokenId: tokenId, owner: _fixedTermStaking.ownerOf(tokenId), principal: principal})
                );
            }

            /// @dev Random price floating
            _randomPriceFloating();
            /// @dev Feed
            if (_fixedTermStaking.feed(_currentTime)) {
                assertEq(
                    uint256(uint128(int128(_fixedTermStaking._totalPrincipal()) + _fixedTermStaking._totalInterest())),
                    _fixedTermStaking.getTotalAssetValueInBasket()
                );
            }

            /// @dev Unstake all CoDs that have reached maturity today
            uint64 normalizedDate = uint64(((block.timestamp - 1 minutes + 17 hours) / 1 days) * 1 days + 7 hours);

            for (uint256 i = 0; i < cods[normalizedDate].length; ++i) {
                CoD memory cod = cods[normalizedDate][i];
                vm.prank(cod.owner);
                _fixedTermStaking.approve(address(_fixedTermStaking), cod.tokenId);
                vm.prank(cod.owner);
                _fixedTermStaking.unstake(cod.tokenId);
                uint128 userBalanceAfterUnstake = uint128(_underlyingToken.balanceOf(cod.owner));
                console.log("APY (in million):", userBalanceAfterUnstake * 1_000_000 / cod.principal);
            }
        }
    }

    function testBoringOpenTermStakingOnlyInitialized() public {
        BoringFixedTermStaking boringFixedTermStaking = new BoringFixedTermStaking();

        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.Uninitialized.selector, "underlyingToken"));
        boringFixedTermStaking.boringTestOnlyInitialized();

        stdstore.target(address(boringFixedTermStaking)).sig(FixedTermStaking.underlyingToken.selector).checked_write(
            address(_underlyingToken)
        );
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.Uninitialized.selector, "whitelist"));
        boringFixedTermStaking.boringTestOnlyInitialized();

        stdstore.target(address(boringFixedTermStaking)).sig(FixedTermStaking.whitelist.selector).checked_write(
            address(_whitelist)
        );
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.Uninitialized.selector, "exchanger"));
        boringFixedTermStaking.boringTestOnlyInitialized();

        stdstore.target(address(boringFixedTermStaking)).sig(FixedTermStaking.exchanger.selector).checked_write(
            address(_exchanger)
        );
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.Uninitialized.selector, "lockPeriod"));
        boringFixedTermStaking.boringTestOnlyInitialized();

        stdstore.enable_packed_slots().target(address(boringFixedTermStaking)).sig(FixedTermStaking.lockPeriod.selector)
            .checked_write(_lockPeriod);
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.Uninitialized.selector, "maxSupply"));
        boringFixedTermStaking.boringTestOnlyInitialized();

        stdstore.enable_packed_slots().target(address(boringFixedTermStaking)).sig(FixedTermStaking.maxSupply.selector)
            .checked_write(_maxSupply);
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.Uninitialized.selector, "lastFeedTime"));
        boringFixedTermStaking.boringTestOnlyInitialized();

        stdstore.enable_packed_slots().target(address(boringFixedTermStaking)).sig(
            FixedTermStaking.lastFeedTime.selector
        ).checked_write(_normalizeTimestamp(_startFeedTime));
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.Uninitialized.selector, "assetsInfoBasket"));
        boringFixedTermStaking.boringTestOnlyInitialized();
    }

    function testBoringOpenTermStakingOnlyWhitelist() public {
        BoringFixedTermStaking boringFixedTermStaking = new BoringFixedTermStaking();

        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.ZeroAddress.selector, "whitelist"));
        boringFixedTermStaking.boringTestOnlyWhitelist();

        stdstore.target(address(boringFixedTermStaking)).sig(FixedTermStaking.whitelist.selector).checked_write(
            address(_whitelist)
        );
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.ZeroAddress.selector, "user"));
        vm.prank(address(0x0));
        boringFixedTermStaking.boringTestOnlyWhitelist();
        vm.expectRevert(abi.encodeWithSelector(IWhitelist.NotWhitelisted.selector, _nonWhitelistedUser1));
        vm.prank(_nonWhitelistedUser1);
        boringFixedTermStaking.boringTestOnlyWhitelist();
    }

    function testBoringOpenTermStake() public {
        BoringFixedTermStaking boringFixedTermStaking = new BoringFixedTermStaking();

        stdstore.target(address(boringFixedTermStaking)).sig(FixedTermStaking.underlyingToken.selector).checked_write(
            address(_underlyingToken)
        );
        stdstore.target(address(boringFixedTermStaking)).sig(FixedTermStaking.whitelist.selector).checked_write(
            address(_whitelist)
        );
        stdstore.target(address(boringFixedTermStaking)).sig(FixedTermStaking.exchanger.selector).checked_write(
            address(_exchanger)
        );
        stdstore.enable_packed_slots().target(address(boringFixedTermStaking)).sig(FixedTermStaking.lockPeriod.selector)
            .checked_write(_lockPeriod);
        stdstore.enable_packed_slots().target(address(boringFixedTermStaking)).sig(FixedTermStaking.maxSupply.selector)
            .checked_write(_maxSupply);
        stdstore.enable_packed_slots().target(address(boringFixedTermStaking)).sig(
            FixedTermStaking.lastFeedTime.selector
        ).checked_write(_normalizeTimestamp(_startFeedTime));

        address operator = makeAddr("operator");
        stdstore.target(address(boringFixedTermStaking)).sig(AccessControlUpgradeable.hasRole.selector).with_key(
            Roles.OPERATOR_ROLE
        ).with_key(operator).checked_write(true);
        vm.prank(operator);
        boringFixedTermStaking.addNewAssetIntoBasket(_assetsInfoBasket);

        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.ZeroAddress.selector, "from"));
        boringFixedTermStaking.boringTestStake(1000, address(0), address(0x01));
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.ZeroAddress.selector, "to"));
        boringFixedTermStaking.boringTestStake(1000, address(0x01), address(0));
    }

    function testBoringOpenTermUnstake() public {
        BoringFixedTermStaking boringFixedTermStaking = BoringFixedTermStaking(
            address(
                new TransparentUpgradeableProxy(
                    address(new BoringFixedTermStaking()),
                    _owner,
                    abi.encodeWithSelector(
                        FixedTermStaking.initialize.selector,
                        [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
                        (
                            uint256(_lockPeriod) | (uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128)
                                | (uint256(_startFeedTime) << 192)
                        ),
                        (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
                        "mosUSD12M+",
                        "mosUSD12M+",
                        _assetsInfoBasket
                    )
                )
            )
        );

        vm.startPrank(_owner);

        _underlyingToken.grantRole(Roles.OPERATOR_ROLE, address(boringFixedTermStaking));

        _exchanger.grantRole(Roles.INVESTMENT_MANAGER_ROLE, address(boringFixedTermStaking));

        vm.stopPrank();

        vm.startPrank(_whitelistedUser1);

        _depositToken.approve(address(_exchanger), 1_000_000 * 10 ** 6);
        _exchanger.exchange(1_000_000 * 10 ** 6, true);

        uint128 userBalanceBeforeStake = uint128(_underlyingToken.balanceOf(_whitelistedUser1));
        uint128 poolBalanceBeforeStake = uint128(_underlyingToken.balanceOf(address(boringFixedTermStaking)));

        assertGe(userBalanceBeforeStake, 1_000_000 * 10 ** 6);

        _underlyingToken.approve(address(boringFixedTermStaking), uint256(1_000_000 * 10 ** 6));

        boringFixedTermStaking.stake(1_000_000 * 10 ** 6);

        vm.stopPrank();

        uint128 userBalanceAfterStake = uint128(_underlyingToken.balanceOf(_whitelistedUser1));
        uint128 poolBalanceAfterStake = uint128(_underlyingToken.balanceOf(address(boringFixedTermStaking)));

        uint128 totalFee = boringFixedTermStaking._totalFee();
        uint128 totalPrincipal = boringFixedTermStaking._totalPrincipal();
        int128 totalInterest = boringFixedTermStaking._totalInterest();

        assertEq(userBalanceBeforeStake - userBalanceAfterStake, 1_000_000 * 10 ** 6);
        assertEq(poolBalanceAfterStake - poolBalanceBeforeStake, 1_000_000 * 10 ** 6);
        assertEq(int128(poolBalanceAfterStake), int128(totalFee) + int128(totalPrincipal) + totalInterest);

        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.ZeroAddress.selector, "from"));
        boringFixedTermStaking.boringTestUnstake(1, address(0), address(0x01));
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.ZeroAddress.selector, "to"));
        boringFixedTermStaking.boringTestUnstake(1, address(0x01), address(0));
    }

    function testUnderlyingToken() public view {
        assertEq(address(_fixedTermStaking.underlyingToken()), address(_underlyingToken));
    }

    function testWhitelist() public view {
        assertEq(address(_fixedTermStaking.whitelist()), address(_whitelist));
    }

    function testExchanger() public view {
        assertEq(address(_fixedTermStaking.exchanger()), address(_exchanger));
    }

    function testTotalPrincipal() public view {
        assertEq(_fixedTermStaking.totalPrincipal(), 0);
    }

    function testTotalFee() public view {
        assertEq(_fixedTermStaking.totalFee(), 0);
    }

    function testTotalInterest() public view {
        assertEq(_fixedTermStaking.totalInterest(), 0);
    }

    function testRemainingBalance() public view {
        assertEq(_fixedTermStaking.remainingBalance(), _maxSupply);
    }

    function testDustBalance() public view {
        assertEq(_fixedTermStaking.dustBalance(), _dustBalance);
    }

    function testMaxSupply() public view {
        assertEq(_fixedTermStaking.maxSupply(), _maxSupply);
    }

    function testLastFeedTime() public view {
        assertEq(_fixedTermStaking.lastFeedTime(), _normalizeTimestamp(_startFeedTime));
    }

    function testLockPeriod() public view {
        assertEq(_fixedTermStaking.lockPeriod(), _lockPeriod);
    }

    function testStakeFeeRate() public view {
        assertEq(_fixedTermStaking.stakeFeeRate(), _stakeFeeRate);
    }

    function testUnstakeFeeRate() public view {
        assertEq(_fixedTermStaking.unstakeFeeRate(), _unstakeFeeRate);
    }

    function testTokenIDToStakeInfo() public {
        uint256 tokenId = _stake(_whitelistedUser1, 100_000 * 10 ** 6, true);
        FixedTermStaking.StakeInfo memory stakeInfo = _fixedTermStaking.tokenIDToStakeInfo(tokenId);

        assertEq(stakeInfo.principal, 100_000 * 10 ** 6 * (10 ** 6 - _stakeFeeRate) / 10 ** 6);
        assertEq(stakeInfo.startDate, _normalizeTimestamp(uint64(block.timestamp)));
        assertEq(stakeInfo.maturityDate, _normalizeTimestamp(uint64(block.timestamp + 365 days)));
        assertEq(uint8(stakeInfo.status), uint8(FixedTermStaking.StakeStatus.ACTIVE));

        assertEq(_fixedTermStaking.principalStartFrom(stakeInfo.startDate), stakeInfo.principal);
        assertEq(_fixedTermStaking.principalMatureAt(stakeInfo.maturityDate), stakeInfo.principal);
    }

    function testAssetsInfoBasket() public view {
        FixedTermStaking.AssetInfo[] memory assetsInfoBasket = _fixedTermStaking.assetsInfoBasket();

        assertEq(assetsInfoBasket.length, _assetsInfoBasket.length);

        for (uint256 i = 0; i < assetsInfoBasket.length; ++i) {
            assertEq(assetsInfoBasket[i].targetVault, _assetsInfoBasket[i].targetVault);
            assertEq(assetsInfoBasket[i].weight, _assetsInfoBasket[i].weight);
        }
    }

    function testAssetInfoAt() public view {
        for (uint256 i = 0; i < _assetsInfoBasket.length; ++i) {
            FixedTermStaking.AssetInfo memory assetInfo = _fixedTermStaking.assetInfoAt(i);
            assertEq(assetInfo.targetVault, _assetsInfoBasket[i].targetVault);
            assertEq(assetInfo.weight, _assetsInfoBasket[i].weight);
        }
    }

    function testAddNewAssetIntoBasket() public {
        FixedTermStaking.AssetInfo[] memory assetsIntoBasket = new FixedTermStaking.AssetInfo[](2);
        assetsIntoBasket[0] = FixedTermStaking.AssetInfo({
            targetVault: address(new AssetVault(IERC20(address(_depositToken)), "MMF@mosUSD", "MMF@mosUSD")),
            weight: 250_000 // 25%
        });
        assetsIntoBasket[1] = FixedTermStaking.AssetInfo({
            targetVault: address(new AssetVault(IERC20(address(_depositToken)), "RWA@mosUSD", "RWA@mosUSD")),
            weight: 250_000 // 25%
        });

        FixedTermStaking.AssetInfo[] memory newAssetsIntoBasket = new FixedTermStaking.AssetInfo[](2);
        newAssetsIntoBasket[0] = FixedTermStaking.AssetInfo({
            targetVault: address(new AssetVault(IERC20(address(_depositToken)), "BTC@mosUSD", "BTC@mosUSD")),
            weight: 300_000 // 30%
        });
        newAssetsIntoBasket[1] = FixedTermStaking.AssetInfo({
            targetVault: address(new AssetVault(IERC20(address(_depositToken)), "ETH@mosUSD", "ETH@mosUSD")),
            weight: 300_000 // 30%
        });

        vm.startPrank(_owner);

        FixedTermStaking fixedTermStaking = FixedTermStaking(
            _deployer.deployFixedTermStaking(
                [_owner, address(_underlyingToken), address(_whitelist), address(_exchanger)],
                (
                    uint256(_lockPeriod) | (uint256(_stakeFeeRate) << 64) | (uint256(_unstakeFeeRate) << 128)
                        | (uint256(_startFeedTime) << 192)
                ),
                (uint256(_dustBalance) | (uint256(_maxSupply) << 128)),
                "mosUSD12M+",
                "mosUSD12M+",
                assetsIntoBasket
            )
        );

        fixedTermStaking.grantRole(Roles.OPERATOR_ROLE, _owner);

        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.InvalidValue.selector, "empty newAssetInfo"));
        vm.prank(_owner);
        fixedTermStaking.addNewAssetIntoBasket(new FixedTermStaking.AssetInfo[](0));

        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.ZeroAddress.selector, "new asset's vault"));
        vm.prank(_owner);
        fixedTermStaking.addNewAssetIntoBasket(new FixedTermStaking.AssetInfo[](1));

        newAssetsIntoBasket[0].weight = 0;
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.InvalidValue.selector, "weight of new asset in basket"));
        vm.prank(_owner);
        fixedTermStaking.addNewAssetIntoBasket(newAssetsIntoBasket);

        newAssetsIntoBasket[0].weight = 300_000;
        vm.expectRevert(
            abi.encodeWithSelector(
                FixedTermStaking.InvalidValue.selector, "total weight of assets in basket and new assets"
            )
        );
        vm.prank(_owner);
        fixedTermStaking.addNewAssetIntoBasket(newAssetsIntoBasket);

        newAssetsIntoBasket[0] = FixedTermStaking.AssetInfo({
            targetVault: address(new AssetVault(IERC20(address(0xdeadbeef)), "BTC@mosUSD", "BTC@mosUSD")),
            weight: 200_000 // 20%
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                FixedTermStaking.VaultAssetNotEqualExchangerToken1.selector, address(0xdeadbeef), address(_depositToken)
            )
        );
        vm.prank(_owner);
        fixedTermStaking.addNewAssetIntoBasket(newAssetsIntoBasket);

        newAssetsIntoBasket[0] = FixedTermStaking.AssetInfo({
            targetVault: address(new AssetVault(IERC20(address(_depositToken)), "BTC@mosUSD", "BTC@mosUSD")),
            weight: 200_000 // 20%
        });
        vm.prank(_owner);
        fixedTermStaking.addNewAssetIntoBasket(newAssetsIntoBasket);
    }

    function testBoringFixedTermToken() public {
        vm.expectEmit(false, false, false, true);
        emit Initializable.Initialized(type(uint64).max);
        new MockFixedTermToken();

        MockFixedTermToken boringFixedTermToken = MockFixedTermToken(
            address(
                new TransparentUpgradeableProxy(
                    address(new MockFixedTermToken()),
                    _owner,
                    abi.encodeWithSelector(MockFixedTermToken.initialize.selector, "Boring Fixed Term Token", "BFTT")
                )
            )
        );

        vm.expectRevert("INVALID_TO_ADDRESS");
        boringFixedTermToken.wrapperMint(address(0x0));

        boringFixedTermToken.wrapperMint(address(0xffff));
        boringFixedTermToken.wrapperMint(address(0xffff));
        boringFixedTermToken.wrapperMint(address(0xffff));
        boringFixedTermToken.wrapperMint(address(0xffff));

        vm.startPrank(address(0xffff));
        boringFixedTermToken.approve(address(boringFixedTermToken), 2);
        boringFixedTermToken.wrapperBurn(2);
        vm.stopPrank();

        vm.expectRevert("NOT_APPROVED");
        vm.prank(address(0x1234));
        boringFixedTermToken.wrapperBurn(1);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 0));
        boringFixedTermToken.tokenURI(0);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 5));
        boringFixedTermToken.tokenURI(5);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 2));
        boringFixedTermToken.tokenURI(2);

        MockFixedTermToken directCallMockFixedTermToken = new MockFixedTermToken();
        vm.expectRevert("INVALID_TO_ADDRESS");
        directCallMockFixedTermToken.wrapperMint(address(0x0));
    }

    function _fundUser(address user_, uint128 amount_) internal {
        _depositToken.mint(user_, amount_);
    }

    function _whitelistUser(address user_) internal {
        vm.prank(_owner);
        _whitelist.add(user_);
    }

    function _stake(address user_, uint128 amountToStake_, bool stakeFrom_) internal returns (uint256 tokenId_) {
        vm.startPrank(user_);

        _depositToken.approve(address(_exchanger), amountToStake_);
        _exchanger.exchange(amountToStake_, true);

        uint128 userBalanceBeforeStake = uint128(_underlyingToken.balanceOf(user_));
        uint128 poolBalanceBeforeStake = uint128(_underlyingToken.balanceOf(address(_fixedTermStaking)));

        assertGe(userBalanceBeforeStake, amountToStake_);

        _underlyingToken.approve(address(_fixedTermStaking), uint256(amountToStake_));

        vm.stopPrank();

        if (stakeFrom_) {
            vm.prank(_owner);
            tokenId_ = _fixedTermStaking.stakeFrom(amountToStake_, user_);
        } else {
            vm.prank(user_);
            tokenId_ = _fixedTermStaking.stake(amountToStake_);
        }

        uint128 userBalanceAfterStake = uint128(_underlyingToken.balanceOf(user_));
        uint128 poolBalanceAfterStake = uint128(_underlyingToken.balanceOf(address(_fixedTermStaking)));

        uint128 totalFee = _fixedTermStaking._totalFee();
        uint128 totalPrincipal = _fixedTermStaking._totalPrincipal();
        int128 totalInterest = _fixedTermStaking._totalInterest();

        assertEq(userBalanceBeforeStake - userBalanceAfterStake, amountToStake_);
        assertEq(poolBalanceAfterStake - poolBalanceBeforeStake, amountToStake_);
        assertEq(int128(poolBalanceAfterStake), int128(totalFee) + int128(totalPrincipal) + totalInterest);
    }

    function _randomPriceFloating() internal {
        vm.startPrank(_owner);
        for (uint256 i = 0; i < _assetsInfoBasket.length; ++i) {
            _depositToken.transfer(
                _assetsInfoBasket[i].targetVault,
                _randomUint256() % 70_000 * IERC4626(_assetsInfoBasket[i].targetVault).totalAssets() / 1_000_000 / 365
            );
        }
        vm.stopPrank();
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

contract BoringFixedTermStaking is FixedTermStaking {
    function boringTestOnlyWhitelist() public view onlyWhitelisted(msg.sender) returns (bool) {
        return true;
    }

    function boringTestOnlyInitialized() public view onlyInitialized returns (bool) {
        return true;
    }

    function boringTestStake(uint128 stakeAmount_, address from_, address to_) public returns (uint256) {
        return _stake(stakeAmount_, from_, to_);
    }

    function boringTestUnstake(uint256 tokenId_, address from_, address to_) public returns (uint128) {
        return _unstake(tokenId_, from_, to_);
    }
}

contract MockFixedTermToken is FixedTermToken {
    constructor() FixedTermToken() {
        if (_getInitializedVersion() != type(uint64).max) {
            revert("undisabled initializer");
        }
    }

    function initialize(string memory tokenName, string memory tokenSymbol) external initializer {
        __FixedTermToken_init(tokenName, tokenSymbol);
    }

    function readFixedTermTokenDetails(uint256 /* tokenId_ */ )
        internal
        view
        override(FixedTermToken)
        returns (uint128 principal_, uint64 startDate_, uint64 maturityDate_)
    {
        return (100_000_000_000, uint64(block.timestamp), uint64(block.timestamp + 365 days));
    }

    function wrapperMint(address to_) public {
        mint(to_);
    }

    function wrapperBurn(uint256 tokenId_) public {
        burn(tokenId_);
    }
}
