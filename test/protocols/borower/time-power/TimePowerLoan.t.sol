// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console, stdStorage, StdStorage} from "forge-std/Test.sol";

import {TimePowerLoan} from "src/protocols/borrower/time-power/TimePowerLoan.sol";
import {Whitelist} from "src/whitelist/Whitelist.sol";
import {Blacklist} from "src/blacklist/Blacklist.sol";
import {Roles} from "src/common/Roles.sol";
import {Errors} from "src/common/Errors.sol";
import {IWhitelist} from "src/whitelist/IWhitelist.sol";
import {IBlacklist} from "src/blacklist/IBlacklist.sol";

import {DeployContractSuit} from "script/DeployContractSuit.s.sol";

import {DepositAsset} from "test/mock/DepositAsset.sol";
import {AssetVault} from "test/mock/AssetVault.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract TimePowerLoanTest is Test {
    using stdStorage for StdStorage;

    DeployContractSuit internal _deployer = new DeployContractSuit();
    Whitelist internal _whitelist;
    Blacklist internal _blacklist;
    DepositAsset internal _depositToken;

    TimePowerLoan.TrustedVault[] internal _trustedVaults;
    uint64[] internal _secondInterestRates;
    address internal _loanToken;

    address internal _owner = makeAddr("owner");
    address internal _whitelistedUser1 = makeAddr("whitelistedUser1");
    address internal _whitelistedUser2 = makeAddr("whitelistedUser2");
    address internal _blacklistedUser1 = makeAddr("blacklistedUser1");
    address internal _blacklistedUser2 = makeAddr("blacklistedUser2");

    uint64 internal _currentTime = 1759301999; // 2025-10-01 14:59:59 UTC+8

    TimePowerLoan internal _timePowerLoan;

    modifier timeBegin() {
        vm.warp(_currentTime);
        _;
    }

    modifier oneDayPassed() {
        vm.warp(_currentTime += 1 days);
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

        _;
    }

    modifier deployBlacklist() {
        vm.startPrank(_owner);

        _blacklist = Blacklist(_deployer.deployBlacklist(_owner, true));

        _blacklist.grantRole(Roles.OPERATOR_ROLE, address(_owner));

        _blacklist.add(_blacklistedUser1);
        _blacklist.add(_blacklistedUser2);

        vm.stopPrank();

        vm.label(address(_blacklist), "Blacklist");
        vm.label(_blacklistedUser1, "blacklistedUser1");
        vm.label(_blacklistedUser2, "blacklistedUser2");

        _;
    }

    modifier deployDepositToken() {
        _depositToken = new DepositAsset("USD Coin", "USDC");

        _depositToken.mint(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _depositToken.mint(_whitelistedUser2, 1_000_000 * 10 ** 6);
        _depositToken.mint(_blacklistedUser1, 1_000_000 * 10 ** 6);
        _depositToken.mint(_blacklistedUser2, 1_000_000 * 10 ** 6);
        _depositToken.mint(_owner, 1_000_000_000_000_000 * 10 ** 6);

        vm.label(address(_depositToken), "USDC");

        _;
    }

    modifier deployTimePowerLoan() {
        address[] memory addrs = new address[](4);
        addrs[0] = _owner;
        addrs[1] = address(_whitelist);
        addrs[2] = address(_blacklist);
        addrs[3] = address(_depositToken);

        /// @dev 1000000000315520000 = (1 + 1%)^(1 / (365 * 24 * 60 * 60)) * 1e18
        _secondInterestRates.push(1000000000315520000);
        /// @dev 1000000000937300000 = (1 + 3%)^(1 / (365 * 24 * 60 * 60)) * 1e18
        _secondInterestRates.push(1000000000937300000);
        /// @dev 1000000001547130000 = (1 + 5%)^(1 / (365 * 24 * 60 * 60)) * 1e18
        _secondInterestRates.push(1000000001547130000);
        /// @dev 1000000002145440000 = (1 + 7%)^(1 / (365 * 24 * 60 * 60)) * 1e18
        _secondInterestRates.push(1000000002145440000);
        /// @dev 1000000002732680000 = (1 + 9%)^(1 / (365 * 24 * 60 * 60)) * 1e18
        _secondInterestRates.push(1000000002732680000);
        /// @dev 1000000003309230000 = (1 + 11%)^(1 / (365 * 24 * 60 * 60)) * 1e18
        _secondInterestRates.push(1000000003309230000);
        /// @dev 1000000003875500000 = (1 + 13%)^(1 / (365 * 24 * 60 * 60)) * 1e18
        _secondInterestRates.push(1000000003875500000);
        /// @dev 1000000004431820000 = (1 + 15%)^(1 / (365 * 24 * 60 * 60)) * 1e18
        _secondInterestRates.push(1000000004431820000);
        /// @dev 1000000004978560000 = (1 + 17%)^(1 / (365 * 24 * 60 * 60)) * 1e18
        _secondInterestRates.push(1000000004978560000);
        /// @dev 1000000005516020000 = (1 + 19%)^(1 / (365 * 24 * 60 * 60)) * 1e18
        _secondInterestRates.push(1000000005516020000);
        /// @dev 1000000006044530000 = (1 + 21%)^(1 / (365 * 24 * 60 * 60)) * 1e18
        _secondInterestRates.push(1000000006044530000);
        /// @dev 1000000006564380000 = (1 + 23%)^(1 / (365 * 24 * 60 * 60)) * 1e18
        _secondInterestRates.push(1000000006564380000);
        /// @dev 1000000007075840000 = (1 + 25%)^(1 / (365 * 24 * 60 * 60)) * 1e18
        _secondInterestRates.push(1000000007075840000);
        /// @dev 1000000007579180000 = (1 + 27%)^(1 / (365 * 24 * 60 * 60)) * 1e18
        _secondInterestRates.push(1000000007579180000);
        /// @dev 1000000008074650000 = (1 + 29%)^(1 / (365 * 24 * 60 * 60)) * 1e18
        _secondInterestRates.push(1000000008074650000);
        /// @dev 1000000008562500000 = (1 + 31%)^(1 / (365 * 24 * 60 * 60)) * 1e18
        _secondInterestRates.push(1000000008562500000);
        /// @dev 1000000009042960000 = (1 + 33%)^(1 / (365 * 24 * 60 * 60)) * 1e18
        _secondInterestRates.push(1000000009042960000);
        /// @dev 1000000009516250000 = (1 + 35%)^(1 / (365 * 24 * 60 * 60)) * 1e18
        _secondInterestRates.push(1000000009516250000);

        _trustedVaults.push(
            TimePowerLoan.TrustedVault({
                vault: address(new AssetVault(IERC20(address(_depositToken)), "MMF@OpenTerm", "MMF@OpenTerm")),
                minimumPercentage: 10 * 10 ** 4, // 10%
                maximumPercentage: 40 * 10 ** 4 // 40%
            })
        );

        _trustedVaults.push(
            TimePowerLoan.TrustedVault({
                vault: address(new AssetVault(IERC20(address(_depositToken)), "RWA@OpenTerm", "RWA@OpenTerm")),
                minimumPercentage: 30 * 10 ** 4, // 30%
                maximumPercentage: 60 * 10 ** 4 // 60%
            })
        );

        _trustedVaults.push(
            TimePowerLoan.TrustedVault({
                vault: address(new AssetVault(IERC20(address(_depositToken)), "MMF@FixedTerm", "MMF@FixedTerm")),
                minimumPercentage: 50 * 10 ** 4, // 50%
                maximumPercentage: 80 * 10 ** 4 // 80%
            })
        );

        _trustedVaults.push(
            TimePowerLoan.TrustedVault({
                vault: address(new AssetVault(IERC20(address(_depositToken)), "RWA@FixedTerm", "RWA@FixedTerm")),
                minimumPercentage: 70 * 10 ** 4, // 70%
                maximumPercentage: 100 * 10 ** 4 // 100%
            })
        );

        vm.startPrank(_owner);

        _timePowerLoan = TimePowerLoan(_deployer.deployTimePowerLoan(addrs, _secondInterestRates, _trustedVaults));

        _timePowerLoan.grantRole(Roles.OPERATOR_ROLE, _owner);

        vm.stopPrank();

        vm.label(address(_timePowerLoan), "TimePowerLoan");
        vm.label(_trustedVaults[0].vault, "MMF@OpenTerm");
        vm.label(_trustedVaults[1].vault, "RWA@OpenTerm");
        vm.label(_trustedVaults[2].vault, "MMF@FixedTerm");
        vm.label(_trustedVaults[3].vault, "RWA@FixedTerm");

        _;
    }

    modifier setDependencies() {
        vm.startPrank(_owner);

        _whitelist.grantRole(Roles.OPERATOR_ROLE, address(_timePowerLoan));
        _blacklist.grantRole(Roles.OPERATOR_ROLE, address(_timePowerLoan));

        vm.stopPrank();

        _;
    }

    function setUp()
        public
        timeBegin
        deployWhitelist
        deployBlacklist
        deployDepositToken
        deployTimePowerLoan
        setDependencies
        oneDayPassed
    {
        vm.label(_owner, "owner");
    }

    function testNull() public pure {
        assertTrue(true);
    }

    function testJoin() public {
        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoan.TrustedBorrowerAdded(_whitelistedUser1, 0);
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoan.TrustedBorrowerAdded(_whitelistedUser2, 1);
        vm.prank(_whitelistedUser2);
        _timePowerLoan.join();

        (address borrower1,,) = _timePowerLoan._trustedBorrowers(0);
        (address borrower2,,) = _timePowerLoan._trustedBorrowers(1);

        assertEq(borrower1, _whitelistedUser1);
        assertEq(borrower2, _whitelistedUser2);
    }

    function testDuplicateBorrowerJoin() public {
        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoan.TrustedBorrowerAdded(_whitelistedUser1, 0);
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.BorrowerAlreadyExists.selector, _whitelistedUser1, 0));
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();
    }

    function testNotWhitelistedBorrowerJoin() public {
        address someone = makeAddr("someone");
        vm.expectRevert(abi.encodeWithSelector(IWhitelist.NotWhitelisted.selector, someone));
        vm.prank(someone);
        _timePowerLoan.join();

        address zeroAddr = address(0x00);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "borrower"));
        vm.prank(zeroAddr);
        _timePowerLoan.join();
    }

    function testBlacklistedBorrowerJoin() public {
        vm.expectRevert(abi.encodeWithSelector(IBlacklist.Blacklisted.selector, _blacklistedUser1));
        vm.prank(_blacklistedUser1);
        _timePowerLoan.join();

        address zeroAddr = address(0x00);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "borrower"));
        vm.prank(zeroAddr);
        _timePowerLoan.join();
    }

    function testAgree() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_whitelistedUser2);
        _timePowerLoan.join();

        vm.startPrank(_owner);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoan.AgreeJoinRequest(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoan.AgreeJoinRequest(_whitelistedUser2, 2_000_000 * 10 ** 6);
        _timePowerLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.stopPrank();
    }

    function testNotOperatorAgree() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        address someone = makeAddr("someone");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, someone, Roles.OPERATOR_ROLE
            )
        );
        vm.prank(someone);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
    }

    function testDuplicateAgree() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.startPrank(_owner);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoan.AgreeJoinRequest(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.UpdateCeilingLimitDirectly.selector, _whitelistedUser1));
        _timePowerLoan.agree(_whitelistedUser1, 2_000_000 * 10 ** 6);

        vm.stopPrank();
    }

    function testAgreeNotWhitelistedBorrower() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _whitelist.remove(_whitelistedUser1);

        vm.startPrank(_owner);

        vm.expectRevert(abi.encodeWithSelector(IWhitelist.NotWhitelisted.selector, _whitelistedUser1));
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.stopPrank();
    }

    function testAgreeBlacklistedBorrower() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _blacklist.add(_whitelistedUser1);

        vm.startPrank(_owner);

        vm.expectRevert(abi.encodeWithSelector(IBlacklist.Blacklisted.selector, _whitelistedUser1));
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.stopPrank();
    }

    function testAgreeNotTrustedBorrower() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_whitelistedUser2);
        _timePowerLoan.join();

        vm.startPrank(_owner);

        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        _timePowerLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        address someone = makeAddr("someone");
        _whitelist.add(someone);
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotTrustedBorrower.selector, someone));
        _timePowerLoan.agree(someone, 3_000_000 * 10 ** 6);

        vm.stopPrank();
    }

    function testAgreeZeroCeilingLimit() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.startPrank(_owner);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimePowerLoan.AgreeJoinRequestShouldHaveNonZeroCeilingLimit.selector, _whitelistedUser1
            )
        );
        _timePowerLoan.agree(_whitelistedUser1, 0);

        vm.stopPrank();
    }

    function testRequest() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_whitelistedUser2);
        _timePowerLoan.join();

        vm.startPrank(_owner);

        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timePowerLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.stopPrank();

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoan.ReceiveLoanRequest(_whitelistedUser1, 0, 500_000 * 10 ** 6);
        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoan.ReceiveLoanRequest(_whitelistedUser2, 1, 1_500_000 * 10 ** 6);
        vm.prank(_whitelistedUser2);
        _timePowerLoan.request(1_500_000 * 10 ** 6);
    }

    function testBlacklistedBorrowerRequest() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.startPrank(_owner);

        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        _blacklist.add(_whitelistedUser1);

        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IBlacklist.Blacklisted.selector, _whitelistedUser1));
        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);
    }

    function testNotWhitelistedBorrowerRequest() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.startPrank(_owner);

        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        _whitelist.remove(_whitelistedUser1);

        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IWhitelist.NotWhitelisted.selector, _whitelistedUser1));
        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);
    }

    function testNotTrustedBorrowerRequest() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_whitelistedUser2);
        _timePowerLoan.join();

        vm.startPrank(_owner);

        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timePowerLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_whitelistedUser2);
        _timePowerLoan.request(1_500_000 * 10 ** 6);

        address someone = makeAddr("someone");
        vm.prank(_owner);
        _whitelist.add(someone);

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotTrustedBorrower.selector, someone));
        vm.prank(someone);
        _timePowerLoan.request(300_000 * 10 ** 6);
    }

    function testNotValidBorroweerRequest() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_whitelistedUser2);
        _timePowerLoan.join();

        vm.startPrank(_owner);

        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        uint64 borrwoerIndex = _timePowerLoan._borrowerToIndex(_whitelistedUser2);
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotValidBorrower.selector, borrwoerIndex));
        vm.prank(_whitelistedUser2);
        _timePowerLoan.request(1_500_000 * 10 ** 6);
    }

    function testRequestOverAvailableLimit() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_whitelistedUser2);
        _timePowerLoan.join();

        vm.startPrank(_owner);

        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timePowerLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimePowerLoan.LoanCeilingLimitExceedsBorrowerRemainingLimit.selector,
                2_500_000 * 10 ** 6,
                2_000_000 * 10 ** 6
            )
        );
        vm.prank(_whitelistedUser2);
        _timePowerLoan.request(2_500_000 * 10 ** 6);
    }

    function testApprove() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_whitelistedUser2);
        _timePowerLoan.join();

        vm.startPrank(_owner);

        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timePowerLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_whitelistedUser2);
        _timePowerLoan.request(1_500_000 * 10 ** 6);

        vm.startPrank(_owner);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoan.ApproveLoanRequest(_whitelistedUser1, 0, 500_000 * 10 ** 6, 1);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoan.ApproveLoanRequest(_whitelistedUser2, 1, 1_500_000 * 10 ** 6, 3);
        _timePowerLoan.approve(1, 1_500_000 * 10 ** 6, 3);

        vm.stopPrank();
    }

    function testNotOperatorApprove() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        address someone = makeAddr("someone");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, someone, Roles.OPERATOR_ROLE
            )
        );
        vm.prank(someone);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);
    }

    function testApproveNotPendingLoan() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_whitelistedUser2);
        _timePowerLoan.join();

        vm.startPrank(_owner);

        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timePowerLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_whitelistedUser2);
        _timePowerLoan.request(1_500_000 * 10 ** 6);

        vm.startPrank(_owner);

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotValidLoan.selector, 2));
        _timePowerLoan.approve(2, 500_000 * 10 ** 6, 1);

        _timePowerLoan.approve(1, 1_500_000 * 10 ** 6, 3);

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotPendingLoan.selector, 1));
        _timePowerLoan.approve(1, 1_500_000 * 10 ** 6, 3);

        vm.stopPrank();
    }

    function testApproveWithNotValidInterestRate() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_whitelistedUser2);
        _timePowerLoan.join();

        vm.startPrank(_owner);

        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timePowerLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_whitelistedUser2);
        _timePowerLoan.request(1_500_000 * 10 ** 6);

        vm.startPrank(_owner);

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotValidInterestRate.selector, 100));
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 100);

        stdstore.target(address(_timePowerLoan)).sig(TimePowerLoan.getSecondInterestRateAtIndex.selector).with_key(
            uint256(3)
        ).checked_write(uint256(0));
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotValidInterestRate.selector, 3));
        _timePowerLoan.approve(1, 1_500_000 * 10 ** 6, 3);

        vm.stopPrank();
    }

    function testApproveCeilingLimitOverRequest() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_whitelistedUser2);
        _timePowerLoan.join();

        vm.startPrank(_owner);

        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timePowerLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_whitelistedUser2);
        _timePowerLoan.request(1_500_000 * 10 ** 6);

        vm.startPrank(_owner);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoan.ApproveLoanRequest(_whitelistedUser1, 0, 1_000_000 * 10 ** 6, 1);
        _timePowerLoan.approve(0, 1_000_000 * 10 ** 6, 1);
        (uint128 ceilingLimit1,,,,,) = _timePowerLoan._allLoans(0);
        assertEq(ceilingLimit1, 500_000 * 10 ** 6);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoan.ApproveLoanRequest(_whitelistedUser2, 1, 2_000_000 * 10 ** 6, 3);
        _timePowerLoan.approve(1, 2_000_000 * 10 ** 6, 3);
        (uint128 ceilingLimit2,,,,,) = _timePowerLoan._allLoans(1);
        assertEq(ceilingLimit2, 1_500_000 * 10 ** 6);

        vm.stopPrank();
    }

    function testApproveCeilingLimitBelowRequest() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_whitelistedUser2);
        _timePowerLoan.join();

        vm.startPrank(_owner);

        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timePowerLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_whitelistedUser2);
        _timePowerLoan.request(1_500_000 * 10 ** 6);

        vm.startPrank(_owner);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoan.ApproveLoanRequest(_whitelistedUser1, 0, 400_000 * 10 ** 6, 1);
        _timePowerLoan.approve(0, 400_000 * 10 ** 6, 1);
        (uint128 ceilingLimit1,,,,,) = _timePowerLoan._allLoans(0);
        assertEq(ceilingLimit1, 400_000 * 10 ** 6);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoan.ApproveLoanRequest(_whitelistedUser2, 1, 1_000_000 * 10 ** 6, 3);
        _timePowerLoan.approve(1, 1_000_000 * 10 ** 6, 3);
        (uint128 ceilingLimit2,,,,,) = _timePowerLoan._allLoans(1);
        assertEq(ceilingLimit2, 1_000_000 * 10 ** 6);

        vm.stopPrank();
    }

    function testBorrow() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_whitelistedUser2);
        _timePowerLoan.join();

        vm.startPrank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timePowerLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);
        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_whitelistedUser2);
        _timePowerLoan.request(1_500_000 * 10 ** 6);

        vm.startPrank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);
        _timePowerLoan.approve(1, 1_500_000 * 10 ** 6, 3);
        vm.stopPrank();

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoan.Borrowed(_whitelistedUser1, 0, 300_000 * 10 ** 6, true, 0);
        vm.prank(_whitelistedUser1);
        (bool isAllSatisfied1,) = _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);
        assertTrue(isAllSatisfied1);
        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoan.Borrowed(_whitelistedUser2, 1, 1_000_000 * 10 ** 6, true, 1);
        vm.prank(_whitelistedUser2);
        (bool isAllSatisfied2,) = _timePowerLoan.borrow(1, 1_000_000 * 10 ** 6, _currentTime + 60 days);
        assertTrue(isAllSatisfied2);
    }

    function testBlacklistedBorrowerBorrow() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_owner);
        _blacklist.add(_whitelistedUser1);

        vm.expectRevert(abi.encodeWithSelector(IBlacklist.Blacklisted.selector, _whitelistedUser1));
        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);
    }

    function testNotWhitelistedBorrowerBorrow() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_owner);
        _whitelist.remove(_whitelistedUser1);

        vm.expectRevert(abi.encodeWithSelector(IWhitelist.NotWhitelisted.selector, _whitelistedUser1));
        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);
    }

    function testBorrowFromNotValidLoan() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotValidLoan.selector, 100));
        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(100, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotValidLoan.selector, 0));
        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);
    }

    function testNotLoanOwnerBorrow() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotValidLoan.selector, 100));
        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(100, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.expectRevert(
            abi.encodeWithSelector(TimePowerLoan.NotLoanOwner.selector, 0, _whitelistedUser1, _whitelistedUser2)
        );
        vm.prank(_whitelistedUser2);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);
    }

    function testBorrowWithNotValidMaturityDate() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotValidLoan.selector, 100));
        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(100, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimePowerLoan.MaturityTimeShouldAfterBlockTimestamp.selector, _currentTime - 1 minutes, _currentTime
            )
        );
        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime - 1 minutes);
    }

    function testBorrowAmountOverLoanRemainingLimit() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotValidLoan.selector, 100));
        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(100, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimePowerLoan.BorrowAmountOverLoanRemainingLimit.selector, 500_000 * 10 ** 6 + 1, 500_000 * 10 ** 6, 0
            )
        );
        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 500_000 * 10 ** 6 + 1, _currentTime + 30 days);
    }

    function testBorrowAmountNotFullSatisfied() public {
        _prepareFund(50_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoan.Borrowed(_whitelistedUser1, 0, 50_000 * 10 ** 6, false, 0);
        vm.prank(_whitelistedUser1);
        (bool isAllSatisfied,) = _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);
        assertFalse(isAllSatisfied);
    }

    function testRepay() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_whitelistedUser2);
        _timePowerLoan.join();

        vm.startPrank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timePowerLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);
        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_whitelistedUser2);
        _timePowerLoan.request(1_500_000 * 10 ** 6);

        vm.startPrank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);
        _timePowerLoan.approve(1, 1_500_000 * 10 ** 6, 3);
        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.prank(_whitelistedUser2);
        _timePowerLoan.borrow(1, 1_000_000 * 10 ** 6, _currentTime + 60 days);

        vm.warp(_currentTime + 25 days);

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), 300_000 * 10 ** 6 * 2);
        _timePowerLoan.repay(0, 300_000 * 10 ** 6 * 2);
        vm.stopPrank();
        (,, uint128 principal1, uint128 normalizedPrincipal1,, TimePowerLoan.DebtStatus status1) =
            _timePowerLoan._allDebts(0);
        assertEq(uint256(principal1), 0);
        assertEq(uint256(normalizedPrincipal1), 0);
        assertEq(uint8(TimePowerLoan.DebtStatus.REPAID), uint8(status1));

        vm.warp(_currentTime + 40 days);

        vm.startPrank(_whitelistedUser2);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), 1_000_000 * 10 ** 6 * 2);
        _timePowerLoan.repay(1, 1_000_000 * 10 ** 6 * 2);
        vm.stopPrank();
        (,, uint128 principal2, uint128 normalizedPrincipal2,, TimePowerLoan.DebtStatus status2) =
            _timePowerLoan._allDebts(1);
        assertEq(uint256(principal2), 0);
        assertEq(uint256(normalizedPrincipal2), 0);
        assertEq(uint8(TimePowerLoan.DebtStatus.REPAID), uint8(status2));
    }

    function testBlacklistedBorrowerRepay() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 25 days);

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), 300_000 * 10 ** 6 * 2);

        vm.prank(_owner);
        _blacklist.add(_whitelistedUser1);

        vm.expectRevert(abi.encodeWithSelector(IBlacklist.Blacklisted.selector, _whitelistedUser1));
        vm.prank(_whitelistedUser1);
        _timePowerLoan.repay(0, 300_000 * 10 ** 6 * 2);
    }

    function testNotWhitelistedBorrowerRepay() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 25 days);

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), 300_000 * 10 ** 6 * 2);

        vm.prank(_owner);
        _whitelist.remove(_whitelistedUser1);

        vm.expectRevert(abi.encodeWithSelector(IWhitelist.NotWhitelisted.selector, _whitelistedUser1));
        vm.prank(_whitelistedUser1);
        _timePowerLoan.repay(0, 300_000 * 10 ** 6 * 2);
    }

    function testRepayNotValidDebt() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 25 days);

        vm.startPrank(_whitelistedUser1);
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotValidDebt.selector, 100));
        _timePowerLoan.repay(100, 300_000 * 10 ** 6 * 2);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), 300_000 * 10 ** 6 * 2);
        _timePowerLoan.repay(0, 300_000 * 10 ** 6 * 2);
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotValidDebt.selector, 0));
        _timePowerLoan.repay(0, 300_000 * 10 ** 6 * 2);
        vm.stopPrank();
    }

    function testNotLoanOwnerRepay() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 25 days);

        vm.expectRevert(
            abi.encodeWithSelector(TimePowerLoan.NotLoanOwner.selector, 0, _whitelistedUser1, _whitelistedUser2)
        );
        vm.prank(_whitelistedUser2);
        _timePowerLoan.repay(0, 2 * 300_000 * 10 ** 6);

        vm.store(
            address(_timePowerLoan),
            bytes32(0xd7b6990105719101dabeb77144f2a3385c8033acd3af97e9423a695e81ad1eb6),
            bytes32(0x00000000000000010000000000000064000000000000000000000045d7f20637)
        );
        vm.prank(_whitelistedUser1);
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotValidLoan.selector, 100));
        _timePowerLoan.repay(0, 2 * 300_000 * 10 ** 6);
    }

    function testRepayAmountBelowTotalDebtButOverInterest() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days);

        uint256 totalDebt = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimePowerLoan.DebtInfo memory debtInfo = _timePowerLoan.getDebtInfoAtIndex(0);
        uint256 repayAmount = ((totalDebt - uint256(debtInfo.principal)) + totalDebt) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        (bool isAllRepaid, uint128 remainingDebt) = _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        assertFalse(isAllRepaid);
        assertEq(uint256(remainingDebt), totalDebt - repayAmount);

        debtInfo = _timePowerLoan.getDebtInfoAtIndex(0);
        assertEq(uint256(remainingDebt), uint256(debtInfo.principal));
    }

    function testRepayAmountBelowInterest() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days);

        uint256 totalDebt = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimePowerLoan.DebtInfo memory debtInfo = _timePowerLoan.getDebtInfoAtIndex(0);
        uint256 repayAmount = (totalDebt - uint256(debtInfo.principal)) / 2;
        uint128 originalPrincipal = debtInfo.principal;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        (bool isAllRepaid, uint128 remainingDebt) = _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        assertFalse(isAllRepaid);
        assertEq(uint256(remainingDebt), totalDebt - repayAmount);

        debtInfo = _timePowerLoan.getDebtInfoAtIndex(0);
        assertEq(uint256(remainingDebt), uint256(debtInfo.principal));
        assertLt(uint256(originalPrincipal), uint256(debtInfo.principal));
    }

    function testRepayAmountTooLittleButInterestTooMuchEvenOverLoanRemainingLimit() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(950_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 950_000 * 10 ** 6, 17);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 900_000 * 10 ** 6, _currentTime + 90 days);

        vm.warp(_currentTime + 90 days);

        uint256 totalDebt = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimePowerLoan.DebtInfo memory debtInfo = _timePowerLoan.getDebtInfoAtIndex(0);
        uint256 repayAmount = (totalDebt - uint256(debtInfo.principal)) / 1000;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimePowerLoan.RepayTooLittle.selector,
                _whitelistedUser1,
                0,
                totalDebt - debtInfo.principal - 50_000 * 10 ** 6,
                uint128(repayAmount)
            )
        );
        _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();
    }

    function testDefault() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimePowerLoan.DebtInfo memory debtInfoBeforeRepay = _timePowerLoan.getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();
        uint256 totalDebtAfterRepay = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);

        /// @dev Verify that after repayment, the total debt is reduced by the repay amount (with 1 unit tolerance)
        /// @dev The 1 unit tolerance accounts for precision loss in interest calculations with dividing
        assertEq(totalDebtAfterRepay + 1, totalDebtBeforeRepay - repayAmount);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoan.Defaulted(_whitelistedUser1, 0, uint128(totalDebtAfterRepay) - 1, 17);
        vm.prank(_owner);
        _timePowerLoan.defaulted(_whitelistedUser1, 0, 17);
        uint256 totalDebtAfterDefaulted = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);

        /// @dev Verify that after defaulting, the total debt increases due to penalty interest (with 1 unit tolerance)
        /// @dev The 1 unit tolerance accounts for precision loss in interest calculations with dividing
        assertEq(totalDebtAfterRepay, totalDebtAfterDefaulted + 1);
    }

    function testNotOperatorDefault() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimePowerLoan.DebtInfo memory debtInfoBeforeRepay = _timePowerLoan.getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        address someone = makeAddr("someone");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, someone, Roles.OPERATOR_ROLE
            )
        );
        vm.prank(someone);
        _timePowerLoan.defaulted(_whitelistedUser1, 0, 17);
    }

    function testDefaultNotMaturedDebt() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days - 1 seconds);

        uint256 totalDebtBeforeRepay = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimePowerLoan.DebtInfo memory debtInfoBeforeRepay = _timePowerLoan.getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotValidDebt.selector, 100));
        vm.prank(_owner);
        _timePowerLoan.defaulted(_whitelistedUser1, 100, 17);

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotMaturedDebt.selector, 0));
        vm.prank(_owner);
        _timePowerLoan.defaulted(_whitelistedUser1, 0, 17);
    }

    function testDefaultWithNotValidInterestRate() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimePowerLoan.DebtInfo memory debtInfoBeforeRepay = _timePowerLoan.getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotValidInterestRate.selector, 100));
        vm.prank(_owner);
        _timePowerLoan.defaulted(_whitelistedUser1, 0, 100);

        stdstore.target(address(_timePowerLoan)).sig(TimePowerLoan.getSecondInterestRateAtIndex.selector).with_key(17)
            .checked_write(uint256(0));
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotValidInterestRate.selector, 17));
        vm.prank(_owner);
        _timePowerLoan.defaulted(_whitelistedUser1, 0, 17);
    }

    function testDefaultDebtForNotLoanOwner() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimePowerLoan.DebtInfo memory debtInfoBeforeRepay = _timePowerLoan.getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(TimePowerLoan.NotLoanOwner.selector, 0, _whitelistedUser1, _whitelistedUser2)
        );
        vm.prank(_owner);
        _timePowerLoan.defaulted(_whitelistedUser2, 0, 17);

        vm.store(
            address(_timePowerLoan),
            bytes32(0xd7b6990105719101dabeb77144f2a3385c8033acd3af97e9423a695e81ad1eb6),
            bytes32(0x00000000000000010000000000000064000000000000000000000045d7f20637)
        );
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotValidLoan.selector, 100));
        vm.prank(_owner);
        _timePowerLoan.defaulted(_whitelistedUser1, 0, 17);
    }

    function testDefaultDebtWithUnchangedInterestRate() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimePowerLoan.DebtInfo memory debtInfoBeforeRepay = _timePowerLoan.getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        uint256 totalDebtAfterRepay = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoan.Defaulted(_whitelistedUser1, 0, uint128(totalDebtAfterRepay), 1);
        vm.prank(_owner);
        _timePowerLoan.defaulted(_whitelistedUser1, 0, 1);
    }

    function testRecovery() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimePowerLoan.DebtInfo memory debtInfoBeforeRepay = _timePowerLoan.getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.prank(_owner);
        uint128 remainingDebt = _timePowerLoan.defaulted(_whitelistedUser1, 0, 17);

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), remainingDebt);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoan.Recovery(_whitelistedUser1, 0, remainingDebt, 0);
        vm.prank(_owner);
        _timePowerLoan.recovery(_whitelistedUser1, 0, remainingDebt);
    }

    function testNotOperatorRecovery() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimePowerLoan.DebtInfo memory debtInfoBeforeRepay = _timePowerLoan.getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.prank(_owner);
        uint128 remainingDebt = _timePowerLoan.defaulted(_whitelistedUser1, 0, 17);

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), remainingDebt);

        address someone = makeAddr("someone");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, someone, Roles.OPERATOR_ROLE
            )
        );
        vm.prank(someone);
        _timePowerLoan.recovery(_whitelistedUser1, 0, remainingDebt);
    }

    function testRecoveryNotDefaultedDebt() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days - 1 seconds);

        uint256 totalDebtBeforeRepay = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimePowerLoan.DebtInfo memory debtInfoBeforeRepay = _timePowerLoan.getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        (, uint128 remainingDebt) = _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), remainingDebt);

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotValidDebt.selector, 100));
        vm.prank(_owner);
        _timePowerLoan.recovery(_whitelistedUser1, 100, remainingDebt);

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotDefaultedDebt.selector, 0));
        vm.prank(_owner);
        _timePowerLoan.recovery(_whitelistedUser1, 0, remainingDebt);
    }

    function testRecoveryDebtForNotLoanOwner() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimePowerLoan.DebtInfo memory debtInfoBeforeRepay = _timePowerLoan.getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.prank(_owner);
        uint128 remainingDebt = _timePowerLoan.defaulted(_whitelistedUser1, 0, 17);

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), remainingDebt);

        vm.expectRevert(
            abi.encodeWithSelector(TimePowerLoan.NotLoanOwner.selector, 0, _whitelistedUser1, _whitelistedUser2)
        );
        vm.prank(_owner);
        _timePowerLoan.recovery(_whitelistedUser2, 0, remainingDebt);

        vm.store(
            address(_timePowerLoan),
            bytes32(0xd7b6990105719101dabeb77144f2a3385c8033acd3af97e9423a695e81ad1eb6),
            bytes32(0x00000000000000030000000000000064000000000000000000000045d7f20637)
        );
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotValidLoan.selector, 100));
        vm.prank(_owner);
        _timePowerLoan.recovery(_whitelistedUser1, 0, remainingDebt);
    }

    function testRecoveryPartialDebt() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimePowerLoan.DebtInfo memory debtInfoBeforeRepay = _timePowerLoan.getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.prank(_owner);
        uint128 remainingDebt = _timePowerLoan.defaulted(_whitelistedUser1, 0, 17);
        uint128 recoveryAmount = remainingDebt / 2;

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), recoveryAmount);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoan.Recovery(_whitelistedUser1, 0, recoveryAmount, remainingDebt - recoveryAmount);
        vm.prank(_owner);
        _timePowerLoan.recovery(_whitelistedUser1, 0, recoveryAmount);
    }

    function testClose() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimePowerLoan.DebtInfo memory debtInfoBeforeRepay = _timePowerLoan.getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.prank(_owner);
        uint128 remainingDebtAtDefaulted = _timePowerLoan.defaulted(_whitelistedUser1, 0, 17);

        vm.warp(_currentTime + 40 days);

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), remainingDebtAtDefaulted);

        vm.prank(_owner);
        (, uint128 remainingDebtAtRecovery) = _timePowerLoan.recovery(_whitelistedUser1, 0, remainingDebtAtDefaulted);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        /// @dev precision loss in interest calculations with dividing
        emit TimePowerLoan.Closed(_whitelistedUser1, 0, remainingDebtAtRecovery - 1);
        vm.prank(_owner);
        _timePowerLoan.close(_whitelistedUser1, 0);
    }

    function testNotOperatorClose() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimePowerLoan.DebtInfo memory debtInfoBeforeRepay = _timePowerLoan.getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.prank(_owner);
        uint128 remainingDebtAtDefaulted = _timePowerLoan.defaulted(_whitelistedUser1, 0, 17);

        vm.warp(_currentTime + 40 days);

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), remainingDebtAtDefaulted);

        vm.prank(_owner);
        _timePowerLoan.recovery(_whitelistedUser1, 0, remainingDebtAtDefaulted);

        address someone = makeAddr("someone");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, someone, Roles.OPERATOR_ROLE
            )
        );
        vm.prank(someone);
        _timePowerLoan.close(_whitelistedUser1, 0);
    }

    function testCloseNotDefaultedDebt() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days - 1 seconds);

        uint256 totalDebtBeforeRepay = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimePowerLoan.DebtInfo memory debtInfoBeforeRepay = _timePowerLoan.getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotValidDebt.selector, 100));
        vm.prank(_owner);
        _timePowerLoan.close(_whitelistedUser1, 100);

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotDefaultedDebt.selector, 0));
        vm.prank(_owner);
        _timePowerLoan.close(_whitelistedUser1, 0);
    }

    function testCloseDebtForNotLoanOwner() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimePowerLoan.DebtInfo memory debtInfoBeforeRepay = _timePowerLoan.getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.prank(_owner);
        uint128 remainingDebtAtDefaulted = _timePowerLoan.defaulted(_whitelistedUser1, 0, 17);

        vm.warp(_currentTime + 40 days);

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), remainingDebtAtDefaulted);

        vm.prank(_owner);
        _timePowerLoan.recovery(_whitelistedUser1, 0, remainingDebtAtDefaulted);

        vm.expectRevert(
            abi.encodeWithSelector(TimePowerLoan.NotLoanOwner.selector, 0, _whitelistedUser1, _whitelistedUser2)
        );
        vm.prank(_owner);
        _timePowerLoan.close(_whitelistedUser2, 0);

        vm.store(
            address(_timePowerLoan),
            bytes32(0xd7b6990105719101dabeb77144f2a3385c8033acd3af97e9423a695e81ad1eb6),
            bytes32(0x00000000000000030000000000000064000000000000000000000045d7f20637)
        );
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotValidLoan.selector, 100));
        vm.prank(_owner);
        _timePowerLoan.close(_whitelistedUser1, 0);
    }

    function testAddWhitelist() public {
        address someone = makeAddr("someone");
        vm.prank(_owner);
        _timePowerLoan.addWhitelist(someone);
        assertTrue(_whitelist.isWhitelisted(someone));
    }

    function testNotOperatorAddWhitelist() public {
        address someone = makeAddr("someone");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, someone, Roles.OPERATOR_ROLE
            )
        );
        vm.prank(someone);
        _timePowerLoan.addWhitelist(someone);
    }

    function testRemoveWhitelist() public {
        vm.prank(_owner);
        _timePowerLoan.removeWhitelist(_whitelistedUser1);
        assertFalse(_whitelist.isWhitelisted(_whitelistedUser1));
    }

    function testNotOperatorRemoveWhitelist() public {
        address someone = makeAddr("someone");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, someone, Roles.OPERATOR_ROLE
            )
        );
        vm.prank(someone);
        _timePowerLoan.removeWhitelist(someone);
    }

    function testAddBlacklist() public {
        address someone = makeAddr("someone");
        vm.prank(_owner);
        _timePowerLoan.addBlacklist(someone);
        assertTrue(_blacklist.isBlacklisted(someone));
    }

    function testNotOperatorAddBlacklist() public {
        address someone = makeAddr("someone");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, someone, Roles.OPERATOR_ROLE
            )
        );
        vm.prank(someone);
        _timePowerLoan.addBlacklist(someone);
    }

    function testRemoveBlacklist() public {
        vm.prank(_owner);
        _timePowerLoan.removeBlacklist(_blacklistedUser1);
        assertFalse(_blacklist.isBlacklisted(_blacklistedUser1));
    }

    function testNotOperatorRemoveBlacklist() public {
        address someone = makeAddr("someone");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, someone, Roles.OPERATOR_ROLE
            )
        );
        vm.prank(someone);
        _timePowerLoan.removeBlacklist(someone);
    }

    function testUpdateBorrowerLimit() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_whitelistedUser2);
        _timePowerLoan.join();

        vm.startPrank(_owner);

        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        _timePowerLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoan.BorrowerCeilingLimitUpdated(1_000_000 * 10 ** 6, 1_500_000 * 10 ** 6);
        _timePowerLoan.updateBorrowerLimit(_whitelistedUser1, 1_500_000 * 10 ** 6);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoan.BorrowerCeilingLimitUpdated(2_000_000 * 10 ** 6, 2_500_000 * 10 ** 6);
        _timePowerLoan.updateBorrowerLimit(_whitelistedUser2, 2_500_000 * 10 ** 6);

        vm.stopPrank();
    }

    function testNotOperatorUpdateBorrowerLimit() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        address someone = makeAddr("someone");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, someone, Roles.OPERATOR_ROLE
            )
        );
        vm.prank(someone);
        _timePowerLoan.updateBorrowerLimit(_whitelistedUser1, 1_500_000 * 10 ** 6);
    }

    function testUpdateNotWhitelistedBorrowerLimit() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_owner);
        _whitelist.remove(_whitelistedUser1);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSelector(IWhitelist.NotWhitelisted.selector, _whitelistedUser1));
        _timePowerLoan.updateBorrowerLimit(_whitelistedUser1, 1_500_000 * 10 ** 6);
    }

    function testUpdateBlacklistedBorrowerLimit() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_owner);
        _blacklist.add(_whitelistedUser1);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSelector(IBlacklist.Blacklisted.selector, _whitelistedUser1));
        _timePowerLoan.updateBorrowerLimit(_whitelistedUser1, 1_500_000 * 10 ** 6);
    }

    function testUpdateNotTrustedBorrowerLimit() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_whitelistedUser2);
        _timePowerLoan.join();

        vm.startPrank(_owner);

        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        _timePowerLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        address someone = makeAddr("someone");
        _whitelist.add(someone);
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoan.NotTrustedBorrower.selector, someone));
        _timePowerLoan.updateBorrowerLimit(someone, 3_000_000 * 10 ** 6);

        vm.stopPrank();
    }

    function testUpdateBorrowerLimitBelowRemainingLimit() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.store(
            address(_timePowerLoan),
            bytes32(0x1b6847dc741a1b0cd08d278845f9d819d87b734759afb55fe2de5cb82a9ae673),
            bytes32(0x0000000000000000000000746a5288000000000000000000000000746a5287ff)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                TimePowerLoan.CeilingLimitBelowRemainingLimit.selector, 500_000 * 10 ** 6 - 1, 500_000 * 10 ** 6
            )
        );
        vm.prank(_owner);
        _timePowerLoan.updateBorrowerLimit(_whitelistedUser1, 1_500_000 * 10 ** 6);
    }

    function testUpdateBorrowerLimitBelowUsedLimit() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimePowerLoan.CeilingLimitBelowUsedLimit.selector, 500_000 * 10 ** 6 - 1, 500_000 * 10 ** 6
            )
        );
        vm.prank(_owner);
        _timePowerLoan.updateBorrowerLimit(_whitelistedUser1, 500_000 * 10 ** 6 - 1);
    }

    function testUpdateLoanLimit() public {}
    function testNotOperatorUpdateLoanLimit() public {}
    function testUpdateNotValidLoanLimit() public {}
    function testUpdateNotTrustedBorrowerLoanLimit() public {}
    function testUpdateLoanLimitBelowRemainingLimit() public {}
    function testUpdateLoanLimitBelowUsedLimit() public {}
    function testUpdateLoanLimitExceedBorrowerRemainingLimit() public {}

    function testUpdateLoanInterestRate() public {}
    function testNotOperatorUpdateLoanInterestRate() public {}
    function testUpdateNotValidLoanInterestRate() public {}
    function testUpdateLoanNotValidInterestRate() public {}
    function testUpdateLoanInterestRateForNotTrustedBorrower() public {}

    function testUpdateTrustedVaults() public {}
    function testNotOperatorUpdateTrustedVaults() public {}
    function testUpdateTrustedVaultsWhenVaultsNotExist() public {}

    function testPile() public {}
    function testTotalDebtOfBorrower() public {}
    function testTotalDebtOfNotTrustedBorrower() public {}
    function testTotalDebtOfVault() public {}
    function testTotalDebtOfNotTrustedVault() public {}

    function testGetSecondInterestRateAtIndex() public view {
        assertEq(_timePowerLoan.getSecondInterestRateAtIndex(0), 1000000000315520000);
        assertEq(_timePowerLoan.getSecondInterestRateAtIndex(1), 1000000000937300000);
        assertEq(_timePowerLoan.getSecondInterestRateAtIndex(2), 1000000001547130000);
        assertEq(_timePowerLoan.getSecondInterestRateAtIndex(3), 1000000002145440000);
        assertEq(_timePowerLoan.getSecondInterestRateAtIndex(4), 1000000002732680000);
        assertEq(_timePowerLoan.getSecondInterestRateAtIndex(5), 1000000003309230000);
        assertEq(_timePowerLoan.getSecondInterestRateAtIndex(6), 1000000003875500000);
        assertEq(_timePowerLoan.getSecondInterestRateAtIndex(7), 1000000004431820000);
        assertEq(_timePowerLoan.getSecondInterestRateAtIndex(8), 1000000004978560000);
        assertEq(_timePowerLoan.getSecondInterestRateAtIndex(9), 1000000005516020000);
        assertEq(_timePowerLoan.getSecondInterestRateAtIndex(10), 1000000006044530000);
        assertEq(_timePowerLoan.getSecondInterestRateAtIndex(11), 1000000006564380000);
        assertEq(_timePowerLoan.getSecondInterestRateAtIndex(12), 1000000007075840000);
        assertEq(_timePowerLoan.getSecondInterestRateAtIndex(13), 1000000007579180000);
        assertEq(_timePowerLoan.getSecondInterestRateAtIndex(14), 1000000008074650000);
        assertEq(_timePowerLoan.getSecondInterestRateAtIndex(15), 1000000008562500000);
        assertEq(_timePowerLoan.getSecondInterestRateAtIndex(16), 1000000009042960000);
        assertEq(_timePowerLoan.getSecondInterestRateAtIndex(17), 1000000009516250000);
    }

    function testGetAccumulatedInterestRateAtIndex() public {
        vm.warp(_currentTime + 30 days);
        vm.prank(_owner);
        _timePowerLoan.pile();
        uint256 accumulatedInterestRate1At30 = _timePowerLoan.getAccumulatedInterestRateAtIndex(1);
        uint256 accumulatedInterestRate2At30 = _timePowerLoan.getAccumulatedInterestRateAtIndex(2);
        assertLt(accumulatedInterestRate1At30, accumulatedInterestRate2At30);

        vm.warp(_currentTime + 60 days);
        vm.prank(_owner);
        _timePowerLoan.pile();
        uint256 accumulatedInterestRate1At60 = _timePowerLoan.getAccumulatedInterestRateAtIndex(1);
        uint256 accumulatedInterestRate2At60 = _timePowerLoan.getAccumulatedInterestRateAtIndex(2);
        assertLt(accumulatedInterestRate1At60, accumulatedInterestRate2At60);
        assertLt(accumulatedInterestRate1At30, accumulatedInterestRate1At60);
        assertLt(accumulatedInterestRate2At30, accumulatedInterestRate2At60);
    }

    function testGetTrancheInfoAtIndex() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));
        _prepareDebt();

        vm.warp(_currentTime + 30 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        TimePowerLoan.TrancheInfo memory trancheInfo = _timePowerLoan.getTrancheInfoAtIndex(0);
        assertEq(trancheInfo.debtIndex, 0);
        assertEq(trancheInfo.loanIndex, 0);
        assertEq(trancheInfo.borrowerIndex, 0);
        assertGt(trancheInfo.normalizedPrincipal, 0);
    }

    function testGetDebtInfoAtIndex() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));
        _prepareDebt();

        vm.warp(_currentTime + 30 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        TimePowerLoan.DebtInfo memory debtInfo = _timePowerLoan.getDebtInfoAtIndex(0);
        assertEq(debtInfo.loanIndex, 0);
        assertGt(debtInfo.normalizedPrincipal, 0);
        assertEq(uint8(debtInfo.status), uint8(TimePowerLoan.DebtStatus.ACTIVE));
    }

    function testGetLoanInfoAtIndex() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));
        _prepareDebt();

        vm.warp(_currentTime + 30 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        TimePowerLoan.LoanInfo memory loanInfo = _timePowerLoan.getLoanInfoAtIndex(0);
        assertEq(loanInfo.borrowerIndex, 0);
        assertGt(loanInfo.normalizedPrincipal, 0);
        assertEq(uint8(loanInfo.status), uint8(TimePowerLoan.LoanStatus.APPROVED));
    }

    function testGetBorrowerInfoAtIndex() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));
        _prepareDebt();

        vm.warp(_currentTime + 30 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        TimePowerLoan.TrustedBorrower memory borrowerInfo = _timePowerLoan.getBorrowerInfoAtIndex(0);
        assertEq(borrowerInfo.borrower, _whitelistedUser1);
        assertGt(borrowerInfo.ceilingLimit, 0);
        assertGt(borrowerInfo.remainingLimit, 0);
    }

    function testGetVaultInfoAtIndex() public view {
        TimePowerLoan.TrustedVault memory vaultInfo = _timePowerLoan.getVaultInfoAtIndex(0);
        assertEq(vaultInfo.vault, _trustedVaults[0].vault);
    }

    function testGetTranchesOfDebt() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));
        _prepareDebt();

        vm.warp(_currentTime + 30 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        uint64[] memory tranchesIndexOfDebt = _timePowerLoan.getTranchesOfDebt(0);
        assertGt(tranchesIndexOfDebt.length, 0);
        for (uint256 i = 0; i < tranchesIndexOfDebt.length; ++i) {
            assertGt(_timePowerLoan.getTrancheInfoAtIndex(tranchesIndexOfDebt[i]).normalizedPrincipal, 0);
        }
    }

    function testGetTranchesOfLoan() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));
        _prepareDebt();

        vm.warp(_currentTime + 30 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        uint64[] memory tranchesIndexOfLoan = _timePowerLoan.getTranchesOfLoan(0);
        assertGt(tranchesIndexOfLoan.length, 0);
        for (uint256 i = 0; i < tranchesIndexOfLoan.length; ++i) {
            assertGt(_timePowerLoan.getTrancheInfoAtIndex(tranchesIndexOfLoan[i]).normalizedPrincipal, 0);
        }
    }

    function testGetTranchesOfBorrower() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));
        _prepareDebt();

        vm.warp(_currentTime + 30 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        uint64[] memory tranchesIndexOfBorrower = _timePowerLoan.getTranchesOfBorrower(0);
        assertGt(tranchesIndexOfBorrower.length, 0);
        for (uint256 i = 0; i < tranchesIndexOfBorrower.length; ++i) {
            assertGt(_timePowerLoan.getTrancheInfoAtIndex(tranchesIndexOfBorrower[i]).normalizedPrincipal, 0);
        }
    }

    function testGetTranchesOfVault() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));
        _prepareDebt();

        vm.warp(_currentTime + 30 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        uint64[] memory tranchesIndexOfVault = _timePowerLoan.getTranchesOfVault(0);
        assertGt(tranchesIndexOfVault.length, 0);
        for (uint256 i = 0; i < tranchesIndexOfVault.length; ++i) {
            assertGt(_timePowerLoan.getTrancheInfoAtIndex(tranchesIndexOfVault[i]).normalizedPrincipal, 0);
        }
    }

    function testGetDebtsOfLoan() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));
        _prepareDebt();

        vm.warp(_currentTime + 30 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        uint64[] memory debtsIndexOfLoan = _timePowerLoan.getDebtsOfLoan(0);
        assertGt(debtsIndexOfLoan.length, 0);
        for (uint256 i = 0; i < debtsIndexOfLoan.length; ++i) {
            TimePowerLoan.DebtInfo memory debtInfo = _timePowerLoan.getDebtInfoAtIndex(debtsIndexOfLoan[i]);
            assertGt(debtInfo.normalizedPrincipal, 0);
            assertEq(uint8(debtInfo.status), uint8(TimePowerLoan.DebtStatus.ACTIVE));
        }
    }

    function testGetDebtsOfBorrower() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));
        _prepareDebt();

        vm.warp(_currentTime + 30 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        uint64[] memory debtsIndexOfBorrower = _timePowerLoan.getDebtsOfBorrower(0);
        assertGt(debtsIndexOfBorrower.length, 0);
        for (uint256 i = 0; i < debtsIndexOfBorrower.length; ++i) {
            TimePowerLoan.DebtInfo memory debtInfo = _timePowerLoan.getDebtInfoAtIndex(debtsIndexOfBorrower[i]);
            assertGt(debtInfo.normalizedPrincipal, 0);
            assertEq(uint8(debtInfo.status), uint8(TimePowerLoan.DebtStatus.ACTIVE));
        }
    }

    function testGetLoansOfBorrower() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));
        _prepareDebt();

        vm.warp(_currentTime + 30 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        uint64[] memory loansIndexOfBorrower = _timePowerLoan.getLoansOfBorrower(0);
        assertGt(loansIndexOfBorrower.length, 0);
        for (uint256 i = 0; i < loansIndexOfBorrower.length; ++i) {
            TimePowerLoan.LoanInfo memory loanInfo = _timePowerLoan.getLoanInfoAtIndex(loansIndexOfBorrower[i]);
            assertGt(loanInfo.normalizedPrincipal, 0);
            assertEq(uint8(loanInfo.status), uint8(TimePowerLoan.LoanStatus.APPROVED));
        }
    }

    function _prepareFund(uint256 fundForEachVault_) internal {
        for (uint256 i = 0; i < _trustedVaults.length; ++i) {
            vm.startPrank(_owner);

            IERC20(address(_depositToken)).approve(_trustedVaults[i].vault, fundForEachVault_);
            AssetVault(_trustedVaults[i].vault).deposit(fundForEachVault_, _owner);

            vm.stopPrank();

            vm.startPrank(_trustedVaults[i].vault);

            IERC20(address(_depositToken)).approve(address(_timePowerLoan), fundForEachVault_);

            vm.stopPrank();
        }
    }

    function _prepareDebt() internal {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_whitelistedUser2);
        _timePowerLoan.join();

        vm.startPrank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timePowerLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);
        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_whitelistedUser2);
        _timePowerLoan.request(1_500_000 * 10 ** 6);

        vm.startPrank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);
        _timePowerLoan.approve(1, 1_500_000 * 10 ** 6, 3);
        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.prank(_whitelistedUser2);
        _timePowerLoan.borrow(1, 1_000_000 * 10 ** 6, _currentTime + 60 days);
    }
}
