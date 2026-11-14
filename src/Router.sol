// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Pool} from "./Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

error Router__ZeroAddress();
error Router__ZeroAmounts();
error Router__DeadlineExpired();
error Router__InsufficientAmount(uint256 actual, uint256 minimum);

contract Router is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct AddLiquidityParams {
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 minLiquidity;
        address to;
        uint256 deadline;
    }

    Pool public immutable i_pool;

    constructor(address pool) {
        if (pool == address(0)) {
            revert Router__ZeroAddress();
        }

        i_pool = Pool(pool);
    }

    function quoteAddLiquidity(uint256 amount0Desired, uint256 amount1Desired)
        public
        view
        returns (uint256 amount0, uint256 amount1)
    {
        if (amount0Desired == 0 || amount1Desired == 0) {
            revert Router__ZeroAmounts();
        }

        if (i_pool.i_lpToken().totalSupply() == 0) {
            return (amount0Desired, amount1Desired);
        }

        (uint256 reserve0, uint256 reserve1) = i_pool.getReserves();

        uint256 amount1Optimal = i_pool.quote(amount0Desired, reserve0, reserve1);

        if (amount1Optimal <= amount1Desired) {
            amount0 = amount0Desired;
            amount1 = amount1Optimal;
        } else {
            amount0 = i_pool.quote(amount1Desired, reserve1, reserve0);
            amount1 = amount1Desired;
        }

        if (amount0 == 0 || amount1 == 0) {
            revert Router__ZeroAmounts();
        }
    }

    function addLiquidity(AddLiquidityParams calldata params)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1, uint256 liquidity)
    {
        if (block.timestamp > params.deadline) {
            revert Router__DeadlineExpired();
        }

        if (params.to == address(0)) {
            revert Router__ZeroAddress();
        }

        (amount0, amount1) = quoteAddLiquidity(params.amount0Desired, params.amount1Desired);

        if (amount0 < params.amount0Min) {
            revert Router__InsufficientAmount(amount0, params.amount0Min);
        }

        if (amount1 < params.amount1Min) {
            revert Router__InsufficientAmount(amount1, params.amount1Min);
        }

        IERC20 token0 = i_pool.i_token0();
        IERC20 token1 = i_pool.i_token1();

        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);

        token0.forceApprove(address(i_pool), amount0);
        token1.forceApprove(address(i_pool), amount1);

        liquidity = i_pool.addLiquidity(amount0, amount1, params.minLiquidity);

        IERC20(address(i_pool.i_lpToken())).safeTransfer(params.to, liquidity);
    }
}
