// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {LiquidityToken} from "./LiquidityToken.sol";

contract Pool {
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

    function k() public view returns (uint256) {
        return s_reserve0 * s_reserve1;
    }
}
