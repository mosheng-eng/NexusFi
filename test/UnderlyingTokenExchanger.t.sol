// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {Roles} from "src/common/Roles.sol";
import {Errors} from "src/common/Errors.sol";
import {UnderlyingToken} from "src/underlying/UnderlyingToken.sol";
import {UnderlyingTokenExchanger} from "src/underlying/UnderlyingTokenExchanger.sol";
import {Whitelist} from "src/whitelist/Whitelist.sol";
import {IWhitelist} from "src/whitelist/IWhitelist.sol";
import {DeployContractSuit} from "script/DeployContractSuit.s.sol";

import {DepositAsset} from "test/mock/DepositAsset.sol";

import {stdStorage, StdStorage, Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

contract UnderlyingTokenExchangerTest is Test {
    using stdStorage for StdStorage;

    DeployContractSuit internal _deployer = new DeployContractSuit();
    UnderlyingTokenExchanger internal _exchanger;
    Whitelist internal _whitelist;
    DepositAsset internal _depositToken;
    UnderlyingToken internal _underlyingToken;

    address internal _owner = makeAddr("owner");
    address internal _whitelistedUser1 = makeAddr("whitelistedUser1");
    address internal _whitelistedUser2 = makeAddr("whitelistedUser2");
    address internal _nonWhitelistedUser1 = makeAddr("nonWhitelistedUser1");
    address internal _nonWhitelistedUser2 = makeAddr("nonWhitelistedUser2");

    modifier deployUnderlyingToken() {
        vm.startPrank(_owner);

        _underlyingToken = UnderlyingToken(_deployer.deployUnderlyingToken(_owner, "mosUSD", "mosUSD"));

        _underlyingToken.grantRole(Roles.OPERATOR_ROLE, address(_owner));

        vm.stopPrank();

        vm.label(address(_underlyingToken), "mosUSD");

        _;
    }

    modifier deployDepositToken() {
        _depositToken = new DepositAsset("USD Coin", "USDC");

        _depositToken.mint(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _depositToken.mint(_whitelistedUser2, 1_000_000 * 10 ** 6);
        _depositToken.mint(_nonWhitelistedUser1, 1_000_000 * 10 ** 6);
        _depositToken.mint(_nonWhitelistedUser2, 1_000_000 * 10 ** 6);

        vm.label(address(_depositToken), "USDC");

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

    modifier deployExchanger() {
        address[4] memory addrs = [address(_underlyingToken), address(_depositToken), address(_whitelist), _owner];
        uint256 properties = (uint256(1e6) | (uint256(1e6) << 64) | (uint256(1e6) << 128));

        vm.startPrank(_owner);

        _exchanger = UnderlyingTokenExchanger(_deployer.deployExchanger(addrs, properties));

        _exchanger.grantRole(Roles.OPERATOR_ROLE, address(_owner));

        vm.stopPrank();

        vm.label(address(_exchanger), "Exchanger");
        vm.label(address(_depositToken), "USDC");

        _;
    }

    modifier setContractDependencies() {
        vm.startPrank(_owner);

        _underlyingToken.grantRole(Roles.OPERATOR_ROLE, address(_exchanger));

        vm.stopPrank();

        _;
    }

    function setUp()
        public
        deployDepositToken
        deployWhitelist
        deployUnderlyingToken
        deployExchanger
        setContractDependencies
    {
        vm.label(_owner, "owner");
    }

    function testNull() public {}

    function testWhitelistUserDeposit() public {
        vm.startPrank(_whitelistedUser1);

        _depositToken.approve(address(_exchanger), 1_000_000 * 10 ** 6);
        _exchanger.exchange(1_000_000 * 10 ** 6, true);

        assertEq(_underlyingToken.balanceOf(_whitelistedUser1), 1_000_000 * 10 ** 6);
        assertEq(_depositToken.balanceOf(_whitelistedUser1), 0);

        vm.stopPrank();
    }

    function testWhitelistUserDepositWithdraw() public {
        vm.startPrank(_whitelistedUser1);

        _depositToken.approve(address(_exchanger), 1_000_000 * 10 ** 6);
        vm.expectEmit(true, false, false, true, address(_exchanger));
        emit UnderlyingTokenExchanger.Exchanged(_whitelistedUser1, true, 1_000_000 * 10 ** 6, 1_000_000 * 10 ** 6);
        _exchanger.exchange(1_000_000 * 10 ** 6, true);

        assertEq(_underlyingToken.balanceOf(_whitelistedUser1), 1_000_000 * 10 ** 6);
        assertEq(_depositToken.balanceOf(_whitelistedUser1), 0);

        _underlyingToken.approve(address(_exchanger), 1_000_000 * 10 ** 6);
        vm.expectEmit(true, false, false, true, address(_exchanger));
        emit UnderlyingTokenExchanger.Exchanged(_whitelistedUser1, false, 1_000_000 * 10 ** 6, 1_000_000 * 10 ** 6);
        _exchanger.exchange(1_000_000 * 10 ** 6, false);

        assertEq(_underlyingToken.balanceOf(_whitelistedUser1), 0);
        assertEq(_depositToken.balanceOf(_whitelistedUser1), 1_000_000 * 10 ** 6);

        vm.stopPrank();
    }

    function testNonWhitelistUserDeposit() public {
        vm.startPrank(_nonWhitelistedUser1);

        _depositToken.approve(address(_exchanger), 1_000_000 * 10 ** 6);
        vm.expectRevert(abi.encodeWithSelector(IWhitelist.NotWhitelisted.selector, _nonWhitelistedUser1));
        _exchanger.exchange(1_000_000 * 10 ** 6, true);

        assertEq(_underlyingToken.balanceOf(_nonWhitelistedUser1), 0);
        assertEq(_depositToken.balanceOf(_nonWhitelistedUser1), 1_000_000 * 10 ** 6);

        vm.stopPrank();
    }

    function testUpdateExchangeRate() public {
        vm.startPrank(_owner);

        uint64 token0_token1_rate = _exchanger._token0_token1_rate();
        uint64 token1_token0_rate = _exchanger._token1_token0_rate();

        vm.expectEmit(false, false, false, true, address(_exchanger));
        emit UnderlyingTokenExchanger.ExchangeRatesUpdated(true, token0_token1_rate, 2_000_000);
        _exchanger.updateExchangeRate(true, 2_000_000);

        vm.expectEmit(false, false, false, true, address(_exchanger));
        emit UnderlyingTokenExchanger.ExchangeRatesUpdated(false, token1_token0_rate, 2_000_000);
        _exchanger.updateExchangeRate(false, 2_000_000);

        vm.stopPrank();

        assertEq(_exchanger._token0_token1_rate(), 2_000_000);
        assertEq(_exchanger._token1_token0_rate(), 2_000_000);
    }

    function testUpdateExchangeRateToZero() public {
        vm.startPrank(_owner);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "new_exchange_rate"));
        _exchanger.updateExchangeRate(true, 0);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "new_exchange_rate"));
        _exchanger.updateExchangeRate(false, 0);

        vm.stopPrank();
    }

    function testNonInitializedExchanger() public {
        UnderlyingTokenExchanger exchanger2 = new UnderlyingTokenExchanger();

        vm.startPrank(_whitelistedUser1);

        _depositToken.approve(address(exchanger2), 1_000_000 * 10 ** 6);
        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "token0"));
        exchanger2.exchange(1_000_000 * 10 ** 6, true);

        vm.stopPrank();
    }

    function testContractName() public view {
        assertEq(_exchanger.contractName(), "UnderlyingTokenExchanger");
        assertEq(_underlyingToken.contractName(), "UnderlyingToken");
    }

    function testInvalidInitialize() public {
        address[4] memory addrs = [address(_underlyingToken), address(_depositToken), address(_whitelist), _owner];
        uint256 properties = (uint256(1e6) | (uint256(1e6) << 64) | (uint256(1e6) << 128));

        addrs[0] = address(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "token0"));
        _deployer.deployExchanger(addrs, properties);
        addrs[0] = address(_underlyingToken);

        addrs[1] = address(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "token1"));
        _deployer.deployExchanger(addrs, properties);
        addrs[1] = address(_depositToken);

        addrs[2] = address(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "whitelist"));
        _deployer.deployExchanger(addrs, properties);
        addrs[2] = address(_whitelist);

        addrs[3] = address(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "owner"));
        _deployer.deployExchanger(addrs, properties);
        addrs[3] = _owner;

        properties = (uint256(0) | (uint256(1e6) << 64) | (uint256(1e6) << 128));
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "precision"));
        _deployer.deployExchanger(addrs, properties);

        properties = (uint256(1e6) | (uint256(0) << 64) | (uint256(1e6) << 128));
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "token0_token1_rate"));
        _deployer.deployExchanger(addrs, properties);

        properties = (uint256(1e6) | (uint256(1e6) << 64) | (uint256(0) << 128));
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "token1_token0_rate"));
        _deployer.deployExchanger(addrs, properties);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "owner"));
        _deployer.deployUnderlyingToken(address(0), "mosUSD", "mosUSD");
    }

    function testBoringExchange() public {
        vm.startPrank(_whitelistedUser1);
        _depositToken.approve(address(_exchanger), 1_000_000 * 10 ** 6);
        _underlyingToken.approve(address(_exchanger), 1_000_000 * 10 ** 6);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "amountIn"));
        vm.prank(_whitelistedUser1);
        _exchanger.exchange(0, true);

        vm.startPrank(_whitelistedUser1);
        _exchanger.dryrunExchange(500_000 * 10 ** 6, true);
        _exchanger.dryrunExchange(250_000 * 10 ** 6, false);
        _exchanger.exchange(500_000 * 10 ** 6, true);
        _exchanger.exchange(250_000 * 10 ** 6, false);
        vm.stopPrank();
    }

    function testExtractDepositTokenForInvestment() public {
        address manager = makeAddr("manager");
        vm.prank(_owner);
        _exchanger.grantRole(Roles.INVESTMENT_MANAGER_ROLE, manager);

        vm.startPrank(manager);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "amount"));
        _exchanger.extractDepositTokenForInvestment(0);
        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientBalance.selector, 0, 1));
        _exchanger.extractDepositTokenForInvestment(1);
        vm.stopPrank();
    }

    function testNondirectCallToExchanger() public {
        address[4] memory addrs = [address(_underlyingToken), address(_depositToken), address(_whitelist), _owner];
        uint256 properties = (uint256(1e6) | (uint256(1e6) << 64) | (uint256(1e6) << 128));

        UnderlyingTokenExchanger mockContract = new UnderlyingTokenExchanger();
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        mockContract.initialize(addrs, properties);
    }

    function testNondirectCallToToken() public {
        UnderlyingToken mockContract = new UnderlyingToken();
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        mockContract.initialize(_owner, "mosUSD", "mosUSD");
    }

    function testBoringExchangerOnlyWhitelist() public {
        BoringUnderlyingTokenExchanger boringExchanger = new BoringUnderlyingTokenExchanger();

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "whitelist"));
        boringExchanger.boringTestOnlyWhitelist();

        stdstore.target(address(boringExchanger)).sig(UnderlyingTokenExchanger.whitelist.selector).checked_write(
            address(_whitelist)
        );
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "user"));
        vm.prank(address(0x0));
        boringExchanger.boringTestOnlyWhitelist();
        vm.expectRevert(abi.encodeWithSelector(IWhitelist.NotWhitelisted.selector, _nonWhitelistedUser1));
        vm.prank(_nonWhitelistedUser1);
        boringExchanger.boringTestOnlyWhitelist();
    }

    function testBoringExchangerOnlyInitialized() public {
        BoringUnderlyingTokenExchanger boringExchanger = new BoringUnderlyingTokenExchanger();

        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "token0"));
        boringExchanger.boringTestOnlyInitialized();

        stdstore.enable_packed_slots().target(address(boringExchanger)).sig(UnderlyingTokenExchanger.token0.selector)
            .checked_write(address(_underlyingToken));
        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "token0"));
        boringExchanger.boringTestOnlyInitialized();

        stdstore.enable_packed_slots().target(address(boringExchanger)).sig(
            UnderlyingTokenExchanger.token0Decimals.selector
        ).checked_write(6);
        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "token1"));
        boringExchanger.boringTestOnlyInitialized();

        stdstore.enable_packed_slots().target(address(boringExchanger)).sig(UnderlyingTokenExchanger.token1.selector)
            .checked_write(address(_depositToken));
        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "token1"));
        boringExchanger.boringTestOnlyInitialized();

        stdstore.enable_packed_slots().target(address(boringExchanger)).sig(
            UnderlyingTokenExchanger.token1Decimals.selector
        ).checked_write(6);
        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "precision"));
        boringExchanger.boringTestOnlyInitialized();

        stdstore.enable_packed_slots().target(address(boringExchanger)).sig(UnderlyingTokenExchanger.precision.selector)
            .checked_write(1e6);
        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "token0_token1_rate"));
        boringExchanger.boringTestOnlyInitialized();

        stdstore.enable_packed_slots().target(address(boringExchanger)).sig(
            UnderlyingTokenExchanger.token0ToToken1Rate.selector
        ).checked_write(1e6);
        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "token1_token0_rate"));
        boringExchanger.boringTestOnlyInitialized();
    }

    function testToken0() public view {
        assertEq(_exchanger.token0(), address(_underlyingToken));
    }

    function testToken1() public view {
        assertEq(_exchanger.token1(), address(_depositToken));
    }

    function testToken0Decimals() public view {
        assertEq(_exchanger.token0Decimals(), 6);
    }

    function testToken1Decimals() public view {
        assertEq(_exchanger.token1Decimals(), 6);
    }

    function testWhitelist() public view {
        assertEq(_exchanger.whitelist(), address(_whitelist));
    }

    function testPrecision() public view {
        assertEq(_exchanger.precision(), 1e6);
    }

    function testToken0ToToken1Rate() public view {
        assertEq(_exchanger.token0ToToken1Rate(), 1e6);
    }

    function testToken1ToToken0Rate() public view {
        assertEq(_exchanger.token1ToToken0Rate(), 1e6);
    }
}

contract BoringUnderlyingTokenExchanger is UnderlyingTokenExchanger {
    function boringTestOnlyWhitelist() external view onlyWhitelist(msg.sender) returns (bool) {
        return true;
    }

    function boringTestOnlyInitialized() external view onlyInitialized returns (bool) {
        return true;
    }
}
