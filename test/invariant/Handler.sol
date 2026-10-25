// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Pool} from "../../src/Pool.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract InvariantMockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract Handler is Test {
    Pool public pool;
    InvariantMockToken public token0;
    InvariantMockToken public token1;

    address public currentActor;
    address[] public actors;

    constructor(Pool _pool, InvariantMockToken _token0, InvariantMockToken _token1) {
        pool = _pool;
        token0 = _token0;
        token1 = _token1;

        actors.push(makeAddr("actor1"));
        actors.push(makeAddr("actor2"));
        actors.push(makeAddr("actor3"));

        for (uint256 i = 0; i < actors.length; i++) {
            token0.mint(actors[i], 1_000_000 ether);
            token1.mint(actors[i], 1_000_000 ether);

            vm.prank(actors[i]);
            token0.approve(address(pool), type(uint256).max);
            vm.prank(actors[i]);
            token1.approve(address(pool), type(uint256).max);
        }
    }

    function addLiquidity(uint256 actorSeed, uint256 amount0, uint256 amount1) public {
        currentActor = actors[actorSeed % actors.length];
        (uint256 r0, uint256 r1) = pool.getReserves();

        if (r0 == 0 || r1 == 0) {
            amount0 = bound(amount0, 1001, 100_000 ether);
            amount1 = bound(amount1, 1001, 100_000 ether);
        } else {
            // For subsequent deposits, bind amount0 and compute proportional amount1
            amount0 = bound(amount0, 1 ether, 10_000 ether);
            amount1 = pool.quote(amount0, r0, r1);
            if (amount1 == 0) return;
        }

        token0.mint(currentActor, amount0);
        token1.mint(currentActor, amount1);

        vm.prank(currentActor);
        try pool.addLiquidity(amount0, amount1, 0) {} catch {}
    }

    function removeLiquidity(uint256 actorSeed, uint256 lpAmount) public {
        currentActor = actors[actorSeed % actors.length];
        uint256 balance = pool.i_lpToken().balanceOf(currentActor);
        if (balance == 0) return;

        lpAmount = bound(lpAmount, 1, balance);

        vm.prank(currentActor);
        try pool.removeLiquidity(lpAmount, 0, 0) {} catch {}
    }

    function swapToken0(uint256 actorSeed, uint256 amountIn) public {
        currentActor = actors[actorSeed % actors.length];
        (uint256 r0, uint256 r1) = pool.getReserves();
        if (r0 == 0 || r1 == 0) return;

        amountIn = bound(amountIn, 1, 10_000 ether);
        token0.mint(currentActor, amountIn);

        vm.prank(currentActor);
        try pool.swap(address(token0), amountIn, 0) {} catch {}
    }

    function swapToken1(uint256 actorSeed, uint256 amountIn) public {
        currentActor = actors[actorSeed % actors.length];
        (uint256 r0, uint256 r1) = pool.getReserves();
        if (r0 == 0 || r1 == 0) return;

        amountIn = bound(amountIn, 1, 10_000 ether);
        token1.mint(currentActor, amountIn);

        vm.prank(currentActor);
        try pool.swap(address(token1), amountIn, 0) {} catch {}
    }
}

