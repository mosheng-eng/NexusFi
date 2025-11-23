// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {DeployContractSuit} from "script/DeployContractSuit.s.sol";
import {IWhitelist} from "src/whitelist/IWhitelist.sol";
import {Whitelist} from "src/whitelist/Whitelist.sol";
import {Roles} from "src/common/Roles.sol";
import {Errors} from "src/common/Errors.sol";

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract WhitelistTest is Test {
    DeployContractSuit internal _deployer = new DeployContractSuit();
    Whitelist internal _whitelist;

    address internal _owner = makeAddr("owner");
    address internal _whitelistedUser1 = makeAddr("whitelistedUser1");
    address internal _whitelistedUser2 = makeAddr("whitelistedUser2");
    address internal _nonWhitelistedUser1 = makeAddr("nonWhitelistedUser1");
    address internal _nonWhitelistedUser2 = makeAddr("nonWhitelistedUser2");

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

    function setUp() public deployWhitelist {
        vm.label(_owner, "owner");
    }

    function testEnableAndDisableWhitelist() public {
        // Initially enabled
        assertTrue(_whitelist.whitelistEnabled());

        // Disable whitelist
        vm.prank(_owner);
        _whitelist.disable();
        assertFalse(_whitelist.whitelistEnabled());

        // Enable whitelist
        vm.prank(_owner);
        _whitelist.enable();
        assertTrue(_whitelist.whitelistEnabled());
    }

    function testAddAndRemoveAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "addr"));
        vm.prank(_owner);
        _whitelist.add(address(0x0));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "addr"));
        vm.prank(_owner);
        _whitelist.remove(address(0x0));

        address addr = address(0x1234);
        assertFalse(_whitelist.isWhitelisted(addr));

        vm.prank(_owner);
        _whitelist.add(addr);
        assertTrue(_whitelist.isWhitelisted(addr));

        vm.prank(_owner);
        _whitelist.remove(addr);
        assertFalse(_whitelist.isWhitelisted(addr));
    }

    function testInvalidInitialize() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "owner"));
        _deployer.deployWhitelist(address(0x0), true);
    }

    function testModifierOnlyWhitelisted() public {
        MockContractUsingWhitelist mockContract = MockContractUsingWhitelist(
            address(
                new TransparentUpgradeableProxy(
                    address(new MockContractUsingWhitelist()),
                    _owner,
                    abi.encodeWithSelector(Whitelist.initialize.selector, _owner, true)
                )
            )
        );

        vm.startPrank(_owner);
        mockContract.grantRole(Roles.OPERATOR_ROLE, _owner);
        mockContract.add(_whitelistedUser1);
        mockContract.add(_whitelistedUser2);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IWhitelist.NotWhitelisted.selector, _nonWhitelistedUser1));
        vm.prank(_nonWhitelistedUser1);
        mockContract.testMockFunction();

        vm.prank(_whitelistedUser1);
        mockContract.testMockFunction();
    }

    function testNondirectCallToWhitelist() public {
        MockContractUsingWhitelist mockContract = new MockContractUsingWhitelist();
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        mockContract.initialize(address(this), true);
    }
}

contract MockContractUsingWhitelist is Whitelist {
    function testMockFunction() external view onlyWhitelisted(msg.sender) {}
}
