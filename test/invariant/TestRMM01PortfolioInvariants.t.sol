// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "../Setup.sol";
import "./HelperInvariantLib.sol";

import { HandlerPortfolio } from "./HandlerPortfolio.sol";
import { HandlerExternal } from "./HandlerExternal.sol";

bytes32 constant SLOT_LOCKED = bytes32(uint256(11));

interface AccountLike {
    function __account__() external view returns (bool);
}

/**
 * @dev Most important test suite, verifies the critical invariants of Portfolio.
 *
 * Invariant 1. balanceOf >= getReserve for all tokens.
 * Invariant 2. AccountSystem.settled == true.
 * Invariant 3. AccountSystem.prepared == false.
 * Invariant 4. (balanceOf(asset), balanceOf(quote)) >= Portfolio.getVirtualReserves, for all pools.
 * Invariant 5. ∑ Portfolio.positions(owner, poolId).freeLiquidity == Portfolio.pools(poolId).liquidity, for all
 * pools.
 */
contract TestRMM01PortfolioInvariants is Setup {
    using AssemblyLib for uint256;
    /**
     * @dev Helper to manage the pools that are being interacted with via the handlers.
     */

    InvariantGhostState private _ghostInvariant;

    HandlerPortfolio internal _portfolio;
    HandlerExternal internal _external;

    function setUp() public override {
        super.setUp();

        _portfolio = new HandlerPortfolio();

        {
            bytes4[] memory selectors = new bytes4[](3);
            selectors[0] = HandlerPortfolio.create_pool.selector;
            selectors[1] = HandlerPortfolio.allocate.selector;
            selectors[2] = HandlerPortfolio.deallocate.selector;
            targetSelector(
                FuzzSelector({addr: address(_portfolio), selectors: selectors})
            );
            targetContract(address(_portfolio));
        }

        // Create default pool, used in handlers via `usePool(uint)` modifier.
        uint64 poolId = Configs.fresh().edit(
            "asset", abi.encode(address(subjects().tokens[0]))
        ).edit("quote", abi.encode(address(subjects().tokens[1]))).generate(
            address(subject())
        );

        setGhostPoolId(poolId);
    }

    function addGhostPoolId(uint64 poolId) public virtual {
        _ghostInvariant.add(poolId);
    }

    function setGhostPoolId(uint64 poolId) public override {
        super.setGhostPoolId(poolId);
        addGhostPoolId(poolId);
    }

    // ===== Invariants ===== //

    function invariant_asset_balance_gte_reserves() public {
        (uint256 reserve, uint256 physical) =
            getBalances(ghost().asset().to_addr());
        reserve =
            reserve.scaleFromWadDown(ghost().asset().to_token().decimals());
        assertTrue(physical >= reserve, "invariant-asset-physical-balance");
    }

    function invariant_quote_balance_gte_reserves() public {
        (uint256 reserve, uint256 physical) =
            getBalances(ghost().quote().to_addr());
        reserve =
            reserve.scaleFromWadDown(ghost().quote().to_token().decimals());
        assertTrue(physical >= reserve, "invariant-quote-physical-balance");
    }

    function invariant_account_settled() public {
        bool settled = AccountLike(address(subject())).__account__();
        assertTrue(settled, "invariant-settled");
    }

    function invariant_virtual_pool_asset_reserves() public {
        PortfolioPool memory pool = ghost().pool();

        if (pool.liquidity > 0) {
            (uint256 dAsset,) = subject().getPoolReserves(ghost().poolId);
            uint256 bAsset = ghost().physicalBalance(ghost().asset().to_addr());
            dAsset =
                dAsset.scaleFromWadDown(ghost().asset().to_token().decimals());
            assertTrue(bAsset >= dAsset, "invariant-virtual-reserves-asset");
        }
    }

    function invariant_virtual_pool_quote_reserves() public {
        PortfolioPool memory pool = ghost().pool();

        if (pool.liquidity > 0) {
            (, uint256 dQuote) = subject().getPoolReserves(ghost().poolId);
            uint256 bQuote = ghost().physicalBalance(ghost().quote().to_addr());
            dQuote =
                dQuote.scaleFromWadDown(ghost().quote().to_token().decimals());
            assertTrue(bQuote >= dQuote, "invariant-virtual-reserves-quote");
        }
    }

    function invariant_reentrancy() public {
        bytes32 locked = vm.load(address(subject()), SLOT_LOCKED);
        assertEq(uint256(locked), 1, "invariant-locked");

        uint256 balance = address(subject()).balance;
        assertEq(balance, 0, "invariant-ether");
    }

    function invariant_callSummary() public view {
        console.log("Call summary:");
        console.log("-------------------");
        _portfolio.callSummary();
        console.log("pools created", getPoolIds().length);
    }

    // ===== Helpers ===== //

    function ghost_invariant()
        internal
        virtual
        returns (InvariantGhostState storage)
    {
        return _ghostInvariant;
    }

    function lastPoolId() public view virtual returns (uint64) {
        return _ghostInvariant.last;
    }

    function getPoolIds() public view virtual returns (uint64[] memory) {
        return _ghostInvariant.poolIds;
    }

    function getRandomPoolId(uint256 index)
        public
        view
        virtual
        returns (uint64)
    {
        return _ghostInvariant.rand(index);
    }

    function getBalances(address token)
        internal
        view
        returns (uint256 reserve, uint256 physical)
    {
        if (ghost().subject != address(0)) {
            reserve = ghost().reserve(token);
            physical = ghost().physicalBalance(token);
        }
    }

    function getPositionsLiquiditySum() public view virtual returns (uint256) {
        address[] memory actors = getActors();
        uint256 sum;
        for (uint256 i; i != actors.length; ++i) {
            sum += ghost().position(actors[i]).freeLiquidity;
        }

        return sum;
    }
}
