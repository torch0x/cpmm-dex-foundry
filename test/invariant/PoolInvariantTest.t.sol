// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Pool} from "../../src/Pool.sol";
import {Handler, InvariantMockToken} from "./Handler.sol";

contract PoolInvariantTest is StdInvariant, Test {
    Pool pool;
    InvariantMockToken token0;
    InvariantMockToken token1;
    Handler handler;

    function setUp() public {
        token0 = new InvariantMockToken("Token0", "TK0");
        token1 = new InvariantMockToken("Token1", "TK1");

        pool = new Pool(address(token0), address(token1));
        handler = new Handler(pool, token0, token1);

        // Bootstrap pool with initial liquidity
        token0.mint(address(this), 10_000 ether);
        token1.mint(address(this), 10_000 ether);

        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);

        pool.addLiquidity(10_000 ether, 10_000 ether, 0);

        targetContract(address(handler));
    }

    /// @notice Invariant: Token balances of the pool must always be >= stored reserves
    function invariant_solvencyBalancesGteReserves() public view {
        (uint256 r0, uint256 r1) = pool.getReserves();
        assertGe(token0.balanceOf(address(pool)), r0);
        assertGe(token1.balanceOf(address(pool)), r1);
    }

    /// @notice Invariant: Minimum liquidity (1000) locked permanently at DEAD_ADDRESS
    function invariant_minimumLiquidityPermanentlyLocked() public view {
        assertEq(pool.i_lpToken().balanceOf(pool.DEAD_ADDRESS()), pool.MINIMUM_LIQUIDITY());
    }

    /// @notice Invariant: Total LP supply is always >= MINIMUM_LIQUIDITY
    function invariant_totalSupplyGteMinimum() public view {
        assertGe(pool.i_lpToken().totalSupply(), pool.MINIMUM_LIQUIDITY());
    }
}

