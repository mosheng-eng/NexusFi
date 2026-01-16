// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {DeployContractSuit} from "script/DeployContractSuit.s.sol";
import {IBlacklist} from "src/blacklist/IBlacklist.sol";
import {Blacklist} from "src/blacklist/Blacklist.sol";
import {Roles} from "src/common/Roles.sol";
import {Errors} from "src/common/Errors.sol";

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract BlacklistTest is Test {
    DeployContractSuit internal _deployer = new DeployContractSuit();
    Blacklist internal _blacklist;

    address internal _owner = makeAddr("owner");
    address internal _blacklistedUser1 = makeAddr("blacklistedUser1");
    address internal _blacklistedUser2 = makeAddr("blacklistedUser2");
    address internal _nonBlacklistedUser1 = makeAddr("nonBlacklistedUser1");
    address internal _nonBlacklistedUser2 = makeAddr("nonBlacklistedUser2");

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
        vm.label(_nonBlacklistedUser1, "nonBlacklistedUser1");
        vm.label(_nonBlacklistedUser2, "nonBlacklistedUser2");

        _;
    }

    function setUp() public deployBlacklist {
        vm.label(_owner, "owner");
    }

    function testEnableAndDisableBlacklist() public {
        // Initially enabled
        assertTrue(_blacklist.blacklistEnabled());

        // Disable blacklist
        vm.prank(_owner);
        _blacklist.disable();
        assertFalse(_blacklist.blacklistEnabled());

        // Enable blacklist
        vm.prank(_owner);
        _blacklist.enable();
        assertTrue(_blacklist.blacklistEnabled());
    }

    function testAddAndRemoveAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "addr"));
        vm.prank(_owner);
        _blacklist.add(address(0x0));

        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "addr"));
        vm.prank(_owner);
        _blacklist.remove(address(0x0));

        address addr = address(0x1234);
        assertFalse(_blacklist.isBlacklisted(addr));

        vm.prank(_owner);
        _blacklist.add(addr);
        assertTrue(_blacklist.isBlacklisted(addr));

        vm.prank(_owner);
        _blacklist.remove(addr);
        assertFalse(_blacklist.isBlacklisted(addr));
    }

    function testInvalidInitialize() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "owner"));
        _deployer.deployBlacklist(address(0x0), true);
    }

    function testModifierOnlyNotBlacklisted() public {
        MockContractUsingBlacklist mockContract = MockContractUsingBlacklist(
            address(
                new TransparentUpgradeableProxy(
                    address(new MockContractUsingBlacklist()),
                    _owner,
                    abi.encodeWithSelector(Blacklist.initialize.selector, _owner, true)
                )
            )
        );

        vm.startPrank(_owner);
        mockContract.grantRole(Roles.OPERATOR_ROLE, _owner);
        mockContract.add(_blacklistedUser1);
        mockContract.add(_blacklistedUser2);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IBlacklist.Blacklisted.selector, _blacklistedUser1));
        vm.prank(_blacklistedUser1);
        mockContract.testMockFunction();

        vm.prank(_nonBlacklistedUser1);
        mockContract.testMockFunction();
    }

    function testNondirectCallToBlacklist() public {
        MockContractUsingBlacklist mockContract = new MockContractUsingBlacklist();
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        mockContract.initialize(address(this), true);
    }
}

contract MockContractUsingBlacklist is Blacklist {
    function testMockFunction() external view onlyNotBlacklisted(msg.sender) {}
}
