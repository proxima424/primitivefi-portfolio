> Beta: Not production ready. Pending on-going audits.

# Primitive Portfolio

On-chain portfolio management. Optimized for managing risk and liquidity.

## System Invariants

The system is designed around a single invariant:

```
Balance >= Reserve
```

Exposed via: `Portfolio.getNetBalance(token)`

For more invariants, [read this](./test/README.md).

# Portfolio Manual

## Clone

```
git clone https://github.com/primitivefinance/portfolio.git
```

## Installation

Required:

- Foundry
- Python (if running echidna)

### 1. Install foundry. [source](https://github.com/foundry-rs/foundry)

```
curl -L https://foundry.paradigm.xyz | bash
```

### 2. Restart terminal or reload `PATH`, then run:

```
foundryup
```

### 3. Install deps

```
forge install
```

### 4. Test

```
forge test --match-contract TestRMM01
```

## Resources

- [Portfolio Yellow Paper](https://www.primitive.xyz/papers/yellow.pdf)
- [RMM in desmos](https://www.desmos.com/calculator/8py0nzdgfp)
- [Original codebase](https://github.com/primitivefinance/rmm-core)
- [solstat](https://github.com/primitivefinance/solstat)
- [Replicating Market Makers](https://github.com/angeris/angeris.github.io/blob/master/papers/rmms.pdf)
- [RMM whitepaper](https://primitive.xyz/whitepaper)
- [High precision calculator](https://keisan.casio.com/calculator)

## Audits

| Security Firm | Review Time | Status    |
| ------------- | ----------- | --------- |
| ChainSecurity | 8-weeks     | Completed |
| Trail of Bits | 8-weeks     | Completed |
| Spearbit      | 5-weeks     | Scheduled |
