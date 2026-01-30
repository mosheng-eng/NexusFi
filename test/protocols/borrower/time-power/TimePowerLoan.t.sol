// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console, stdStorage, StdStorage} from "forge-std/Test.sol";

import {TimePowerLoan} from "src/protocols/borrower/time-power/TimePowerLoan.sol";
import {TimePowerLoanLibs} from "src/protocols/borrower/time-power/utils/TimePowerLoanLibs.sol";
import {TimePowerLoanDefs} from "src/protocols/borrower/time-power/utils/TimePowerLoanDefs.sol";
import {Whitelist} from "src/whitelist/Whitelist.sol";
import {Blacklist} from "src/blacklist/Blacklist.sol";
import {Roles} from "src/common/Roles.sol";
import {Errors} from "src/common/Errors.sol";
import {IWhitelist} from "src/whitelist/IWhitelist.sol";
import {IBlacklist} from "src/blacklist/IBlacklist.sol";

import {DeployContractSuit} from "script/DeployContractSuit.s.sol";

import {DepositAsset} from "test/mock/DepositAsset.sol";
import {AssetVault} from "test/mock/AssetVault.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract TimePowerLoanTest is Test {
    using stdStorage for StdStorage;
    using Math for uint256;

    DeployContractSuit internal _deployer = new DeployContractSuit();
    Whitelist internal _whitelist;
    Blacklist internal _blacklist;
    DepositAsset internal _depositToken;

    TimePowerLoanDefs.TrustedVault[] internal _trustedVaults;
    uint64[] internal _secondInterestRates;

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
            TimePowerLoanDefs.TrustedVault({
                vault: address(new AssetVault(IERC20(address(_depositToken)), "MMF@OpenTerm", "MMF@OpenTerm")),
                minimumPercentage: 10 * 10 ** 4, // 10%
                maximumPercentage: 40 * 10 ** 4 // 40%
            })
        );

        _trustedVaults.push(
            TimePowerLoanDefs.TrustedVault({
                vault: address(new AssetVault(IERC20(address(_depositToken)), "RWA@OpenTerm", "RWA@OpenTerm")),
                minimumPercentage: 30 * 10 ** 4, // 30%
                maximumPercentage: 60 * 10 ** 4 // 60%
            })
        );

        _trustedVaults.push(
            TimePowerLoanDefs.TrustedVault({
                vault: address(new AssetVault(IERC20(address(_depositToken)), "MMF@FixedTerm", "MMF@FixedTerm")),
                minimumPercentage: 50 * 10 ** 4, // 50%
                maximumPercentage: 80 * 10 ** 4 // 80%
            })
        );

        _trustedVaults.push(
            TimePowerLoanDefs.TrustedVault({
                vault: address(new AssetVault(IERC20(address(_depositToken)), "RWA@FixedTerm", "RWA@FixedTerm")),
                minimumPercentage: 70 * 10 ** 4, // 70%
                maximumPercentage: 100 * 10 ** 4 // 100%
            })
        );

        vm.startPrank(_owner);

        _timePowerLoan = TimePowerLoan(
            _deployer.deployTimePowerLoan(
                [_owner, address(_whitelist), address(_blacklist), address(_depositToken)],
                _secondInterestRates,
                _trustedVaults
            )
        );

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
        emit TimePowerLoanDefs.TrustedBorrowerAdded(_whitelistedUser1, 0);
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.TrustedBorrowerAdded(_whitelistedUser2, 1);
        vm.prank(_whitelistedUser2);
        _timePowerLoan.join();

        (address borrower1,,) = _timePowerLoan._trustedBorrowers(0);
        (address borrower2,,) = _timePowerLoan._trustedBorrowers(1);

        assertEq(borrower1, _whitelistedUser1);
        assertEq(borrower2, _whitelistedUser2);
    }

    function testDuplicateBorrowerJoin() public {
        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.TrustedBorrowerAdded(_whitelistedUser1, 0);
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.BorrowerAlreadyExists.selector, _whitelistedUser1, 0));
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
        emit TimePowerLoanDefs.AgreeJoinRequest(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.AgreeJoinRequest(_whitelistedUser2, 2_000_000 * 10 ** 6);
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
        emit TimePowerLoanDefs.AgreeJoinRequest(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.expectRevert(
            abi.encodeWithSelector(TimePowerLoanDefs.UpdateCeilingLimitDirectly.selector, _whitelistedUser1)
        );
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
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotTrustedBorrower.selector, someone));
        _timePowerLoan.agree(someone, 3_000_000 * 10 ** 6);

        vm.stopPrank();
    }

    function testAgreeZeroCeilingLimit() public {
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.startPrank(_owner);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimePowerLoanDefs.AgreeJoinRequestShouldHaveNonZeroCeilingLimit.selector, _whitelistedUser1
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
        emit TimePowerLoanDefs.ReceiveLoanRequest(_whitelistedUser1, 0, 500_000 * 10 ** 6);
        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.ReceiveLoanRequest(_whitelistedUser2, 1, 1_500_000 * 10 ** 6);
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

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotTrustedBorrower.selector, someone));
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
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidBorrower.selector, borrwoerIndex));
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
                TimePowerLoanDefs.LoanCeilingLimitExceedsBorrowerRemainingLimit.selector,
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
        emit TimePowerLoanDefs.ApproveLoanRequest(_whitelistedUser1, 0, 500_000 * 10 ** 6, 1);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.ApproveLoanRequest(_whitelistedUser2, 1, 1_500_000 * 10 ** 6, 3);
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

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidLoan.selector, 2));
        _timePowerLoan.approve(2, 500_000 * 10 ** 6, 1);

        _timePowerLoan.approve(1, 1_500_000 * 10 ** 6, 3);

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotPendingLoan.selector, 1));
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

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidInterestRate.selector, 100));
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 100);

        stdstore.target(address(_timePowerLoan)).sig("_secondInterestRates(uint256)").with_key(uint256(3)).checked_write(
            uint256(0)
        );
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidInterestRate.selector, 3));
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
        emit TimePowerLoanDefs.ApproveLoanRequest(_whitelistedUser1, 0, 1_000_000 * 10 ** 6, 1);
        _timePowerLoan.approve(0, 1_000_000 * 10 ** 6, 1);
        (uint128 ceilingLimit1,,,,,) = _timePowerLoan._allLoans(0);
        assertEq(ceilingLimit1, 500_000 * 10 ** 6);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.ApproveLoanRequest(_whitelistedUser2, 1, 2_000_000 * 10 ** 6, 3);
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
        emit TimePowerLoanDefs.ApproveLoanRequest(_whitelistedUser1, 0, 400_000 * 10 ** 6, 1);
        _timePowerLoan.approve(0, 400_000 * 10 ** 6, 1);
        (uint128 ceilingLimit1,,,,,) = _timePowerLoan._allLoans(0);
        assertEq(ceilingLimit1, 400_000 * 10 ** 6);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.ApproveLoanRequest(_whitelistedUser2, 1, 1_000_000 * 10 ** 6, 3);
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
        emit TimePowerLoanDefs.Borrowed(_whitelistedUser1, 0, 300_000 * 10 ** 6, true, 0);
        vm.prank(_whitelistedUser1);
        (bool isAllSatisfied1,) = _timePowerLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);
        assertTrue(isAllSatisfied1);
        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.Borrowed(_whitelistedUser2, 1, 1_000_000 * 10 ** 6, true, 1);
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

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidLoan.selector, 100));
        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(100, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidLoan.selector, 0));
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

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidLoan.selector, 100));
        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(100, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.expectRevert(
            abi.encodeWithSelector(TimePowerLoanDefs.NotLoanOwner.selector, 0, _whitelistedUser1, _whitelistedUser2)
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

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidLoan.selector, 100));
        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(100, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimePowerLoanDefs.MaturityTimeShouldAfterBlockTimestamp.selector, _currentTime - 1 minutes, _currentTime
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

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidLoan.selector, 100));
        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(100, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimePowerLoanDefs.BorrowAmountOverLoanRemainingLimit.selector,
                500_000 * 10 ** 6 + 1,
                500_000 * 10 ** 6,
                0
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
        emit TimePowerLoanDefs.Borrowed(_whitelistedUser1, 0, 50_000 * 10 ** 6, false, 0);
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
        (,, uint128 principal1, uint128 normalizedPrincipal1,, TimePowerLoanDefs.DebtStatus status1) =
            _timePowerLoan._allDebts(0);
        assertEq(uint256(principal1), 0);
        assertEq(uint256(normalizedPrincipal1), 0);
        assertEq(uint8(TimePowerLoanDefs.DebtStatus.REPAID), uint8(status1));

        vm.warp(_currentTime + 40 days);

        vm.startPrank(_whitelistedUser2);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), 1_000_000 * 10 ** 6 * 2);
        _timePowerLoan.repay(1, 1_000_000 * 10 ** 6 * 2);
        vm.stopPrank();
        (,, uint128 principal2, uint128 normalizedPrincipal2,, TimePowerLoanDefs.DebtStatus status2) =
            _timePowerLoan._allDebts(1);
        assertEq(uint256(principal2), 0);
        assertEq(uint256(normalizedPrincipal2), 0);
        assertEq(uint8(TimePowerLoanDefs.DebtStatus.REPAID), uint8(status2));
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
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidDebt.selector, 100));
        _timePowerLoan.repay(100, 300_000 * 10 ** 6 * 2);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), 300_000 * 10 ** 6 * 2);
        _timePowerLoan.repay(0, 300_000 * 10 ** 6 * 2);
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidDebt.selector, 0));
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
            abi.encodeWithSelector(TimePowerLoanDefs.NotLoanOwner.selector, 0, _whitelistedUser1, _whitelistedUser2)
        );
        vm.prank(_whitelistedUser2);
        _timePowerLoan.repay(0, 2 * 300_000 * 10 ** 6);

        vm.store(
            address(_timePowerLoan),
            bytes32(0xd7b6990105719101dabeb77144f2a3385c8033acd3af97e9423a695e81ad1eb6),
            bytes32(0x00000000000000010000000000000064000000000000000000000045d7f20637)
        );
        vm.prank(_whitelistedUser1);
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidLoan.selector, 100));
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
        TimePowerLoanDefs.DebtInfo memory debtInfo = _getDebtInfoAtIndex(0);
        uint256 repayAmount = ((totalDebt - uint256(debtInfo.principal)) + totalDebt) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        (bool isAllRepaid, uint128 remainingDebt) = _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        assertFalse(isAllRepaid);
        assertEq(uint256(remainingDebt), totalDebt - repayAmount);

        debtInfo = _getDebtInfoAtIndex(0);
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
        TimePowerLoanDefs.DebtInfo memory debtInfo = _getDebtInfoAtIndex(0);
        uint256 repayAmount = (totalDebt - uint256(debtInfo.principal)) / 2;
        uint128 originalPrincipal = debtInfo.principal;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        (bool isAllRepaid, uint128 remainingDebt) = _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        assertFalse(isAllRepaid);
        assertEq(uint256(remainingDebt), totalDebt - repayAmount);

        debtInfo = _getDebtInfoAtIndex(0);
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
        TimePowerLoanDefs.DebtInfo memory debtInfo = _getDebtInfoAtIndex(0);
        uint256 repayAmount = (totalDebt - uint256(debtInfo.principal)) / 1000;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimePowerLoanDefs.RepayTooLittle.selector,
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
        TimePowerLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        (, uint128 totalDebtAfterRepay) = _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        assertEq(totalDebtAfterRepay, totalDebtBeforeRepay - repayAmount);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.Defaulted(_whitelistedUser1, 0, uint128(totalDebtAfterRepay) + 2, 17);
        vm.prank(_owner);
        uint128 totalDebtAfterDefaulted = _timePowerLoan.defaulted(_whitelistedUser1, 0, 17);

        /// @dev Verify that after defaulting, the total debt increases due to penalty interest
        assertLt(_abs(totalDebtAfterRepay, totalDebtAfterDefaulted), 8);
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
        TimePowerLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
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
        TimePowerLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidDebt.selector, 100));
        vm.prank(_owner);
        _timePowerLoan.defaulted(_whitelistedUser1, 100, 17);

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotMaturedDebt.selector, 0));
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
        TimePowerLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidInterestRate.selector, 100));
        vm.prank(_owner);
        _timePowerLoan.defaulted(_whitelistedUser1, 0, 100);

        stdstore.target(address(_timePowerLoan)).sig("_secondInterestRates(uint256)").with_key(17).checked_write(
            uint256(0)
        );
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidInterestRate.selector, 17));
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
        TimePowerLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(TimePowerLoanDefs.NotLoanOwner.selector, 0, _whitelistedUser1, _whitelistedUser2)
        );
        vm.prank(_owner);
        _timePowerLoan.defaulted(_whitelistedUser2, 0, 17);

        vm.store(
            address(_timePowerLoan),
            bytes32(0xd7b6990105719101dabeb77144f2a3385c8033acd3af97e9423a695e81ad1eb6),
            bytes32(0x00000000000000010000000000000064000000000000000000000045d7f20637)
        );
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidLoan.selector, 100));
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
        TimePowerLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        uint256 totalDebtAfterRepay = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.Defaulted(_whitelistedUser1, 0, uint128(totalDebtAfterRepay), 1);
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
        TimePowerLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
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
        emit TimePowerLoanDefs.Recovery(_whitelistedUser1, 0, remainingDebt, 0);
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
        TimePowerLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
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
        TimePowerLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        (, uint128 remainingDebt) = _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), remainingDebt);

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidDebt.selector, 100));
        vm.prank(_owner);
        _timePowerLoan.recovery(_whitelistedUser1, 100, remainingDebt);

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotDefaultedDebt.selector, 0));
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
        TimePowerLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
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
            abi.encodeWithSelector(TimePowerLoanDefs.NotLoanOwner.selector, 0, _whitelistedUser1, _whitelistedUser2)
        );
        vm.prank(_owner);
        _timePowerLoan.recovery(_whitelistedUser2, 0, remainingDebt);

        vm.store(
            address(_timePowerLoan),
            bytes32(0xd7b6990105719101dabeb77144f2a3385c8033acd3af97e9423a695e81ad1eb6),
            bytes32(0x00000000000000030000000000000064000000000000000000000045d7f20637)
        );
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidLoan.selector, 100));
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
        TimePowerLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
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
        emit TimePowerLoanDefs.Recovery(_whitelistedUser1, 0, recoveryAmount, remainingDebt - recoveryAmount);
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
        TimePowerLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
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
        emit TimePowerLoanDefs.Closed(_whitelistedUser1, 0, remainingDebtAtRecovery + 1);
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
        TimePowerLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
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
        TimePowerLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidDebt.selector, 100));
        vm.prank(_owner);
        _timePowerLoan.close(_whitelistedUser1, 100);

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotDefaultedDebt.selector, 0));
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
        TimePowerLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
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
            abi.encodeWithSelector(TimePowerLoanDefs.NotLoanOwner.selector, 0, _whitelistedUser1, _whitelistedUser2)
        );
        vm.prank(_owner);
        _timePowerLoan.close(_whitelistedUser2, 0);

        vm.store(
            address(_timePowerLoan),
            bytes32(0xd7b6990105719101dabeb77144f2a3385c8033acd3af97e9423a695e81ad1eb6),
            bytes32(0x00000000000000030000000000000064000000000000000000000045d7f20637)
        );
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidLoan.selector, 100));
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
        emit TimePowerLoanDefs.BorrowerCeilingLimitUpdated(1_000_000 * 10 ** 6, 1_500_000 * 10 ** 6);
        _timePowerLoan.updateBorrowerLimit(_whitelistedUser1, 1_500_000 * 10 ** 6);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.BorrowerCeilingLimitUpdated(2_000_000 * 10 ** 6, 2_500_000 * 10 ** 6);
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
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotTrustedBorrower.selector, someone));
        _timePowerLoan.updateBorrowerLimit(someone, 3_000_000 * 10 ** 6);

        vm.stopPrank();
    }

    function testUpdateBorrowerLimitBelowRemainingLimit() public {
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
        _timePowerLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.store(
            address(_timePowerLoan),
            bytes32(0x1b6847dc741a1b0cd08d278845f9d819d87b734759afb55fe2de5cb82a9ae673),
            bytes32(0x0000000000000000000000746a5288000000000000000000000000746a5287ff)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                TimePowerLoanDefs.CeilingLimitBelowRemainingLimit.selector, 500_000 * 10 ** 6 - 1, 500_000 * 10 ** 6
            )
        );
        vm.prank(_owner);
        _timePowerLoan.updateBorrowerLimit(_whitelistedUser1, 1_500_000 * 10 ** 6);
    }

    function testUpdateBorrowerLimitBelowUsedLimit() public {
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
        _timePowerLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimePowerLoanDefs.CeilingLimitBelowUsedLimit.selector, 500_000 * 10 ** 6 - 1, 500_000 * 10 ** 6
            )
        );
        vm.prank(_owner);
        _timePowerLoan.updateBorrowerLimit(_whitelistedUser1, 500_000 * 10 ** 6 - 1);
    }

    function testUpdateLoanLimit() public {
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
        _timePowerLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.LoanCeilingLimitUpdated(800_000 * 10 ** 6, 500_000 * 10 ** 6);
        vm.prank(_owner);
        _timePowerLoan.updateLoanLimit(0, 800_000 * 10 ** 6);
    }

    function testNotOperatorUpdateLoanLimit() public {
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
        _timePowerLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        address someone = makeAddr("someone");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, makeAddr("someone"), Roles.OPERATOR_ROLE
            )
        );
        vm.prank(someone);
        _timePowerLoan.updateLoanLimit(0, 800_000 * 10 ** 6);
    }

    function testUpdateNotValidLoanLimit() public {
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
        _timePowerLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidLoan.selector, 100));
        vm.prank(_owner);
        _timePowerLoan.updateLoanLimit(100, 800_000 * 10 ** 6);

        stdstore.target(address(_timePowerLoan)).sig("_allLoans(uint256)").with_key(uint256(0)).depth(5).checked_write(
            uint256(3)
        );
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidLoan.selector, 0));
        vm.prank(_owner);
        _timePowerLoan.updateLoanLimit(0, 800_000 * 10 ** 6);
    }

    function testUpdateNotTrustedBorrowerLoanLimit() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_whitelistedUser2);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_whitelistedUser2);
        _timePowerLoan.request(1_500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_owner);
        _timePowerLoan.approve(1, 1_500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.prank(_whitelistedUser2);
        _timePowerLoan.borrow(1, 1_500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        address someone = makeAddr("someone");
        /// @dev modify loan 0's borrower to `someone`
        vm.store(
            address(_timePowerLoan),
            bytes32(0x1b6847dc741a1b0cd08d278845f9d819d87b734759afb55fe2de5cb82a9ae672),
            bytes32(uint256(uint160(someone)))
        );
        /// @dev modify 'someone' borrower index to 1
        stdstore.target(address(_timePowerLoan)).sig("_borrowerToIndex(address)").with_key(someone).checked_write(
            uint256(1)
        );
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotTrustedBorrower.selector, someone));
        vm.prank(_owner);
        _timePowerLoan.updateLoanLimit(0, 800_000 * 10 ** 6);
    }

    function testUpdateLoanLimitBelowRemainingLimit() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(1_000_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 1_000_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        vm.store(
            address(_timePowerLoan),
            bytes32(0xdf6966c971051c3d54ec59162606531493a51404a002842f56009d7e5cf4a8c7),
            bytes32(0x0000000000000000000000746a5288000000000000000000000000746a5287ff)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                TimePowerLoanDefs.CeilingLimitBelowRemainingLimit.selector, 500_000 * 10 ** 6 - 1, 500_000 * 10 ** 6
            )
        );
        vm.prank(_owner);
        _timePowerLoan.updateLoanLimit(0, 800_000 * 10 ** 6);
    }

    function testUpdateLoanLimitBelowUsedLimit() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(1_000_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 1_000_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        vm.expectRevert(
            abi.encodeWithSelector(
                TimePowerLoanDefs.CeilingLimitBelowUsedLimit.selector, 500_000 * 10 ** 6 - 1, 500_000 * 10 ** 6
            )
        );
        vm.prank(_owner);
        _timePowerLoan.updateLoanLimit(0, 500_000 * 10 ** 6 - 1);
    }

    function testUpdateLoanLimitExceedBorrowerRemainingLimit() public {
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
        _timePowerLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        vm.expectRevert(
            abi.encodeWithSelector(
                TimePowerLoanDefs.LoanCeilingLimitExceedsBorrowerRemainingLimit.selector,
                1_000_000 * 10 ** 6 + 1,
                500_000 * 10 ** 6
            )
        );
        vm.prank(_owner);
        _timePowerLoan.updateLoanLimit(0, 1_000_000 * 10 ** 6 + 1);
    }

    function testUpdateLoanInterestRate() public {
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
        _timePowerLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.LoanInterestRateUpdated(0, 1, 17);
        vm.prank(_owner);
        _timePowerLoan.updateLoanInterestRate(0, 17);

        vm.warp(_currentTime + 30 days);

        vm.prank(_owner);
        _timePowerLoan.pile();
    }

    function testNotOperatorUpdateLoanInterestRate() public {
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
        _timePowerLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        address someone = makeAddr("someone");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, makeAddr("someone"), Roles.OPERATOR_ROLE
            )
        );
        vm.prank(someone);
        _timePowerLoan.updateLoanInterestRate(0, 17);
    }

    function testUpdateNotValidLoanInterestRate() public {
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
        _timePowerLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidLoan.selector, 100));
        vm.prank(_owner);
        _timePowerLoan.updateLoanInterestRate(100, 17);

        stdstore.target(address(_timePowerLoan)).sig("_allLoans(uint256)").with_key(uint256(0)).depth(5).checked_write(
            uint256(3)
        );
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidLoan.selector, 0));
        vm.prank(_owner);
        _timePowerLoan.updateLoanInterestRate(0, 17);
    }

    function testUpdateLoanNotValidInterestRate() public {
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
        _timePowerLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidInterestRate.selector, 100));
        vm.prank(_owner);
        _timePowerLoan.updateLoanInterestRate(0, 100);

        stdstore.target(address(_timePowerLoan)).sig("_secondInterestRates(uint256)").with_key(uint256(17))
            .checked_write(uint256(0));
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidInterestRate.selector, 17));
        vm.prank(_owner);
        _timePowerLoan.updateLoanInterestRate(0, 17);
    }

    function testUpdateLoanInterestRateForNotTrustedBorrower() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_whitelistedUser2);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(500_000 * 10 ** 6);

        vm.prank(_whitelistedUser2);
        _timePowerLoan.request(1_500_000 * 10 ** 6);

        vm.prank(_owner);
        _timePowerLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_owner);
        _timePowerLoan.approve(1, 1_500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.prank(_whitelistedUser2);
        _timePowerLoan.borrow(1, 1_500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        address someone = makeAddr("someone");
        /// @dev modify loan 0's borrower to `someone`
        vm.store(
            address(_timePowerLoan),
            bytes32(0x1b6847dc741a1b0cd08d278845f9d819d87b734759afb55fe2de5cb82a9ae672),
            bytes32(uint256(uint160(someone)))
        );
        /// @dev modify 'someone' borrower index to 1
        stdstore.target(address(_timePowerLoan)).sig("_borrowerToIndex(address)").with_key(someone).checked_write(
            uint256(1)
        );
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotTrustedBorrower.selector, someone));
        vm.prank(_owner);
        _timePowerLoan.updateLoanInterestRate(0, 17);
    }

    function testUpdateLoanInterestRateAfterDefault() public {
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
        TimePowerLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount);
        (, uint128 totalDebtAfterRepay) = _timePowerLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        /// @dev Verify that after repayment, the total debt is reduced by the repay amount
        assertEq(totalDebtAfterRepay, totalDebtBeforeRepay - repayAmount);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.Defaulted(_whitelistedUser1, 0, uint128(totalDebtAfterRepay) + 2, 10);
        vm.prank(_owner);
        uint128 totalDebtAfterDefaulted = _timePowerLoan.defaulted(_whitelistedUser1, 0, 10);

        /// @dev Verify that after defaulting, the total debt increases due to penalty interest
        assertEq(totalDebtAfterRepay + 2, totalDebtAfterDefaulted);

        vm.warp(_currentTime + 50 days);
        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.LoanInterestRateUpdated(0, 10, 17);
        vm.prank(_owner);
        _timePowerLoan.updateLoanInterestRate(0, 17);
    }

    function testUpdateTrustedVaults() public {
        TimePowerLoanDefs.TrustedVault memory newTrustedVault = TimePowerLoanDefs.TrustedVault({
            vault: address(new AssetVault(IERC20(address(_depositToken)), "MMF@OpenTerm", "MMF@OpenTerm")),
            minimumPercentage: 10 * 10 ** 4, // 10%
            maximumPercentage: 40 * 10 ** 4 // 40%
        });

        TimePowerLoanDefs.TrustedVault memory tempTrustedVault;

        tempTrustedVault = TimePowerLoanDefs.TrustedVault({
            vault: newTrustedVault.vault,
            minimumPercentage: newTrustedVault.minimumPercentage, // 10%
            maximumPercentage: newTrustedVault.maximumPercentage // 40%
        });
        tempTrustedVault.vault = address(0x00);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "trusted vault address"));
        vm.prank(_owner);
        _timePowerLoan.updateTrustedVaults(tempTrustedVault, 1);

        tempTrustedVault = TimePowerLoanDefs.TrustedVault({
            vault: newTrustedVault.vault,
            minimumPercentage: newTrustedVault.minimumPercentage, // 10%
            maximumPercentage: newTrustedVault.maximumPercentage // 40%
        });
        tempTrustedVault.vault = address(
            new AssetVault(
                IERC20(address(new DepositAsset("UNKNOWN", "UNKNOWN"))), "UNKNOWN@UNKNOWN", "UNKNOWN@UNKNOWN"
            )
        );
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidValue.selector, "trusted vault asset and loan token mismatch")
        );
        vm.prank(_owner);
        _timePowerLoan.updateTrustedVaults(tempTrustedVault, 1);

        tempTrustedVault = TimePowerLoanDefs.TrustedVault({
            vault: newTrustedVault.vault,
            minimumPercentage: newTrustedVault.minimumPercentage, // 10%
            maximumPercentage: newTrustedVault.maximumPercentage // 40%
        });
        tempTrustedVault.minimumPercentage = tempTrustedVault.maximumPercentage + 1;
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "trusted vault percentage"));
        vm.prank(_owner);
        _timePowerLoan.updateTrustedVaults(tempTrustedVault, 1);

        tempTrustedVault = TimePowerLoanDefs.TrustedVault({
            vault: newTrustedVault.vault,
            minimumPercentage: newTrustedVault.minimumPercentage, // 10%
            maximumPercentage: newTrustedVault.maximumPercentage // 40%
        });
        tempTrustedVault.maximumPercentage = 1_000_000 + 1;
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidValue.selector, "trusted vault maximum percentage exceeds 100%")
        );
        vm.prank(_owner);
        _timePowerLoan.updateTrustedVaults(tempTrustedVault, 1);

        (tempTrustedVault.vault, tempTrustedVault.minimumPercentage, tempTrustedVault.maximumPercentage) =
            _timePowerLoan._trustedVaults(1);
        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.TrustedVaultUpdated(
            tempTrustedVault.vault,
            tempTrustedVault.minimumPercentage,
            tempTrustedVault.maximumPercentage,
            newTrustedVault.vault,
            newTrustedVault.minimumPercentage,
            newTrustedVault.maximumPercentage,
            1
        );
        vm.prank(_owner);
        assertTrue(_timePowerLoan.updateTrustedVaults(newTrustedVault, 1));
    }

    function testNotOperatorUpdateTrustedVaults() public {
        TimePowerLoanDefs.TrustedVault memory newTrustedVault = TimePowerLoanDefs.TrustedVault({
            vault: address(new AssetVault(IERC20(address(_depositToken)), "MMF@OpenTerm", "MMF@OpenTerm")),
            minimumPercentage: 10 * 10 ** 4, // 10%
            maximumPercentage: 40 * 10 ** 4 // 40%
        });

        address someone = makeAddr("someone");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, someone, Roles.OPERATOR_ROLE
            )
        );
        vm.prank(someone);
        _timePowerLoan.updateTrustedVaults(newTrustedVault, 100);
    }

    function testUpdateTrustedVaultsWhenVaultsNotExist() public {
        TimePowerLoanDefs.TrustedVault memory newTrustedVault = TimePowerLoanDefs.TrustedVault({
            vault: address(new AssetVault(IERC20(address(_depositToken)), "MMF@OpenTerm", "MMF@OpenTerm")),
            minimumPercentage: 10 * 10 ** 4, // 10%
            maximumPercentage: 40 * 10 ** 4 // 40%
        });

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.TrustedVaultAdded(
            newTrustedVault.vault, newTrustedVault.minimumPercentage, newTrustedVault.maximumPercentage, 4
        );
        vm.prank(_owner);
        assertFalse(_timePowerLoan.updateTrustedVaults(newTrustedVault, 100));
    }

    function testPile() public {
        vm.warp(_currentTime + 60 days);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.AccumulatedInterestUpdated(_currentTime + 60 days);
        vm.prank(makeAddr("anyone"));
        _timePowerLoan.pile();
    }

    function testTotalDebtOfBorrower() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));
        _prepareDebt();

        vm.warp(_currentTime + 30 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        uint256 totalDebtOfWhitelistedUser1 = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);
        uint256 totalDebtOfWhitelistedUser2 = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser2);
        assertGt(totalDebtOfWhitelistedUser1, 0);
        assertGt(totalDebtOfWhitelistedUser2, 0);
        assertLt(totalDebtOfWhitelistedUser1, totalDebtOfWhitelistedUser2);
    }

    function testTotalDebtOfNotTrustedBorrower() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));
        _prepareDebt();

        vm.warp(_currentTime + 30 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        address someone = makeAddr("someone");
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotTrustedBorrower.selector, someone));
        _timePowerLoan.totalDebtOfBorrower(someone);
    }

    function testTotalDebtOfVault() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));
        _prepareDebt();

        vm.warp(_currentTime + 30 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        uint256 totalDebtOfVault;

        for (uint256 i = 0; i < _trustedVaults.length; i++) {
            totalDebtOfVault += _timePowerLoan.totalDebtOfVault(_trustedVaults[i].vault);
        }

        uint256 totalDebtOfBorrower;

        totalDebtOfBorrower += _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);
        totalDebtOfBorrower += _timePowerLoan.totalDebtOfBorrower(_whitelistedUser2);

        assertEq(totalDebtOfVault, totalDebtOfBorrower);
    }

    function testTotalDebtOfNotTrustedVault() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));
        _prepareDebt();

        vm.warp(_currentTime + 30 days);

        vm.prank(_owner);
        _timePowerLoan.pile();

        address mockVault = makeAddr("mockVault");
        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotTrustedVault.selector, mockVault));
        _timePowerLoan.totalDebtOfVault(mockVault);
    }

    function testFuzzBorrowAndRepay(
        uint128 borrowAmount_,
        uint128 repayAmount_,
        uint8 interestRateIndex_,
        uint16 borrowDays_
    ) public {
        uint128 maxBorrowFund = uint128(IERC20(address(_depositToken)).balanceOf(_owner));
        _prepareFund(uint256(maxBorrowFund / _trustedVaults.length));

        borrowAmount_ = uint128(bound(borrowAmount_, 1_000 * 10 ** 6, maxBorrowFund / 2));
        repayAmount_ = uint128(bound(repayAmount_, borrowAmount_ / 2, borrowAmount_ * 2));
        interestRateIndex_ = uint8(bound(interestRateIndex_, 0, 17));
        borrowDays_ = uint16(bound(borrowDays_, 1, 365));

        _depositToken.mint(_whitelistedUser1, 1_000_000_000_000_000 * 10 ** 6);
        _depositToken.mint(_whitelistedUser2, 1_000_000_000_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(_whitelistedUser1, maxBorrowFund);

        vm.prank(_whitelistedUser1);
        uint64 loanIndex = _timePowerLoan.request(maxBorrowFund);

        vm.prank(_owner);
        _timePowerLoan.approve(loanIndex, maxBorrowFund, interestRateIndex_);

        vm.prank(_whitelistedUser1);
        (, uint64 debtIndex) =
            _timePowerLoan.borrow(loanIndex, borrowAmount_, uint64(_currentTime + uint256(borrowDays_) * 1 days));

        vm.warp(_currentTime + uint256(borrowDays_) * 1 days / 2);

        vm.prank(_owner);
        _timePowerLoan.pile();

        uint256 totalDebtBeforeRepay = _timePowerLoan.totalDebtOfBorrower(_whitelistedUser1);
        assertGt(totalDebtBeforeRepay, borrowAmount_);

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), repayAmount_);

        vm.prank(_whitelistedUser1);
        (bool isAllRepaid, uint128 remainingDebt) = _timePowerLoan.repay(debtIndex, repayAmount_);

        if (isAllRepaid) {
            assertEq(remainingDebt, 0);
        } else {
            assertLt(_abs(uint256(remainingDebt), totalDebtBeforeRepay - uint256(repayAmount_)), 10);
        }
    }

    function testOnlyInitialized() public {
        MockTimePowerLoan mockTimePowerLoan = new MockTimePowerLoan();

        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "whitelist"));
        mockTimePowerLoan.mockOnlyInitialized();

        stdstore.target(address(mockTimePowerLoan)).sig("_whitelist()").checked_write(address(_whitelist));

        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "blacklist"));
        mockTimePowerLoan.mockOnlyInitialized();

        stdstore.target(address(mockTimePowerLoan)).sig("_blacklist()").checked_write(address(_blacklist));

        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "loanToken"));
        mockTimePowerLoan.mockOnlyInitialized();

        stdstore.target(address(mockTimePowerLoan)).sig("_loanToken()").checked_write(address(_depositToken));

        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "secondInterestRates"));
        mockTimePowerLoan.mockOnlyInitialized();

        vm.store(
            address(mockTimePowerLoan),
            0x0000000000000000000000000000000000000000000000000000000000000011,
            0x0000000000000000000000000000000000000000000000000de0b6b3ba327400
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "trustedVaults"));
        mockTimePowerLoan.mockOnlyInitialized();
    }

    function testOnlyWhitelisted() public {
        MockTimePowerLoan mockTimePowerLoan = new MockTimePowerLoan();

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "whitelist"));
        vm.prank(address(0x01));
        mockTimePowerLoan.mockOnlyWhitelisted();

        stdstore.target(address(mockTimePowerLoan)).sig("_whitelist()").checked_write(address(_whitelist));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "borrower"));
        vm.prank(address(0x00));
        mockTimePowerLoan.mockOnlyWhitelisted();
    }

    function testOnlyNotBlacklisted() public {
        MockTimePowerLoan mockTimePowerLoan = new MockTimePowerLoan();

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "blacklist"));
        vm.prank(address(0x01));
        mockTimePowerLoan.mockOnlyNotBlacklisted();

        stdstore.target(address(mockTimePowerLoan)).sig("_blacklist()").checked_write(address(_blacklist));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "borrower"));
        vm.prank(address(0x00));
        mockTimePowerLoan.mockOnlyNotBlacklisted();
    }

    function testOnlyTrustedBorrower() public {
        MockTimePowerLoan mockTimePowerLoan = new MockTimePowerLoan();

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "borrower"));
        vm.prank(address(0x00));
        mockTimePowerLoan.mockOnlyTrustedBorrower();
    }

    function testOnlyTrustedVault() public {
        MockTimePowerLoan mockTimePowerLoan = new MockTimePowerLoan();

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "vault"));
        vm.prank(address(0x00));
        mockTimePowerLoan.mockOnlyTrustedVault();
    }

    function testOnlyValidTranche() public {
        MockTimePowerLoan mockTimePowerLoan = new MockTimePowerLoan();

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidTranche.selector, 0));
        mockTimePowerLoan.mockOnlyValidTranche(0);
    }

    function testOnlyValidVault() public {
        MockTimePowerLoan mockTimePowerLoan = MockTimePowerLoan(
            address(
                new TransparentUpgradeableProxy(
                    address(new MockTimePowerLoan()),
                    _owner,
                    abi.encodeWithSelector(
                        TimePowerLoan.initialize.selector,
                        [_owner, address(_whitelist), address(_blacklist), address(_depositToken)],
                        _secondInterestRates,
                        _trustedVaults
                    )
                )
            )
        );

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidVault.selector, 4));
        mockTimePowerLoan.mockOnlyValidVault(4);

        vm.store(
            address(mockTimePowerLoan),
            0x8d1108e10bcb7c27dddfc02ed9d693a074039d026cf4ea4240b40f7d581ac802,
            0x000000061a800000000186a00000000000000000000000000000000000000000
        );

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidVault.selector, 0));
        mockTimePowerLoan.mockOnlyValidVault(0);

        vm.store(
            address(mockTimePowerLoan),
            0x8d1108e10bcb7c27dddfc02ed9d693a074039d026cf4ea4240b40f7d581ac802,
            0x000000000000000000000000f62849f9a0b5bf2913b396098f7c7019b51a820a
        );

        vm.expectRevert(abi.encodeWithSelector(TimePowerLoanDefs.NotValidVault.selector, 0));
        mockTimePowerLoan.mockOnlyValidVault(0);
    }

    function testRevertWhenInitialize() public {
        address logic = address(new MockTimePowerLoan());
        address[4] memory addrs;

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "owner"));
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimePowerLoan.initialize.selector, addrs, _secondInterestRates, _trustedVaults)
        );
        addrs[0] = _owner;

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "whitelist"));
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimePowerLoan.initialize.selector, addrs, _secondInterestRates, _trustedVaults)
        );
        addrs[1] = address(_whitelist);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "blacklist"));
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimePowerLoan.initialize.selector, addrs, _secondInterestRates, _trustedVaults)
        );
        addrs[2] = address(_blacklist);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "loanToken"));
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimePowerLoan.initialize.selector, addrs, _secondInterestRates, _trustedVaults)
        );
        addrs[3] = address(_depositToken);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "second interest rates length is zero"));
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimePowerLoan.initialize.selector, addrs, new uint64[](0), _trustedVaults)
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "second interest rates value invalid"));
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimePowerLoan.initialize.selector, addrs, new uint64[](18), _trustedVaults)
        );

        _secondInterestRates[17] = 10000000097502800000 + 1;

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "second interest rates value invalid"));
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimePowerLoan.initialize.selector, addrs, _secondInterestRates, _trustedVaults)
        );

        _secondInterestRates[16] = 1000000009516250000;
        _secondInterestRates[17] = 1000000009042960000;

        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidValue.selector, "second interest rates not sorted or duplicated")
        );
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimePowerLoan.initialize.selector, addrs, _secondInterestRates, _trustedVaults)
        );

        _secondInterestRates[16] = 1000000009042960000;
        _secondInterestRates[17] = 1000000009516250000;

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "trusted vaults length is zero"));
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(
                TimePowerLoan.initialize.selector, addrs, _secondInterestRates, new TimePowerLoanDefs.TrustedVault[](0)
            )
        );

        _trustedVaults.push(
            TimePowerLoanDefs.TrustedVault({
                vault: address(0x00),
                minimumPercentage: 40 * 10 ** 4, // 40%
                maximumPercentage: 10 * 10 ** 4 // 10%
            })
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "trusted vault address"));
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimePowerLoan.initialize.selector, addrs, _secondInterestRates, _trustedVaults)
        );

        _trustedVaults[4].vault = address(new AssetVault(IERC20(address(0x01)), "NULL@OpenTerm", "NULL@OpenTerm"));

        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidValue.selector, "trusted vault asset and loan token mismatch")
        );
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimePowerLoan.initialize.selector, addrs, _secondInterestRates, _trustedVaults)
        );

        _trustedVaults[4].vault =
            address(new AssetVault(IERC20(address(_depositToken)), "NULL@OpenTerm", "NULL@OpenTerm"));

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "trusted vault percentage"));
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimePowerLoan.initialize.selector, addrs, _secondInterestRates, _trustedVaults)
        );

        _trustedVaults[4].minimumPercentage = 10 * 10 ** 4; // 10%
        _trustedVaults[4].maximumPercentage = 1_000_000 + 1; // 101%

        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidValue.selector, "trusted vault maximum percentage exceeds 100%")
        );
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimePowerLoan.initialize.selector, addrs, _secondInterestRates, _trustedVaults)
        );
    }

    function testPower() public {
        MockTimePowerLoan mockTimePowerLoan = new MockTimePowerLoan();

        assertEq(mockTimePowerLoan.mockPower(0, 0, 1e18), 1e18);
        assertEq(mockTimePowerLoan.mockPower(0, 1, 1e18), 0);
        assertEq(mockTimePowerLoan.mockPower(1e18, 2, 1e18), 1e18);
        assertEq(mockTimePowerLoan.mockPower(1e18, 3, 1e18), 1e18);

        vm.expectRevert(bytes(""));
        mockTimePowerLoan.mockPower(1 << 128, 2, 1e18);

        vm.expectRevert(bytes(""));
        mockTimePowerLoan.mockPower((1 << 128) - 1, 2, (1 << 130) - 2);
    }

    function testFullFlow() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.TrustedBorrowerAdded(_whitelistedUser1, 0);
        vm.prank(_whitelistedUser1);
        _timePowerLoan.join();

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.TrustedBorrowerAdded(_whitelistedUser2, 1);
        vm.prank(_whitelistedUser2);
        _timePowerLoan.join();

        TimePowerLoanDefs.TrustedBorrower memory borrowerInfo1 = _getBorrowerInfoAtIndex(0);
        TimePowerLoanDefs.TrustedBorrower memory borrowerInfo2 = _getBorrowerInfoAtIndex(1);

        assertEq(borrowerInfo1.borrower, _whitelistedUser1);
        assertEq(borrowerInfo2.borrower, _whitelistedUser2);
        assertEq(borrowerInfo1.ceilingLimit, 0);
        assertEq(borrowerInfo2.ceilingLimit, 0);
        assertEq(borrowerInfo1.remainingLimit, 0);
        assertEq(borrowerInfo2.remainingLimit, 0);

        vm.warp(_currentTime += 1 days);
        _timePowerLoan.pile();

        vm.startPrank(_owner);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.AgreeJoinRequest(_whitelistedUser1, 2_000_000 * 10 ** 6);
        _timePowerLoan.agree(_whitelistedUser1, 2_000_000 * 10 ** 6);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.AgreeJoinRequest(_whitelistedUser2, 4_000_000 * 10 ** 6);
        _timePowerLoan.agree(_whitelistedUser2, 4_000_000 * 10 ** 6);

        vm.stopPrank();

        borrowerInfo1 = _getBorrowerInfoAtIndex(0);
        borrowerInfo2 = _getBorrowerInfoAtIndex(1);

        assertEq(borrowerInfo1.borrower, _whitelistedUser1);
        assertEq(borrowerInfo2.borrower, _whitelistedUser2);
        assertEq(borrowerInfo1.ceilingLimit, 2_000_000 * 10 ** 6);
        assertEq(borrowerInfo2.ceilingLimit, 4_000_000 * 10 ** 6);
        assertEq(borrowerInfo1.remainingLimit, 2_000_000 * 10 ** 6);
        assertEq(borrowerInfo2.remainingLimit, 4_000_000 * 10 ** 6);

        vm.warp(_currentTime += 1 days);
        _timePowerLoan.pile();

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.ReceiveLoanRequest(_whitelistedUser1, 0, 1_500_000 * 10 ** 6);
        vm.prank(_whitelistedUser1);
        _timePowerLoan.request(1_500_000 * 10 ** 6);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.ReceiveLoanRequest(_whitelistedUser2, 1, 3_500_000 * 10 ** 6);
        vm.prank(_whitelistedUser2);
        _timePowerLoan.request(3_500_000 * 10 ** 6);

        TimePowerLoanDefs.LoanInfo memory loanInfo1 = _getLoanInfoAtIndex(0);
        TimePowerLoanDefs.LoanInfo memory loanInfo2 = _getLoanInfoAtIndex(1);

        assertEq(loanInfo1.ceilingLimit, 1_500_000 * 10 ** 6);
        assertEq(loanInfo2.ceilingLimit, 3_500_000 * 10 ** 6);
        assertEq(loanInfo1.remainingLimit, 1_500_000 * 10 ** 6);
        assertEq(loanInfo2.remainingLimit, 3_500_000 * 10 ** 6);
        assertEq(loanInfo1.normalizedPrincipal, 0);
        assertEq(loanInfo2.normalizedPrincipal, 0);
        assertEq(loanInfo1.interestRateIndex, 0);
        assertEq(loanInfo2.interestRateIndex, 0);
        assertEq(loanInfo1.borrowerIndex, 0);
        assertEq(loanInfo2.borrowerIndex, 1);
        assertEq(uint8(loanInfo1.status), uint8(TimePowerLoanDefs.LoanStatus.PENDING));
        assertEq(uint8(loanInfo2.status), uint8(TimePowerLoanDefs.LoanStatus.PENDING));

        vm.warp(_currentTime += 1 days);
        _timePowerLoan.pile();

        vm.startPrank(_owner);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.ApproveLoanRequest(_whitelistedUser1, 0, 1_000_000 * 10 ** 6, 1);
        _timePowerLoan.approve(0, 1_000_000 * 10 ** 6, 1);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.ApproveLoanRequest(_whitelistedUser2, 1, 3_000_000 * 10 ** 6, 3);
        _timePowerLoan.approve(1, 3_000_000 * 10 ** 6, 3);

        vm.stopPrank();

        loanInfo1 = _getLoanInfoAtIndex(0);
        loanInfo2 = _getLoanInfoAtIndex(1);

        assertEq(loanInfo1.ceilingLimit, 1_000_000 * 10 ** 6);
        assertEq(loanInfo2.ceilingLimit, 3_000_000 * 10 ** 6);
        assertEq(loanInfo1.remainingLimit, 1_000_000 * 10 ** 6);
        assertEq(loanInfo2.remainingLimit, 3_000_000 * 10 ** 6);
        assertEq(loanInfo1.normalizedPrincipal, 0);
        assertEq(loanInfo2.normalizedPrincipal, 0);
        assertEq(loanInfo1.interestRateIndex, 1);
        assertEq(loanInfo2.interestRateIndex, 3);
        assertEq(loanInfo1.borrowerIndex, 0);
        assertEq(loanInfo2.borrowerIndex, 1);
        assertEq(uint8(loanInfo1.status), uint8(TimePowerLoanDefs.LoanStatus.APPROVED));
        assertEq(uint8(loanInfo2.status), uint8(TimePowerLoanDefs.LoanStatus.APPROVED));

        vm.warp(_currentTime += 1 days);
        _timePowerLoan.pile();

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.Borrowed(_whitelistedUser1, 0, 500_000 * 10 ** 6, true, 0);
        vm.prank(_whitelistedUser1);
        (bool isAllSatisfied1,) = _timePowerLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);
        assertTrue(isAllSatisfied1);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.Borrowed(_whitelistedUser2, 1, 1_500_000 * 10 ** 6, true, 1);
        vm.prank(_whitelistedUser2);
        (bool isAllSatisfied2,) = _timePowerLoan.borrow(1, 1_500_000 * 10 ** 6, _currentTime + 60 days);
        assertTrue(isAllSatisfied2);

        TimePowerLoanDefs.DebtInfo memory debtInfo1 = _getDebtInfoAtIndex(0);
        TimePowerLoanDefs.DebtInfo memory debtInfo2 = _getDebtInfoAtIndex(1);

        assertEq(debtInfo1.startTime, uint64(block.timestamp));
        assertEq(debtInfo2.startTime, uint64(block.timestamp));
        assertEq(debtInfo1.maturityTime, uint64(block.timestamp + 30 days));
        assertEq(debtInfo2.maturityTime, uint64(block.timestamp + 60 days));
        assertEq(debtInfo1.principal, 500_000 * 10 ** 6);
        assertEq(debtInfo2.principal, 1_500_000 * 10 ** 6);
        assertLt(
            _abs(debtInfo1.normalizedPrincipal, 500_000 * 10 ** 6 * 1e18 / _timePowerLoan._accumulatedInterestRates(1)),
            8
        );
        assertLt(
            _abs(
                debtInfo2.normalizedPrincipal, 1_500_000 * 10 ** 6 * 1e18 / _timePowerLoan._accumulatedInterestRates(3)
            ),
            8
        );
        assertEq(debtInfo1.loanIndex, 0);
        assertEq(debtInfo2.loanIndex, 1);
        assertEq(uint8(debtInfo1.status), uint8(TimePowerLoanDefs.DebtStatus.ACTIVE));
        assertEq(uint8(debtInfo2.status), uint8(TimePowerLoanDefs.DebtStatus.ACTIVE));

        vm.warp(_currentTime += 25 days);
        _timePowerLoan.pile();

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), 300_000 * 10 ** 6);
        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.Repaid(_whitelistedUser1, 0, 300_000 * 10 ** 6, false);
        _timePowerLoan.repay(0, 300_000 * 10 ** 6);
        vm.stopPrank();

        vm.warp(_currentTime += (5 days + 1 seconds));
        _timePowerLoan.pile();

        debtInfo1 = _getDebtInfoAtIndex(0);
        loanInfo1 = _getLoanInfoAtIndex(debtInfo1.loanIndex);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.Defaulted(
            _whitelistedUser1,
            0,
            uint128(
                uint256(debtInfo1.normalizedPrincipal).mulDiv(
                    _timePowerLoan._accumulatedInterestRates(loanInfo1.interestRateIndex), 1e18, Math.Rounding.Ceil
                )
            ),
            17
        );
        vm.prank(_owner);
        uint128 remainingDebt = _timePowerLoan.defaulted(_whitelistedUser1, 0, 17);

        vm.warp(_currentTime += 5 days);
        _timePowerLoan.pile();

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), remainingDebt / 2);

        vm.prank(_owner);
        (, remainingDebt) = _timePowerLoan.recovery(_whitelistedUser1, 0, remainingDebt / 2);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        /// @dev precision loss in interest calculations with dividing
        emit TimePowerLoanDefs.Closed(_whitelistedUser1, 0, remainingDebt + 1);
        vm.prank(_owner);
        _timePowerLoan.close(_whitelistedUser1, 0);

        vm.warp(_currentTime += 5 days);
        _timePowerLoan.pile();

        vm.startPrank(_whitelistedUser2);
        IERC20(address(_depositToken)).approve(address(_timePowerLoan), 1_000_000 * 10 ** 6);
        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.Repaid(_whitelistedUser2, 1, 1_000_000 * 10 ** 6, false);
        _timePowerLoan.repay(1, 1_000_000 * 10 ** 6);
        vm.stopPrank();

        vm.warp(_currentTime += 20 days);
        _timePowerLoan.pile();

        debtInfo2 = _getDebtInfoAtIndex(1);
        loanInfo2 = _getLoanInfoAtIndex(debtInfo2.loanIndex);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        emit TimePowerLoanDefs.Defaulted(
            _whitelistedUser2,
            1,
            uint128(
                uint256(debtInfo2.normalizedPrincipal).mulDiv(
                    _timePowerLoan._accumulatedInterestRates(loanInfo2.interestRateIndex), 1e18, Math.Rounding.Ceil
                )
            ) + 1,
            17
        );
        vm.prank(_owner);
        remainingDebt = _timePowerLoan.defaulted(_whitelistedUser2, 1, 17);

        vm.expectEmit(false, false, false, true, address(_timePowerLoan));
        /// @dev precision loss in interest calculations with dividing
        emit TimePowerLoanDefs.Closed(_whitelistedUser2, 1, remainingDebt);
        vm.prank(_owner);
        _timePowerLoan.close(_whitelistedUser2, 1);
    }

    function _abs(uint256 a_, uint256 b_) internal pure returns (uint256) {
        return a_ >= b_ ? a_ - b_ : b_ - a_;
    }

    function _getLoanInfoAtIndex(uint256 loanIndex_)
        internal
        view
        returns (TimePowerLoanDefs.LoanInfo memory loanInfo_)
    {
        (
            loanInfo_.ceilingLimit,
            loanInfo_.remainingLimit,
            loanInfo_.normalizedPrincipal,
            loanInfo_.interestRateIndex,
            loanInfo_.borrowerIndex,
            loanInfo_.status
        ) = _timePowerLoan._allLoans(loanIndex_);
    }

    function _getBorrowerInfoAtIndex(uint256 borrowerIndex_)
        internal
        view
        returns (TimePowerLoanDefs.TrustedBorrower memory borrowerInfo_)
    {
        (borrowerInfo_.borrower, borrowerInfo_.ceilingLimit, borrowerInfo_.remainingLimit) =
            _timePowerLoan._trustedBorrowers(borrowerIndex_);
    }

    function _getDebtInfoAtIndex(uint256 debtIndex_)
        internal
        view
        returns (TimePowerLoanDefs.DebtInfo memory debtInfo_)
    {
        (
            debtInfo_.startTime,
            debtInfo_.maturityTime,
            debtInfo_.principal,
            debtInfo_.normalizedPrincipal,
            debtInfo_.loanIndex,
            debtInfo_.status
        ) = _timePowerLoan._allDebts(debtIndex_);
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

contract MockTimePowerLoan is TimePowerLoan {
    function mockOnlyInitialized() public view onlyInitialized {}
    function mockOnlyWhitelisted() public view onlyWhitelisted(msg.sender) {}
    function mockOnlyNotBlacklisted() public view onlyNotBlacklisted(msg.sender) {}
    function mockOnlyTrustedBorrower() public view onlyTrustedBorrower(msg.sender) {}
    function mockOnlyTrustedVault() public view onlyTrustedVault(msg.sender) {}
    function mockOnlyValidTranche(uint64 trancheIndex_) public view onlyValidTranche(trancheIndex_) {}
    function mockOnlyValidVault(uint64 vaultIndex_) public view onlyValidVault(vaultIndex_) {}

    function mockPower(uint256 x_, uint256 n_, uint256 base_) public pure returns (uint256) {
        return _rpow(x_, n_, base_);
    }
}
