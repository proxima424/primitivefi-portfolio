// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "./Setup.sol";

contract TestPortfolioDeallocate is Setup {
    function test_deallocate_max()
        public
        noJit
        defaultConfig
        useActor
        usePairTokens(10 ether)
        allocateSome(uint128(BURNED_LIQUIDITY))
        isArmed
    {
        uint128 liquidity = 1 ether;
        subject().multiprocess(
            FVMLib.encodeAllocateOrDeallocate(
                true,
                uint8(0),
                ghost().poolId,
                liquidity,
                type(uint128).max,
                type(uint128).max
            )
        );

        // Deallocating liquidity can round down.
        uint256 prev = ghost().position(actor()).freeLiquidity;
        uint128 amount = liquidity;
        if (amount > prev) {
            amount = uint128(prev);
        }
        subject().multiprocess(
            FVMLib.encodeAllocateOrDeallocate(
                false, uint8(1), ghost().poolId, amount, 0, 0
            )
        );
        uint256 post = ghost().position(actor()).freeLiquidity;

        assertApproxEqAbs(
            post, prev - liquidity, 1, "liquidity-did-not-decrease"
        );
    }

    function test_deallocate_low_decimals(uint64 liquidity)
        public
        noJit
        sixDecimalQuoteConfig
        useActor
        usePairTokens(500 ether)
        allocateSome(uint128(BURNED_LIQUIDITY * 1e3))
        isArmed
    {
        vm.assume(liquidity > 10 ** (18 - 6));
        subject().multiprocess(
            FVMLib.encodeAllocateOrDeallocate(
                true,
                uint8(0),
                ghost().poolId,
                liquidity,
                type(uint128).max,
                type(uint128).max
            )
        );
        _simple_deallocate(liquidity);
    }

    function testFuzz_deallocate_volatility(
        uint64 liquidity,
        uint16 volatility
    )
        public
        noJit
        volatilityConfig(uint16(bound(volatility, MIN_VOLATILITY, MAX_VOLATILITY)))
        useActor
        usePairTokens(500 ether)
        allocateSome(uint128(BURNED_LIQUIDITY))
        isArmed
    {
        vm.assume(liquidity > 0);
        subject().multiprocess(
            FVMLib.encodeAllocateOrDeallocate(
                true,
                uint8(0),
                ghost().poolId,
                liquidity,
                type(uint128).max,
                type(uint128).max
            )
        );
        _simple_deallocate(liquidity);
    }

    function testFuzz_deallocate_duration(
        uint64 liquidity,
        uint16 duration
    )
        public
        noJit
        durationConfig(uint16(bound(duration, MIN_DURATION, MAX_DURATION)))
        useActor
        usePairTokens(500 ether)
        allocateSome(uint128(BURNED_LIQUIDITY))
        isArmed
    {
        vm.assume(liquidity > 0);
        subject().multiprocess(
            FVMLib.encodeAllocateOrDeallocate(
                true,
                uint8(0),
                ghost().poolId,
                liquidity,
                type(uint128).max,
                type(uint128).max
            )
        );
        _simple_deallocate(liquidity);
    }

    function testFuzz_deallocate_weth(uint64 liquidity)
        public
        noJit
        wethConfig
        useActor
        usePairTokens(500 ether)
        isArmed
    {
        vm.assume(liquidity > BURNED_LIQUIDITY);
        vm.deal(actor(), 250 ether);
        subject().multiprocess{value: 250 ether}(
            FVMLib.encodeAllocateOrDeallocate(
                true,
                uint8(0),
                ghost().poolId,
                liquidity,
                type(uint128).max,
                type(uint128).max
            )
        );
        _simple_deallocate(liquidity);
    }

    function testFuzz_deallocate_over_time(
        uint64 liquidity,
        uint24 timestep
    )
        public
        noJit
        defaultConfig
        useActor
        usePairTokens(500 ether)
        allocateSome(uint128(BURNED_LIQUIDITY))
        isArmed
    {
        vm.assume(liquidity > 0);
        subject().multiprocess(
            FVMLib.encodeAllocateOrDeallocate(
                true,
                uint8(0),
                ghost().poolId,
                liquidity,
                type(uint128).max,
                type(uint128).max
            )
        );
        vm.warp(block.timestamp + timestep);
        _simple_deallocate(liquidity);
    }

    function test_deallocate_reverts_when_min_asset_unmatched()
        public
        noJit
        defaultConfig
        useActor
        usePairTokens(10 ether)
        isArmed
    {
        uint128 amount = 0.1 ether;
        uint64 xid = ghost().poolId;

        subject().multiprocess(
            FVMLib.encodeAllocateOrDeallocate({
                shouldAllocate: true,
                useMax: uint8(0),
                poolId: xid,
                deltaLiquidity: amount,
                deltaQuote: type(uint128).max,
                deltaAsset: type(uint128).max
            })
        );

        vm.expectRevert();
        subject().multiprocess(
            FVMLib.encodeAllocateOrDeallocate(
                false, uint8(1), ghost().poolId, amount, type(uint128).max, 0
            )
        );
    }

    function test_deallocate_reverts_when_min_quote_unmatched()
        public
        noJit
        defaultConfig
        useActor
        usePairTokens(10 ether)
        isArmed
    {
        uint128 amount = 0.1 ether;
        uint64 xid = ghost().poolId;

        subject().multiprocess(
            FVMLib.encodeAllocateOrDeallocate({
                shouldAllocate: true,
                useMax: uint8(0),
                poolId: xid,
                deltaLiquidity: amount,
                deltaQuote: type(uint128).max,
                deltaAsset: type(uint128).max
            })
        );

        vm.expectRevert();
        subject().multiprocess(
            FVMLib.encodeAllocateOrDeallocate(
                false, uint8(1), ghost().poolId, amount, 0, type(uint128).max
            )
        );
    }

    function _simple_deallocate(uint128 amount) internal {
        uint256 prev = ghost().position(actor()).freeLiquidity;

        uint128 amountToRemove = amount;
        if (amount > prev) {
            amountToRemove = uint128(prev);
        }

        bool useMax = false;

        subject().multiprocess(
            FVMLib.encodeAllocateOrDeallocate(
                false,
                uint8(useMax ? 1 : 0),
                ghost().poolId,
                amountToRemove,
                0,
                0
            )
        );
        uint256 post = ghost().position(actor()).freeLiquidity;

        // Deallocating liquidity can round down.
        assertApproxEqAbs(
            post, prev - amountToRemove, 1, "liquidity-did-not-decrease"
        );
    }
}
