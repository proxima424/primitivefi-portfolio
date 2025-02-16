// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "./Portfolio.sol";
import "./libraries/RMM01Lib.sol";

/**
 * @title   RMM-01 Portfolio
 * @author  Primitive™
 */
contract RMM01Portfolio is PortfolioVirtual {
    using RMM01Lib for PortfolioPool;
    using AssemblyLib for int256;
    using AssemblyLib for uint256;
    using SafeCastLib for uint256;
    using FixedPointMathLib for int256;
    using FixedPointMathLib for uint128;
    using FixedPointMathLib for uint256;

    constructor(
        address weth,
        address registry
    ) PortfolioVirtual(weth, registry) { }

    /**
     * @dev Computes the price of the pool, which changes over time.
     *
     * @custom:reverts Underflows if the reserve of the input token is lower than the next one, after the next price
     * movement.
     * @custom:reverts Underflows if current reserves of output token is less then next reserves.
     */
    function _getLatestInvariantAndVirtualPrice(
        uint64 poolId,
        bool sellAsset
    )
        internal
        view
        returns (uint256 price, int256 invariant, uint256 updatedTau)
    {
        PortfolioPool storage pool = pools[poolId];
        updatedTau = pool.computeTau(block.timestamp);

        uint256 reserveXPerLiquidity = pool.virtualX;
        uint256 reserveYPerLiquidity = pool.virtualY;

        // The reserve which sends tokens out in this swap must be rounded up
        // to avoid the scenario that the remainder in a truncated output amount
        // is not stolen in the swap.
        if (sellAsset) {
            // Swap X -> Y, Y is output, so round up Y.
            reserveXPerLiquidity =
                reserveXPerLiquidity.divWadDown(pool.liquidity);
            reserveYPerLiquidity = reserveYPerLiquidity.divWadUp(pool.liquidity);
        } else {
            // Swap Y -> X, X is output, so round up X.
            reserveXPerLiquidity = reserveXPerLiquidity.divWadUp(pool.liquidity);
            reserveYPerLiquidity =
                reserveYPerLiquidity.divWadDown(pool.liquidity);
        }

        invariant = int128(
            pool.invariantOf({
                R_x: reserveXPerLiquidity,
                R_y: reserveYPerLiquidity,
                timeRemainingSec: updatedTau
            })
        );

        price = RMM01Lib.getPriceWithX({
            R_x: reserveXPerLiquidity,
            stk: pool.params.maxPrice,
            vol: pool.params.volatility,
            tau: updatedTau
        });
    }

    /// @inheritdoc Objective
    function _beforeSwapEffects(
        uint64 poolId,
        bool sellAsset
    ) internal override returns (bool, int256) {
        (, int256 invariant,) =
            _getLatestInvariantAndVirtualPrice(poolId, sellAsset);
        pools[poolId].syncPoolTimestamp(block.timestamp);

        // Buffer for post-maturity swaps would go here.
        // Without a buffer, it's never possible to take trades at tau == 0.
        // This is acceptable.
        if (pools[poolId].lastTau() == 0) return (false, invariant);

        return (true, invariant);
    }

    /// @inheritdoc Objective
    function checkPosition(
        uint64 poolId,
        address owner,
        int256 delta
    ) public view override returns (bool) {
        // Just in time liquidity protection.
        if (delta < 0) {
            uint256 distance =
                positions[owner][poolId].getTimeSinceChanged(block.timestamp);
            return (pools[poolId].params.jit <= distance);
        }

        return true;
    }

    /// @inheritdoc Objective
    function checkPool(uint64 poolId) public view override returns (bool) {
        return pools[poolId].exists();
    }

    /// @inheritdoc Objective
    function checkInvariant(
        uint64 poolId,
        int256 invariant,
        uint256 reserveX,
        uint256 reserveY,
        uint256 timestamp
    ) public view override returns (bool, int256 nextInvariant) {
        // Computes the time until pool maturity or zero if expired.
        uint256 tau = pools[poolId].computeTau(timestamp);
        nextInvariant = RMM01Lib.invariantOf({
            self: pools[poolId],
            R_x: reserveX,
            R_y: reserveY,
            timeRemainingSec: tau
        });
        return (nextInvariant >= invariant, nextInvariant);
    }

    /// @inheritdoc Objective
    function computeMaxInput(
        uint64 poolId,
        bool sellAsset,
        uint256 reserveIn,
        uint256 liquidity
    ) public view override returns (uint256) {
        uint256 maxInput;
        if (sellAsset) {
            maxInput = (FixedPointMathLib.WAD - reserveIn).mulWadDown(liquidity); // There can be maximum 1:1 ratio
                // between assets and liqudiity.
        } else {
            maxInput = (pools[poolId].params.maxPrice - reserveIn).mulWadDown(
                liquidity
            ); // There can be maximum
                // strike:1 liquidity ratio between quote and liquidity.
        }

        return maxInput;
    }

    /// @inheritdoc Objective
    function computeReservesFromPrice(
        uint64 poolId,
        uint256 price
    ) public view override returns (uint256 reserveX, uint256 reserveY) {
        (reserveX, reserveY) = RMM01Lib.computeReservesWithPrice({
            self: pools[poolId],
            priceWad: price,
            invariantWad: 0
        });
    }

    /// @inheritdoc Objective
    function getAmountOut(
        uint64 poolId,
        bool sellAsset,
        uint256 amountIn,
        address swapper
    ) public view override(Objective) returns (uint256 output) {
        PortfolioPool memory pool = pools[poolId];
        output = pool.getAmountOut({
            sellAsset: sellAsset,
            amountIn: amountIn,
            timestamp: block.timestamp,
            swapper: swapper
        });
    }

    /// @inheritdoc Objective
    function getVirtualPrice(uint64 poolId)
        public
        view
        override
        returns (uint256 price)
    {
        (price,,) = _getLatestInvariantAndVirtualPrice(poolId, true);
    }
}
