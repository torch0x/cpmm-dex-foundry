# CPMM (Constant Product Market Maker)

A minimalist, constant-product AMM ($x \cdot y = k$) written in Solidity using Foundry and OpenZeppelin contracts, inspired by Uniswap v2 core mechanics.

## What's Implemented

- **Core Pool ([`src/Pool.sol`](src/Pool.sol))**:
  - Constant-product swaps with a 0.3% LP fee.
  - Slippage protection on `addLiquidity`, `removeLiquidity`, and `swap`.
  - Inflation attack mitigation (permanently locks `MINIMUM_LIQUIDITY = 1000` at `0xdEaD`).
  - Math helpers (`getAmountOut`, `getAmountIn`, `quote`).
  - Pool maintenance utilities (`sync`, `skim`).
  - Reentrancy protection (`ReentrancyGuard`).
- **LP Token ([`src/LiquidityToken.sol`](src/LiquidityToken.sol))**:
  - Standard ERC-20 minted and burned exclusively by the pool.

## Honest Limitations

This repository implements the **Core pool only**, not the periphery:

1. **No Router**: Direct calls to `addLiquidity` require callers to calculate and supply tokens in the exact pool ratio; any surplus is retained by the pool without extra LP.
2. **No Multi-Hop**: Only direct swaps between `token0` and `token1`.
3. **No Native ETH**: Operates on ERC-20 tokens only (no automated WETH wrapping/unwrapping).
4. **No Factory**: Pools are deployed standalone, without a deterministic registry or CREATE2 counterfactual deployment.
5. **Standard ERC-20 Only**: Fee-on-transfer or rebasing tokens are not natively tracked without manual `sync()` calls.

## Testing & Verification

The core contracts have **100% test coverage** (lines, statements, branches, functions):

- **Unit Tests** ([`test/unit/`](test/unit/)): 38 tests covering all paths, revert conditions, and edge cases.
- **Fuzz Tests** ([`test/fuzz/`](test/fuzz/)): 2,000 fuzz runs proving invariant $k$ monotonicity ($k_{\text{after}} \ge k_{\text{before}}$) and initial deposit safety.
- **Invariant Tests** ([`test/invariant/`](test/invariant/)): Stateful fuzzing over 128,000 calls across multiple simulated actors, validating solvency ($\text{balance} \ge \text{reserve}$) and permanent liquidity locks.

### Commands

```shell
# Build
forge build

# Run all test suites
forge test

# Check test coverage
forge coverage
```

## License

MIT
