// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {InvariantAllocate} from "./InvariantAllocate.sol";
import "./setup/TestE2ESetup.sol";
import "./setup/TestInvariantSetup.sol";

contract InvariantBreaker {
    bool public flag0 = true;
    bool public flag1 = true;

    function set0(int val) public returns (bool) {
        if (val % 100 == 0) flag0 = false;
        return flag0;
    }

    function set1(int val) public returns (bool) {
        if (val % 10 == 0 && !flag0) flag1 = false;
        return flag1;
    }
}

contract TestE2EInvariant is TestInvariantSetup, TestE2ESetup {
    InvariantAllocate internal _allocate;
    InvariantBreaker inv;

    function setUp() public override {
        super.setUp();

        inv = new InvariantBreaker();
        _allocate = new InvariantAllocate(address(__hyper__), address(__asset__), address(__quote__));

        addTargetContract(address(_allocate));
        addTargetContract(address(inv));
    }

    function invariant_global() public withGlobalInvariants {
        console.log("Woooo");
    }

    function invariant_neverFalse() public {
        require(inv.flag1());
    }
}
