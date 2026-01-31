// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console, stdStorage, StdStorage} from "forge-std/Test.sol";

import {TimeLinearLoan} from "src/protocols/borrower/time-linear/TimeLinearLoan.sol";
import {TimeLinearLoanDefs} from "src/protocols/borrower/time-linear/utils/TimeLinearLoanDefs.sol";
import {Whitelist} from "src/whitelist/Whitelist.sol";
import {Blacklist} from "src/blacklist/Blacklist.sol";
import {Roles} from "src/common/Roles.sol";
import {Errors} from "src/common/Errors.sol";
import {IWhitelist} from "src/whitelist/IWhitelist.sol";
import {IBlacklist} from "src/blacklist/IBlacklist.sol";

import {DeployContractSuite} from "script/DeployContractSuite.s.sol";

import {DepositAsset} from "test/mock/DepositAsset.sol";
import {AssetVault} from "test/mock/AssetVault.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract TimeLinearLoanTest is Test {
    using stdStorage for StdStorage;
    using Math for uint256;

    DeployContractSuite internal _deployer = new DeployContractSuite();
    Whitelist internal _whitelist;
    Blacklist internal _blacklist;
    DepositAsset internal _depositToken;

    TimeLinearLoanDefs.TrustedVault[] internal _trustedVaults;
    uint64[] internal _secondInterestRates;

    address internal _owner = makeAddr("owner");
    address internal _whitelistedUser1 = makeAddr("whitelistedUser1");
    address internal _whitelistedUser2 = makeAddr("whitelistedUser2");
    address internal _blacklistedUser1 = makeAddr("blacklistedUser1");
    address internal _blacklistedUser2 = makeAddr("blacklistedUser2");

    uint64 internal _currentTime = 1759301999; // 2025-10-01 14:59:59 UTC+8

    TimeLinearLoan internal _timeLinearLoan;

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

    modifier deployTimeLinearLoan() {
        /// @dev 317097920 = 1% / (365 * 24 * 60 * 60) * 1e18
        _secondInterestRates.push(317097920);
        /// @dev 634195840 = 3% / (365 * 24 * 60 * 60) * 1e18
        _secondInterestRates.push(951293760);
        /// @dev 951293760 = 5% / (365 * 24 * 60 * 60) * 1e18
        _secondInterestRates.push(1585489599);
        /// @dev 1268382720 = 7% / (365 * 24 * 60 * 60) * 1e18
        _secondInterestRates.push(2219685439);
        /// @dev 1585489599 = 9% / (365 * 24 * 60 * 60) * 1e18
        _secondInterestRates.push(2853881279);
        /// @dev 1902596479 = 11% / (365 * 24 * 60 * 60) * 1e18
        _secondInterestRates.push(3488077118);
        /// @dev 2219703358 = 13% / (365 * 24 * 60 * 60) * 1e18
        _secondInterestRates.push(4122272958);
        /// @dev 2536810238 = 15% / (365 * 24 * 60 * 60) * 1e18
        _secondInterestRates.push(4756468798);
        /// @dev 2853881279 = 17% / (365 * 24 * 60 * 60) * 1e18
        _secondInterestRates.push(5390664637);
        /// @dev 3170979200 = 19% / (365 * 24 * 60 * 60) * 1e18
        _secondInterestRates.push(6024860477);
        /// @dev 3488077118 = 21% / (365 * 24 * 60 * 60) * 1e18
        _secondInterestRates.push(6659056317);
        /// @dev 3805183998 = 23% / (365 * 24 * 60 * 60) * 1e18
        _secondInterestRates.push(7293252156);
        /// @dev 4122272958 = 25% / (365 * 24 * 60 * 60) * 1e18
        _secondInterestRates.push(7927447996);
        /// @dev 4439379838 = 27% / (365 * 24 * 60 * 60) * 1e18
        _secondInterestRates.push(8561643836);
        /// @dev 4756468798 = 29% / (365 * 24 * 60 * 60) * 1e18
        _secondInterestRates.push(9195839675);
        /// @dev 5073575678 = 31% / (365 * 24 * 60 * 60) * 1e18
        _secondInterestRates.push(9830035515);
        /// @dev 5390664637 = 33% / (365 * 24 * 60 * 60) * 1e18
        _secondInterestRates.push(10464231355);
        /// @dev 5707771517 = 35% / (365 * 24 * 60 * 60) * 1e18
        _secondInterestRates.push(11098427194);

        _trustedVaults.push(
            TimeLinearLoanDefs.TrustedVault({
                vault: address(new AssetVault(IERC20(address(_depositToken)), "MMF@OpenTerm", "MMF@OpenTerm")),
                minimumPercentage: 10 * 10 ** 4, // 10%
                maximumPercentage: 40 * 10 ** 4 // 40%
            })
        );

        _trustedVaults.push(
            TimeLinearLoanDefs.TrustedVault({
                vault: address(new AssetVault(IERC20(address(_depositToken)), "RWA@OpenTerm", "RWA@OpenTerm")),
                minimumPercentage: 30 * 10 ** 4, // 30%
                maximumPercentage: 60 * 10 ** 4 // 60%
            })
        );

        _trustedVaults.push(
            TimeLinearLoanDefs.TrustedVault({
                vault: address(new AssetVault(IERC20(address(_depositToken)), "MMF@FixedTerm", "MMF@FixedTerm")),
                minimumPercentage: 50 * 10 ** 4, // 50%
                maximumPercentage: 80 * 10 ** 4 // 80%
            })
        );

        _trustedVaults.push(
            TimeLinearLoanDefs.TrustedVault({
                vault: address(new AssetVault(IERC20(address(_depositToken)), "RWA@FixedTerm", "RWA@FixedTerm")),
                minimumPercentage: 70 * 10 ** 4, // 70%
                maximumPercentage: 100 * 10 ** 4 // 100%
            })
        );

        vm.startPrank(_owner);

        _timeLinearLoan = TimeLinearLoan(
            _deployer.deployTimeLinearLoan(
                [_owner, address(_whitelist), address(_blacklist), address(_depositToken)],
                _secondInterestRates,
                _trustedVaults
            )
        );

        _timeLinearLoan.grantRole(Roles.OPERATOR_ROLE, _owner);

        vm.stopPrank();

        vm.label(address(_timeLinearLoan), "TimeLinearLoan");
        vm.label(_trustedVaults[0].vault, "MMF@OpenTerm");
        vm.label(_trustedVaults[1].vault, "RWA@OpenTerm");
        vm.label(_trustedVaults[2].vault, "MMF@FixedTerm");
        vm.label(_trustedVaults[3].vault, "RWA@FixedTerm");

        _;
    }

    modifier setDependencies() {
        vm.startPrank(_owner);

        _whitelist.grantRole(Roles.OPERATOR_ROLE, address(_timeLinearLoan));
        _blacklist.grantRole(Roles.OPERATOR_ROLE, address(_timeLinearLoan));

        vm.stopPrank();

        _;
    }

    function setUp()
        public
        timeBegin
        deployWhitelist
        deployBlacklist
        deployDepositToken
        deployTimeLinearLoan
        setDependencies
        oneDayPassed
    {
        vm.label(_owner, "owner");
    }

    function testNull() public pure {
        assertTrue(true);
    }

    function testJoin() public {
        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.TrustedBorrowerAdded(_whitelistedUser1, 0);
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.TrustedBorrowerAdded(_whitelistedUser2, 1);
        vm.prank(_whitelistedUser2);
        _timeLinearLoan.join();

        (address borrower1,,) = _timeLinearLoan._trustedBorrowers(0);
        (address borrower2,,) = _timeLinearLoan._trustedBorrowers(1);

        assertEq(borrower1, _whitelistedUser1);
        assertEq(borrower2, _whitelistedUser2);
    }

    function testDuplicateBorrowerJoin() public {
        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.TrustedBorrowerAdded(_whitelistedUser1, 0);
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.BorrowerAlreadyExists.selector, _whitelistedUser1, 0));
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();
    }

    function testNotWhitelistedBorrowerJoin() public {
        address someone = makeAddr("someone");
        vm.expectRevert(abi.encodeWithSelector(IWhitelist.NotWhitelisted.selector, someone));
        vm.prank(someone);
        _timeLinearLoan.join();

        address zeroAddr = address(0x00);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "borrower"));
        vm.prank(zeroAddr);
        _timeLinearLoan.join();
    }

    function testBlacklistedBorrowerJoin() public {
        vm.expectRevert(abi.encodeWithSelector(IBlacklist.Blacklisted.selector, _blacklistedUser1));
        vm.prank(_blacklistedUser1);
        _timeLinearLoan.join();

        address zeroAddr = address(0x00);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "borrower"));
        vm.prank(zeroAddr);
        _timeLinearLoan.join();
    }

    function testAgree() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.join();

        vm.startPrank(_owner);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.AgreeJoinRequest(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.AgreeJoinRequest(_whitelistedUser2, 2_000_000 * 10 ** 6);
        _timeLinearLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.stopPrank();
    }

    function testNotOperatorAgree() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        address someone = makeAddr("someone");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, someone, Roles.OPERATOR_ROLE
            )
        );
        vm.prank(someone);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
    }

    function testDuplicateAgree() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.startPrank(_owner);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.AgreeJoinRequest(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.expectRevert(
            abi.encodeWithSelector(TimeLinearLoanDefs.UpdateCeilingLimitDirectly.selector, _whitelistedUser1)
        );
        _timeLinearLoan.agree(_whitelistedUser1, 2_000_000 * 10 ** 6);

        vm.stopPrank();
    }

    function testAgreeNotWhitelistedBorrower() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _whitelist.remove(_whitelistedUser1);

        vm.startPrank(_owner);

        vm.expectRevert(abi.encodeWithSelector(IWhitelist.NotWhitelisted.selector, _whitelistedUser1));
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.stopPrank();
    }

    function testAgreeBlacklistedBorrower() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _blacklist.add(_whitelistedUser1);

        vm.startPrank(_owner);

        vm.expectRevert(abi.encodeWithSelector(IBlacklist.Blacklisted.selector, _whitelistedUser1));
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.stopPrank();
    }

    function testAgreeNotTrustedBorrower() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.join();

        vm.startPrank(_owner);

        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        _timeLinearLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        address someone = makeAddr("someone");
        _whitelist.add(someone);
        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotTrustedBorrower.selector, someone));
        _timeLinearLoan.agree(someone, 3_000_000 * 10 ** 6);

        vm.stopPrank();
    }

    function testAgreeZeroCeilingLimit() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.startPrank(_owner);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimeLinearLoanDefs.AgreeJoinRequestShouldHaveNonZeroCeilingLimit.selector, _whitelistedUser1
            )
        );
        _timeLinearLoan.agree(_whitelistedUser1, 0);

        vm.stopPrank();
    }

    function testRequest() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.join();

        vm.startPrank(_owner);

        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timeLinearLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.stopPrank();

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.ReceiveLoanRequest(_whitelistedUser1, 0, 500_000 * 10 ** 6);
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.ReceiveLoanRequest(_whitelistedUser2, 1, 1_500_000 * 10 ** 6);
        vm.prank(_whitelistedUser2);
        _timeLinearLoan.request(1_500_000 * 10 ** 6);
    }

    function testBlacklistedBorrowerRequest() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.startPrank(_owner);

        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        _blacklist.add(_whitelistedUser1);

        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IBlacklist.Blacklisted.selector, _whitelistedUser1));
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);
    }

    function testNotWhitelistedBorrowerRequest() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.startPrank(_owner);

        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        _whitelist.remove(_whitelistedUser1);

        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IWhitelist.NotWhitelisted.selector, _whitelistedUser1));
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);
    }

    function testNotTrustedBorrowerRequest() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.join();

        vm.startPrank(_owner);

        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timeLinearLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.request(1_500_000 * 10 ** 6);

        address someone = makeAddr("someone");
        vm.prank(_owner);
        _whitelist.add(someone);

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotTrustedBorrower.selector, someone));
        vm.prank(someone);
        _timeLinearLoan.request(300_000 * 10 ** 6);
    }

    function testNotValidBorroweerRequest() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.join();

        vm.startPrank(_owner);

        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        uint64 borrwoerIndex = _timeLinearLoan._borrowerToIndex(_whitelistedUser2);
        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidBorrower.selector, borrwoerIndex));
        vm.prank(_whitelistedUser2);
        _timeLinearLoan.request(1_500_000 * 10 ** 6);
    }

    function testRequestOverAvailableLimit() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.join();

        vm.startPrank(_owner);

        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timeLinearLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimeLinearLoanDefs.LoanCeilingLimitExceedsBorrowerRemainingLimit.selector,
                2_500_000 * 10 ** 6,
                2_000_000 * 10 ** 6
            )
        );
        vm.prank(_whitelistedUser2);
        _timeLinearLoan.request(2_500_000 * 10 ** 6);
    }

    function testApprove() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.join();

        vm.startPrank(_owner);

        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timeLinearLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.request(1_500_000 * 10 ** 6);

        vm.startPrank(_owner);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.ApproveLoanRequest(_whitelistedUser1, 0, 500_000 * 10 ** 6, 1);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.ApproveLoanRequest(_whitelistedUser2, 1, 1_500_000 * 10 ** 6, 3);
        _timeLinearLoan.approve(1, 1_500_000 * 10 ** 6, 3);

        vm.stopPrank();
    }

    function testNotOperatorApprove() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        address someone = makeAddr("someone");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, someone, Roles.OPERATOR_ROLE
            )
        );
        vm.prank(someone);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);
    }

    function testApproveNotPendingLoan() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.join();

        vm.startPrank(_owner);

        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timeLinearLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.request(1_500_000 * 10 ** 6);

        vm.startPrank(_owner);

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidLoan.selector, 2));
        _timeLinearLoan.approve(2, 500_000 * 10 ** 6, 1);

        _timeLinearLoan.approve(1, 1_500_000 * 10 ** 6, 3);

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotPendingLoan.selector, 1));
        _timeLinearLoan.approve(1, 1_500_000 * 10 ** 6, 3);

        vm.stopPrank();
    }

    function testApproveWithNotValidInterestRate() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.join();

        vm.startPrank(_owner);

        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timeLinearLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.request(1_500_000 * 10 ** 6);

        vm.startPrank(_owner);

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidInterestRate.selector, 100));
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 100);

        stdstore.target(address(_timeLinearLoan)).sig("_secondInterestRates(uint256)").with_key(uint256(3))
            .checked_write(uint256(0));
        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidInterestRate.selector, 3));
        _timeLinearLoan.approve(1, 1_500_000 * 10 ** 6, 3);

        vm.stopPrank();
    }

    function testApproveCeilingLimitOverRequest() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.join();

        vm.startPrank(_owner);

        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timeLinearLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.request(1_500_000 * 10 ** 6);

        vm.startPrank(_owner);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.ApproveLoanRequest(_whitelistedUser1, 0, 1_000_000 * 10 ** 6, 1);
        _timeLinearLoan.approve(0, 1_000_000 * 10 ** 6, 1);
        (uint128 ceilingLimit1,,,,) = _timeLinearLoan._allLoans(0);
        assertEq(ceilingLimit1, 500_000 * 10 ** 6);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.ApproveLoanRequest(_whitelistedUser2, 1, 2_000_000 * 10 ** 6, 3);
        _timeLinearLoan.approve(1, 2_000_000 * 10 ** 6, 3);
        (uint128 ceilingLimit2,,,,) = _timeLinearLoan._allLoans(1);
        assertEq(ceilingLimit2, 1_500_000 * 10 ** 6);

        vm.stopPrank();
    }

    function testApproveCeilingLimitBelowRequest() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.join();

        vm.startPrank(_owner);

        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timeLinearLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.request(1_500_000 * 10 ** 6);

        vm.startPrank(_owner);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.ApproveLoanRequest(_whitelistedUser1, 0, 400_000 * 10 ** 6, 1);
        _timeLinearLoan.approve(0, 400_000 * 10 ** 6, 1);
        (uint128 ceilingLimit1,,,,) = _timeLinearLoan._allLoans(0);
        assertEq(ceilingLimit1, 400_000 * 10 ** 6);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.ApproveLoanRequest(_whitelistedUser2, 1, 1_000_000 * 10 ** 6, 3);
        _timeLinearLoan.approve(1, 1_000_000 * 10 ** 6, 3);
        (uint128 ceilingLimit2,,,,) = _timeLinearLoan._allLoans(1);
        assertEq(ceilingLimit2, 1_000_000 * 10 ** 6);

        vm.stopPrank();
    }

    function testBorrow() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.join();

        vm.startPrank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timeLinearLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);
        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.request(1_500_000 * 10 ** 6);

        vm.startPrank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);
        _timeLinearLoan.approve(1, 1_500_000 * 10 ** 6, 3);
        vm.stopPrank();

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.Borrowed(_whitelistedUser1, 0, 300_000 * 10 ** 6, true, 0);
        vm.prank(_whitelistedUser1);
        (bool isAllSatisfied1,) = _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);
        assertTrue(isAllSatisfied1);
        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.Borrowed(_whitelistedUser2, 1, 1_000_000 * 10 ** 6, true, 1);
        vm.prank(_whitelistedUser2);
        (bool isAllSatisfied2,) = _timeLinearLoan.borrow(1, 1_000_000 * 10 ** 6, _currentTime + 60 days);
        assertTrue(isAllSatisfied2);
    }

    function testBlacklistedBorrowerBorrow() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_owner);
        _blacklist.add(_whitelistedUser1);

        vm.expectRevert(abi.encodeWithSelector(IBlacklist.Blacklisted.selector, _whitelistedUser1));
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);
    }

    function testNotWhitelistedBorrowerBorrow() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_owner);
        _whitelist.remove(_whitelistedUser1);

        vm.expectRevert(abi.encodeWithSelector(IWhitelist.NotWhitelisted.selector, _whitelistedUser1));
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);
    }

    function testBorrowFromNotValidLoan() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidLoan.selector, 100));
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(100, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidLoan.selector, 0));
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);
    }

    function testNotLoanOwnerBorrow() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidLoan.selector, 100));
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(100, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.expectRevert(
            abi.encodeWithSelector(TimeLinearLoanDefs.NotLoanOwner.selector, 0, _whitelistedUser1, _whitelistedUser2)
        );
        vm.prank(_whitelistedUser2);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);
    }

    function testBorrowWithNotValidMaturityDate() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidLoan.selector, 100));
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(100, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimeLinearLoanDefs.MaturityTimeShouldAfterBlockTimestamp.selector,
                _currentTime - 1 minutes,
                _currentTime
            )
        );
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime - 1 minutes);
    }

    function testBorrowAmountOverLoanRemainingLimit() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidLoan.selector, 100));
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(100, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimeLinearLoanDefs.BorrowAmountOverLoanRemainingLimit.selector,
                500_000 * 10 ** 6 + 1,
                500_000 * 10 ** 6,
                0
            )
        );
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 500_000 * 10 ** 6 + 1, _currentTime + 30 days);
    }

    function testBorrowAmountNotFullSatisfied() public {
        _prepareFund(50_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.Borrowed(_whitelistedUser1, 0, 50_000 * 10 ** 6, false, 0);
        vm.prank(_whitelistedUser1);
        (bool isAllSatisfied,) = _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);
        assertFalse(isAllSatisfied);
    }

    function testRepay() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.join();

        vm.startPrank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timeLinearLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);
        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.request(1_500_000 * 10 ** 6);

        vm.startPrank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);
        _timeLinearLoan.approve(1, 1_500_000 * 10 ** 6, 3);
        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.borrow(1, 1_000_000 * 10 ** 6, _currentTime + 60 days);

        vm.warp(_currentTime + 25 days);

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), 300_000 * 10 ** 6 * 2);
        _timeLinearLoan.repay(0, 300_000 * 10 ** 6 * 2);
        vm.stopPrank();
        TimeLinearLoanDefs.DebtInfo memory debtInfo1 = _getDebtInfoAtIndex(0);
        assertEq(uint256(debtInfo1.netRemainingDebt), 0);
        assertEq(uint256(debtInfo1.netRemainingInterest), 0);
        assertEq(uint256(debtInfo1.interestBearingAmount), 0);
        assertEq(uint8(TimeLinearLoanDefs.DebtStatus.REPAID), uint8(debtInfo1.status));

        vm.warp(_currentTime + 40 days);

        vm.startPrank(_whitelistedUser2);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), 1_000_000 * 10 ** 6 * 2);
        _timeLinearLoan.repay(1, 1_000_000 * 10 ** 6 * 2);
        vm.stopPrank();
        TimeLinearLoanDefs.DebtInfo memory debtInfo2 = _getDebtInfoAtIndex(1);
        assertEq(uint256(debtInfo2.netRemainingDebt), 0);
        assertEq(uint256(debtInfo2.netRemainingInterest), 0);
        assertEq(uint256(debtInfo2.interestBearingAmount), 0);
        assertEq(uint8(TimeLinearLoanDefs.DebtStatus.REPAID), uint8(debtInfo2.status));
    }

    function testBlacklistedBorrowerRepay() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 25 days);

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), 300_000 * 10 ** 6 * 2);

        vm.prank(_owner);
        _blacklist.add(_whitelistedUser1);

        vm.expectRevert(abi.encodeWithSelector(IBlacklist.Blacklisted.selector, _whitelistedUser1));
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.repay(0, 300_000 * 10 ** 6 * 2);
    }

    function testNotWhitelistedBorrowerRepay() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 25 days);

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), 300_000 * 10 ** 6 * 2);

        vm.prank(_owner);
        _whitelist.remove(_whitelistedUser1);

        vm.expectRevert(abi.encodeWithSelector(IWhitelist.NotWhitelisted.selector, _whitelistedUser1));
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.repay(0, 300_000 * 10 ** 6 * 2);
    }

    function testRepayNotValidDebt() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 25 days);

        vm.startPrank(_whitelistedUser1);
        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidDebt.selector, 100));
        _timeLinearLoan.repay(100, 300_000 * 10 ** 6 * 2);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), 300_000 * 10 ** 6 * 2);
        _timeLinearLoan.repay(0, 300_000 * 10 ** 6 * 2);
        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidDebt.selector, 0));
        _timeLinearLoan.repay(0, 300_000 * 10 ** 6 * 2);
        vm.stopPrank();
    }

    function testNotLoanOwnerRepay() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 25 days);

        vm.expectRevert(
            abi.encodeWithSelector(TimeLinearLoanDefs.NotLoanOwner.selector, 0, _whitelistedUser1, _whitelistedUser2)
        );
        vm.prank(_whitelistedUser2);
        _timeLinearLoan.repay(0, 2 * 300_000 * 10 ** 6);

        vm.store(
            address(_timeLinearLoan),
            bytes32(0xd7b6990105719101dabeb77144f2a3385c8033acd3af97e9423a695e81ad1eb5),
            bytes32(0x0000000068de22ef000000006905afef0000000068de22ef0000000000000064)
        );

        vm.prank(_whitelistedUser1);
        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidLoan.selector, 100));
        _timeLinearLoan.repay(0, 2 * 300_000 * 10 ** 6);
    }

    function testRepayAmountBelowTotalDebtButOverInterest() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days);

        uint256 totalDebt = _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimeLinearLoanDefs.DebtInfo memory debtInfo = _getDebtInfoAtIndex(0);
        uint256 repayAmount = ((totalDebt - uint256(debtInfo.principal)) + totalDebt) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), repayAmount);
        (bool isAllRepaid, uint128 remainingDebt) = _timeLinearLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        assertFalse(isAllRepaid);
        assertEq(uint256(remainingDebt), totalDebt - repayAmount);
    }

    function testRepayAmountBelowInterest() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days);

        uint256 totalDebt = _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimeLinearLoanDefs.DebtInfo memory debtInfo = _getDebtInfoAtIndex(0);
        uint256 repayAmount = (totalDebt - uint256(debtInfo.principal)) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), repayAmount);
        (bool isAllRepaid, uint128 remainingDebt) = _timeLinearLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        assertFalse(isAllRepaid);
        assertEq(uint256(remainingDebt), totalDebt - repayAmount);
    }

    function testDefault() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimeLinearLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), repayAmount);
        (, uint128 totalDebtAfterRepay) = _timeLinearLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        assertEq(totalDebtAfterRepay, totalDebtBeforeRepay - repayAmount);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.Defaulted(_whitelistedUser1, 0, uint128(totalDebtAfterRepay), 17);
        vm.prank(_owner);
        uint128 totalDebtAfterDefaulted = _timeLinearLoan.defaulted(_whitelistedUser1, 0, 17);

        /// @dev Verify that after defaulting, the total debt increases due to penalty interest
        assertLt(_abs(totalDebtAfterRepay, totalDebtAfterDefaulted), 8);
    }

    function testNotOperatorDefault() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimeLinearLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), repayAmount);
        _timeLinearLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        address someone = makeAddr("someone");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, someone, Roles.OPERATOR_ROLE
            )
        );
        vm.prank(someone);
        _timeLinearLoan.defaulted(_whitelistedUser1, 0, 17);
    }

    function testDefaultNotMaturedDebt() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days - 1 seconds);

        uint256 totalDebtBeforeRepay = _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimeLinearLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), repayAmount);
        _timeLinearLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidDebt.selector, 100));
        vm.prank(_owner);
        _timeLinearLoan.defaulted(_whitelistedUser1, 100, 17);

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotMaturedDebt.selector, 0));
        vm.prank(_owner);
        _timeLinearLoan.defaulted(_whitelistedUser1, 0, 17);
    }

    function testDefaultWithNotValidInterestRate() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimeLinearLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), repayAmount);
        _timeLinearLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidInterestRate.selector, 100));
        vm.prank(_owner);
        _timeLinearLoan.defaulted(_whitelistedUser1, 0, 100);

        stdstore.target(address(_timeLinearLoan)).sig("_secondInterestRates(uint256)").with_key(17).checked_write(
            uint256(0)
        );
        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidInterestRate.selector, 17));
        vm.prank(_owner);
        _timeLinearLoan.defaulted(_whitelistedUser1, 0, 17);
    }

    function testDefaultDebtForNotLoanOwner() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimeLinearLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), repayAmount);
        _timeLinearLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(TimeLinearLoanDefs.NotLoanOwner.selector, 0, _whitelistedUser1, _whitelistedUser2)
        );
        vm.prank(_owner);
        _timeLinearLoan.defaulted(_whitelistedUser2, 0, 17);

        vm.store(
            address(_timeLinearLoan),
            bytes32(0xd7b6990105719101dabeb77144f2a3385c8033acd3af97e9423a695e81ad1eb5),
            bytes32(0x0000000068de22ef000000006905afef0000000068de22ef0000000000000064)
        );

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidLoan.selector, 100));
        vm.prank(_owner);
        _timeLinearLoan.defaulted(_whitelistedUser1, 0, 17);
    }

    function testDefaultDebtWithUnchangedInterestRate() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimeLinearLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), repayAmount);
        _timeLinearLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        uint256 totalDebtAfterRepay = _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser1);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.Defaulted(_whitelistedUser1, 0, uint128(totalDebtAfterRepay), 1);
        vm.prank(_owner);
        _timeLinearLoan.defaulted(_whitelistedUser1, 0, 1);
    }

    function testRecovery() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimeLinearLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), repayAmount);
        _timeLinearLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.prank(_owner);
        uint128 remainingDebt = _timeLinearLoan.defaulted(_whitelistedUser1, 0, 17);

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), remainingDebt);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.Recovery(_whitelistedUser1, 0, remainingDebt, 0);
        vm.prank(_owner);
        _timeLinearLoan.recovery(_whitelistedUser1, 0, remainingDebt);
    }

    function testNotOperatorRecovery() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimeLinearLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), repayAmount);
        _timeLinearLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.prank(_owner);
        uint128 remainingDebt = _timeLinearLoan.defaulted(_whitelistedUser1, 0, 17);

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), remainingDebt);

        address someone = makeAddr("someone");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, someone, Roles.OPERATOR_ROLE
            )
        );
        vm.prank(someone);
        _timeLinearLoan.recovery(_whitelistedUser1, 0, remainingDebt);
    }

    function testRecoveryNotDefaultedDebt() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days - 1 seconds);

        uint256 totalDebtBeforeRepay = _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimeLinearLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), repayAmount);
        (, uint128 remainingDebt) = _timeLinearLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), remainingDebt);

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidDebt.selector, 100));
        vm.prank(_owner);
        _timeLinearLoan.recovery(_whitelistedUser1, 100, remainingDebt);

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotDefaultedDebt.selector, 0));
        vm.prank(_owner);
        _timeLinearLoan.recovery(_whitelistedUser1, 0, remainingDebt);
    }

    function testRecoveryDebtForNotLoanOwner() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimeLinearLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), repayAmount);
        _timeLinearLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.prank(_owner);
        uint128 remainingDebt = _timeLinearLoan.defaulted(_whitelistedUser1, 0, 17);

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), remainingDebt);

        vm.expectRevert(
            abi.encodeWithSelector(TimeLinearLoanDefs.NotLoanOwner.selector, 0, _whitelistedUser1, _whitelistedUser2)
        );
        vm.prank(_owner);
        _timeLinearLoan.recovery(_whitelistedUser2, 0, remainingDebt);

        vm.store(
            address(_timeLinearLoan),
            bytes32(0xd7b6990105719101dabeb77144f2a3385c8033acd3af97e9423a695e81ad1eb5),
            bytes32(0x0000000068de22ef000000006905afef0000000068de22ef0000000000000064)
        );

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidLoan.selector, 100));
        vm.prank(_owner);
        _timeLinearLoan.recovery(_whitelistedUser1, 0, remainingDebt);
    }

    function testRecoveryPartialDebt() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimeLinearLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), repayAmount);
        _timeLinearLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.prank(_owner);
        uint128 remainingDebt = _timeLinearLoan.defaulted(_whitelistedUser1, 0, 17);
        uint128 recoveryAmount = remainingDebt / 2;

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), recoveryAmount);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.Recovery(_whitelistedUser1, 0, recoveryAmount, remainingDebt - recoveryAmount);
        vm.prank(_owner);
        _timeLinearLoan.recovery(_whitelistedUser1, 0, recoveryAmount);
    }

    function testClose() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimeLinearLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), repayAmount);
        _timeLinearLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.prank(_owner);
        uint128 remainingDebtAtDefaulted = _timeLinearLoan.defaulted(_whitelistedUser1, 0, 17);

        vm.warp(_currentTime + 40 days);

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), remainingDebtAtDefaulted);

        vm.prank(_owner);
        (, uint128 remainingDebtAtRecovery) = _timeLinearLoan.recovery(_whitelistedUser1, 0, remainingDebtAtDefaulted);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        /// @dev precision loss in interest calculations with dividing
        emit TimeLinearLoanDefs.Closed(_whitelistedUser1, 0, remainingDebtAtRecovery);
        vm.prank(_owner);
        _timeLinearLoan.close(_whitelistedUser1, 0);
    }

    function testNotOperatorClose() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimeLinearLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), repayAmount);
        _timeLinearLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.prank(_owner);
        uint128 remainingDebtAtDefaulted = _timeLinearLoan.defaulted(_whitelistedUser1, 0, 17);

        vm.warp(_currentTime + 40 days);

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), remainingDebtAtDefaulted);

        vm.prank(_owner);
        _timeLinearLoan.recovery(_whitelistedUser1, 0, remainingDebtAtDefaulted);

        address someone = makeAddr("someone");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, someone, Roles.OPERATOR_ROLE
            )
        );
        vm.prank(someone);
        _timeLinearLoan.close(_whitelistedUser1, 0);
    }

    function testCloseNotDefaultedDebt() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days - 1 seconds);

        uint256 totalDebtBeforeRepay = _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimeLinearLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), repayAmount);
        _timeLinearLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidDebt.selector, 100));
        vm.prank(_owner);
        _timeLinearLoan.close(_whitelistedUser1, 100);

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotDefaultedDebt.selector, 0));
        vm.prank(_owner);
        _timeLinearLoan.close(_whitelistedUser1, 0);
    }

    function testCloseDebtForNotLoanOwner() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimeLinearLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), repayAmount);
        _timeLinearLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        vm.prank(_owner);
        uint128 remainingDebtAtDefaulted = _timeLinearLoan.defaulted(_whitelistedUser1, 0, 17);

        vm.warp(_currentTime + 40 days);

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), remainingDebtAtDefaulted);

        vm.prank(_owner);
        _timeLinearLoan.recovery(_whitelistedUser1, 0, remainingDebtAtDefaulted);

        vm.expectRevert(
            abi.encodeWithSelector(TimeLinearLoanDefs.NotLoanOwner.selector, 0, _whitelistedUser1, _whitelistedUser2)
        );
        vm.prank(_owner);
        _timeLinearLoan.close(_whitelistedUser2, 0);

        vm.store(
            address(_timeLinearLoan),
            bytes32(0xd7b6990105719101dabeb77144f2a3385c8033acd3af97e9423a695e81ad1eb5),
            bytes32(0x0000000068de22ef000000006905afef0000000068de22ef0000000000000064)
        );

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidLoan.selector, 100));
        vm.prank(_owner);
        _timeLinearLoan.close(_whitelistedUser1, 0);
    }

    function testAddWhitelist() public {
        address someone = makeAddr("someone");
        vm.prank(_owner);
        _timeLinearLoan.addWhitelist(someone);
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
        _timeLinearLoan.addWhitelist(someone);
    }

    function testRemoveWhitelist() public {
        vm.prank(_owner);
        _timeLinearLoan.removeWhitelist(_whitelistedUser1);
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
        _timeLinearLoan.removeWhitelist(someone);
    }

    function testAddBlacklist() public {
        address someone = makeAddr("someone");
        vm.prank(_owner);
        _timeLinearLoan.addBlacklist(someone);
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
        _timeLinearLoan.addBlacklist(someone);
    }

    function testRemoveBlacklist() public {
        vm.prank(_owner);
        _timeLinearLoan.removeBlacklist(_blacklistedUser1);
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
        _timeLinearLoan.removeBlacklist(someone);
    }

    function testUpdateBorrowerLimit() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.join();

        vm.startPrank(_owner);

        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        _timeLinearLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.BorrowerCeilingLimitUpdated(1_000_000 * 10 ** 6, 1_500_000 * 10 ** 6);
        _timeLinearLoan.updateBorrowerLimit(_whitelistedUser1, 1_500_000 * 10 ** 6);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.BorrowerCeilingLimitUpdated(2_000_000 * 10 ** 6, 2_500_000 * 10 ** 6);
        _timeLinearLoan.updateBorrowerLimit(_whitelistedUser2, 2_500_000 * 10 ** 6);

        vm.stopPrank();
    }

    function testNotOperatorUpdateBorrowerLimit() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        address someone = makeAddr("someone");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, someone, Roles.OPERATOR_ROLE
            )
        );
        vm.prank(someone);
        _timeLinearLoan.updateBorrowerLimit(_whitelistedUser1, 1_500_000 * 10 ** 6);
    }

    function testUpdateNotWhitelistedBorrowerLimit() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_owner);
        _whitelist.remove(_whitelistedUser1);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSelector(IWhitelist.NotWhitelisted.selector, _whitelistedUser1));
        _timeLinearLoan.updateBorrowerLimit(_whitelistedUser1, 1_500_000 * 10 ** 6);
    }

    function testUpdateBlacklistedBorrowerLimit() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_owner);
        _blacklist.add(_whitelistedUser1);

        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSelector(IBlacklist.Blacklisted.selector, _whitelistedUser1));
        _timeLinearLoan.updateBorrowerLimit(_whitelistedUser1, 1_500_000 * 10 ** 6);
    }

    function testUpdateNotTrustedBorrowerLimit() public {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.join();

        vm.startPrank(_owner);

        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        _timeLinearLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        address someone = makeAddr("someone");
        _whitelist.add(someone);
        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotTrustedBorrower.selector, someone));
        _timeLinearLoan.updateBorrowerLimit(someone, 3_000_000 * 10 ** 6);

        vm.stopPrank();
    }

    function testUpdateBorrowerLimitBelowRemainingLimit() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.store(
            address(_timeLinearLoan),
            bytes32(0x1b6847dc741a1b0cd08d278845f9d819d87b734759afb55fe2de5cb82a9ae673),
            bytes32(0x0000000000000000000000746a5288000000000000000000000000746a5287ff)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                TimeLinearLoanDefs.CeilingLimitBelowRemainingLimit.selector, 500_000 * 10 ** 6 - 1, 500_000 * 10 ** 6
            )
        );
        vm.prank(_owner);
        _timeLinearLoan.updateBorrowerLimit(_whitelistedUser1, 1_500_000 * 10 ** 6);
    }

    function testUpdateBorrowerLimitBelowUsedLimit() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimeLinearLoanDefs.CeilingLimitBelowUsedLimit.selector, 500_000 * 10 ** 6 - 1, 500_000 * 10 ** 6
            )
        );
        vm.prank(_owner);
        _timeLinearLoan.updateBorrowerLimit(_whitelistedUser1, 500_000 * 10 ** 6 - 1);
    }

    function testUpdateLoanLimit() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.LoanCeilingLimitUpdated(800_000 * 10 ** 6, 500_000 * 10 ** 6);
        vm.prank(_owner);
        _timeLinearLoan.updateLoanLimit(0, 800_000 * 10 ** 6);
    }

    function testNotOperatorUpdateLoanLimit() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        address someone = makeAddr("someone");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, makeAddr("someone"), Roles.OPERATOR_ROLE
            )
        );
        vm.prank(someone);
        _timeLinearLoan.updateLoanLimit(0, 800_000 * 10 ** 6);
    }

    function testUpdateNotValidLoanLimit() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidLoan.selector, 100));
        vm.prank(_owner);
        _timeLinearLoan.updateLoanLimit(100, 800_000 * 10 ** 6);

        vm.store(
            address(_timeLinearLoan),
            0xdf6966c971051c3d54ec59162606531493a51404a002842f56009d7e5cf4a8c8,
            0x0000000000000000000000000000000300000000000000000000000000000001
        );

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidLoan.selector, 0));
        vm.prank(_owner);
        _timeLinearLoan.updateLoanLimit(0, 800_000 * 10 ** 6);
    }

    function testUpdateNotTrustedBorrowerLoanLimit() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.request(1_500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_owner);
        _timeLinearLoan.approve(1, 1_500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.borrow(1, 1_500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        address someone = makeAddr("someone");
        /// @dev modify loan 0's borrower to `someone`
        vm.store(
            address(_timeLinearLoan),
            bytes32(0x1b6847dc741a1b0cd08d278845f9d819d87b734759afb55fe2de5cb82a9ae672),
            bytes32(uint256(uint160(someone)))
        );
        /// @dev modify 'someone' borrower index to 1
        stdstore.target(address(_timeLinearLoan)).sig("_borrowerToIndex(address)").with_key(someone).checked_write(
            uint256(1)
        );
        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotTrustedBorrower.selector, someone));
        vm.prank(_owner);
        _timeLinearLoan.updateLoanLimit(0, 800_000 * 10 ** 6);
    }

    function testUpdateLoanLimitBelowRemainingLimit() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(1_000_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 1_000_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        vm.store(
            address(_timeLinearLoan),
            bytes32(0xdf6966c971051c3d54ec59162606531493a51404a002842f56009d7e5cf4a8c7),
            bytes32(0x0000000000000000000000746a5288000000000000000000000000746a5287ff)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                TimeLinearLoanDefs.CeilingLimitBelowRemainingLimit.selector, 500_000 * 10 ** 6 - 1, 500_000 * 10 ** 6
            )
        );
        vm.prank(_owner);
        _timeLinearLoan.updateLoanLimit(0, 800_000 * 10 ** 6);
    }

    function testUpdateLoanLimitBelowUsedLimit() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(1_000_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 1_000_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimeLinearLoanDefs.CeilingLimitBelowUsedLimit.selector, 500_000 * 10 ** 6 - 1, 500_000 * 10 ** 6
            )
        );
        vm.prank(_owner);
        _timeLinearLoan.updateLoanLimit(0, 500_000 * 10 ** 6 - 1);
    }

    function testUpdateLoanLimitExceedBorrowerRemainingLimit() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimeLinearLoanDefs.LoanCeilingLimitExceedsBorrowerRemainingLimit.selector,
                1_000_000 * 10 ** 6 + 1,
                500_000 * 10 ** 6
            )
        );
        vm.prank(_owner);
        _timeLinearLoan.updateLoanLimit(0, 1_000_000 * 10 ** 6 + 1);
    }

    function testUpdateLoanInterestRate() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.LoanInterestRateUpdated(0, 1, 17);
        vm.prank(_owner);
        _timeLinearLoan.updateLoanInterestRate(0, 17);
    }

    function testNotOperatorUpdateLoanInterestRate() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        address someone = makeAddr("someone");
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, makeAddr("someone"), Roles.OPERATOR_ROLE
            )
        );
        vm.prank(someone);
        _timeLinearLoan.updateLoanInterestRate(0, 17);
    }

    function testUpdateNotValidLoanInterestRate() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidLoan.selector, 100));
        vm.prank(_owner);
        _timeLinearLoan.updateLoanInterestRate(100, 17);

        vm.store(
            address(_timeLinearLoan),
            0xdf6966c971051c3d54ec59162606531493a51404a002842f56009d7e5cf4a8c8,
            0x0000000000000000000000000000000300000000000000000000000000000001
        );

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidLoan.selector, 0));
        vm.prank(_owner);
        _timeLinearLoan.updateLoanInterestRate(0, 17);
    }

    function testUpdateLoanNotValidInterestRate() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidInterestRate.selector, 100));
        vm.prank(_owner);
        _timeLinearLoan.updateLoanInterestRate(0, 100);

        stdstore.target(address(_timeLinearLoan)).sig("_secondInterestRates(uint256)").with_key(uint256(17))
            .checked_write(uint256(0));
        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidInterestRate.selector, 17));
        vm.prank(_owner);
        _timeLinearLoan.updateLoanInterestRate(0, 17);
    }

    function testUpdateLoanInterestRateForNotTrustedBorrower() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.request(1_500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_owner);
        _timeLinearLoan.approve(1, 1_500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.borrow(1, 1_500_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 15 days);

        address someone = makeAddr("someone");
        /// @dev modify loan 0's borrower to `someone`
        vm.store(
            address(_timeLinearLoan),
            bytes32(0x1b6847dc741a1b0cd08d278845f9d819d87b734759afb55fe2de5cb82a9ae672),
            bytes32(uint256(uint160(someone)))
        );
        /// @dev modify 'someone' borrower index to 1
        stdstore.target(address(_timeLinearLoan)).sig("_borrowerToIndex(address)").with_key(someone).checked_write(
            uint256(1)
        );
        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotTrustedBorrower.selector, someone));
        vm.prank(_owner);
        _timeLinearLoan.updateLoanInterestRate(0, 17);
    }

    function testUpdateLoanInterestRateAfterDefault() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.warp(_currentTime + 30 days + 1 seconds);

        uint256 totalDebtBeforeRepay = _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser1);
        TimeLinearLoanDefs.DebtInfo memory debtInfoBeforeRepay = _getDebtInfoAtIndex(0);
        uint256 repayAmount =
            ((totalDebtBeforeRepay - uint256(debtInfoBeforeRepay.principal)) + totalDebtBeforeRepay) / 2;

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), repayAmount);
        (, uint128 totalDebtAfterRepay) = _timeLinearLoan.repay(0, uint128(repayAmount));
        vm.stopPrank();

        /// @dev Verify that after repayment, the total debt is reduced by the repay amount
        assertEq(totalDebtAfterRepay, totalDebtBeforeRepay - repayAmount);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.Defaulted(_whitelistedUser1, 0, uint128(totalDebtAfterRepay), 10);
        vm.prank(_owner);
        uint128 totalDebtAfterDefaulted = _timeLinearLoan.defaulted(_whitelistedUser1, 0, 10);

        /// @dev Verify that after defaulting, the total debt increases due to penalty interest
        assertEq(totalDebtAfterRepay, totalDebtAfterDefaulted);

        vm.warp(_currentTime + 50 days);
        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.LoanInterestRateUpdated(0, 10, 17);
        vm.prank(_owner);
        _timeLinearLoan.updateLoanInterestRate(0, 17);
    }

    function testUpdateTrustedVaults() public {
        TimeLinearLoanDefs.TrustedVault memory newTrustedVault = TimeLinearLoanDefs.TrustedVault({
            vault: address(new AssetVault(IERC20(address(_depositToken)), "MMF@OpenTerm", "MMF@OpenTerm")),
            minimumPercentage: 10 * 10 ** 4, // 10%
            maximumPercentage: 40 * 10 ** 4 // 40%
        });

        TimeLinearLoanDefs.TrustedVault memory tempTrustedVault;

        tempTrustedVault = TimeLinearLoanDefs.TrustedVault({
            vault: newTrustedVault.vault,
            minimumPercentage: newTrustedVault.minimumPercentage, // 10%
            maximumPercentage: newTrustedVault.maximumPercentage // 40%
        });
        tempTrustedVault.vault = address(0x00);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "trusted vault address"));
        vm.prank(_owner);
        _timeLinearLoan.updateTrustedVaults(tempTrustedVault, 1);

        tempTrustedVault = TimeLinearLoanDefs.TrustedVault({
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
        _timeLinearLoan.updateTrustedVaults(tempTrustedVault, 1);

        tempTrustedVault = TimeLinearLoanDefs.TrustedVault({
            vault: newTrustedVault.vault,
            minimumPercentage: newTrustedVault.minimumPercentage, // 10%
            maximumPercentage: newTrustedVault.maximumPercentage // 40%
        });
        tempTrustedVault.minimumPercentage = tempTrustedVault.maximumPercentage + 1;
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "trusted vault percentage"));
        vm.prank(_owner);
        _timeLinearLoan.updateTrustedVaults(tempTrustedVault, 1);

        tempTrustedVault = TimeLinearLoanDefs.TrustedVault({
            vault: newTrustedVault.vault,
            minimumPercentage: newTrustedVault.minimumPercentage, // 10%
            maximumPercentage: newTrustedVault.maximumPercentage // 40%
        });
        tempTrustedVault.maximumPercentage = 1_000_000 + 1;
        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidValue.selector, "trusted vault maximum percentage exceeds 100%")
        );
        vm.prank(_owner);
        _timeLinearLoan.updateTrustedVaults(tempTrustedVault, 1);

        (tempTrustedVault.vault, tempTrustedVault.minimumPercentage, tempTrustedVault.maximumPercentage) =
            _timeLinearLoan._trustedVaults(1);
        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.TrustedVaultUpdated(
            tempTrustedVault.vault,
            tempTrustedVault.minimumPercentage,
            tempTrustedVault.maximumPercentage,
            newTrustedVault.vault,
            newTrustedVault.minimumPercentage,
            newTrustedVault.maximumPercentage,
            1
        );
        vm.prank(_owner);
        assertTrue(_timeLinearLoan.updateTrustedVaults(newTrustedVault, 1));
    }

    function testNotOperatorUpdateTrustedVaults() public {
        TimeLinearLoanDefs.TrustedVault memory newTrustedVault = TimeLinearLoanDefs.TrustedVault({
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
        _timeLinearLoan.updateTrustedVaults(newTrustedVault, 100);
    }

    function testUpdateTrustedVaultsWhenVaultsNotExist() public {
        TimeLinearLoanDefs.TrustedVault memory newTrustedVault = TimeLinearLoanDefs.TrustedVault({
            vault: address(new AssetVault(IERC20(address(_depositToken)), "MMF@OpenTerm", "MMF@OpenTerm")),
            minimumPercentage: 10 * 10 ** 4, // 10%
            maximumPercentage: 40 * 10 ** 4 // 40%
        });

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.TrustedVaultAdded(
            newTrustedVault.vault, newTrustedVault.minimumPercentage, newTrustedVault.maximumPercentage, 4
        );
        vm.prank(_owner);
        assertFalse(_timeLinearLoan.updateTrustedVaults(newTrustedVault, 100));
    }

    function testTotalDebtOfBorrower() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));
        _prepareDebt();

        vm.warp(_currentTime + 30 days);

        uint256 totalDebtOfWhitelistedUser1 = _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser1);
        uint256 totalDebtOfWhitelistedUser2 = _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser2);
        assertGt(totalDebtOfWhitelistedUser1, 0);
        assertGt(totalDebtOfWhitelistedUser2, 0);
        assertLt(totalDebtOfWhitelistedUser1, totalDebtOfWhitelistedUser2);
    }

    function testTotalDebtOfNotTrustedBorrower() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));
        _prepareDebt();

        vm.warp(_currentTime + 30 days);

        address someone = makeAddr("someone");
        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotTrustedBorrower.selector, someone));
        _timeLinearLoan.totalDebtOfBorrower(someone);
    }

    function testTotalDebtOfVault() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));
        _prepareDebt();

        vm.warp(_currentTime + 30 days);

        uint256 totalDebtOfVault;

        for (uint256 i = 0; i < _trustedVaults.length; i++) {
            totalDebtOfVault += _timeLinearLoan.totalDebtOfVault(_trustedVaults[i].vault);
        }

        uint256 totalDebtOfBorrower;

        totalDebtOfBorrower += _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser1);
        totalDebtOfBorrower += _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser2);

        assertLt(_abs(totalDebtOfVault, totalDebtOfBorrower), 8);
    }

    function testTotalDebtOfNotTrustedVault() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));
        _prepareDebt();

        vm.warp(_currentTime + 30 days);

        address mockVault = makeAddr("mockVault");
        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotTrustedVault.selector, mockVault));
        _timeLinearLoan.totalDebtOfVault(mockVault);
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
        _timeLinearLoan.join();

        vm.prank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, maxBorrowFund);

        vm.prank(_whitelistedUser1);
        uint64 loanIndex = _timeLinearLoan.request(maxBorrowFund);

        vm.prank(_owner);
        _timeLinearLoan.approve(loanIndex, maxBorrowFund, interestRateIndex_);

        vm.prank(_whitelistedUser1);
        (, uint64 debtIndex) =
            _timeLinearLoan.borrow(loanIndex, borrowAmount_, uint64(_currentTime + uint256(borrowDays_) * 1 days));

        vm.warp(_currentTime + uint256(borrowDays_) * 1 days / 2);

        uint256 totalDebtBeforeRepay = _timeLinearLoan.totalDebtOfBorrower(_whitelistedUser1);
        assertGt(totalDebtBeforeRepay, borrowAmount_);

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), repayAmount_);

        vm.prank(_whitelistedUser1);
        (bool isAllRepaid, uint128 remainingDebt) = _timeLinearLoan.repay(debtIndex, repayAmount_);

        if (isAllRepaid) {
            assertEq(remainingDebt, 0);
        } else {
            assertLt(_abs(uint256(remainingDebt), totalDebtBeforeRepay - uint256(repayAmount_)), 10);
        }
    }

    function testOnlyInitialized() public {
        MockTimeLinearLoan mockTimeLinearLoan = new MockTimeLinearLoan();

        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "whitelist"));
        mockTimeLinearLoan.mockOnlyInitialized();

        stdstore.target(address(mockTimeLinearLoan)).sig("_whitelist()").checked_write(address(_whitelist));

        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "blacklist"));
        mockTimeLinearLoan.mockOnlyInitialized();

        stdstore.target(address(mockTimeLinearLoan)).sig("_blacklist()").checked_write(address(_blacklist));

        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "loanToken"));
        mockTimeLinearLoan.mockOnlyInitialized();

        stdstore.target(address(mockTimeLinearLoan)).sig("_loanToken()").checked_write(address(_depositToken));

        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "secondInterestRates"));
        mockTimeLinearLoan.mockOnlyInitialized();

        vm.store(
            address(mockTimeLinearLoan),
            0x0000000000000000000000000000000000000000000000000000000000000011,
            0x0000000000000000000000000000000000000000000000000de0b6b3ba327400
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.Uninitialized.selector, "trustedVaults"));
        mockTimeLinearLoan.mockOnlyInitialized();
    }

    function testOnlyWhitelisted() public {
        MockTimeLinearLoan mockTimeLinearLoan = new MockTimeLinearLoan();

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "whitelist"));
        vm.prank(address(0x01));
        mockTimeLinearLoan.mockOnlyWhitelisted();

        stdstore.target(address(mockTimeLinearLoan)).sig("_whitelist()").checked_write(address(_whitelist));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "borrower"));
        vm.prank(address(0x00));
        mockTimeLinearLoan.mockOnlyWhitelisted();
    }

    function testOnlyNotBlacklisted() public {
        MockTimeLinearLoan mockTimeLinearLoan = new MockTimeLinearLoan();

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "blacklist"));
        vm.prank(address(0x01));
        mockTimeLinearLoan.mockOnlyNotBlacklisted();

        stdstore.target(address(mockTimeLinearLoan)).sig("_blacklist()").checked_write(address(_blacklist));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "borrower"));
        vm.prank(address(0x00));
        mockTimeLinearLoan.mockOnlyNotBlacklisted();
    }

    function testOnlyTrustedBorrower() public {
        MockTimeLinearLoan mockTimeLinearLoan = new MockTimeLinearLoan();

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "borrower"));
        vm.prank(address(0x00));
        mockTimeLinearLoan.mockOnlyTrustedBorrower();
    }

    function testOnlyTrustedVault() public {
        MockTimeLinearLoan mockTimeLinearLoan = new MockTimeLinearLoan();

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "vault"));
        vm.prank(address(0x00));
        mockTimeLinearLoan.mockOnlyTrustedVault();
    }

    function testOnlyValidTranche() public {
        MockTimeLinearLoan mockTimeLinearLoan = new MockTimeLinearLoan();

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidTranche.selector, 0));
        mockTimeLinearLoan.mockOnlyValidTranche(0);
    }

    function testOnlyValidVault() public {
        MockTimeLinearLoan mockTimeLinearLoan = MockTimeLinearLoan(
            address(
                new TransparentUpgradeableProxy(
                    address(new MockTimeLinearLoan()),
                    _owner,
                    abi.encodeWithSelector(
                        TimeLinearLoan.initialize.selector,
                        [_owner, address(_whitelist), address(_blacklist), address(_depositToken)],
                        _secondInterestRates,
                        _trustedVaults
                    )
                )
            )
        );

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidVault.selector, 4));
        mockTimeLinearLoan.mockOnlyValidVault(4);

        vm.store(
            address(mockTimeLinearLoan),
            0x8d1108e10bcb7c27dddfc02ed9d693a074039d026cf4ea4240b40f7d581ac802,
            0x000000061a800000000186a00000000000000000000000000000000000000000
        );

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidVault.selector, 0));
        mockTimeLinearLoan.mockOnlyValidVault(0);

        vm.store(
            address(mockTimeLinearLoan),
            0x8d1108e10bcb7c27dddfc02ed9d693a074039d026cf4ea4240b40f7d581ac802,
            0x000000000000000000000000f62849f9a0b5bf2913b396098f7c7019b51a820a
        );

        vm.expectRevert(abi.encodeWithSelector(TimeLinearLoanDefs.NotValidVault.selector, 0));
        mockTimeLinearLoan.mockOnlyValidVault(0);
    }

    function testRevertWhenInitialize() public {
        address logic = address(new MockTimeLinearLoan());
        address[4] memory addrs;

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "owner"));
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimeLinearLoan.initialize.selector, addrs, _secondInterestRates, _trustedVaults)
        );
        addrs[0] = _owner;

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "whitelist"));
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimeLinearLoan.initialize.selector, addrs, _secondInterestRates, _trustedVaults)
        );
        addrs[1] = address(_whitelist);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "blacklist"));
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimeLinearLoan.initialize.selector, addrs, _secondInterestRates, _trustedVaults)
        );
        addrs[2] = address(_blacklist);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "loanToken"));
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimeLinearLoan.initialize.selector, addrs, _secondInterestRates, _trustedVaults)
        );
        addrs[3] = address(_depositToken);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "second interest rates length is zero"));
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimeLinearLoan.initialize.selector, addrs, new uint64[](0), _trustedVaults)
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "second interest rates value invalid"));
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimeLinearLoan.initialize.selector, addrs, new uint64[](18), _trustedVaults)
        );

        _secondInterestRates[17] = 11415525114 + 1;

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "second interest rates value invalid"));
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimeLinearLoan.initialize.selector, addrs, _secondInterestRates, _trustedVaults)
        );

        _secondInterestRates[16] = 11098427194;
        _secondInterestRates[17] = 10464231355;

        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidValue.selector, "second interest rates not sorted or duplicated")
        );
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimeLinearLoan.initialize.selector, addrs, _secondInterestRates, _trustedVaults)
        );

        _secondInterestRates[16] = 10464231355;
        _secondInterestRates[17] = 11098427194;

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "trusted vaults length is zero"));
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(
                TimeLinearLoan.initialize.selector,
                addrs,
                _secondInterestRates,
                new TimeLinearLoanDefs.TrustedVault[](0)
            )
        );

        _trustedVaults.push(
            TimeLinearLoanDefs.TrustedVault({
                vault: address(0x00),
                minimumPercentage: 40 * 10 ** 4, // 40%
                maximumPercentage: 10 * 10 ** 4 // 10%
            })
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "trusted vault address"));
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimeLinearLoan.initialize.selector, addrs, _secondInterestRates, _trustedVaults)
        );

        _trustedVaults[4].vault = address(new AssetVault(IERC20(address(0x01)), "NULL@OpenTerm", "NULL@OpenTerm"));

        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidValue.selector, "trusted vault asset and loan token mismatch")
        );
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimeLinearLoan.initialize.selector, addrs, _secondInterestRates, _trustedVaults)
        );

        _trustedVaults[4].vault =
            address(new AssetVault(IERC20(address(_depositToken)), "NULL@OpenTerm", "NULL@OpenTerm"));

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "trusted vault percentage"));
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimeLinearLoan.initialize.selector, addrs, _secondInterestRates, _trustedVaults)
        );

        _trustedVaults[4].minimumPercentage = 10 * 10 ** 4; // 10%
        _trustedVaults[4].maximumPercentage = 1_000_000 + 1; // 101%

        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidValue.selector, "trusted vault maximum percentage exceeds 100%")
        );
        new TransparentUpgradeableProxy(
            logic,
            _owner,
            abi.encodeWithSelector(TimeLinearLoan.initialize.selector, addrs, _secondInterestRates, _trustedVaults)
        );
    }

    function testFullFlow() public {
        _prepareFund(IERC20(address(_depositToken)).balanceOf(_owner) / (_trustedVaults.length * 2));

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.TrustedBorrowerAdded(_whitelistedUser1, 0);
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.TrustedBorrowerAdded(_whitelistedUser2, 1);
        vm.prank(_whitelistedUser2);
        _timeLinearLoan.join();

        TimeLinearLoanDefs.TrustedBorrower memory borrowerInfo1 = _getBorrowerInfoAtIndex(0);
        TimeLinearLoanDefs.TrustedBorrower memory borrowerInfo2 = _getBorrowerInfoAtIndex(1);

        assertEq(borrowerInfo1.borrower, _whitelistedUser1);
        assertEq(borrowerInfo2.borrower, _whitelistedUser2);
        assertEq(borrowerInfo1.ceilingLimit, 0);
        assertEq(borrowerInfo2.ceilingLimit, 0);
        assertEq(borrowerInfo1.remainingLimit, 0);
        assertEq(borrowerInfo2.remainingLimit, 0);

        vm.warp(_currentTime += 1 days);
        _timeLinearLoan.pile();

        vm.startPrank(_owner);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.AgreeJoinRequest(_whitelistedUser1, 2_000_000 * 10 ** 6);
        _timeLinearLoan.agree(_whitelistedUser1, 2_000_000 * 10 ** 6);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.AgreeJoinRequest(_whitelistedUser2, 4_000_000 * 10 ** 6);
        _timeLinearLoan.agree(_whitelistedUser2, 4_000_000 * 10 ** 6);

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
        _timeLinearLoan.pile();

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.ReceiveLoanRequest(_whitelistedUser1, 0, 1_500_000 * 10 ** 6);
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(1_500_000 * 10 ** 6);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.ReceiveLoanRequest(_whitelistedUser2, 1, 3_500_000 * 10 ** 6);
        vm.prank(_whitelistedUser2);
        _timeLinearLoan.request(3_500_000 * 10 ** 6);

        TimeLinearLoanDefs.LoanInfo memory loanInfo1 = _getLoanInfoAtIndex(0);
        TimeLinearLoanDefs.LoanInfo memory loanInfo2 = _getLoanInfoAtIndex(1);

        assertEq(loanInfo1.ceilingLimit, 1_500_000 * 10 ** 6);
        assertEq(loanInfo2.ceilingLimit, 3_500_000 * 10 ** 6);
        assertEq(loanInfo1.remainingLimit, 1_500_000 * 10 ** 6);
        assertEq(loanInfo2.remainingLimit, 3_500_000 * 10 ** 6);
        assertEq(loanInfo1.interestRateIndex, 0);
        assertEq(loanInfo2.interestRateIndex, 0);
        assertEq(loanInfo1.borrowerIndex, 0);
        assertEq(loanInfo2.borrowerIndex, 1);
        assertEq(uint8(loanInfo1.status), uint8(TimeLinearLoanDefs.LoanStatus.PENDING));
        assertEq(uint8(loanInfo2.status), uint8(TimeLinearLoanDefs.LoanStatus.PENDING));

        vm.warp(_currentTime += 1 days);
        _timeLinearLoan.pile();

        vm.startPrank(_owner);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.ApproveLoanRequest(_whitelistedUser1, 0, 1_000_000 * 10 ** 6, 1);
        _timeLinearLoan.approve(0, 1_000_000 * 10 ** 6, 1);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.ApproveLoanRequest(_whitelistedUser2, 1, 3_000_000 * 10 ** 6, 3);
        _timeLinearLoan.approve(1, 3_000_000 * 10 ** 6, 3);

        vm.stopPrank();

        loanInfo1 = _getLoanInfoAtIndex(0);
        loanInfo2 = _getLoanInfoAtIndex(1);

        assertEq(loanInfo1.ceilingLimit, 1_000_000 * 10 ** 6);
        assertEq(loanInfo2.ceilingLimit, 3_000_000 * 10 ** 6);
        assertEq(loanInfo1.remainingLimit, 1_000_000 * 10 ** 6);
        assertEq(loanInfo2.remainingLimit, 3_000_000 * 10 ** 6);
        assertEq(loanInfo1.interestRateIndex, 1);
        assertEq(loanInfo2.interestRateIndex, 3);
        assertEq(loanInfo1.borrowerIndex, 0);
        assertEq(loanInfo2.borrowerIndex, 1);
        assertEq(uint8(loanInfo1.status), uint8(TimeLinearLoanDefs.LoanStatus.APPROVED));
        assertEq(uint8(loanInfo2.status), uint8(TimeLinearLoanDefs.LoanStatus.APPROVED));

        vm.warp(_currentTime += 1 days);
        _timeLinearLoan.pile();

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.Borrowed(_whitelistedUser1, 0, 500_000 * 10 ** 6, true, 0);
        vm.prank(_whitelistedUser1);
        (bool isAllSatisfied1,) = _timeLinearLoan.borrow(0, 500_000 * 10 ** 6, _currentTime + 30 days);
        assertTrue(isAllSatisfied1);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.Borrowed(_whitelistedUser2, 1, 1_500_000 * 10 ** 6, true, 1);
        vm.prank(_whitelistedUser2);
        (bool isAllSatisfied2,) = _timeLinearLoan.borrow(1, 1_500_000 * 10 ** 6, _currentTime + 60 days);
        assertTrue(isAllSatisfied2);

        TimeLinearLoanDefs.DebtInfo memory debtInfo1 = _getDebtInfoAtIndex(0);
        TimeLinearLoanDefs.DebtInfo memory debtInfo2 = _getDebtInfoAtIndex(1);

        assertEq(debtInfo1.startTime, uint64(block.timestamp));
        assertEq(debtInfo2.startTime, uint64(block.timestamp));
        assertEq(debtInfo1.maturityTime, uint64(block.timestamp + 30 days));
        assertEq(debtInfo2.maturityTime, uint64(block.timestamp + 60 days));
        assertEq(debtInfo1.principal, 500_000 * 10 ** 6);
        assertEq(debtInfo2.principal, 1_500_000 * 10 ** 6);
        assertEq(debtInfo1.loanIndex, 0);
        assertEq(debtInfo2.loanIndex, 1);
        assertEq(uint8(debtInfo1.status), uint8(TimeLinearLoanDefs.DebtStatus.ACTIVE));
        assertEq(uint8(debtInfo2.status), uint8(TimeLinearLoanDefs.DebtStatus.ACTIVE));

        vm.warp(_currentTime += 25 days);
        _timeLinearLoan.pile();

        vm.startPrank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), 300_000 * 10 ** 6);
        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.Repaid(_whitelistedUser1, 0, 300_000 * 10 ** 6, false);
        _timeLinearLoan.repay(0, 300_000 * 10 ** 6);
        vm.stopPrank();

        vm.warp(_currentTime += (5 days + 1 seconds));
        _timeLinearLoan.pile();

        debtInfo1 = _getDebtInfoAtIndex(0);
        loanInfo1 = _getLoanInfoAtIndex(debtInfo1.loanIndex);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.Defaulted(_whitelistedUser1, 0, debtInfo1.netRemainingDebt, 17);
        vm.prank(_owner);
        uint128 remainingDebt = _timeLinearLoan.defaulted(_whitelistedUser1, 0, 17);

        vm.warp(_currentTime += 5 days);
        _timeLinearLoan.pile();

        vm.prank(_whitelistedUser1);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), remainingDebt / 2);

        vm.prank(_owner);
        (, remainingDebt) = _timeLinearLoan.recovery(_whitelistedUser1, 0, remainingDebt / 2);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        /// @dev precision loss in interest calculations with dividing
        emit TimeLinearLoanDefs.Closed(_whitelistedUser1, 0, remainingDebt);
        vm.prank(_owner);
        _timeLinearLoan.close(_whitelistedUser1, 0);

        vm.warp(_currentTime += 5 days);
        _timeLinearLoan.pile();

        vm.startPrank(_whitelistedUser2);
        IERC20(address(_depositToken)).approve(address(_timeLinearLoan), 1_000_000 * 10 ** 6);
        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.Repaid(_whitelistedUser2, 1, 1_000_000 * 10 ** 6, false);
        _timeLinearLoan.repay(1, 1_000_000 * 10 ** 6);
        vm.stopPrank();

        vm.warp(_currentTime += 20 days);
        _timeLinearLoan.pile();

        debtInfo2 = _getDebtInfoAtIndex(1);
        loanInfo2 = _getLoanInfoAtIndex(debtInfo2.loanIndex);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        emit TimeLinearLoanDefs.Defaulted(_whitelistedUser2, 1, debtInfo2.netRemainingDebt, 17);
        vm.prank(_owner);
        remainingDebt = _timeLinearLoan.defaulted(_whitelistedUser2, 1, 17);

        vm.expectEmit(false, false, false, true, address(_timeLinearLoan));
        /// @dev precision loss in interest calculations with dividing
        emit TimeLinearLoanDefs.Closed(_whitelistedUser2, 1, remainingDebt);
        vm.prank(_owner);
        _timeLinearLoan.close(_whitelistedUser2, 1);
    }

    function _abs(uint256 a_, uint256 b_) internal pure returns (uint256) {
        return a_ >= b_ ? a_ - b_ : b_ - a_;
    }

    function _getLoanInfoAtIndex(uint256 loanIndex_)
        internal
        view
        returns (TimeLinearLoanDefs.LoanInfo memory loanInfo_)
    {
        (
            loanInfo_.ceilingLimit,
            loanInfo_.remainingLimit,
            loanInfo_.interestRateIndex,
            loanInfo_.borrowerIndex,
            loanInfo_.status
        ) = _timeLinearLoan._allLoans(loanIndex_);
    }

    function _getBorrowerInfoAtIndex(uint256 borrowerIndex_)
        internal
        view
        returns (TimeLinearLoanDefs.TrustedBorrower memory borrowerInfo_)
    {
        (borrowerInfo_.borrower, borrowerInfo_.ceilingLimit, borrowerInfo_.remainingLimit) =
            _timeLinearLoan._trustedBorrowers(borrowerIndex_);
    }

    function _getDebtInfoAtIndex(uint256 debtIndex_)
        internal
        view
        returns (TimeLinearLoanDefs.DebtInfo memory debtInfo_)
    {
        (
            debtInfo_.loanIndex,
            debtInfo_.startTime,
            debtInfo_.maturityTime,
            debtInfo_.lastUpdateTime,
            debtInfo_.principal,
            debtInfo_.netRemainingDebt,
            debtInfo_.interestBearingAmount,
            debtInfo_.netRemainingInterest,
            debtInfo_.status
        ) = _timeLinearLoan._allDebts(debtIndex_);
    }

    function _prepareFund(uint256 fundForEachVault_) internal {
        for (uint256 i = 0; i < _trustedVaults.length; ++i) {
            vm.startPrank(_owner);

            IERC20(address(_depositToken)).approve(_trustedVaults[i].vault, fundForEachVault_);
            AssetVault(_trustedVaults[i].vault).deposit(fundForEachVault_, _owner);

            vm.stopPrank();

            vm.startPrank(_trustedVaults[i].vault);

            IERC20(address(_depositToken)).approve(address(_timeLinearLoan), fundForEachVault_);

            vm.stopPrank();
        }
    }

    function _prepareDebt() internal {
        vm.prank(_whitelistedUser1);
        _timeLinearLoan.join();

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.join();

        vm.startPrank(_owner);
        _timeLinearLoan.agree(_whitelistedUser1, 1_000_000 * 10 ** 6);
        _timeLinearLoan.agree(_whitelistedUser2, 2_000_000 * 10 ** 6);
        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.request(500_000 * 10 ** 6);

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.request(1_500_000 * 10 ** 6);

        vm.startPrank(_owner);
        _timeLinearLoan.approve(0, 500_000 * 10 ** 6, 1);
        _timeLinearLoan.approve(1, 1_500_000 * 10 ** 6, 3);
        vm.stopPrank();

        vm.prank(_whitelistedUser1);
        _timeLinearLoan.borrow(0, 300_000 * 10 ** 6, _currentTime + 30 days);

        vm.prank(_whitelistedUser2);
        _timeLinearLoan.borrow(1, 1_000_000 * 10 ** 6, _currentTime + 60 days);
    }
}

contract MockTimeLinearLoan is TimeLinearLoan {
    function mockOnlyInitialized() public view onlyInitialized {}
    function mockOnlyWhitelisted() public view onlyWhitelisted(msg.sender) {}
    function mockOnlyNotBlacklisted() public view onlyNotBlacklisted(msg.sender) {}
    function mockOnlyTrustedBorrower() public view onlyTrustedBorrower(msg.sender) {}
    function mockOnlyTrustedVault() public view onlyTrustedVault(msg.sender) {}
    function mockOnlyValidTranche(uint64 trancheIndex_) public view onlyValidTranche(trancheIndex_) {}
    function mockOnlyValidVault(uint64 vaultIndex_) public view onlyValidVault(vaultIndex_) {}
}
