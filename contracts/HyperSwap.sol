pragma solidity ^0.8.0;

import "hardhat/console.sol";

import "./EnigmaVirtualMachine.sol";
import "./libraries/ReplicationMath.sol";

/// @notice Executes trading on a target curve.
contract HyperSwap is EnigmaVirtualMachine {
    // --- View --- //

    function getInvariant(uint48 poolId) public view returns (int128) {
        Pool memory pool = pools[poolId];
        return int128(1);
    }

    // --- Internals --- //

    function _updateLastTimestamp(uint48 poolId) internal virtual returns (uint128 blockTimestamp) {
        Pool storage pool = pools[poolId];
        if (pool.blockTimestamp == 0) revert PoolExists();

        uint32 curveId = uint32(poolId); // ToDo: Fix with actual curveId
        Curve storage curve = curves[curveId];
        uint32 maturity = curve.maturity;
        blockTimestamp = _blockTimestamp();
        if (blockTimestamp > maturity) blockTimestamp = maturity; // if expired, set to the maturity

        pool.blockTimestamp = blockTimestamp; // set state
        emit UpdateLastTimestamp(poolId);
    }

    function _swapExactTokens(bytes calldata data) internal returns (uint256) {
        (uint8 useMax, uint48 poolId, uint128 deltaIn, uint8 dir) = Instructions.decodeSwapExactTokens(data); // note: includes instruction.
        uint256 deltaOut = 970860704930000;
        _swap(poolId, dir, deltaIn, deltaOut);
    }

    /// @param dir 0 = base -> quote, 1 = quote -> base
    function _swap(
        uint48 poolId,
        uint8 dir,
        uint256 input,
        uint256 output
    ) internal returns (uint256) {
        Pool storage pool = pools[poolId];

        uint128 lastTimestamp = _updateLastTimestamp(poolId);
        // todo: swap maturity buffer logic implementation
        int128 invariant = getInvariant(poolId);

        Pair memory pair = pairs[uint16(poolId >> 32)];

        {
            // swap logic
            uint32 curveId = uint32(poolId); // note: explicit converse removes first two bytes, which is the pairId.
            Curve memory curve = curves[curveId];
            uint32 tau = curve.maturity - uint32(pool.blockTimestamp);
            uint256 amountInFee = (input * curve.gamma) / PERCENTAGE;
            uint256 adjustedBase;
            uint256 adjustedQuote;

            if (dir == 0) {
                adjustedBase = uint256(pool.internalBase) + amountInFee;
                adjustedQuote = uint256(pool.internalQuote) - output;
            } else {
                adjustedBase = uint256(pool.internalBase) - output;
                adjustedQuote = uint256(pool.internalQuote) + amountInFee;
            }

            adjustedBase = (adjustedBase * PRECISION) / pool.internalLiquidity;
            adjustedQuote = (adjustedQuote * PRECISION) / pool.internalLiquidity;

            int128 invariantAfter = ReplicationMath.calcInvariant(
                10**(18 - pair.decimalsBase),
                10**(18 - pair.decimalsQuote),
                adjustedBase,
                adjustedQuote,
                curve.strike,
                curve.sigma,
                tau
            );
            // invariant check
            if (invariantAfter < invariant) revert InvariantError(invariant, invariantAfter);

            // Commit swap update and settle
            if (dir == 0) {
                pool.internalBase += uint128(input);
                pool.internalQuote -= uint128(output);
                globalReserves[pair.tokenBase] += uint128(input);
                globalReserves[pair.tokenQuote] -= uint128(output);
            } else {
                pool.internalBase -= uint128(output);
                pool.internalQuote += uint128(input);
                globalReserves[pair.tokenBase] -= uint128(output);
                globalReserves[pair.tokenQuote] += uint128(input);
            }

            pool.blockTimestamp = lastTimestamp;
        }

        emit Swap(
            poolId,
            input,
            output,
            dir == 0 ? pair.tokenBase : pair.tokenQuote,
            dir == 0 ? pair.tokenQuote : pair.tokenBase
        );
    }

    // --- External --- //

    // --- Storage --- //
}
