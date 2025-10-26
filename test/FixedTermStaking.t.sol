// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

import {FixedTermStaking} from "src/protocols/fixed-term/FixedTermStaking.sol";
import {UnderlyingToken} from "src/underlying/UnderlyingToken.sol";
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

contract FixedTermStakingTest is Test {
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

    modifier deployFixedTermStaking() {
        _assetsInfoBasket.push(
            FixedTermStaking.AssetInfo({
                targetVault: address(new AssetVault(IERC20(address(_depositToken)), "MMF@lbUSD", "MMF@lbUSD")),
                weight: 500_000 // 50%
            })
        );

        _assetsInfoBasket.push(
            FixedTermStaking.AssetInfo({
                targetVault: address(new AssetVault(IERC20(address(_depositToken)), "RWA@lbUSD", "RWA@lbUSD")),
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
                "lbUSD12M+",
                "lbUSD12M+",
                _assetsInfoBasket
            )
        );

        _fixedTermStaking.grantRole(Roles.OPERATOR_ROLE, _owner);

        vm.stopPrank();

        vm.label(address(_fixedTermStaking), "lbUSD12M+");
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
    }

    function testUpdateMaxSupply() public {
        vm.prank(_owner);
        _fixedTermStaking.updateMaxSupply(_maxSupply * 2);
        assertEq(_fixedTermStaking._maxSupply(), _maxSupply * 2);
    }

    function testUpdateMaxSupplyOverTotalPrincipal() public {
        _stake(_whitelistedUser1, 1_000_000 * 10 ** 6, false);
        uint128 newMaxSupply = _fixedTermStaking._totalPrincipal() - 1;
        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSelector(FixedTermStaking.InvalidValue.selector, "newMaxSupply"));
        _fixedTermStaking.updateMaxSupply(newMaxSupply);
    }

    function testPauseWhenUnpaused() public {
        vm.prank(_owner);
        _fixedTermStaking.pause();
        assertTrue(_fixedTermStaking.paused());
    }

    function testPausedWhenPaused() public {
        vm.prank(_owner);
        _fixedTermStaking.pause();
        assertTrue(_fixedTermStaking.paused());
        vm.prank(_whitelistedUser1);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        _fixedTermStaking.stake(1_000 * 10 ** 6);
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

        uint128 totalAssetValueInBasket = _fixedTermStaking.getTotalAssetValueInBasket();
        uint128 totalFee = _fixedTermStaking._totalFee();
        uint128 totalPrincipal = _fixedTermStaking._totalPrincipal();
        int128 totalInterest = _fixedTermStaking._totalInterest();

        assertEq(userBalanceBeforeStake - userBalanceAfterStake, amountToStake_);
        assertEq(poolBalanceAfterStake - poolBalanceBeforeStake, amountToStake_);
        assertEq(int128(poolBalanceAfterStake), int128(totalFee) + int128(totalPrincipal) + totalInterest);

        assertLe(
            int128(totalAssetValueInBasket) > int128(totalPrincipal) + totalInterest
                ? int128(totalAssetValueInBasket) - (int128(totalPrincipal) + totalInterest)
                : (int128(totalPrincipal) + totalInterest) - int128(totalAssetValueInBasket),
            125
        );
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
}
