// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {DeployContractSuit} from "script/DeployContractSuit.s.sol";
import {FixedTermStaking} from "src/protocols/fixed-term/FixedTermStaking.sol";
import {UnderlyingToken} from "src/underlying/UnderlyingToken.sol";
import {Whitelist} from "src/whitelist/Whitelist.sol";
import {FixedTermStaking} from "src/protocols/fixed-term/FixedTermStaking.sol";
import {UnderlyingTokenExchanger} from "src/underlying/UnderlyingTokenExchanger.sol";
import {Roles} from "src/common/Roles.sol";
import {Errors} from "src/common/Errors.sol";

import {AssetVault} from "test/mock/AssetVault.sol";
import {DepositAsset} from "test/mock/DepositAsset.sol";

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FixedTermStakingHandler is StdCheats, StdUtils, StdAssertions, CommonBase {
    DeployContractSuit internal _deployer = new DeployContractSuit();
    FixedTermStaking internal _fixedTermStaking;
    UnderlyingToken internal _underlyingToken;
    Whitelist internal _whitelist;
    FixedTermStaking.AssetInfo[] internal _assetsInfoBasket;
    DepositAsset internal _depositToken;
    UnderlyingTokenExchanger internal _exchanger;

    uint64 internal _lockPeriod = 365 days;
    uint64 internal _stakeFeeRate = 1_000; // in base points, 0.1%
    uint64 internal _unstakeFeeRate = 1_000; // in base points, 0.2%
    uint64 internal _startFeedTime = 1759301999; // 2025-10-01 14:59:59 UTC+8
    uint64 internal _currentTime = _startFeedTime - 1 days; // 2025-09-30 14:59:59 UTC+8
    uint128 internal _dustBalance = 1_000 * 10 ** 6; // 1,000 USDC
    uint128 internal _maxSupply = 1_000_000_000_000 * 10 ** 6; // 1000 billion USDC

    constructor() {
        _timeBegin();
        _deployUnderlyingToken();
        _deployWhitelist();
        _deployDepositToken();
        _deployExchanger();
        _deployFixedTermStaking();
        _setContractDependencies();
        _oneDayPassed();
    }

    function getFixedTermStaking() external view returns (FixedTermStaking) {
        return _fixedTermStaking;
    }

    function getDepositToken() external view returns (DepositAsset) {
        return _depositToken;
    }

    function getAssetsNumInBasket() external view returns (uint256) {
        return _assetsInfoBasket.length;
    }

    function getAssetInfoInBasket(uint256 index_) external view returns (FixedTermStaking.AssetInfo memory) {
        return _assetsInfoBasket[index_];
    }

    function getCurrentTime() external view returns (uint64) {
        return _currentTime;
    }

    function _timeBegin() internal {
        vm.warp(_currentTime);
    }

    function _oneDayPassed() internal {
        vm.warp(_currentTime += 1 days);
    }

    function _deployUnderlyingToken() internal {
        _underlyingToken = UnderlyingToken(_deployer.deployUnderlyingToken(address(this), "lbUSD", "lbUSD"));

        _underlyingToken.grantRole(Roles.OPERATOR_ROLE, address(this));

        vm.label(address(_underlyingToken), "lbUSD");
    }

    function _deployWhitelist() internal {
        _whitelist = Whitelist(_deployer.deployWhitelist(address(this), true));

        _whitelist.grantRole(Roles.OPERATOR_ROLE, address(this));

        vm.label(address(_whitelist), "Whitelist");
    }

    function _deployDepositToken() internal {
        _depositToken = new DepositAsset("USD Coin", "USDC");

        _depositToken.mint(msg.sender, 1_000_000_000_000_000 * 10 ** 6);

        vm.label(address(_depositToken), "USDC");
    }

    function _deployFixedTermStaking() internal {
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

        _fixedTermStaking = FixedTermStaking(
            _deployer.deployFixedTermStaking(
                [address(this), address(_underlyingToken), address(_whitelist), address(_exchanger)],
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

        vm.label(address(_fixedTermStaking), "lbUSD12M+");
        vm.label(address(_assetsInfoBasket[0].targetVault), "MMF@lbUSD");
        vm.label(address(_assetsInfoBasket[1].targetVault), "RWA@lbUSD");
    }

    function _deployExchanger() internal {
        address[4] memory addrs =
            [address(_underlyingToken), address(_depositToken), address(_whitelist), address(this)];
        uint256 properties = (uint256(1e6) | (uint256(1e6) << 64) | (uint256(1e6) << 128));

        _exchanger = UnderlyingTokenExchanger(_deployer.deployExchanger(addrs, properties));

        _exchanger.grantRole(Roles.OPERATOR_ROLE, address(this));

        vm.label(address(_exchanger), "Exchanger");
    }

    function _setContractDependencies() internal {
        _underlyingToken.grantRole(Roles.OPERATOR_ROLE, address(_fixedTermStaking));
        _underlyingToken.grantRole(Roles.OPERATOR_ROLE, address(_exchanger));

        _exchanger.grantRole(Roles.INVESTMENT_MANAGER_ROLE, address(_fixedTermStaking));
    }

    function stake(address user_, uint128 amountToStake_) external {
        vm.assume(user_ != address(0x0) && user_.code.length == 0);
        amountToStake_ = uint128(bound(amountToStake_, 10 ** 6, 9_000_000 * 10 ** 6));

        _fundUser(user_, amountToStake_);
        _whitelistUser(user_);
        _stake(user_, amountToStake_);
    }

    function _fundUser(address user_, uint128 amount_) internal {
        _depositToken.mint(user_, amount_);
    }

    function _whitelistUser(address user_) internal {
        _whitelist.add(user_);
    }

    function _stake(address user_, uint128 amountToStake_) internal {
        vm.label(user_, "FuzzStaker");

        vm.startPrank(user_);

        _depositToken.approve(address(_exchanger), amountToStake_);
        _exchanger.exchange(amountToStake_, true);
        assertEq(_depositToken.balanceOf(user_), 0);
        assertEq(_underlyingToken.balanceOf(user_), uint256(amountToStake_));

        uint256 userBalanceBeforeStake = _underlyingToken.balanceOf(user_);
        assertEq(userBalanceBeforeStake, amountToStake_);

        _underlyingToken.approve(address(_fixedTermStaking), uint256(amountToStake_));
        _fixedTermStaking.stake(amountToStake_);

        uint256 userBalanceAfterStake = _underlyingToken.balanceOf(user_);
        uint256 stakingProtocolBalanceAfterStake = _underlyingToken.balanceOf(address(_fixedTermStaking));
        uint256 totalAssetValueInBasket = _fixedTermStaking.getTotalAssetValueInBasket();
        uint256 totalFee = _fixedTermStaking._totalFee();
        uint256 totalPrincipal = _fixedTermStaking._totalPrincipal();
        assertEq(userBalanceAfterStake, 0);
        assertEq(stakingProtocolBalanceAfterStake, totalFee + totalPrincipal);
        assertLe(
            totalAssetValueInBasket > totalPrincipal
                ? totalAssetValueInBasket - totalPrincipal
                : totalPrincipal - totalAssetValueInBasket,
            1000
        );

        vm.stopPrank();
    }
}
