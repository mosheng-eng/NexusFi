// SPDX-License-License: MIT

pragma solidity ^0.8.24;

import {ValueInflationVault} from "src/vault/ValueInflationVault.sol";
import {IVaultBorrower} from "src/vault/IVaultBorrower.sol";
import {DeployContractSuite} from "script/DeployContractSuite.s.sol";
import {DepositAsset} from "test/mock/DepositAsset.sol";
import {Errors} from "src/common/Errors.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Test, console, stdStorage, StdStorage} from "forge-std/Test.sol";

contract ValueInflationVaultTest is Test {
    using Math for uint256;
    using stdStorage for StdStorage;

    string constant VAULT_TOKEN_NAME = "VIV Token";
    string constant VAULT_TOKEN_SYMBOL = "VIV";

    address _owner = makeAddr("owner");
    address _asset;
    address _trustedBorrower1 = address(new VaultBorrower(1 ether));
    address _trustedBorrower2 = address(new VaultBorrower(2 ether));
    uint256 _trustedBorrower1Allowance = 1_000_000 ether;
    uint256 _trustedBorrower2Allowance = 2_000_000 ether;
    address _trustedLender1 = makeAddr("trustedLender1");
    address _trustedLender2 = makeAddr("trustedLender2");

    uint64 internal _startTime = 1759301999; // 2025-10-01 14:59:59 UTC+8
    uint64 internal _currentTime = _startTime - 1 days; // 2025-09-30 14:59:59 UTC+8

    DeployContractSuite internal _deployer = new DeployContractSuite();
    ValueInflationVault internal _valueInflationVault;
    DepositAsset internal _depositToken;

    modifier timeBegin() {
        vm.warp(_currentTime);
        _;
    }

    modifier oneDayPassed() {
        vm.warp(_currentTime += 1 days);
        _;
    }

    modifier deployDepositToken() {
        _depositToken = new DepositAsset("USD Coin", "USDC");

        _depositToken.mint(_trustedBorrower1, 1_000_000 * 10 ** 6);
        _depositToken.mint(_trustedBorrower2, 1_000_000 * 10 ** 6);
        _depositToken.mint(_trustedLender1, 1_000_000 * 10 ** 6);
        _depositToken.mint(_trustedLender2, 1_000_000 * 10 ** 6);
        _depositToken.mint(_owner, 1_000_000_000_000_000 * 10 ** 6);

        vm.label(address(_depositToken), "USDC");

        _;
    }

    modifier deployValueInflationVault() {
        address[] memory trustedBorrowers = new address[](2);
        trustedBorrowers[0] = _trustedBorrower1;
        trustedBorrowers[1] = _trustedBorrower2;

        uint256[] memory trustedBorrowersAllowance = new uint256[](2);
        trustedBorrowersAllowance[0] = _trustedBorrower1Allowance;
        trustedBorrowersAllowance[1] = _trustedBorrower2Allowance;

        address[] memory trustedLenders = new address[](2);
        trustedLenders[0] = _trustedLender1;
        trustedLenders[1] = _trustedLender2;

        _valueInflationVault = ValueInflationVault(
            _deployer.deployValueInflationVault(
                VAULT_TOKEN_NAME,
                VAULT_TOKEN_SYMBOL,
                [_owner, address(_depositToken)],
                trustedBorrowers,
                trustedBorrowersAllowance,
                trustedLenders
            )
        );

        vm.label(address(_valueInflationVault), "ValueInflationVault");

        _;
    }

    function setUp() public timeBegin deployDepositToken deployValueInflationVault oneDayPassed {
        vm.label(_owner, "owner");
        vm.label(_trustedBorrower1, "trustedBorrower1");
        vm.label(_trustedBorrower2, "trustedBorrower2");
        vm.label(_trustedLender1, "trustedLender1");
        vm.label(_trustedLender2, "trustedLender2");
    }

    function testNull() public pure {
        assertTrue(true);
    }

    function testDeposit() public {
        uint256 totalAssetBeforeDeposit = (uint256(1 ether) * uint160(address(_valueInflationVault)))
            % (type(uint32).max / 100)
            + (uint256(2 ether) * uint160(address(_valueInflationVault))) % (type(uint32).max / 100);

        vm.startPrank(_trustedLender1);

        _depositToken.approve(address(_valueInflationVault), 1_000_000 * 10 ** 6);

        vm.expectEmit(true, true, false, true);
        emit IERC4626.Deposit(
            _trustedLender1, _trustedLender1, 1_000_000 * 10 ** 6, 1_000_000 * 10 ** 6 / totalAssetBeforeDeposit
        );

        _valueInflationVault.deposit(1_000_000 * 10 ** 6, _trustedLender1);

        vm.stopPrank();

        assertEq(_valueInflationVault.totalAssets(), 1_000_000 * 10 ** 6 + totalAssetBeforeDeposit);
        assertEq(_valueInflationVault.totalSupply(), 1_000_000 * 10 ** 6 / totalAssetBeforeDeposit);
    }

    function testNotTrustedLenderDeposit() public {
        address unknownLender = makeAddr("unknowLender");

        vm.expectRevert(abi.encodeWithSelector(ValueInflationVault.NotTrustedLender.selector, unknownLender));

        vm.prank(unknownLender);
        _valueInflationVault.deposit(1_000_000 * 10 ** 6, unknownLender);
    }

    function testMint() public {
        uint256 totalAssetBeforeMint = (uint256(1 ether) * uint160(address(_valueInflationVault)))
            % (type(uint32).max / 100)
            + (uint256(2 ether) * uint160(address(_valueInflationVault))) % (type(uint32).max / 100);

        vm.startPrank(_trustedLender1);

        _depositToken.approve(address(_valueInflationVault), 1_000_000 * 10 ** 6);

        vm.expectEmit(true, true, false, true);
        emit IERC4626.Deposit(_trustedLender1, _trustedLender1, 29667 * (totalAssetBeforeMint + 1), 29667);

        _valueInflationVault.mint(29667, _trustedLender1);

        vm.stopPrank();

        assertEq(_valueInflationVault.totalSupply(), 29667);
        assertEq(_valueInflationVault.totalAssets(), totalAssetBeforeMint + 29667 * (totalAssetBeforeMint + 1));
    }

    function testNotTrustedLenderMint() public {
        address unknownLender = makeAddr("unknowLender");

        vm.expectRevert(abi.encodeWithSelector(ValueInflationVault.NotTrustedLender.selector, unknownLender));

        vm.prank(unknownLender);
        _valueInflationVault.mint(29667, unknownLender);
    }

    function testWithdraw() public {
        uint256 totalAssetBeforeDeposit = (uint256(1 ether) * uint160(address(_valueInflationVault)))
            % (type(uint32).max / 100)
            + (uint256(2 ether) * uint160(address(_valueInflationVault))) % (type(uint32).max / 100);

        vm.startPrank(_trustedLender1);

        _depositToken.approve(address(_valueInflationVault), 1_000_000 * 10 ** 6);

        _valueInflationVault.deposit(1_000_000 * 10 ** 6, _trustedLender1);

        uint256 totalAssetAfterDeposit = totalAssetBeforeDeposit + 1_000_000 * 10 ** 6;

        vm.expectEmit(true, true, true, true);
        emit IERC4626.Withdraw(
            _trustedLender1,
            _trustedLender1,
            _trustedLender1,
            500_000 * 10 ** 6,
            500_000 * 10 ** 6 * (1_000_000 * 10 ** 6 / totalAssetBeforeDeposit) / (totalAssetAfterDeposit + 1) + 1
        );

        _valueInflationVault.withdraw(500_000 * 10 ** 6, _trustedLender1, _trustedLender1);

        vm.stopPrank();

        assertEq(
            _valueInflationVault.totalSupply(),
            1_000_000 * 10 ** 6 / totalAssetBeforeDeposit
                - (500_000 * 10 ** 6 * (1_000_000 * 10 ** 6 / totalAssetBeforeDeposit) / (totalAssetAfterDeposit + 1) + 1)
        );
        assertEq(_valueInflationVault.totalAssets(), totalAssetAfterDeposit - 500_000 * 10 ** 6);
    }

    function testNotTrustedLenderWithdraw() public {
        address unknownLender = makeAddr("unknowLender");

        vm.expectRevert(abi.encodeWithSelector(ValueInflationVault.NotTrustedLender.selector, unknownLender));

        vm.prank(unknownLender);
        _valueInflationVault.withdraw(500_000 * 10 ** 6, unknownLender, unknownLender);
    }

    function testRedeem() public {
        uint256 totalAssetBeforeMint = (uint256(1 ether) * uint160(address(_valueInflationVault)))
            % (type(uint32).max / 100)
            + (uint256(2 ether) * uint160(address(_valueInflationVault))) % (type(uint32).max / 100);

        vm.startPrank(_trustedLender1);

        _depositToken.approve(address(_valueInflationVault), 1_000_000 * 10 ** 6);

        _valueInflationVault.mint(29667, _trustedLender1);

        uint256 totalAssetAfterMint = totalAssetBeforeMint + 29667 * (totalAssetBeforeMint + 1);

        vm.expectEmit(true, true, true, true);
        emit IERC4626.Withdraw(
            _trustedLender1, _trustedLender1, _trustedLender1, 14833 * (totalAssetAfterMint + 1) / (29667 + 1), 14833
        );

        _valueInflationVault.redeem(14833, _trustedLender1, _trustedLender1);

        vm.stopPrank();

        assertEq(_valueInflationVault.totalSupply(), 29667 - 14833);
        assertEq(
            _valueInflationVault.totalAssets(), totalAssetAfterMint - 14833 * (totalAssetAfterMint + 1) / (29667 + 1)
        );
    }

    function testNotTrustedLenderRedeem() public {
        address unknownLender = makeAddr("unknowLender");

        vm.expectRevert(abi.encodeWithSelector(ValueInflationVault.NotTrustedLender.selector, unknownLender));

        vm.prank(unknownLender);
        _valueInflationVault.redeem(14833, unknownLender, unknownLender);
    }

    function testTotalAssets() public view {
        assertEq(
            _valueInflationVault.totalAssets(),
            (uint256(1 ether) * uint160(address(_valueInflationVault))) % (type(uint32).max / 100)
                + (uint256(2 ether) * uint160(address(_valueInflationVault))) % (type(uint32).max / 100)
        );
    }

    function testAddTrustedBorrower() public {
        address newTrustedBorrower = address(new VaultBorrower(3 ether));

        vm.expectEmit(true, false, false, false);
        emit ValueInflationVault.TrustedBorrowerAdded(newTrustedBorrower);

        vm.prank(_owner);
        _valueInflationVault.addTrustedBorrower(newTrustedBorrower);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "borrower"));
        vm.prank(_owner);
        _valueInflationVault.addTrustedBorrower(address(0));

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "borrower is not a contract"));
        vm.prank(_owner);
        _valueInflationVault.addTrustedBorrower(makeAddr("notContract"));

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "borrower is already trusted"));
        vm.prank(_owner);
        _valueInflationVault.addTrustedBorrower(_trustedBorrower1);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidValue.selector, "borrower does not implement IVaultBorrower")
        );
        vm.prank(_owner);
        _valueInflationVault.addTrustedBorrower(address(_depositToken));

        address invalidDebtBorrower = address(new VaultBorrower(4 ether));
        vm.mockCall(
            invalidDebtBorrower,
            abi.encodeWithSelector(IVaultBorrower.totalDebtOfVault.selector, address(_valueInflationVault)),
            abi.encode(uint256(type(uint64).max) + 1)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                ValueInflationVault.ExistedDebtTooLarge.selector, invalidDebtBorrower, uint256(type(uint64).max) + 1
            )
        );
        vm.prank(_owner);
        _valueInflationVault.addTrustedBorrower(invalidDebtBorrower);

        stdstore.target(address(_valueInflationVault)).sig("_trustedBorrowers(address)").with_key(newTrustedBorrower)
            .checked_write(false);
        vm.expectEmit(true, false, false, false);
        emit ValueInflationVault.TrustedBorrowerAdded(newTrustedBorrower);

        vm.prank(_owner);
        _valueInflationVault.addTrustedBorrower(newTrustedBorrower);
    }

    function testRemoveTrustedBorrower() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ValueInflationVault.ExistedDebtNotZero.selector,
                _trustedBorrower1,
                (uint256(1 ether) * uint160(address(_valueInflationVault))) % (type(uint32).max / 100)
            )
        );
        vm.prank(_owner);
        _valueInflationVault.removeTrustedBorrower(_trustedBorrower1);

        vm.mockCall(
            _trustedBorrower1,
            abi.encodeWithSelector(IVaultBorrower.totalDebtOfVault.selector, address(_valueInflationVault)),
            abi.encode(0)
        );

        vm.expectEmit(true, false, false, false);
        emit ValueInflationVault.TrustedBorrowerRemoved(_trustedBorrower1);

        vm.prank(_owner);
        _valueInflationVault.removeTrustedBorrower(_trustedBorrower1);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "borrower"));
        vm.prank(_owner);
        _valueInflationVault.removeTrustedBorrower(address(0));

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "borrower is already removed"));
        vm.prank(_owner);
        _valueInflationVault.removeTrustedBorrower(_trustedBorrower1);
    }

    function testApproveTrustedBorrower() public {
        uint256 newAllowance = 5_000_000 ether;

        vm.expectEmit(true, false, false, false);
        emit ValueInflationVault.ApprovedTrustedBorrower(_trustedBorrower1, newAllowance);

        vm.prank(_owner);
        _valueInflationVault.approveTrustedBorrower(_trustedBorrower1, newAllowance);

        address notTrustedBorrower = makeAddr("notTrustedBorrower");
        vm.expectRevert(abi.encodeWithSelector(ValueInflationVault.NotTrustedBorrower.selector, notTrustedBorrower));
        vm.prank(_owner);
        _valueInflationVault.approveTrustedBorrower(notTrustedBorrower, newAllowance);

        stdstore.target(address(_valueInflationVault)).sig("_trustedBorrowers(address)").with_key(address(0))
            .checked_write(true);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "borrower"));
        vm.prank(_owner);
        _valueInflationVault.approveTrustedBorrower(address(0), newAllowance);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "allowance is zero"));
        vm.prank(_owner);
        _valueInflationVault.approveTrustedBorrower(_trustedBorrower1, 0);
    }

    function testAddTrustedLender() public {
        address newTrustedLender = makeAddr("newTrustedLender");

        vm.expectEmit(true, false, false, false);
        emit ValueInflationVault.TrustedLenderAdded(newTrustedLender);

        vm.prank(_owner);
        _valueInflationVault.addTrustedLender(newTrustedLender);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "lender"));
        vm.prank(_owner);
        _valueInflationVault.addTrustedLender(address(0));

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "lender is already trusted"));
        vm.prank(_owner);
        _valueInflationVault.addTrustedLender(newTrustedLender);

        stdstore.target(address(_valueInflationVault)).sig("_trustedLenders(address)").with_key(newTrustedLender)
            .checked_write(false);
        vm.expectEmit(true, false, false, false);
        emit ValueInflationVault.TrustedLenderAdded(newTrustedLender);

        vm.prank(_owner);
        _valueInflationVault.addTrustedLender(newTrustedLender);
    }

    function testRemoveTrustedLender() public {
        vm.expectEmit(true, false, false, false);
        emit ValueInflationVault.TrustedLenderRemoved(_trustedLender1);

        vm.prank(_owner);
        _valueInflationVault.removeTrustedLender(_trustedLender1);

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "lender"));
        vm.prank(_owner);
        _valueInflationVault.removeTrustedLender(address(0));

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "lender is already removed"));
        vm.prank(_owner);
        _valueInflationVault.removeTrustedLender(_trustedLender1);
    }

    function testInvalidInitialize() public {
        address[] memory trustedBorrowers = new address[](2);
        trustedBorrowers[0] = _trustedBorrower1;
        trustedBorrowers[1] = _trustedBorrower2;

        uint256[] memory trustedBorrowersAllowance = new uint256[](2);
        trustedBorrowersAllowance[0] = _trustedBorrower1Allowance;
        trustedBorrowersAllowance[1] = _trustedBorrower2Allowance;

        address[] memory trustedLenders = new address[](2);
        trustedLenders[0] = _trustedLender1;
        trustedLenders[1] = _trustedLender2;

        _deployer.deployValueInflationVault(
            VAULT_TOKEN_NAME,
            VAULT_TOKEN_SYMBOL,
            [_owner, address(_depositToken)],
            trustedBorrowers,
            trustedBorrowersAllowance,
            trustedLenders
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "name is empty"));
        _deployer.deployValueInflationVault(
            "",
            VAULT_TOKEN_SYMBOL,
            [_owner, address(_depositToken)],
            trustedBorrowers,
            trustedBorrowersAllowance,
            trustedLenders
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidValue.selector, "symbol is empty"));
        _deployer.deployValueInflationVault(
            VAULT_TOKEN_NAME,
            "",
            [_owner, address(_depositToken)],
            trustedBorrowers,
            trustedBorrowersAllowance,
            trustedLenders
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "owner"));
        _deployer.deployValueInflationVault(
            VAULT_TOKEN_NAME,
            VAULT_TOKEN_SYMBOL,
            [address(0x00), address(_depositToken)],
            trustedBorrowers,
            trustedBorrowersAllowance,
            trustedLenders
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "asset"));
        _deployer.deployValueInflationVault(
            VAULT_TOKEN_NAME,
            VAULT_TOKEN_SYMBOL,
            [_owner, address(0x00)],
            trustedBorrowers,
            trustedBorrowersAllowance,
            trustedLenders
        );

        vm.expectRevert(
            abi.encodeWithSelector(Errors.InvalidValue.selector, "trusted borrowers and allowance length mismatch")
        );
        _deployer.deployValueInflationVault(
            VAULT_TOKEN_NAME,
            VAULT_TOKEN_SYMBOL,
            [_owner, address(_depositToken)],
            trustedBorrowers,
            new uint256[](3),
            trustedLenders
        );
    }

    function testDecimals() public view {
        assertEq(_valueInflationVault.decimals(), 6);
    }
}

contract VaultBorrower is IVaultBorrower {
    uint256 internal _totalDebt;

    constructor(uint256 totalDebt_) {
        _totalDebt = totalDebt_;
    }

    function totalDebtOfVault(address vault_) external view returns (uint256) {
        return _totalDebt * uint160(vault_) % (type(uint32).max / 100);
    }
}
