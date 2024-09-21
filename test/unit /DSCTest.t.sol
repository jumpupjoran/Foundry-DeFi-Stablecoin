// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralisedStableCoin} from "src/DecentralisedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract DSCTest is Test {
    DecentralisedStableCoin dsc;
    address public USER = makeAddr("user");
    uint256 public constant AMOUNT = 100;
    address owner;

    function setUp() public {
        dsc = new DecentralisedStableCoin();
        owner = dsc.owner();
    }

    /////////////////////
    //////Mint Tests/////
    /////////////////////
    function testMustMintMoreThanZero() public {
        vm.prank(dsc.owner());
        vm.expectRevert();
        dsc.mint(address(this), 0);
    }

    function testOnlyOwnerCanMint() public {
        vm.prank(USER);
        vm.expectRevert();
        dsc.mint(USER, AMOUNT);
    }

    function testCannotMintToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStableCoin__MintToZeroAddress.selector);
        dsc.mint(address(0), AMOUNT);
    }
    /////////////////////
    //////burn Tests/////
    /////////////////////

    function testOwnerCanBurn() public {
        vm.startPrank(owner);
        dsc.mint(owner, AMOUNT);
        assertEq(dsc.balanceOf(owner), AMOUNT);
        dsc.burn(AMOUNT);
        assertEq(dsc.balanceOf(owner), 0);
        vm.stopPrank();
    }

    function testNotOwnerCannotBurn() public {
        vm.prank(owner);
        dsc.mint(USER, AMOUNT);
        vm.prank(USER);
        vm.expectRevert();
        dsc.burn(AMOUNT);
    }

    function testCannotBurnMoreThanYouHave() public {
        vm.startPrank(owner);
        dsc.mint(owner, AMOUNT);
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStableCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(AMOUNT + 1);
    }
}
