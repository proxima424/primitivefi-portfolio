// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "contracts/interfaces/IHyper.sol";
import "contracts/HyperLib.sol";
import "solmate/test/utils/mocks/MockERC20.sol";
import {Coin} from "./HelperUtils.sol";

using Ghost for GhostState global;

struct GhostState {
    address actor;
    address subject;
    uint64 poolId;
}

library Ghost {
    error InvalidFileKey(bytes32 what);

    function pair(GhostState memory self) internal view returns (HyperPair memory) {
        return self.pool().pair;
    }

    function pool(GhostState memory self) internal view returns (HyperPool memory) {
        return IHyperStruct(self.subject).pools(self.poolId);
    }

    function position(GhostState memory self, address owner) internal view returns (HyperPosition memory) {
        return IHyperStruct(self.subject).positions(owner, self.poolId);
    }

    function file(GhostState storage self, bytes32 what, bytes memory data) internal {
        if (what == "subject") {
            self.subject = abi.decode(data, (address));
        } else if (what == "poolId") {
            self.poolId = abi.decode(data, (uint64));
        } else {
            revert InvalidFileKey(what);
        }
    }

    function net(GhostState memory self, address token) internal view returns (int) {
        return IHyperGetters(self.subject).getNetBalance(token);
    }

    function balance(GhostState memory self, address account, address token) internal view returns (uint) {
        return IHyperGetters(self.subject).getBalance(account, token);
    }

    function reserve(GhostState memory self, address token) internal view returns (uint) {
        return IHyperGetters(self.subject).getReserve(token);
    }

    function config(GhostState memory self) internal view returns (HyperCurve memory) {
        return self.pool().params;
    }

    function asset(GhostState memory self) internal view returns (Coin) {
        return Coin.wrap(self.pair().tokenAsset);
    }

    function quote(GhostState memory self) internal view returns (Coin) {
        return Coin.wrap(self.pair().tokenQuote);
    }
}

interface IHyperStruct {
    function pairs(uint24 pairId) external view returns (HyperPair memory);

    function positions(address owner, uint64 positionId) external view returns (HyperPosition memory);

    function pools(uint64 poolId) external view returns (HyperPool memory);
}
