// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Roles} from "src/common/Roles.sol";
import {Errors} from "src/common/Errors.sol";
import {UnderlyingTokenExchanger} from "src/underlying/UnderlyingTokenExchanger.sol";
import {Whitelist} from "src/whitelist/Whitelist.sol";
import {IWhitelist} from "src/whitelist/IWhitelist.sol";
import {DeployContractSuit} from "script/DeployContractSuit.s.sol";
import {UnderlyingToken} from "src/underlying/UnderlyingToken.sol";

import {DepositAsset} from "test/mock/DepositAsset.sol";

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

contract UnderlyingTokenExchangerTest is Test {
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

        _underlyingToken = UnderlyingToken(_deployer.deployUnderlyingToken(_owner, "lbUSD", "lbUSD"));

        _underlyingToken.grantRole(Roles.OPERATOR_ROLE, address(_owner));

        vm.stopPrank();

        vm.label(address(_underlyingToken), "lbUSD");

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
        _exchanger.exchange(1_000_000 * 10 ** 6, true);

        assertEq(_underlyingToken.balanceOf(_whitelistedUser1), 1_000_000 * 10 ** 6);
        assertEq(_depositToken.balanceOf(_whitelistedUser1), 0);

        _underlyingToken.approve(address(_exchanger), 1_000_000 * 10 ** 6);
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
}
