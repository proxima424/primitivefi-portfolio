// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "contracts/libraries/FVMLib.sol";

contract FVMLibTarget is Test {
    function doEncodeSwap(
        uint8 useMax,
        uint64 poolId,
        uint8 power0,
        uint128 amount0,
        uint8 power1,
        uint128 amount1,
        uint8 sellAsset
    ) external pure returns (bytes memory) {
        return encodeSwap(useMax, poolId, power0, amount0, power1, amount1, sellAsset);
    }

    function doDecodeSwap(bytes calldata data)
        external
        pure
        returns (uint8 useMax, uint64 poolId, uint128 input, uint128 output, uint8 sellAsset)
    {
        return decodeSwap(data);
    }

    function doEncodeClaim(uint64 poolId, uint128 fee0, uint128 fee1) external pure returns (bytes memory data) {
        return encodeClaim(poolId, fee0, fee1);
    }

    function doDecodeClaim(bytes calldata data) external pure returns (uint64 poolId, uint128 fee0, uint128 fee1) {
        return decodeClaim(data);
    }
}

contract TestFVMLib is Test {
    FVMLibTarget public target = new FVMLibTarget();

    function testFuzz_encodeSwap(
        bool useMax,
        uint64 poolId,
        uint8 power0,
        uint64 amount0,
        uint8 power1,
        uint64 amount1,
        bool sellAsset
    ) public {
        vm.assume(power0 <= 18);
        vm.assume(power1 <= 18);

        bytes memory data = target.doEncodeSwap(
            useMax ? uint8(1) : uint8(0), poolId, power0, amount0, power1, amount1, sellAsset ? uint8(1) : uint8(0)
        );

        (uint8 useMax_, uint64 poolId_, uint128 input_, uint128 output_, uint8 sellAsset_) = target.doDecodeSwap(data);

        assertEq(useMax ? uint8(1) : uint8(0), useMax_, "Wrong use max");
        assertEq(poolId, poolId_);
        assertEq(amount0 * 10 ** power0, input_);
        assertEq(amount1 * 10 ** power1, output_);
        assertEq(sellAsset ? uint8(1) : uint8(0), sellAsset_, "Wrong sellAsset");
    }

    function testFuzz_encodeClaim(uint64 poolId, uint128 fee0, uint128 fee1) public {
        bytes memory data = target.doEncodeClaim(poolId, fee0, fee1);

        (uint64 poolId_, uint128 fee0_, uint128 fee1_) = target.doDecodeClaim(data);

        assertEq(poolId, poolId_);
        assertEq(fee0, fee0_);
        assertEq(fee1, fee1_);
    }

    function test_decodeClaim() public {
        bytes memory data = hex"1004002a0806052b03147bd7";
        (uint64 poolId, uint128 fee0, uint128 fee1) = target.doDecodeClaim(data);

        assertEq(poolId, 42);
        assertEq(fee0, 1323 * 10 ** 6);
        assertEq(fee1, 1342423 * 10 ** 3);
    }
}
