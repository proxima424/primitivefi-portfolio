// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "solmate/utils/SafeCastLib.sol";
import "./Setup.sol";

contract TestPortfolioSwap is Setup {
    using SafeCastLib for uint256;
    using AssemblyLib for uint256;
    using AssemblyLib for uint128;
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for uint128;

    function test_swap_increases_user_balance_token_out()
        public
        defaultConfig
        useActor
        usePairTokens(10 ether)
        allocateSome(1 ether)
        isArmed
    {
        // Estimate amount out.
        bool sellAsset = true;
        uint128 amtIn = 0.1 ether;
        uint128 amtOut = uint128(
            subject().getAmountOut(
                ghost().poolId, sellAsset, amtIn, address(this)
            )
        );

        uint256 prev = ghost().quote().to_token().balanceOf(actor());
        subject().multiprocess(
            FVMLib.encodeSwap(
                uint8(0),
                ghost().poolId,
                amtIn,
                amtOut,
                uint8(sellAsset ? 1 : 0)
            )
        );
        uint256 post = ghost().quote().to_token().balanceOf(actor());

        assertTrue(post > prev, "balance-did-not-increase");
    }

    function test_swap_after_time_passed()
        public
        defaultConfig
        useActor
        usePairTokens(10 ether)
        allocateSome(1 ether)
        isArmed
    {
        bool sellAsset = true;
        uint128 amtIn = 0.1 ether;
        uint128 amtOut = uint128(
            subject().getAmountOut(ghost().poolId, sellAsset, amtIn, actor())
        );

        uint256 prev = ghost().quote().to_token().balanceOf(actor());

        vm.warp(
            block.timestamp
                + (uint256(ghost().pool().params.duration) / 2 * 60 * 60 * 24)
        );
        subject().multiprocess(
            FVMLib.encodeSwap(
                uint8(0),
                ghost().poolId,
                amtIn,
                amtOut,
                uint8(sellAsset ? 1 : 0)
            )
        );
        uint256 post = ghost().quote().to_token().balanceOf(actor());

        assertTrue(post > prev, "physical-balance-did-not-increase");
    }

    function test_swap_protocol_fee()
        public
        defaultConfig
        useActor
        usePairTokens(10 ether)
        allocateSome(1 ether)
        isArmed
    {
        // Set fee
        SimpleRegistry(subjects().registry).setFee(address(subject()), 5);

        // Do swap
        bool sellAsset = true;
        uint128 amtIn = 0.1 ether;
        uint128 amtOut = uint128(
            subject().getAmountOut(
                ghost().poolId, sellAsset, amtIn, address(this)
            )
        );

        subject().multiprocess(
            FVMLib.encodeSwap(
                uint8(0),
                ghost().poolId,
                amtIn,
                amtOut,
                uint8(sellAsset ? 1 : 0)
            )
        );

        uint256 preBal =
            ghost().asset().to_token().balanceOf(subjects().registry);
        SimpleRegistry(subjects().registry).claimFee(
            address(subject()), ghost().asset().to_addr(), type(uint256).max
        );
        uint256 postBal =
            ghost().asset().to_token().balanceOf(subjects().registry);
        assertTrue(postBal > preBal, "nothing claimed");
    }

    function testFuzz_swap_virtual_reserves_do_not_stay_the_same(
        bool sellAsset,
        uint128 amountIn,
        uint128 amountOut
    )
        public
        defaultConfig
        useActor
        usePairTokens(10 ether)
        allocateSome(1 ether)
        isArmed
    {
        vm.assume(amountIn > 0);
        vm.assume(amountOut > 0);
        _swap_check_virtual_reserves(sellAsset, amountIn, amountOut);
    }

    function testFuzz_swap_virtual_reserves_do_not_stay_the_same_low_decimals(
        bool sellAsset,
        uint128 amountIn,
        uint128 amountOut
    )
        public
        sixDecimalQuoteConfig
        useActor
        usePairTokens(10 ether)
        allocateSome(1 ether)
        isArmed
    {
        vm.assume(amountIn > 0);
        vm.assume(amountOut > 0);
        _swap_check_virtual_reserves(sellAsset, amountIn, amountOut);
    }

    // todo: update this test to coerce the amount out so it will be a valid trade.
    // once the bisection update is merged in, getAmountOut can be used more reliably.
    function _swap_check_virtual_reserves(
        bool sellAsset,
        uint128 amountIn,
        uint128 amountOut
    ) internal {
        PortfolioPool memory pool = ghost().pool();
        (uint256 prevXPerL, uint256 prevYPerL) = pool.getVirtualReservesWad();

        // Pre-invariant check will round the output token reserve up when computing
        // how much is in the reserve per liquidity.
        if (sellAsset) {
            prevXPerL = prevXPerL.divWadDown(pool.liquidity);
            prevYPerL = prevYPerL.divWadUp(pool.liquidity);
        } else {
            prevXPerL = prevXPerL.divWadUp(pool.liquidity);
            prevYPerL = prevYPerL.divWadDown(pool.liquidity);
        }

        try subject().multiprocess(
            FVMLib.encodeSwap(
                uint8(0),
                ghost().poolId,
                amountIn,
                amountOut,
                uint8(sellAsset ? 1 : 0)
            )
        ) {
            pool = ghost().pool();

            (uint256 postXPerL, uint256 postYPerL) =
                pool.getVirtualReservesWad();
            postXPerL = postXPerL.divWadDown(pool.liquidity);
            postYPerL = postYPerL.divWadDown(pool.liquidity);

            console.log("prevXPerL", prevXPerL);
            console.log("postXPerL", postXPerL);
            console.log("prevYPerL", prevYPerL);
            console.log("postYPerL", postYPerL);

            assertTrue(postXPerL != prevXPerL, "invariant-x-unchanged");
            assertTrue(postYPerL != prevYPerL, "invariant-y-unchanged");
        } catch {
            // Swap failed, so don't do anything.
        }
    }

    function testFuzz_swap_low_decimals(
        uint256 seed,
        uint128 amountIn
    )
        public
        sixDecimalQuoteConfig
        useActor
        usePairTokens(100 ether)
        allocateSome(1 ether)
        isArmed
    {
        bool sellAsset = seed % 2 == 0;
        _fuzz_swap(sellAsset, amountIn);
    }

    function testFuzz_swap_durationConfig(
        uint256 seed,
        uint128 amountIn,
        uint16 dur
    )
        public
        durationConfig(uint16(bound(dur, MIN_DURATION, MAX_DURATION)))
        useActor
        usePairTokens(100 ether)
        allocateSome(1 ether)
        isArmed
    {
        bool sellAsset = seed % 2 == 0;
        _fuzz_swap(sellAsset, amountIn);
    }

    function testFuzz_swap_volatilityConfig(
        uint256 seed,
        uint128 amountIn,
        uint16 vol
    )
        public
        volatilityConfig(uint16(bound(vol, MIN_VOLATILITY, MAX_VOLATILITY)))
        useActor
        usePairTokens(100 ether)
        allocateSome(1 ether)
        isArmed
    {
        bool sellAsset = seed % 2 == 0;
        _fuzz_swap(sellAsset, amountIn);
    }

    function testFuzz_swap_random_inputs(
        uint256 seed,
        uint64 amountIn,
        uint64 amountOut
    )
        public
        defaultConfig
        useActor
        usePairTokens(100 ether)
        allocateSome(1 ether)
        isArmed
    {
        _fuzz_random_args(seed % 2 == 0, amountIn, amountOut);
    }

    function testFuzz_swap_random_small_inputs(
        uint256 seed,
        uint64 amountIn,
        uint64 amountOut
    )
        public
        defaultConfig
        useActor
        usePairTokens(100 ether)
        allocateSome(1 ether)
        isArmed
    {
        amountIn = bound(amountIn, 1, 1000).safeCastTo64();
        amountOut = bound(amountOut, 1, 1000).safeCastTo64();
        _fuzz_random_args(seed % 2 == 0, amountIn, amountOut);
    }

    function testFuzz_swap_random_large_inputs(
        uint256 seed,
        uint128 amountIn,
        uint128 amountOut
    )
        public
        defaultConfig
        useActor
        usePairTokens(100 ether)
        allocateSome(1 ether)
        isArmed
    {
        amountIn = bound(amountIn, type(uint128).max - 1e18, type(uint128).max)
            .safeCastTo128();
        amountOut = bound(
            amountOut, type(uint128).max - 1e18, type(uint128).max
        ).safeCastTo128();
        _fuzz_random_args(seed % 2 == 0, amountIn, amountOut);
    }

    function _fuzz_random_args(
        bool sellAsset,
        uint256 amountIn,
        uint256 amountOut
    ) internal {
        PortfolioPool memory pool = ghost().pool();

        (, int256 prevInvariant) = RMM01Portfolio(
            payable(address(ghost().subject))
        ).checkInvariant(
            ghost().poolId,
            int256(0),
            pool.virtualX.divWadDown(pool.liquidity),
            pool.virtualY.divWadDown(pool.liquidity),
            block.timestamp
        );

        try subject().multiprocess(
            FVMLib.encodeSwap(
                uint8(0),
                ghost().poolId,
                amountIn.safeCastTo128(),
                amountOut.safeCastTo128(),
                uint8(sellAsset ? 1 : 0)
            )
        ) {
            pool = ghost().pool();

            (, int256 invariant) = RMM01Portfolio(
                payable(address(ghost().subject))
            ).checkInvariant(
                ghost().poolId,
                prevInvariant,
                pool.virtualX.divWadDown(pool.liquidity),
                pool.virtualY.divWadDown(pool.liquidity),
                block.timestamp
            );
            assertTrue(invariant >= 0, "invariant-negative");
            assertTrue(invariant >= prevInvariant, "invariant-decreased");
        } catch { }
    }

    function _fuzz_swap(bool sellAsset, uint128 amountIn) internal {
        vm.assume(amountIn > 100);

        uint256 reserveIn;

        PortfolioPool memory pool = ghost().pool();
        if (sellAsset) {
            reserveIn = pool.virtualX;
        } else {
            reserveIn = pool.virtualY;
        }
        {
            uint256 maxAmountIn = RMM01Portfolio(
                payable(address(ghost().subject))
            ).computeMaxInput(
                ghost().poolId, sellAsset, reserveIn, pool.liquidity
            );

            uint256 decimalsIn =
                sellAsset ? pool.pair.decimalsAsset : pool.pair.decimalsQuote;

            uint256 decimalsOut =
                sellAsset ? pool.pair.decimalsQuote : pool.pair.decimalsAsset;

            maxAmountIn = maxAmountIn.scaleFromWadDown(decimalsIn);
            vm.assume(maxAmountIn > amountIn);
        }

        uint128 amountOut = subject().getAmountOut(
            ghost().poolId, sellAsset, amountIn, actor()
        ).safeCastTo128();

        // todo: fix getAmountOut to be accurate
        amountOut = amountOut * 80 / 100;

        vm.assume(amountOut > 0);

        address tokenIn;
        address tokenOut;
        if (sellAsset) {
            tokenIn = pool.pair.tokenAsset;
            tokenOut = pool.pair.tokenQuote;
        } else {
            tokenIn = pool.pair.tokenQuote;
            tokenOut = pool.pair.tokenAsset;
        }

        uint256 prevPhysicalOut =
            IERC20(tokenOut).balanceOf(address(ghost().subject));

        subject().multiprocess{
            value: tokenIn == subject().WETH() ? amountIn : 0
        }(
            FVMLib.encodeSwap(
                uint8(0),
                ghost().poolId,
                amountIn,
                amountOut,
                uint8(sellAsset ? 1 : 0)
            )
        );

        uint256 postPhysicalOut =
            IERC20(tokenOut).balanceOf(address(ghost().subject));

        assertApproxEqAbs(
            postPhysicalOut,
            prevPhysicalOut - amountOut,
            1,
            "out-physical-not-eq"
        );
    }

    function test_swap_price_decreases()
        public
        defaultConfig
        useActor
        usePairTokens(100 ether)
        allocateSome(1 ether)
        isArmed
    {
        bool sellAsset = true;
        uint256 amountIn = 0.01 ether;
        uint256 amountOut =
            subject().getAmountOut(ghost().poolId, sellAsset, amountIn, actor());

        _swap_assert_price(sellAsset, amountIn, amountOut);
    }

    function test_swap_price_increases()
        public
        defaultConfig
        useActor
        usePairTokens(100 ether)
        allocateSome(1 ether)
        isArmed
    {
        bool sellAsset = false;
        uint256 amountIn = 0.01 ether;
        uint256 amountOut =
            subject().getAmountOut(ghost().poolId, sellAsset, amountIn, actor());

        _swap_assert_price(sellAsset, amountIn, amountOut);
    }

    function test_swap_price_decreases_low_decimals()
        public
        sixDecimalQuoteConfig
        useActor
        usePairTokens(100 ether)
        allocateSome(1 ether)
        isArmed
    {
        bool sellAsset = true;
        uint256 amountIn = uint256(0.01 ether).scaleFromWadDown(
            ghost().asset().to_token().decimals()
        );
        uint256 amountOut =
            subject().getAmountOut(ghost().poolId, sellAsset, amountIn, actor());

        _swap_assert_price(sellAsset, amountIn, amountOut);
    }

    function test_swap_price_increases_low_decimals()
        public
        sixDecimalQuoteConfig
        useActor
        usePairTokens(100 ether)
        allocateSome(1 ether)
        isArmed
    {
        bool sellAsset = false;
        uint256 amountIn = uint256(0.01 ether).scaleFromWadDown(
            ghost().quote().to_token().decimals()
        );
        uint256 amountOut =
            subject().getAmountOut(ghost().poolId, sellAsset, amountIn, actor());

        _swap_assert_price(sellAsset, amountIn, amountOut);
    }

    function _swap_assert_price(
        bool sellAsset,
        uint256 amountIn,
        uint256 amountOut
    ) internal {
        uint256 prevPrice = subject().getVirtualPrice(ghost().poolId);

        subject().multiprocess(
            FVM.encodeSwap(
                uint8(0),
                ghost().poolId,
                amountIn.safeCastTo128(),
                amountOut.safeCastTo128(),
                uint8(sellAsset ? 1 : 0)
            )
        );

        uint256 postPrice = subject().getVirtualPrice(ghost().poolId);
        if (sellAsset) {
            assertTrue(postPrice < prevPrice, "price-not-decreased");
        } else {
            assertTrue(postPrice > prevPrice, "price-not-increased");
        }
    }

    function testFuzz_swap_invariant_gte_previous_invariant(
        bool sellAsset,
        uint256 amountIn,
        uint256 amountOut
    )
        public
        defaultConfig
        useActor
        usePairTokens(100 ether)
        allocateSome(10 ether)
        isArmed
    {
        PortfolioPool memory pool = ghost().pool();

        uint256 reserveXPerL;
        uint256 reserveYPerL;

        if (sellAsset) {
            reserveXPerL = pool.virtualX.divWadDown(pool.liquidity);
            reserveYPerL = pool.virtualY.divWadUp(pool.liquidity);
        } else {
            reserveXPerL = pool.virtualX.divWadUp(pool.liquidity);
            reserveYPerL = pool.virtualY.divWadDown(pool.liquidity);
        }

        {
            // bound the amounts to be within the max amount in and max amount out
            uint256 maxAmountIn = RMM01Portfolio(
                payable(address(ghost().subject))
            ).computeMaxInput(
                ghost().poolId,
                sellAsset,
                sellAsset ? reserveXPerL : reserveYPerL,
                pool.liquidity
            );

            amountIn = bound(amountIn, 1, maxAmountIn);
            amountOut = bound(
                amountOut, 1, ((sellAsset ? reserveYPerL : reserveXPerL) - 1)
            );

            amountIn = amountIn.scaleFromWadDown(
                sellAsset ? pool.pair.decimalsAsset : pool.pair.decimalsQuote
            );
            amountOut = amountOut.scaleFromWadDown(
                sellAsset ? pool.pair.decimalsQuote : pool.pair.decimalsAsset
            );

            _swap_check_invariant(
                sellAsset, amountIn, amountOut, reserveXPerL, reserveYPerL
            );
        }
    }

    function testFuzz_swap_amountIn_invariant_does_not_decrease(
        bool sellAsset,
        uint256 amountIn
    )
        public
        defaultConfig
        useActor
        usePairTokens(100 ether)
        allocateSome(10 ether)
        isArmed
    {
        vm.assume(amountIn > 100);

        PortfolioPool memory pool = ghost().pool();

        uint256 reserveXPerL;
        uint256 reserveYPerL;

        if (sellAsset) {
            reserveXPerL = pool.virtualX.divWadDown(pool.liquidity);
            reserveYPerL = pool.virtualY.divWadUp(pool.liquidity);
        } else {
            reserveXPerL = pool.virtualX.divWadUp(pool.liquidity);
            reserveYPerL = pool.virtualY.divWadDown(pool.liquidity);
        }

        uint256 maxIn = Objective(address(subject())).computeMaxInput(
            ghost().poolId,
            sellAsset,
            sellAsset ? reserveXPerL : reserveYPerL,
            pool.liquidity
        );
        vm.assume(maxIn > amountIn);

        uint256 amountOut =
            subject().getAmountOut(ghost().poolId, sellAsset, amountIn, actor());

        _swap_check_invariant(
            sellAsset, amountIn, amountOut, reserveXPerL, reserveYPerL
        );
    }

    function _swap_check_invariant(
        bool sellAsset,
        uint256 amountIn,
        uint256 amountOut,
        uint256 reserveXPerL,
        uint256 reserveYPerL
    ) internal {
        (, int256 prev) = RMM01Portfolio(payable(address(ghost().subject)))
            .checkInvariant({
            poolId: ghost().poolId,
            invariant: 0,
            reserveX: reserveXPerL,
            reserveY: reserveYPerL,
            timestamp: block.timestamp
        });

        try subject().multiprocess(
            FVM.encodeSwap(
                uint8(0),
                ghost().poolId,
                amountIn.safeCastTo128(),
                amountOut.safeCastTo128(),
                uint8(sellAsset ? 1 : 0)
            )
        ) {
            PortfolioPool memory pool = ghost().pool();

            if (sellAsset) {
                reserveXPerL = pool.virtualX.divWadDown(pool.liquidity);
                reserveYPerL = pool.virtualY.divWadUp(pool.liquidity);
            } else {
                reserveXPerL = pool.virtualX.divWadUp(pool.liquidity);
                reserveYPerL = pool.virtualY.divWadDown(pool.liquidity);
            }

            (, int256 post) = RMM01Portfolio(payable(address(ghost().subject)))
                .checkInvariant({
                poolId: ghost().poolId,
                invariant: prev,
                reserveX: reserveXPerL,
                reserveY: reserveYPerL,
                timestamp: block.timestamp
            });

            assertTrue(post >= prev, "post-invariant-not-gte-prev");
        } catch {
            // do nothing, since it failed.
        }
    }
}
