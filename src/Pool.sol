// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LiquidityToken} from "./LiquidityToken.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

error Pool__ZeroAmounts();
error Pool__InsufficientLiquidityMinted(uint256 liquidity, uint256 minLiquidity);

contract Pool {
    using SafeERC20 for IERC20;
    IERC20 public immutable i_token0;
    IERC20 public immutable i_token1;
    LiquidityToken public immutable i_lpToken;

    uint256 public s_reserve0;
    uint256 public s_reserve1;

    uint256 public constant FEE_NUMERATOR = 997;
    uint256 public constant FEE_DENOMINATOR = 1000;
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

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

    constructor(address _token0, address _token1) {
        i_token0 = IERC20(_token0);
        i_token1 = IERC20(_token1);
        i_lpToken = new LiquidityToken("CPMM LP Token", "CPMM-LP");
    }

    function addLiquidity(uint256 amount0, uint256 amount1, uint256 minLiquidity) external returns (uint256 liquidity) {
        if (amount0 == 0 || amount1 == 0) {
            revert Pool__ZeroAmounts();
        }

        uint256 _reserve0 = s_reserve0;
        uint256 _reserve1 = s_reserve1;
        uint256 totalLp = i_lpToken.totalSupply();

        if (totalLp == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
        } else {
            liquidity = Math.min((amount0 * totalLp) / _reserve0, (amount1 * totalLp) / _reserve1);
        }

        if (liquidity < minLiquidity) {
            revert Pool__InsufficientLiquidityMinted(liquidity, minLiquidity);
        }

        s_reserve0 = _reserve0 + amount0;
        s_reserve1 = _reserve1 + amount1;

        i_token0.safeTransferFrom(msg.sender, address(this), amount0);
        i_token1.safeTransferFrom(msg.sender, address(this), amount1);

        if (totalLp == 0) {
            i_lpToken.mint(address(0), MINIMUM_LIQUIDITY);
        }
        i_lpToken.mint(msg.sender, liquidity);

        emit Mint(msg.sender, amount0, amount1);
    }

    function k() public view returns (uint256) {
        return s_reserve0 * s_reserve1;
    }
}
