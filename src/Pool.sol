// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LiquidityToken} from "./LiquidityToken.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

error Pool__ZeroAmounts();
error Pool__ZeroAddress();
error Pool__InvalidToken();
error Pool__InsufficientLiquidityMinted(uint256 liquidity, uint256 minLiquidity);
error Pool__InsufficientInitialLiquidity();
error Pool__InsufficientLiquidityBurned();
error Pool__InsufficientOutputAmount(uint256 amountOut, uint256 minAmountOut);
error Pool__InsufficientInputAmount();
error Pool__InsufficientLiquidity();

contract Pool is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable i_token0;
    IERC20 public immutable i_token1;
    LiquidityToken public immutable i_lpToken;

    uint256 public s_reserve0;
    uint256 public s_reserve1;

    uint256 public constant FEE_NUMERATOR = 997;
    uint256 public constant FEE_DENOMINATOR = 1000;
    uint256 public constant MINIMUM_LIQUIDITY = 1000;
    address public constant DEAD_ADDRESS = address(0xdEaD);

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint256 reserve0, uint256 reserve1);

    constructor(address _token0, address _token1) {
        if (_token0 == address(0) || _token1 == address(0)) {
            revert Pool__ZeroAddress();
        }
        if (_token0 == _token1) {
            revert Pool__InvalidToken();
        }
        i_token0 = IERC20(_token0);
        i_token1 = IERC20(_token1);
        i_lpToken = new LiquidityToken("CPMM LP Token", "CPMM-LP");
    }

    function addLiquidity(uint256 amount0, uint256 amount1, uint256 minLiquidity)
        external
        nonReentrant
        returns (uint256 liquidity)
    {
        if (amount0 == 0 || amount1 == 0) {
            revert Pool__ZeroAmounts();
        }

        uint256 _reserve0 = s_reserve0;
        uint256 _reserve1 = s_reserve1;
        uint256 totalLp = i_lpToken.totalSupply();

        if (totalLp == 0) {
            uint256 initialLiquidity = Math.sqrt(amount0 * amount1);
            if (initialLiquidity <= MINIMUM_LIQUIDITY) {
                revert Pool__InsufficientInitialLiquidity();
            }
            liquidity = initialLiquidity - MINIMUM_LIQUIDITY;
        } else {
            liquidity = Math.min((amount0 * totalLp) / _reserve0, (amount1 * totalLp) / _reserve1);
        }

        if (liquidity < minLiquidity) {
            revert Pool__InsufficientLiquidityMinted(liquidity, minLiquidity);
        }

        s_reserve0 = _reserve0 + amount0;
        s_reserve1 = _reserve1 + amount1;

        emit Mint(msg.sender, amount0, amount1);

        i_token0.safeTransferFrom(msg.sender, address(this), amount0);
        i_token1.safeTransferFrom(msg.sender, address(this), amount1);

        if (totalLp == 0) {
            i_lpToken.mint(DEAD_ADDRESS, MINIMUM_LIQUIDITY);
        }
        i_lpToken.mint(msg.sender, liquidity);
    }

    function removeLiquidity(uint256 lpAmount, uint256 minAmount0, uint256 minAmount1, address to)
        public
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        if (lpAmount == 0) {
            revert Pool__ZeroAmounts();
        }
        if (to == address(0)) {
            revert Pool__ZeroAddress();
        }

        uint256 _reserve0 = s_reserve0;
        uint256 _reserve1 = s_reserve1;
        uint256 totalLp = i_lpToken.totalSupply();

        amount0 = (lpAmount * _reserve0) / totalLp;
        amount1 = (lpAmount * _reserve1) / totalLp;

        if (amount0 == 0 || amount1 == 0) {
            revert Pool__InsufficientLiquidityBurned();
        }
        if (amount0 < minAmount0 || amount1 < minAmount1) {
            revert Pool__InsufficientOutputAmount(
                amount0 < minAmount0 ? amount0 : amount1, amount0 < minAmount0 ? minAmount0 : minAmount1
            );
        }

        s_reserve0 = _reserve0 - amount0;
        s_reserve1 = _reserve1 - amount1;

        emit Burn(msg.sender, amount0, amount1, to);

        i_lpToken.burn(msg.sender, lpAmount);

        i_token0.safeTransfer(to, amount0);
        i_token1.safeTransfer(to, amount1);
    }

    function removeLiquidity(uint256 lpAmount, uint256 minAmount0, uint256 minAmount1)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        return removeLiquidity(lpAmount, minAmount0, minAmount1, msg.sender);
    }

    function swap(address tokenIn, uint256 amountIn, uint256 minAmountOut, address to)
        public
        nonReentrant
        returns (uint256 amountOut)
    {
        if (amountIn == 0) {
            revert Pool__ZeroAmounts();
        }
        if (to == address(0)) {
            revert Pool__ZeroAddress();
        }

        bool isToken0 = tokenIn == address(i_token0);
        if (!isToken0 && tokenIn != address(i_token1)) {
            revert Pool__InvalidToken();
        }

        uint256 _reserve0 = s_reserve0;
        uint256 _reserve1 = s_reserve1;

        (uint256 reserveIn, uint256 reserveOut) = isToken0 ? (_reserve0, _reserve1) : (_reserve1, _reserve0);

        amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
        if (amountOut < minAmountOut) {
            revert Pool__InsufficientOutputAmount(amountOut, minAmountOut);
        }

        if (isToken0) {
            s_reserve0 = _reserve0 + amountIn;
            s_reserve1 = _reserve1 - amountOut;

            emit Swap(msg.sender, amountIn, 0, 0, amountOut, to);

            i_token0.safeTransferFrom(msg.sender, address(this), amountIn);
            i_token1.safeTransfer(to, amountOut);
        } else {
            s_reserve0 = _reserve0 - amountOut;
            s_reserve1 = _reserve1 + amountIn;

            emit Swap(msg.sender, 0, amountIn, amountOut, 0, to);

            i_token1.safeTransferFrom(msg.sender, address(this), amountIn);
            i_token0.safeTransfer(to, amountOut);
        }
    }

    function swap(address tokenIn, uint256 amountIn, uint256 minAmountOut) external returns (uint256 amountOut) {
        return swap(tokenIn, amountIn, minAmountOut, msg.sender);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256 amountOut)
    {
        if (amountIn == 0) {
            revert Pool__InsufficientInputAmount();
        }
        if (reserveIn == 0 || reserveOut == 0) {
            revert Pool__InsufficientLiquidity();
        }

        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256 amountIn)
    {
        if (amountOut == 0) {
            revert Pool__InsufficientOutputAmount(0, 1);
        }
        if (reserveIn == 0 || reserveOut == 0 || amountOut >= reserveOut) {
            revert Pool__InsufficientLiquidity();
        }

        uint256 numerator = reserveIn * amountOut * FEE_DENOMINATOR;
        uint256 denominator = (reserveOut - amountOut) * FEE_NUMERATOR;
        amountIn = (numerator / denominator) + 1;
    }

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) public pure returns (uint256 amountB) {
        if (amountA == 0) {
            revert Pool__InsufficientInputAmount();
        }
        if (reserveA == 0 || reserveB == 0) {
            revert Pool__InsufficientLiquidity();
        }
        amountB = (amountA * reserveB) / reserveA;
    }

    function sync() external {
        s_reserve0 = i_token0.balanceOf(address(this));
        s_reserve1 = i_token1.balanceOf(address(this));
        emit Sync(s_reserve0, s_reserve1);
    }

    function skim(address to) external {
        if (to == address(0)) {
            revert Pool__ZeroAddress();
        }
        uint256 balance0 = i_token0.balanceOf(address(this));
        uint256 balance1 = i_token1.balanceOf(address(this));

        if (balance0 > s_reserve0) {
            i_token0.safeTransfer(to, balance0 - s_reserve0);
        }
        if (balance1 > s_reserve1) {
            i_token1.safeTransfer(to, balance1 - s_reserve1);
        }
    }

    function getReserves() external view returns (uint256, uint256) {
        return (s_reserve0, s_reserve1);
    }

    function k() public view returns (uint256) {
        return s_reserve0 * s_reserve1;
    }
}
