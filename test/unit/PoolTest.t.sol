// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    Pool,
    Pool__ZeroAmounts,
    Pool__ZeroAddress,
    Pool__InvalidToken,
    Pool__InsufficientLiquidityMinted,
    Pool__InsufficientInitialLiquidity,
    Pool__InsufficientLiquidityBurned,
    Pool__InsufficientOutputAmount,
    Pool__InsufficientInputAmount,
    Pool__InsufficientLiquidity
} from "../../src/Pool.sol";

contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract PoolTest is Test {
    MockToken token0;
    MockToken token1;
    Pool pool;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    uint256 constant INITIAL_BALANCE = 1_000_000 ether;

    function setUp() public {
        token0 = new MockToken("Token0", "TK0");
        token1 = new MockToken("Token1", "TK1");

        pool = new Pool(address(token0), address(token1));

        token0.mint(alice, INITIAL_BALANCE);
        token1.mint(alice, INITIAL_BALANCE);

        token0.mint(bob, INITIAL_BALANCE);
        token1.mint(bob, INITIAL_BALANCE);

        vm.prank(alice);
        token0.approve(address(pool), type(uint256).max);
        vm.prank(alice);
        token1.approve(address(pool), type(uint256).max);

        vm.prank(bob);
        token0.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        token1.approve(address(pool), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructorRevertZeroAddress() public {
        vm.expectRevert(Pool__ZeroAddress.selector);
        new Pool(address(0), address(token1));

        vm.expectRevert(Pool__ZeroAddress.selector);
        new Pool(address(token0), address(0));
    }

    function test_constructorRevertIdenticalTokens() public {
        vm.expectRevert(Pool__InvalidToken.selector);
        new Pool(address(token0), address(token0));
    }

    function test_constructorInitializesCorrectly() public view {
        assertEq(address(pool.i_token0()), address(token0));
        assertEq(address(pool.i_token1()), address(token1));
        assertTrue(address(pool.i_lpToken()) != address(0));
    }

    /*//////////////////////////////////////////////////////////////
                          ADD LIQUIDITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_addLiquidityRevertZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(Pool__ZeroAmounts.selector);
        pool.addLiquidity(0, 100 ether, 0);

        vm.prank(alice);
        vm.expectRevert(Pool__ZeroAmounts.selector);
        pool.addLiquidity(100 ether, 0, 0);
    }

    function test_addLiquidityRevertInsufficientInitialLiquidity() public {
        vm.prank(alice);
        // sqrt(1000 * 1000) = 1000 <= MINIMUM_LIQUIDITY (1000)
        vm.expectRevert(Pool__InsufficientInitialLiquidity.selector);
        pool.addLiquidity(1000, 1000, 0);
    }

    function test_addLiquidityInitialSuccess() public {
        uint256 amount0 = 10 ether;
        uint256 amount1 = 40 ether;
        // sqrt(10e18 * 40e18) = 20e18
        uint256 expectedLiquidity = 20 ether - pool.MINIMUM_LIQUIDITY();

        vm.prank(alice);
        uint256 liquidity = pool.addLiquidity(amount0, amount1, 0);

        assertEq(liquidity, expectedLiquidity);
        assertEq(pool.i_lpToken().balanceOf(alice), expectedLiquidity);
        assertEq(pool.i_lpToken().balanceOf(pool.DEAD_ADDRESS()), pool.MINIMUM_LIQUIDITY());
        assertEq(pool.i_lpToken().totalSupply(), 20 ether);

        (uint256 r0, uint256 r1) = pool.getReserves();
        assertEq(r0, amount0);
        assertEq(r1, amount1);
        assertEq(token0.balanceOf(address(pool)), amount0);
        assertEq(token1.balanceOf(address(pool)), amount1);
    }

    function test_addLiquiditySubsequent() public {
        // Alice deposits first
        vm.prank(alice);
        pool.addLiquidity(100 ether, 100 ether, 0);

        uint256 totalLpBefore = pool.i_lpToken().totalSupply();

        // Bob deposits matching proportion: 50 ether of each
        vm.prank(bob);
        uint256 bobLiquidity = pool.addLiquidity(50 ether, 50 ether, 0);

        // Expected bob LP = min((50 * totalLpBefore)/100, (50 * totalLpBefore)/100) = totalLpBefore / 2
        assertEq(bobLiquidity, totalLpBefore / 2);
        assertEq(pool.i_lpToken().balanceOf(bob), bobLiquidity);

        (uint256 r0, uint256 r1) = pool.getReserves();
        assertEq(r0, 150 ether);
        assertEq(r1, 150 ether);
    }

    function test_addLiquidityRevertSlippage() public {
        vm.prank(alice);
        // Expecting more than will be minted
        vm.expectRevert(abi.encodeWithSelector(Pool__InsufficientLiquidityMinted.selector, 20 ether - 1000, 25 ether));
        pool.addLiquidity(10 ether, 40 ether, 25 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        REMOVE LIQUIDITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_removeLiquidityRevertZeroAmount() public {
        vm.prank(alice);
        pool.addLiquidity(100 ether, 100 ether, 0);

        vm.prank(alice);
        vm.expectRevert(Pool__ZeroAmounts.selector);
        pool.removeLiquidity(0, 0, 0);
    }

    function test_removeLiquidityRevertZeroAddress() public {
        vm.prank(alice);
        pool.addLiquidity(100 ether, 100 ether, 0);

        vm.prank(alice);
        vm.expectRevert(Pool__ZeroAddress.selector);
        pool.removeLiquidity(10 ether, 0, 0, address(0));
    }

    function test_removeLiquiditySuccess() public {
        vm.prank(alice);
        uint256 lpAlice = pool.addLiquidity(100 ether, 100 ether, 0);

        uint256 aliceToken0Before = token0.balanceOf(alice);
        uint256 aliceToken1Before = token1.balanceOf(alice);

        // Remove half of Alice's liquidity
        uint256 lpToRemove = lpAlice / 2;

        vm.prank(alice);
        (uint256 out0, uint256 out1) = pool.removeLiquidity(lpToRemove, 0, 0);

        assertTrue(out0 > 0);
        assertTrue(out1 > 0);
        assertEq(token0.balanceOf(alice), aliceToken0Before + out0);
        assertEq(token1.balanceOf(alice), aliceToken1Before + out1);
        assertEq(pool.i_lpToken().balanceOf(alice), lpAlice - lpToRemove);
    }

    function test_removeLiquidityOverload() public {
        vm.prank(alice);
        uint256 lpAlice = pool.addLiquidity(100 ether, 100 ether, 0);

        uint256 aliceToken0Before = token0.balanceOf(alice);
        uint256 aliceToken1Before = token1.balanceOf(alice);

        vm.prank(alice);
        // Calls the 3-arg overload without 'to' parameter
        (uint256 out0, uint256 out1) = pool.removeLiquidity(lpAlice / 4, 0, 0);

        assertTrue(out0 > 0);
        assertTrue(out1 > 0);
        assertEq(token0.balanceOf(alice), aliceToken0Before + out0);
        assertEq(token1.balanceOf(alice), aliceToken1Before + out1);
    }

    function test_removeLiquidityRevertInsufficientLiquidityBurned() public {
        vm.prank(alice);
        pool.addLiquidity(1000 ether, 9000 ether, 0);

        vm.prank(alice);
        vm.expectRevert(Pool__InsufficientLiquidityBurned.selector);
        // (1 * 1000 ether) / 3000 ether = 0
        pool.removeLiquidity(1, 0, 0);
    }

    function test_removeLiquidityRevertSlippage() public {
        vm.prank(alice);
        uint256 lpAlice = pool.addLiquidity(100 ether, 100 ether, 0);

        vm.prank(alice);
        vm.expectRevert();
        pool.removeLiquidity(lpAlice / 2, 60 ether, 60 ether);
    }

    function test_removeLiquidityRevertSlippageAmount1() public {
        vm.prank(alice);
        uint256 lpAlice = pool.addLiquidity(100 ether, 100 ether, 0);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Pool__InsufficientOutputAmount.selector, 50 ether - 500, 60 ether)
        );
        // minAmount0 is satisfied (0), but minAmount1 is not (60 ether > ~50 ether)
        pool.removeLiquidity(lpAlice / 2, 0, 60 ether);
    }

    /*//////////////////////////////////////////////////////////////
                             PRICING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getAmountOut() public view {
        // Pool: 100 token0, 100 token1. Swap 10 token0.
        uint256 expected = (uint256(10 ether) * 997 * 100 ether) / (uint256(100 ether) * 1000 + 10 ether * 997);
        uint256 out = pool.getAmountOut(10 ether, 100 ether, 100 ether);
        assertEq(out, expected);
    }

    function test_getAmountOutRevertZeroInput() public {
        vm.expectRevert(Pool__InsufficientInputAmount.selector);
        pool.getAmountOut(0, 100 ether, 100 ether);
    }

    function test_getAmountOutRevertZeroReserves() public {
        vm.expectRevert(Pool__InsufficientLiquidity.selector);
        pool.getAmountOut(10 ether, 0, 100 ether);

        vm.expectRevert(Pool__InsufficientLiquidity.selector);
        pool.getAmountOut(10 ether, 100 ether, 0);
    }

    function test_getAmountIn() public view {
        uint256 out = pool.getAmountOut(10 ether, 100 ether, 100 ether);
        uint256 calculatedIn = pool.getAmountIn(out, 100 ether, 100 ether);

        // calculatedIn should be approximately 10 ether (with rounding +1)
        assertApproxEqAbs(calculatedIn, 10 ether, 2);
    }

    function test_getAmountInRevertZeroOutput() public {
        vm.expectRevert(
            abi.encodeWithSelector(Pool__InsufficientOutputAmount.selector, 0, 1)
        );
        pool.getAmountIn(0, 100 ether, 100 ether);
    }

    function test_getAmountInRevertInsufficientLiquidity() public {
        vm.expectRevert(Pool__InsufficientLiquidity.selector);
        pool.getAmountIn(10 ether, 0, 100 ether);

        vm.expectRevert(Pool__InsufficientLiquidity.selector);
        pool.getAmountIn(10 ether, 100 ether, 0);

        // amountOut >= reserveOut
        vm.expectRevert(Pool__InsufficientLiquidity.selector);
        pool.getAmountIn(100 ether, 100 ether, 100 ether);

        vm.expectRevert(Pool__InsufficientLiquidity.selector);
        pool.getAmountIn(101 ether, 100 ether, 100 ether);
    }

    function test_quote() public view {
        uint256 quoteOut = pool.quote(10 ether, 100 ether, 200 ether);
        assertEq(quoteOut, 20 ether);
    }

    function test_quoteRevertZeroInput() public {
        vm.expectRevert(Pool__InsufficientInputAmount.selector);
        pool.quote(0, 100 ether, 100 ether);
    }

    function test_quoteRevertZeroReserves() public {
        vm.expectRevert(Pool__InsufficientLiquidity.selector);
        pool.quote(10 ether, 0, 100 ether);

        vm.expectRevert(Pool__InsufficientLiquidity.selector);
        pool.quote(10 ether, 100 ether, 0);
    }

    /*//////////////////////////////////////////////////////////////
                              SWAP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_swapRevertZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(Pool__ZeroAmounts.selector);
        pool.swap(address(token0), 0, 0);
    }

    function test_swapRevertZeroAddress() public {
        vm.prank(alice);
        pool.addLiquidity(100 ether, 100 ether, 0);

        vm.prank(bob);
        vm.expectRevert(Pool__ZeroAddress.selector);
        pool.swap(address(token0), 10 ether, 0, address(0));
    }

    function test_swapOverload() public {
        vm.prank(alice);
        pool.addLiquidity(100 ether, 100 ether, 0);

        uint256 amountIn = 10 ether;
        uint256 expectedOut = pool.getAmountOut(amountIn, 100 ether, 100 ether);

        uint256 bobToken1Before = token1.balanceOf(bob);

        vm.prank(bob);
        // Calls the 3-arg overload without 'to' parameter
        uint256 actualOut = pool.swap(address(token0), amountIn, expectedOut);

        assertEq(actualOut, expectedOut);
        assertEq(token1.balanceOf(bob), bobToken1Before + actualOut);
    }

    function test_swapRevertInvalidToken() public {
        vm.prank(alice);
        vm.expectRevert(Pool__InvalidToken.selector);
        pool.swap(address(0x123), 10 ether, 0);
    }

    function test_swapToken0ForToken1() public {
        vm.prank(alice);
        pool.addLiquidity(100 ether, 100 ether, 0);

        uint256 bobToken0Before = token0.balanceOf(bob);
        uint256 bobToken1Before = token1.balanceOf(bob);

        uint256 amountIn = 10 ether;
        uint256 expectedOut = pool.getAmountOut(amountIn, 100 ether, 100 ether);

        uint256 kBefore = pool.k();

        vm.prank(bob);
        uint256 actualOut = pool.swap(address(token0), amountIn, expectedOut);

        assertEq(actualOut, expectedOut);
        assertEq(token0.balanceOf(bob), bobToken0Before - amountIn);
        assertEq(token1.balanceOf(bob), bobToken1Before + actualOut);

        (uint256 r0, uint256 r1) = pool.getReserves();
        assertEq(r0, 100 ether + amountIn);
        assertEq(r1, 100 ether - actualOut);

        // Due to 0.3% fee, k must increase!
        uint256 kAfter = pool.k();
        assertTrue(kAfter > kBefore);
    }

    function test_swapToken1ForToken0() public {
        vm.prank(alice);
        pool.addLiquidity(100 ether, 100 ether, 0);

        uint256 amountIn = 10 ether;
        uint256 expectedOut = pool.getAmountOut(amountIn, 100 ether, 100 ether);

        vm.prank(bob);
        uint256 actualOut = pool.swap(address(token1), amountIn, expectedOut);

        assertEq(actualOut, expectedOut);

        (uint256 r0, uint256 r1) = pool.getReserves();
        assertEq(r0, 100 ether - actualOut);
        assertEq(r1, 100 ether + amountIn);
    }

    function test_swapRevertSlippage() public {
        vm.prank(alice);
        pool.addLiquidity(100 ether, 100 ether, 0);

        uint256 amountIn = 10 ether;
        uint256 expectedOut = pool.getAmountOut(amountIn, 100 ether, 100 ether);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(Pool__InsufficientOutputAmount.selector, expectedOut, expectedOut + 1 ether)
        );
        pool.swap(address(token0), amountIn, expectedOut + 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                           SYNC & SKIM TESTS
    //////////////////////////////////////////////////////////////*/

    function test_sync() public {
        vm.prank(alice);
        pool.addLiquidity(100 ether, 100 ether, 0);

        // Direct donation without calling addLiquidity
        token0.mint(address(pool), 50 ether);
        token1.mint(address(pool), 50 ether);

        (uint256 r0Before, uint256 r1Before) = pool.getReserves();
        assertEq(r0Before, 100 ether);
        assertEq(r1Before, 100 ether);

        pool.sync();

        (uint256 r0After, uint256 r1After) = pool.getReserves();
        assertEq(r0After, 150 ether);
        assertEq(r1After, 150 ether);
    }

    function test_skim() public {
        vm.prank(alice);
        pool.addLiquidity(100 ether, 100 ether, 0);

        // Direct donation to pool
        token0.mint(address(pool), 20 ether);
        token1.mint(address(pool), 30 ether);

        uint256 charlie0Before = token0.balanceOf(charlie);
        uint256 charlie1Before = token1.balanceOf(charlie);

        pool.skim(charlie);

        assertEq(token0.balanceOf(charlie), charlie0Before + 20 ether);
        assertEq(token1.balanceOf(charlie), charlie1Before + 30 ether);

        (uint256 r0, uint256 r1) = pool.getReserves();
        assertEq(r0, 100 ether);
        assertEq(r1, 100 ether);
    }

    function test_skimRevertZeroAddress() public {
        vm.expectRevert(Pool__ZeroAddress.selector);
        pool.skim(address(0));
    }

    function test_skimOnlyToken0() public {
        vm.prank(alice);
        pool.addLiquidity(100 ether, 100 ether, 0);

        token0.mint(address(pool), 15 ether);

        uint256 charlie0Before = token0.balanceOf(charlie);
        uint256 charlie1Before = token1.balanceOf(charlie);

        pool.skim(charlie);

        assertEq(token0.balanceOf(charlie), charlie0Before + 15 ether);
        assertEq(token1.balanceOf(charlie), charlie1Before);
    }

    function test_skimOnlyToken1() public {
        vm.prank(alice);
        pool.addLiquidity(100 ether, 100 ether, 0);

        token1.mint(address(pool), 25 ether);

        uint256 charlie0Before = token0.balanceOf(charlie);
        uint256 charlie1Before = token1.balanceOf(charlie);

        pool.skim(charlie);

        assertEq(token0.balanceOf(charlie), charlie0Before);
        assertEq(token1.balanceOf(charlie), charlie1Before + 25 ether);
    }
}
