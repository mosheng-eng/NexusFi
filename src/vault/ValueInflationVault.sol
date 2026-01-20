// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

import {Roles} from "src/common/Roles.sol";
import {Errors} from "src/common/Errors.sol";
import {IVaultBorrower} from "src/vault/IVaultBorrower.sol";

contract ValueInflationVault is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    ERC20Upgradeable,
    ERC4626Upgradeable
{
    /// @dev events emitted when trusted borrower is added
    /// @param borrower_ address of the borrower
    event TrustedBorrowerAdded(address indexed borrower_);

    /// @dev events emitted when trusted borrower is removed
    /// @param borrower_ address of the borrower
    event TrustedBorrowerRemoved(address indexed borrower_);

    /// @dev events emitted when trusted borrower is approved
    /// @param borrower_ address of the borrower
    /// @param allowance_ allowance amount
    event ApprovedTrustedBorrower(address indexed borrower_, uint256 allowance_);

    /// @dev events emitted when trusted lender is added
    /// @param lender_ address of the lender
    event TrustedLenderAdded(address indexed lender_);

    /// @dev events emitted when trusted lender is removed
    /// @param lender_ address of the lender
    event TrustedLenderRemoved(address indexed lender_);

    /// @dev error thrown when the lender is not trusted
    /// @param lender_ address of the lender
    error NotTrustedLender(address lender_);

    /// @dev error thrown when the borrower is not trusted
    /// @param borrower_ address of the borrower
    error NotTrustedBorrower(address borrower_);

    /// @dev error thrown when the existing debt of vault in borrower is too large
    /// @param borrower_ address of the borrower
    /// @param totalDebt_ existing total debt of the borrower
    error ExistedDebtTooLarge(address borrower_, uint256 totalDebt_);

    /// @dev error thrown when the existing debt of vault in borrower is not zero
    /// @param borrower_ address of the borrower
    /// @param totalDebt_ existing total debt of the borrower
    error ExistedDebtNotZero(address borrower_, uint256 totalDebt_);

    /// @dev fixed point 18 precision
    /// @notice constant, not stored in storage
    uint256 public constant FIXED18 = 1_000_000_000_000_000_000;

    /// @dev precision in million (1_000_000 = 100%)
    /// @notice constant, not stored in storage
    uint256 public constant PRECISION = 1_000_000;

    /// @dev minimum reserve ratio in basis points (500_000 = 50%)
    /// @notice won't accept borrowing if reserve below this ratio
    /// @notice constant, not stored in storage
    uint256 public constant MINIMUM_RESERVE_RATIO = 300_000;

    /// @dev maximum reserve ratio in basis points (800_000 = 80%)
    /// @notice won't accept deposit if reserve above this ratio
    /// @notice constant, not stored in storage
    uint256 public constant MAXIMUM_RESERVE_RATIO = 800_000;

    /// @dev floor reserve amount (without decimals)
    /// @notice won't accept borrowing if reserve below this amount
    /// @notice constant, not stored in storage
    uint256 public constant FLOOR_RESERVE = 500_000;

    /// @dev ceiling reserve amount (without decimals)
    /// @notice won't accept deposit if reserve above this amount
    /// @notice constant, not stored in storage
    uint256 public constant CEILING_RESERVE = 100_000_000;

    /// @dev whether lender is trusted
    mapping(address => bool) public _trustedLenders;

    /// @dev all trusted lenders
    /// @notice for enumeration purpose only
    address[] public _trustedLendersList;

    /// @dev whether borrower is trusted
    mapping(address => bool) public _trustedBorrowers;

    /// @dev all trusted borrowers
    /// @notice for enumeration purpose only
    address[] public _trustedBorrowersList;

    /// @dev modifier to check if lender is trusted
    /// @param lender_ address of the lender
    modifier onlyTrustedLender(address lender_) {
        if (!_trustedLenders[lender_]) {
            revert NotTrustedLender(lender_);
        }
        _;
    }

    /// @dev modifier to check if borrower is trusted
    /// @param borrower_ address of the borrower
    modifier onlyTrustedBorrower(address borrower_) {
        if (!_trustedBorrowers[borrower_]) {
            revert NotTrustedBorrower(borrower_);
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        /**
         * vault token name
         */
        string memory name_,
        /**
         * vault token symbol
         */
        string memory symbol_,
        /**
         * 0: address owner_,
         * 1: address asset_,
         */
        address[2] memory addr_,
        /**
         * trusted borrowers addresses
         */
        address[] memory trustedBorrowers_,
        /**
         * trusted borrowers allowances
         */
        uint256[] memory trustedBorrowersAllowance_,
        /**
         * trusted lenders addresses
         */
        address[] memory trustedLenders_
    ) public initializer {
        if (bytes(name_).length == 0) {
            revert Errors.InvalidValue("name is empty");
        }

        if (bytes(symbol_).length == 0) {
            revert Errors.InvalidValue("symbol is empty");
        }

        if (addr_[0] == address(0)) {
            revert Errors.ZeroAddress("owner");
        }

        if (addr_[1] == address(0)) {
            revert Errors.ZeroAddress("asset");
        }

        if (trustedBorrowers_.length != trustedBorrowersAllowance_.length) {
            revert Errors.InvalidValue("trusted borrowers and allowance length mismatch");
        }

        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __ERC20_init(name_, symbol_);
        __ERC4626_init(IERC20(addr_[1]));

        for (uint256 i = 0; i < trustedBorrowers_.length; i++) {
            _addTrustedBorrower(trustedBorrowers_[i]);
            _approveTrustedBorrower(trustedBorrowers_[i], trustedBorrowersAllowance_[i]);
        }

        for (uint256 i = 0; i < trustedLenders_.length; i++) {
            _addTrustedLender(trustedLenders_[i]);
        }

        _setRoleAdmin(Roles.OPERATOR_ROLE, Roles.OWNER_ROLE);
        _grantRole(Roles.OPERATOR_ROLE, addr_[0]);
    }

    function deposit(uint256 assets, address receiver)
        public
        override(ERC4626Upgradeable)
        onlyTrustedLender(msg.sender)
        returns (uint256)
    {
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver)
        public
        override(ERC4626Upgradeable)
        onlyTrustedLender(msg.sender)
        returns (uint256)
    {
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override(ERC4626Upgradeable)
        onlyTrustedLender(owner)
        returns (uint256)
    {
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override(ERC4626Upgradeable)
        onlyTrustedLender(owner)
        returns (uint256)
    {
        return super.redeem(shares, receiver, owner);
    }

    function totalAssets() public view override(ERC4626Upgradeable) returns (uint256 totalAssets_) {
        totalAssets_ = IERC20(asset()).balanceOf(address(this));
        for (uint256 i = 0; i < _trustedBorrowersList.length; i++) {
            totalAssets_ += IVaultBorrower(_trustedBorrowersList[i]).totalDebtOfVault(address(this));
        }
    }

    function decimals() public view virtual override(ERC4626Upgradeable, ERC20Upgradeable) returns (uint8) {
        return ERC4626Upgradeable.decimals();
    }

    /// @dev add a trusted lender
    /// @param lender_ address of the lender
    function addTrustedLender(address lender_) public onlyRole(Roles.OPERATOR_ROLE) {
        _addTrustedLender(lender_);
    }

    /// @dev remove a trusted lender
    /// @param lender_ address of the lender
    function removeTrustedLender(address lender_) public onlyRole(Roles.OPERATOR_ROLE) {
        _removeTrustedLender(lender_);
    }

    /// @dev add a trusted borrower
    /// @param borrower_ address of the borrower
    function addTrustedBorrower(address borrower_) public onlyRole(Roles.OPERATOR_ROLE) {
        _addTrustedBorrower(borrower_);
    }

    /// @dev approve allowance for a trusted borrower
    /// @param borrower_ address of the borrower
    /// @param allowance_ allowance amount
    function approveTrustedBorrower(address borrower_, uint256 allowance_)
        public
        onlyRole(Roles.OPERATOR_ROLE)
        onlyTrustedBorrower(borrower_)
    {
        _approveTrustedBorrower(borrower_, allowance_);
    }

    /// @dev remove a trusted borrower
    /// @param borrower_ address of the borrower
    function removeTrustedBorrower(address borrower_) public onlyRole(Roles.OPERATOR_ROLE) {
        _removeTrustedBorrower(borrower_);
    }

    function _addTrustedBorrower(address borrower_) internal {
        if (borrower_ == address(0)) {
            revert Errors.ZeroAddress("borrower");
        }

        if (borrower_.code.length == 0) {
            revert Errors.InvalidValue("borrower is not a contract");
        }

        if (_trustedBorrowers[borrower_]) {
            revert Errors.InvalidValue("borrower is already trusted");
        }

        try IVaultBorrower(borrower_).totalDebtOfVault(address(this)) returns (uint256 totalDebt) {
            if (totalDebt > type(uint64).max) {
                revert ExistedDebtTooLarge(borrower_, totalDebt);
            }
        } catch {
            revert Errors.InvalidValue("borrower does not implement IVaultBorrower");
        }

        _trustedBorrowers[borrower_] = true;

        emit TrustedBorrowerAdded(borrower_);

        for (uint256 i = 0; i < _trustedBorrowersList.length; i++) {
            if (_trustedBorrowersList[i] == borrower_) {
                return;
            }
        }

        _trustedBorrowersList.push(borrower_);
    }

    function _approveTrustedBorrower(address borrower_, uint256 allowance_) internal {
        if (borrower_ == address(0)) {
            revert Errors.ZeroAddress("borrower");
        }

        if (allowance_ == 0) {
            revert Errors.InvalidValue("allowance is zero");
        }

        IERC20(asset()).approve(borrower_, allowance_);

        emit ApprovedTrustedBorrower(borrower_, allowance_);
    }

    function _removeTrustedBorrower(address borrower_) internal {
        if (borrower_ == address(0)) {
            revert Errors.ZeroAddress("borrower");
        }

        if (!_trustedBorrowers[borrower_]) {
            revert Errors.InvalidValue("borrower is already removed");
        }

        uint256 totalDebt = IVaultBorrower(borrower_).totalDebtOfVault(address(this));
        if (totalDebt > 0) {
            revert ExistedDebtNotZero(borrower_, totalDebt);
        }

        _trustedBorrowers[borrower_] = false;

        emit TrustedBorrowerRemoved(borrower_);

        for (uint256 i = 0; i < _trustedBorrowersList.length; i++) {
            if (_trustedBorrowersList[i] == borrower_) {
                _trustedBorrowersList[i] = _trustedBorrowersList[_trustedBorrowersList.length - 1];
                _trustedBorrowersList.pop();
                return;
            }
        }
    }

    function _addTrustedLender(address lender_) internal {
        if (lender_ == address(0)) {
            revert Errors.ZeroAddress("lender");
        }

        if (_trustedLenders[lender_]) {
            revert Errors.InvalidValue("lender is already trusted");
        }

        _trustedLenders[lender_] = true;

        emit TrustedLenderAdded(lender_);

        for (uint256 i = 0; i < _trustedLendersList.length; i++) {
            if (_trustedLendersList[i] == lender_) {
                return;
            }
        }

        _trustedLendersList.push(lender_);
    }

    function _removeTrustedLender(address lender_) internal {
        if (lender_ == address(0)) {
            revert Errors.ZeroAddress("lender");
        }

        if (!_trustedLenders[lender_]) {
            revert Errors.InvalidValue("lender is already removed");
        }

        _trustedLenders[lender_] = false;

        emit TrustedLenderRemoved(lender_);

        for (uint256 i = 0; i < _trustedLendersList.length; i++) {
            if (_trustedLendersList[i] == lender_) {
                _trustedLendersList[i] = _trustedLendersList[_trustedLendersList.length - 1];
                _trustedLendersList.pop();
                return;
            }
        }
    }
}
