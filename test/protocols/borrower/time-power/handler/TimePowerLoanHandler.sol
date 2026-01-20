// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {DeployContractSuit} from "script/DeployContractSuit.s.sol";

import {TimePowerLoan} from "src/protocols/borrower/time-power/TimePowerLoan.sol";
import {Whitelist} from "src/whitelist/Whitelist.sol";
import {Blacklist} from "src/blacklist/Blacklist.sol";
import {Roles} from "src/common/Roles.sol";
import {Errors} from "src/common/Errors.sol";
import {IWhitelist} from "src/whitelist/IWhitelist.sol";
import {IBlacklist} from "src/blacklist/IBlacklist.sol";

import {Vm} from "forge-std/Vm.sol";
import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {console} from "forge-std/console.sol";

import {DepositAsset} from "test/mock/DepositAsset.sol";
import {AssetVault} from "test/mock/AssetVault.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract TimePowerLoanHandler is StdCheats, StdUtils, StdAssertions, CommonBase {
    using Math for uint256;

    enum HandlerType {
        UNION,
        UNIN_OVER,
        JOIN,
        JOIN_OVER,
        REQUEST,
        REQUEST_NO_BORROWER,
        REQUEST_NO_LIMIT,
        REQUEST_NO_AMOUNT,
        REQUEST_OVER,
        BORROW,
        BORROW_NO_LOAN,
        BORROW_NO_LIMIT,
        BORROW_OVER,
        REPAY,
        REPAY_NO_DEBT,
        REPAY_STATUS,
        REPAY_OVER,
        DEFAULT,
        DEFAULT_NO_DEBT,
        DEFAULT_STATUS,
        DEFAULT_OVER,
        RECOVERY,
        RECOVERY_NO_DEBT,
        RECOVERY_STATUS,
        RECOVERY_OVER,
        CLOSE,
        CLOSE_NO_DEBT,
        CLOSE_STATUS,
        CLOSE_OVER,
        TIME,
        TIME_OVER
    }

    /// @dev fixed point 18 precision
    /// @notice constant, not stored in storage
    uint256 public constant FIXED18 = 1_000_000_000_000_000_000;

    /// @dev precision in million (1_000_000 = 100%)
    /// @notice constant, not stored in storage
    uint256 public constant PRECISION = 1_000_000;

    address internal _owner = makeAddr("owner");

    uint64 internal _currentTime = 1759301999; // 2025-10-01 14:59:59 UTC+8
    uint64 internal _currentBlock = 100;

    DeployContractSuit internal _deployer = new DeployContractSuit();
    Whitelist internal _whitelist;
    Blacklist internal _blacklist;
    DepositAsset internal _depositToken;

    TimePowerLoan.TrustedVault[] internal _trustedVaults;
    uint64[] internal _secondInterestRates;
    address internal _loanToken;

    TimePowerLoan internal _timePowerLoan;
    address _proxyAdmin;

    mapping(HandlerType => uint256) internal _handlerEnterCount;
    mapping(HandlerType => uint256) internal _handlerExitCount;

    function _timeBegin() internal {
        vm.warp(_currentTime);
    }

    function _oneDayPassed() internal {
        vm.warp(_currentTime += 1 days);
        vm.roll(_currentBlock += 1);
    }

    function _deployWhitelist() internal {
        vm.startPrank(_owner);

        _whitelist = Whitelist(_deployer.deployWhitelist(_owner, true));

        _whitelist.grantRole(Roles.OPERATOR_ROLE, address(_owner));

        vm.stopPrank();

        vm.label(address(_whitelist), "Whitelist");
    }

    function _deployBlacklist() internal {
        vm.startPrank(_owner);

        _blacklist = Blacklist(_deployer.deployBlacklist(_owner, true));

        _blacklist.grantRole(Roles.OPERATOR_ROLE, address(_owner));

        vm.stopPrank();

        vm.label(address(_blacklist), "Blacklist");
    }

    function _deployDepositToken() internal {
        _depositToken = new DepositAsset("USD Coin", "USDC");

        _depositToken.mint(_owner, type(uint128).max);

        vm.label(address(_depositToken), "USDC");
    }

    function _deployTimePowerLoan() internal {
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

        vm.recordLogs();
        _timePowerLoan = TimePowerLoan(
            _deployer.deployTimePowerLoan(
                [_owner, address(_whitelist), address(_blacklist), address(_depositToken)],
                _secondInterestRates,
                _trustedVaults
            )
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _timePowerLoan.grantRole(Roles.OPERATOR_ROLE, _owner);

        vm.stopPrank();

        vm.label(address(_timePowerLoan), "TimePowerLoan");
        vm.label(_trustedVaults[0].vault, "MMF@OpenTerm");
        vm.label(_trustedVaults[1].vault, "RWA@OpenTerm");
        vm.label(_trustedVaults[2].vault, "MMF@FixedTerm");
        vm.label(_trustedVaults[3].vault, "RWA@FixedTerm");

        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == address(_timePowerLoan)) {
                bytes32[] memory topics = logs[i].topics;
                for (uint256 j = 0; j < topics.length; ++j) {
                    if (topics[j] == bytes32(0x7e644d79422f17c01e4894b5f4f588d331ebfa28653d42ae832dc59e38c9798f)) {
                        (, bytes32 data) = abi.decode(logs[i].data, (bytes32, bytes32));
                        _proxyAdmin = address(bytes20(uint160(uint256(data))));
                    }
                }
            }
        }

        console.log(_proxyAdmin);
    }

    function _setDependencies() internal {
        vm.startPrank(_owner);

        _whitelist.grantRole(Roles.OPERATOR_ROLE, address(_timePowerLoan));
        _blacklist.grantRole(Roles.OPERATOR_ROLE, address(_timePowerLoan));

        vm.stopPrank();
    }

    function _addWhitelist(address someone_) public {
        vm.prank(_owner);
        _timePowerLoan.addWhitelist(someone_);
        assertTrue(_whitelist.isWhitelisted(someone_));
    }

    function _addBlacklist(address someone_) public {
        vm.prank(_owner);
        _timePowerLoan.addBlacklist(someone_);
        assertTrue(_blacklist.isBlacklisted(someone_));
    }

    function _fundSomeone(address someone_, uint256 amount_) public {
        _depositToken.mint(someone_, amount_);
    }

    function _prepareFund(uint256 fundForEachVault_) internal {
        for (uint256 i = 0; i < _trustedVaults.length; ++i) {
            vm.startPrank(_owner);

            IERC20(address(_depositToken)).approve(_trustedVaults[i].vault, fundForEachVault_);
            AssetVault(_trustedVaults[i].vault).deposit(fundForEachVault_, _owner);

            vm.stopPrank();

            vm.startPrank(_trustedVaults[i].vault);

            IERC20(address(_depositToken)).approve(address(_timePowerLoan), type(uint128).max);

            vm.stopPrank();
        }
    }

    constructor() {
        _timeBegin();
        _deployWhitelist();
        _deployBlacklist();
        _deployDepositToken();
        _deployTimePowerLoan();
        _setDependencies();
        _prepareFund(type(uint128).max / 10);
        _oneDayPassed();
    }

    function unionHandler1(
        address someone_,
        uint128 amount_,
        uint128 loanAmount_,
        uint64 interestRateIndex_,
        uint256 threshold_,
        uint128 debtAmount_,
        uint64 maturityTime_
    ) external {
        vm.assume(!_excludeDuplicateBorrowerJoin(someone_));

        _handlerEnterCount[HandlerType.UNION] += 1;

        uint64 borrowerIndex = _joinHandler(someone_, amount_);
        uint64 loanIndex = _requestHandler(borrowerIndex, loanAmount_, interestRateIndex_, threshold_);
        uint64 debtIndex = _borrowHandler(loanIndex, debtAmount_, maturityTime_);
        _handlerExitCount[HandlerType.UNIN_OVER] += 1;
        _unionHandlerLog(
            someone_,
            amount_,
            loanAmount_,
            interestRateIndex_,
            threshold_,
            debtAmount_,
            maturityTime_,
            borrowerIndex,
            loanIndex,
            debtIndex
        );
    }

    function unionHandler2(
        address someone_,
        uint128 amount_,
        uint128 loanAmount_,
        uint64 interestRateIndex_,
        uint256 threshold_,
        uint128 debtAmount_,
        uint64 maturityTime_
    ) external {
        vm.assume(!_excludeDuplicateBorrowerJoin(someone_));

        _handlerEnterCount[HandlerType.UNION] += 1;

        uint64 borrowerIndex = _joinHandler(someone_, amount_);
        uint64 loanIndex = _requestHandler(borrowerIndex, loanAmount_, interestRateIndex_, threshold_);
        uint64 debtIndex = _borrowHandler(loanIndex, debtAmount_, maturityTime_);
        _handlerExitCount[HandlerType.UNIN_OVER] += 1;
        _unionHandlerLog(
            someone_,
            amount_,
            loanAmount_,
            interestRateIndex_,
            threshold_,
            debtAmount_,
            maturityTime_,
            borrowerIndex,
            loanIndex,
            debtIndex
        );
    }

    function unionHandler3(
        address someone_,
        uint128 amount_,
        uint128 loanAmount_,
        uint64 interestRateIndex_,
        uint256 threshold_,
        uint128 debtAmount_,
        uint64 maturityTime_
    ) external {
        vm.assume(!_excludeDuplicateBorrowerJoin(someone_));

        _handlerEnterCount[HandlerType.UNION] += 1;

        uint64 borrowerIndex = _joinHandler(someone_, amount_);
        uint64 loanIndex = _requestHandler(borrowerIndex, loanAmount_, interestRateIndex_, threshold_);
        uint64 debtIndex = _borrowHandler(loanIndex, debtAmount_, maturityTime_);
        _handlerExitCount[HandlerType.UNIN_OVER] += 1;
        _unionHandlerLog(
            someone_,
            amount_,
            loanAmount_,
            interestRateIndex_,
            threshold_,
            debtAmount_,
            maturityTime_,
            borrowerIndex,
            loanIndex,
            debtIndex
        );
    }

    function unionHandler4(
        address someone_,
        uint128 amount_,
        uint128 loanAmount_,
        uint64 interestRateIndex_,
        uint256 threshold_,
        uint128 debtAmount_,
        uint64 maturityTime_
    ) external {
        vm.assume(!_excludeDuplicateBorrowerJoin(someone_));

        _handlerEnterCount[HandlerType.UNION] += 1;

        uint64 borrowerIndex = _joinHandler(someone_, amount_);
        uint64 loanIndex = _requestHandler(borrowerIndex, loanAmount_, interestRateIndex_, threshold_);
        uint64 debtIndex = _borrowHandler(loanIndex, debtAmount_, maturityTime_);
        _handlerExitCount[HandlerType.UNIN_OVER] += 1;
        _unionHandlerLog(
            someone_,
            amount_,
            loanAmount_,
            interestRateIndex_,
            threshold_,
            debtAmount_,
            maturityTime_,
            borrowerIndex,
            loanIndex,
            debtIndex
        );
    }

    function unionHandler5(
        address someone_,
        uint128 amount_,
        uint128 loanAmount_,
        uint64 interestRateIndex_,
        uint256 threshold_,
        uint128 debtAmount_,
        uint64 maturityTime_
    ) external {
        vm.assume(!_excludeDuplicateBorrowerJoin(someone_));

        _handlerEnterCount[HandlerType.UNION] += 1;

        uint64 borrowerIndex = _joinHandler(someone_, amount_);
        uint64 loanIndex = _requestHandler(borrowerIndex, loanAmount_, interestRateIndex_, threshold_);
        uint64 debtIndex = _borrowHandler(loanIndex, debtAmount_, maturityTime_);
        _handlerExitCount[HandlerType.UNIN_OVER] += 1;
        _unionHandlerLog(
            someone_,
            amount_,
            loanAmount_,
            interestRateIndex_,
            threshold_,
            debtAmount_,
            maturityTime_,
            borrowerIndex,
            loanIndex,
            debtIndex
        );
    }

    function _excludeDuplicateBorrowerJoin(address someone_) internal view returns (bool isDuplicate) {
        if (someone_ == address(0) || someone_ == _owner || someone_ == _proxyAdmin) {
            return true;
        }
        uint256 totalBorrowers = _timePowerLoan.getTotalTrustedBorrowers();
        isDuplicate = false;
        for (uint256 i = 0; i < totalBorrowers; ++i) {
            TimePowerLoan.TrustedBorrower memory borrowerInfo = _timePowerLoan.getBorrowerInfoAtIndex(uint64(i));
            if (borrowerInfo.borrower == someone_) {
                isDuplicate = true;
                break;
            }
        }
    }

    function _unionHandlerLog(
        address someone_,
        uint128 amount_,
        uint128 loanAmount_,
        uint64 interestRateIndex_,
        uint256 threshold_,
        uint128 debtAmount_,
        uint64 maturityTime_,
        uint64 borrowerIndex_,
        uint64 loanIndex_,
        uint64 debtIndex_
    ) internal view {
        if (vm.envOr("UNION_HANDLER_LOG", false)) {
            console.log(
                string.concat(
                    "UNION:   ",
                    "TIME: ",
                    vm.toString(block.timestamp),
                    " | ",
                    "borrowerIndex: ",
                    vm.toString(borrowerIndex_),
                    " | ",
                    "loanIndex: ",
                    vm.toString(loanIndex_),
                    " | ",
                    "debtIndex: ",
                    vm.toString(debtIndex_),
                    " | ",
                    "calldata: ",
                    vm.toString(
                        abi.encode(
                            someone_, amount_, loanAmount_, interestRateIndex_, threshold_, debtAmount_, maturityTime_
                        )
                    )
                )
            );
        }
    }

    function _joinHandler(address someone_, uint128 amount_) internal returns (uint64 borrowerIndex_) {
        _handlerEnterCount[HandlerType.JOIN] += 1;

        amount_ = uint128(bound(amount_, 2 * (PRECISION + 5) * (PRECISION + 5), type(uint128).max / 100));

        _fundSomeone(someone_, amount_);

        _addWhitelist(someone_);

        vm.prank(someone_);
        borrowerIndex_ = _timePowerLoan.join();

        vm.prank(_owner);
        _timePowerLoan.agree(someone_, amount_ / 2);

        _handlerExitCount[HandlerType.JOIN_OVER] += 1;

        if (vm.envOr("JOIN_HANDLER_LOG", false)) {
            console.log(
                string.concat(
                    "JOIN:    ",
                    "TIME: ",
                    vm.toString(block.timestamp),
                    " | ",
                    "borrowerIndex: ",
                    vm.toString(borrowerIndex_),
                    " | ",
                    "ceilingLimit: ",
                    vm.toString(amount_ / 2)
                )
            );
        }
    }

    function _requestHandler(uint64 borrowerIndex_, uint128 loanAmount_, uint64 interestRateIndex_, uint256 threshold_)
        internal
        returns (uint64 loanIndex_)
    {
        _handlerEnterCount[HandlerType.REQUEST] += 1;

        uint256 totalBorrowers = _timePowerLoan.getTotalTrustedBorrowers();

        if (totalBorrowers == 0) {
            _handlerExitCount[HandlerType.REQUEST_NO_BORROWER] += 1;
            return type(uint64).max;
        }

        borrowerIndex_ = uint64(bound(borrowerIndex_, 0, totalBorrowers - 1));

        TimePowerLoan.TrustedBorrower memory borrowerInfo = _timePowerLoan.getBorrowerInfoAtIndex(borrowerIndex_);

        if (borrowerInfo.ceilingLimit == 0 || borrowerInfo.remainingLimit == 0) {
            _handlerExitCount[HandlerType.REQUEST_NO_LIMIT] += 1;
            return type(uint64).max;
        }

        loanAmount_ = uint128(bound(loanAmount_, PRECISION * PRECISION, borrowerInfo.remainingLimit));

        if (loanAmount_ == 0) {
            _handlerExitCount[HandlerType.REQUEST_NO_AMOUNT] += 1;
            return type(uint64).max;
        }

        interestRateIndex_ = uint64(bound(interestRateIndex_, 0, _secondInterestRates.length - 1));
        threshold_ = bound(threshold_, 1, PRECISION);

        vm.prank(borrowerInfo.borrower);
        loanIndex_ = _timePowerLoan.request(loanAmount_);

        vm.prank(_owner);
        _timePowerLoan.approve(loanIndex_, uint128(loanAmount_ * threshold_ / PRECISION), interestRateIndex_);

        _handlerExitCount[HandlerType.REQUEST_OVER] += 1;

        if (vm.envOr("REQUEST_HANDLER_LOG", false)) {
            console.log(
                string.concat(
                    "REQUEST: ",
                    "TIME: ",
                    vm.toString(block.timestamp),
                    " | ",
                    "borrowerIndex: ",
                    vm.toString(borrowerIndex_),
                    " | ",
                    "loanIndex: ",
                    vm.toString(loanIndex_),
                    " | ",
                    "loanAmount: ",
                    vm.toString(loanAmount_),
                    " | ",
                    "interestRateIndex: ",
                    vm.toString(interestRateIndex_)
                )
            );
        }
    }

    function _borrowHandler(uint64 loanIndex_, uint128 debtAmount_, uint64 maturityTime_)
        internal
        returns (uint64 debtIndex_)
    {
        _handlerEnterCount[HandlerType.BORROW] += 1;

        uint256 totalLoans = _timePowerLoan.getTotalLoans();

        if (totalLoans == 0) {
            _handlerExitCount[HandlerType.BORROW_NO_LOAN] += 1;
            return type(uint64).max;
        }

        loanIndex_ = uint64(bound(loanIndex_, 0, totalLoans - 1));

        TimePowerLoan.LoanInfo memory loanInfo = _timePowerLoan.getLoanInfoAtIndex(loanIndex_);

        if (loanInfo.status != TimePowerLoan.LoanStatus.APPROVED || loanInfo.remainingLimit == 0) {
            _handlerExitCount[HandlerType.BORROW_NO_LIMIT] += 1;
            return type(uint64).max;
        }

        debtAmount_ = uint128(bound(debtAmount_, PRECISION, loanInfo.remainingLimit));

        maturityTime_ = uint64(bound(maturityTime_, 3 days, 360 days));

        TimePowerLoan.TrustedBorrower memory borrowerInfo =
            _timePowerLoan.getBorrowerInfoAtIndex(loanInfo.borrowerIndex);

        vm.prank(borrowerInfo.borrower);
        (, debtIndex_) = _timePowerLoan.borrow(loanIndex_, debtAmount_, uint64(block.timestamp + maturityTime_));

        _handlerExitCount[HandlerType.BORROW_OVER] += 1;

        if (vm.envOr("BORROW_HANDLER_LOG", false)) {
            console.log(
                string.concat(
                    "BORROW:  ",
                    "TIME: ",
                    vm.toString(block.timestamp),
                    " | ",
                    "loanIndex: ",
                    vm.toString(loanIndex_),
                    " | ",
                    "debtIndex: ",
                    vm.toString(debtIndex_),
                    " | ",
                    "borrowAmount: ",
                    vm.toString(debtAmount_),
                    " | ",
                    "maturityDays: ",
                    vm.toString(maturityTime_ / 1 days)
                )
            );
        }
    }

    function repayHandler(uint64 debtIndex_, uint128 repayAmount_, uint256 threshold_) external {
        bytes memory data = abi.encode(debtIndex_, repayAmount_, threshold_);
        _handlerEnterCount[HandlerType.REPAY] += 1;

        uint256 totalDebts = _timePowerLoan.getTotalDebts();

        if (totalDebts == 0) {
            _handlerExitCount[HandlerType.REPAY_NO_DEBT] += 1;
            return;
        }

        debtIndex_ = uint64(bound(debtIndex_, 0, totalDebts - 1));

        TimePowerLoan.DebtInfo memory debtInfo = _timePowerLoan.getDebtInfoAtIndex(debtIndex_);

        if (vm.envOr("REPAY_HANDLER_LOG", false)) {
            console.log(
                string.concat(
                    "REPAY:   ",
                    "TIME: ",
                    vm.toString(block.timestamp),
                    " | ",
                    "debtIndex: ",
                    vm.toString(debtIndex_),
                    " | ",
                    "status: ",
                    vm.toString(uint256(debtInfo.status)),
                    " | ",
                    "normalizedPrincipal: ",
                    vm.toString(debtInfo.normalizedPrincipal)
                )
            );
        }

        if (debtInfo.status != TimePowerLoan.DebtStatus.ACTIVE /*|| debtInfo.normalizedPrincipal == 0 */ ) {
            _handlerExitCount[HandlerType.REPAY_STATUS] += 1;
            return;
        }

        TimePowerLoan.LoanInfo memory loanInfo = _timePowerLoan.getLoanInfoAtIndex(debtInfo.loanIndex);

        _timePowerLoan.pile();

        uint256 accumulatedInterestRate = _timePowerLoan.getAccumulatedInterestRateAtIndex(loanInfo.interestRateIndex);

        uint128 actualDebt =
            uint128(uint256(debtInfo.normalizedPrincipal).mulDiv(accumulatedInterestRate, FIXED18, Math.Rounding.Ceil));

        threshold_ = bound(threshold_, PRECISION / 24, PRECISION);

        repayAmount_ = uint128(bound(repayAmount_, actualDebt * threshold_ / PRECISION, actualDebt));

        TimePowerLoan.TrustedBorrower memory borrowerInfo =
            _timePowerLoan.getBorrowerInfoAtIndex(loanInfo.borrowerIndex);

        vm.prank(borrowerInfo.borrower);
        _depositToken.approve(address(_timePowerLoan), repayAmount_);

        vm.prank(borrowerInfo.borrower);
        _timePowerLoan.repay(debtIndex_, repayAmount_);

        _handlerExitCount[HandlerType.REPAY_OVER] += 1;

        if (vm.envOr("REPAY_HANDLER_LOG", false)) {
            console.log(
                string.concat(
                    "REPAY:   ",
                    "TIME: ",
                    vm.toString(block.timestamp),
                    " | ",
                    "debtIndex: ",
                    vm.toString(debtIndex_),
                    " | ",
                    "debtBeforeRepay: ",
                    vm.toString(actualDebt),
                    " | ",
                    "repayAmount: ",
                    vm.toString(repayAmount_),
                    " | ",
                    "data: ",
                    vm.toString(data)
                )
            );
        }
    }

    function defaultHandler(uint64 debtIndex_, uint64 defaultInterestRateIndex_) external {
        _handlerEnterCount[HandlerType.DEFAULT] += 1;

        uint256 totalDebts = _timePowerLoan.getTotalDebts();

        if (totalDebts == 0) {
            _handlerExitCount[HandlerType.DEFAULT_NO_DEBT] += 1;
            return;
        }

        debtIndex_ = uint64(bound(debtIndex_, 0, totalDebts - 1));

        TimePowerLoan.DebtInfo memory debtInfo = _timePowerLoan.getDebtInfoAtIndex(debtIndex_);

        if (debtInfo.status != TimePowerLoan.DebtStatus.ACTIVE || debtInfo.maturityTime > block.timestamp) {
            _handlerExitCount[HandlerType.DEFAULT_STATUS] += 1;
            return;
        }

        TimePowerLoan.LoanInfo memory loanInfo = _timePowerLoan.getLoanInfoAtIndex(debtInfo.loanIndex);

        TimePowerLoan.TrustedBorrower memory borrowerInfo =
            _timePowerLoan.getBorrowerInfoAtIndex(loanInfo.borrowerIndex);

        defaultInterestRateIndex_ =
            uint64(bound(defaultInterestRateIndex_, loanInfo.interestRateIndex, _secondInterestRates.length - 1));

        vm.prank(_owner);
        _timePowerLoan.defaulted(borrowerInfo.borrower, debtIndex_, defaultInterestRateIndex_);

        _handlerExitCount[HandlerType.DEFAULT_OVER] += 1;

        if (vm.envOr("DEFAULT_HANDLER_LOG", false)) {
            console.log(
                string.concat(
                    "DEFAULT: ",
                    "TIME: ",
                    vm.toString(block.timestamp),
                    " | ",
                    "debtIndex: ",
                    vm.toString(debtIndex_),
                    " | ",
                    "defaultInterestRateIndex: ",
                    vm.toString(defaultInterestRateIndex_)
                )
            );
        }
    }

    function recoveryHandler(uint64 debtIndex_, uint128 recoveryAmount_, uint256 threshold_) external {
        _handlerEnterCount[HandlerType.RECOVERY] += 1;

        uint256 totalDebts = _timePowerLoan.getTotalDebts();

        if (totalDebts == 0) {
            _handlerExitCount[HandlerType.RECOVERY_NO_DEBT] += 1;
            return;
        }

        debtIndex_ = uint64(bound(debtIndex_, 0, totalDebts - 1));

        TimePowerLoan.DebtInfo memory debtInfo = _timePowerLoan.getDebtInfoAtIndex(debtIndex_);

        if (debtInfo.status != TimePowerLoan.DebtStatus.DEFAULTED || debtInfo.maturityTime > block.timestamp) {
            _handlerExitCount[HandlerType.RECOVERY_STATUS] += 1;
            return;
        }

        TimePowerLoan.LoanInfo memory loanInfo = _timePowerLoan.getLoanInfoAtIndex(debtInfo.loanIndex);

        uint256 accumulatedInterestRate = _timePowerLoan.getAccumulatedInterestRateAtIndex(loanInfo.interestRateIndex);

        uint128 actualDebt =
            uint128(uint256(debtInfo.normalizedPrincipal).mulDiv(accumulatedInterestRate, FIXED18, Math.Rounding.Ceil));

        threshold_ = bound(threshold_, 1, PRECISION);

        recoveryAmount_ = uint128(bound(recoveryAmount_, actualDebt * threshold_ / PRECISION, actualDebt));

        TimePowerLoan.TrustedBorrower memory borrowerInfo =
            _timePowerLoan.getBorrowerInfoAtIndex(loanInfo.borrowerIndex);

        vm.prank(borrowerInfo.borrower);
        _depositToken.approve(address(_timePowerLoan), recoveryAmount_);

        vm.prank(_owner);
        _timePowerLoan.recovery(borrowerInfo.borrower, debtIndex_, recoveryAmount_);

        _handlerExitCount[HandlerType.RECOVERY_OVER] += 1;

        if (vm.envOr("RECOVERY_HANDLER_LOG", false)) {
            console.log(
                string.concat(
                    "RECOVERY:",
                    "TIME: ",
                    vm.toString(block.timestamp),
                    " | ",
                    "debtIndex: ",
                    vm.toString(debtIndex_),
                    " | ",
                    "debtBeforeRecovery: ",
                    vm.toString(actualDebt),
                    " | ",
                    "recoveryAmount: ",
                    vm.toString(recoveryAmount_)
                )
            );
        }
    }

    function closeHandler(uint64 debtIndex_) external {
        _handlerEnterCount[HandlerType.CLOSE] += 1;

        uint256 totalDebts = _timePowerLoan.getTotalDebts();

        if (totalDebts == 0) {
            _handlerExitCount[HandlerType.CLOSE_NO_DEBT] += 1;
            return;
        }

        debtIndex_ = uint64(bound(debtIndex_, 0, totalDebts - 1));

        TimePowerLoan.DebtInfo memory debtInfo = _timePowerLoan.getDebtInfoAtIndex(debtIndex_);

        if (debtInfo.status != TimePowerLoan.DebtStatus.DEFAULTED || debtInfo.maturityTime > block.timestamp) {
            _handlerExitCount[HandlerType.CLOSE_STATUS] += 1;
            return;
        }

        TimePowerLoan.LoanInfo memory loanInfo = _timePowerLoan.getLoanInfoAtIndex(debtInfo.loanIndex);
        TimePowerLoan.TrustedBorrower memory borrowerInfo =
            _timePowerLoan.getBorrowerInfoAtIndex(loanInfo.borrowerIndex);

        vm.prank(_owner);
        _timePowerLoan.close(borrowerInfo.borrower, debtIndex_);

        _handlerExitCount[HandlerType.CLOSE_OVER] += 1;

        if (vm.envOr("CLOSE_HANDLER_LOG", false)) {
            console.log(
                string.concat(
                    "CLOSE:   ", "TIME: ", vm.toString(block.timestamp), " | ", "debtIndex: ", vm.toString(debtIndex_)
                )
            );
        }
    }

    function timeHandler() external {
        _handlerEnterCount[HandlerType.TIME] += 1;

        _oneDayPassed();

        _handlerExitCount[HandlerType.TIME_OVER] += 1;

        if (vm.envOr("TIME_HANDLER_LOG", false)) {
            console.log(string.concat("TIME:    ", "newTime: ", vm.toString(uint256(uint64(block.timestamp)))));
        }
    }

    function getTimePowerLoan() external view returns (TimePowerLoan) {
        return _timePowerLoan;
    }

    function getHandlerEnterCount(HandlerType handlerType_) external view returns (uint256) {
        return _handlerEnterCount[handlerType_];
    }

    function getHandlerExitCount(HandlerType handlerType_) external view returns (uint256) {
        return _handlerExitCount[handlerType_];
    }
}
