// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Pool} from "../../src/Pool.sol";

contract FuzzMockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract PoolFuzzTest is Test {
    FuzzMockToken token0;
    FuzzMockToken token1;
    Pool pool;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        token0 = new FuzzMockToken("Token0", "TK0");
        token1 = new FuzzMockToken("Token1", "TK1");

        pool = new Pool(address(token0), address(token1));

        vm.prank(alice);
        token0.approve(address(pool), type(uint256).max);
        vm.prank(alice);
        token1.approve(address(pool), type(uint256).max);

        vm.prank(bob);
        token0.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        token1.approve(address(pool), type(uint256).max);
    }

    function testFuzz_addLiquidityInitial(uint128 amount0, uint128 amount1) public {
        // We need sqrt(amount0 * amount1) > 1000, and amounts should not be 0
        vm.assume(amount0 > 1000);
        vm.assume(amount1 > 1000);

        token0.mint(alice, amount0);
        token1.mint(alice, amount1);

        vm.prank(alice);
        pool.addLiquidity(amount0, amount1, 0);

        (uint256 r0, uint256 r1) = pool.getReserves();
        assertEq(r0, amount0);
        assertEq(r1, amount1);
        assertEq(pool.i_lpToken().balanceOf(pool.DEAD_ADDRESS()), 1000);
    }

    function testFuzz_swapIncreasesK(uint96 amountIn) public {
        vm.assume(amountIn > 1000);
        vm.assume(amountIn < 1_000_000 ether);

        uint256 init0 = 10_000_000 ether;
        uint256 init1 = 10_000_000 ether;

        token0.mint(alice, init0);
        token1.mint(alice, init1);

        vm.prank(alice);
        pool.addLiquidity(init0, init1, 0);

        token0.mint(bob, amountIn);

        uint256 kBefore = pool.k();

        vm.prank(bob);
        pool.swap(address(token0), amountIn, 0);

        uint256 kAfter = pool.k();

        // Invariant: k must strictly increase or stay equal (in case of rounding) after swap due to 0.3% fee
        assertTrue(kAfter >= kBefore);
    }
}

