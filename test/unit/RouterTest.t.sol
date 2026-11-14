// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Pool, Pool__InsufficientLiquidityMinted} from "../../src/Pool.sol";
import {
    Router,
    Router__ZeroAddress,
    Router__ZeroAmounts,
    Router__DeadlineExpired,
    Router__InsufficientAmount
} from "../../src/Router.sol";

contract RouterMockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1_000 ether);
    }
}

contract RouterTest is Test {
    RouterMockToken token0;
    RouterMockToken token1;
    Pool pool;
    Router router;

    function setUp() public {
        token0 = new RouterMockToken();
        token1 = new RouterMockToken();

        pool = new Pool(address(token0), address(token1));
        router = new Router(address(pool));

        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);

        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
    }

    function test_quoteAddLiquidityInitial() public view {
        (uint256 amount0, uint256 amount1) = router.quoteAddLiquidity(10 ether, 40 ether);

        assertEq(amount0, 10 ether);
        assertEq(amount1, 40 ether);
    }

    function test_quoteAddLiquidityLimitsToken1() public {
        pool.addLiquidity(100 ether, 400 ether, 0);

        (uint256 amount0, uint256 amount1) = router.quoteAddLiquidity(10 ether, 100 ether);

        assertEq(amount0, 10 ether);
        assertEq(amount1, 40 ether);
    }

    function test_quoteAddLiquidityLimitsToken0() public {
        pool.addLiquidity(100 ether, 400 ether, 0);

        (uint256 amount0, uint256 amount1) = router.quoteAddLiquidity(10 ether, 20 ether);

        assertEq(amount0, 5 ether);
        assertEq(amount1, 20 ether);
    }

    function test_quoteAddLiquidityRevertZeroDesired() public {
        vm.expectRevert(Router__ZeroAmounts.selector);
        router.quoteAddLiquidity(0, 10 ether);

        vm.expectRevert(Router__ZeroAmounts.selector);
        router.quoteAddLiquidity(10 ether, 0);
    }

    function test_quoteAddLiquidityRevertRoundedToZero() public {
        pool.addLiquidity(400 ether, 100 ether, 0);

        vm.expectRevert(Router__ZeroAmounts.selector);
        router.quoteAddLiquidity(1, 1);
    }
}
