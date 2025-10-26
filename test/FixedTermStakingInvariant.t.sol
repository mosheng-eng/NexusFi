// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {FixedTermStakingHandler} from "test/handler/FixedTermStakingHandler.sol";

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract FixedTermStakingInvariant is Test {
    FixedTermStakingHandler internal _fixedTermStakingHandler;

    uint64 internal _currentTime;

    function setUp() public {
        _fixedTermStakingHandler = new FixedTermStakingHandler();
        _currentTime = _fixedTermStakingHandler.getCurrentTime();
        bytes4[] memory targetSelectors = new bytes4[](1);
        targetSelectors[0] = FixedTermStakingHandler.stake.selector;
        targetSelector(StdInvariant.FuzzSelector({addr: address(_fixedTermStakingHandler), selectors: targetSelectors}));
        targetContract(address(_fixedTermStakingHandler));
    }

    function invariantTotalAssetValueEqualsTotalPrincipalPlusInterest() public {
        for (uint256 i = 0; i < 365; ++i) {
            _currentTime = _currentTime + 1 days;
            vm.warp(_currentTime + 1 minutes);
            _randomPriceFloating();
            if (_fixedTermStakingHandler.getFixedTermStaking().feed(_currentTime)) {
                assertEq(
                    uint256(
                        uint128(
                            int128(_fixedTermStakingHandler.getFixedTermStaking()._totalPrincipal())
                                + _fixedTermStakingHandler.getFixedTermStaking()._totalInterest()
                        )
                    ),
                    _fixedTermStakingHandler.getFixedTermStaking().getTotalAssetValueInBasket()
                );
            }
        }

        /// @dev snapshot before unstake
        _snapshot();

        /// @dev unstake all tokens
        unstakeAllFixedTermTokens();

        /// @dev snapshot after unstake
        _snapshot();
    }

    function unstakeAllFixedTermTokens() public {
        uint256 totalSupply = _fixedTermStakingHandler.getFixedTermStaking().totalSupply();
        for (uint256 tokenId = 1; tokenId <= totalSupply; ++tokenId) {
            vm.startPrank(_fixedTermStakingHandler.getFixedTermStaking().ownerOf(tokenId));
            _fixedTermStakingHandler.getFixedTermStaking().approve(
                address(_fixedTermStakingHandler.getFixedTermStaking()), tokenId
            );
            _fixedTermStakingHandler.getFixedTermStaking().unstake(tokenId);
            vm.stopPrank();
        }
    }

    function _snapshot() internal view {
        console.log("----- Invariant State -----");
        console.log("Block Time:", block.timestamp);
        console.log("Token ID Counter:", _fixedTermStakingHandler.getFixedTermStaking().totalSupply());
        console.log("Total Principal:", _fixedTermStakingHandler.getFixedTermStaking()._totalPrincipal());
        console.log("Total Interest:", _fixedTermStakingHandler.getFixedTermStaking()._totalInterest());
        console.log("Total Fee:", _fixedTermStakingHandler.getFixedTermStaking()._totalFee());
        console.log("Total Asset Value:", _fixedTermStakingHandler.getFixedTermStaking().getTotalAssetValueInBasket());
    }

    function _randomPriceFloating() internal {
        for (uint256 i = 0; i < _fixedTermStakingHandler.getAssetsNumInBasket(); ++i) {
            _fixedTermStakingHandler.getDepositToken().transfer(
                _fixedTermStakingHandler.getAssetInfoInBasket(i).targetVault,
                _randomUint256() % 70_000
                    * IERC4626(_fixedTermStakingHandler.getAssetInfoInBasket(i).targetVault).totalAssets() / 1_000_000 / 365
            );
        }
    }

    function _randomUint256() internal returns (uint256 randomWord) {
        string[] memory command = new string[](4);
        command[0] = "openssl";
        command[1] = "rand";
        command[2] = "-hex";
        command[3] = "32";

        randomWord = uint256(bytes32(vm.ffi(command)));
    }
}
