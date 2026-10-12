// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LiquidityToken} from "../../src/LiquidityToken.sol";

contract LiquidityTokenTest is Test {
    LiquidityToken token;
    address pool = makeAddr("pool");
    address user = makeAddr("user");

    function setUp() public {
        vm.prank(pool);
        token = new LiquidityToken("CPMM LP", "LP");
    }

    function test_onlyOwnerCanMint() public {
        vm.prank(user);
        vm.expectRevert();
        token.mint(user, 1000);

        vm.prank(pool);
        token.mint(user, 1000);
        assertEq(token.balanceOf(user), 1000);
    }

    function test_onlyOwnerCanBurn() public {
        vm.prank(pool);
        token.mint(user, 1000);

        vm.prank(user);
        vm.expectRevert();
        token.burn(user, 500);

        vm.prank(pool);
        token.burn(user, 500);
        assertEq(token.balanceOf(user), 500);
    }
}
