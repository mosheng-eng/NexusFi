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

    function setUp()
        public
        timeBegin
        deployWhitelist
        deployBlacklist
        deployDepositToken
        deployTimePowerLoan
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

    function testBorrow() public {}
    function testBlacklistedBorrowerBorrow() public {}
    function testNotWhitelistedBorrowerBorrow() public {}
    function testBorrowFromNotValidLoan() public {}
    function testNotLoanOwnerBorrow() public {}
    function testBorrowWithNotValidMaturityDate() public {}
    function testBorrowAmountOverLoanRemainingLimit() public {}
    function testBorrowAmountNotFullSatisfied() public {}
    function testBorrowAmountFullSatisfied() public {}

    function testRepay() public {}
    function testBlacklistedBorrowerRepay() public {}
    function testNotWhitelistedBorrowerRepay() public {}
    function testRepayNotValidDebt() public {}
    function testNotLoanOwnerRepay() public {}
    function testRepayAmountOverTotalDebt() public {}
    function testRepayAmountBelowTotalDebtButOverInterest() public {}
    function testRepayAmountBelowInterest() public {}
    function testRepayAmountTooLittleButInterestTooMuchEvenOverLoanRemainingLimit() public {}

    function testDefault() public {}
    function testNotOperatorDefault() public {}
    function testDefaultNotMaturedDebt() public {}
    function testDefaultWithNotValidInterestRate() public {}
    function testDefaultDebtForNotLoanOwner() public {}
    function testDefaultDebtWithUnchangedInterestRate() public {}

    function testRecovery() public {}
    function testNotOperatorRecovery() public {}
    function testRecoveryNotDefaultedDebt() public {}
    function testRecoveryDebtForNotLoanOwner() public {}

    function testClose() public {}
    function testNotOperatorClose() public {}
    function testCloseNotDefaultedDebt() public {}
    function testCloseDebtForNotLoanOwner() public {}

    function testAddWhitelist() public {}
    function testNotOperatorAddWhitelist() public {}

    function testRemoveWhitelist() public {}
    function testNotOperatorRemoveWhitelist() public {}

    function testAddBlacklist() public {}
    function testNotOperatorAddBlacklist() public {}

    function testRemoveBlacklist() public {}
    function testNotOperatorRemoveBlacklist() public {}

    function testUpdateBorrowerLimit() public {}
    function testNotOperatorUpdateBorrowerLimit() public {}
    function testUpdateNotWhitelistedBorrowerLimit() public {}
    function testUpdateBlacklistedBorrowerLimit() public {}
    function testUpdateNotTrustedBorrowerLimit() public {}
    function testUpdateBorrowerLimitBelowRemainingLimit() public {}
    function testUpdateBorrowerLimitBelowUsedLimit() public {}

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
}
