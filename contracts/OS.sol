// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.13;

import "solmate/utils/SafeTransferLib.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IERC20.sol";
import "./Assembly.sol" as Assembly;

import {console} from "forge-std/Test.sol";

using {
    __wrapEther__,
    dangerousFund,
    dangerousDraw,
    cache,
    increase,
    decrease,
    credit,
    debit,
    settle,
    reset,
    touch,
    getNetBalance
} for AccountSystem global;

/** @dev Novel accounting mechanism to track internally held balances and settle differences with actual balances. */
struct AccountSystem {
    mapping(address => mapping(address => uint)) balances; // Internal user balances.
    mapping(address => uint) reserves; // Global balance of tokens held by a contract.
    mapping(address => bool) cached; // Tokens interacted with that must be settled. TODO: Make it a bitmap.
    address[] warm; // Transiently stored, must be length zero outside of execution.
    bool prepared; // Must be false outside of execution.
    bool settled; // Must be true outside of execution.
}

error EtherTransferFail();
error InsufficientReserve(uint amount, uint delta);
error InvalidBalance();
error NotPreparedToSettle();

/** @dev Gas optimized. */
function __balanceOf__(address token, address account) view returns (uint256) {
    (bool success, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, account));
    if (!success || data.length != 32) revert InvalidBalance();
    return abi.decode(data, (uint256));
}

/** @dev Must validate `weth`. */
function __wrapEther__(AccountSystem storage self, address weth) {
    if (msg.value > 0) {
        self.touch(weth);
        IWETH(weth).deposit{value: msg.value}();
    }
}

/** @dev Dangerously sends ether to `to` in a low-level call. */
function __dangerousUnwrapEther__(address weth, address to, uint256 amount) {
    IWETH(weth).withdraw(amount);
    __dangerousTransferEther__(to, amount);
}

/** @dev Dangerously sends ether to `to` in a low-level call. */
function __dangerousTransferEther__(address to, uint256 value) {
    (bool success, ) = to.call{value: value}(new bytes(0));
    if (!success) revert EtherTransferFail();
}

/** @dev External call to the `to` address is dangerous. */
function __dangerousTransferFrom__(address token, address to, uint amount) {
    SafeTransferLib.safeTransferFrom(ERC20(token), msg.sender, to, amount);
}

/** @dev External call to the `to` address is dangerous. */
function dangerousFund(AccountSystem storage self, address token, address to, uint amount) {
    self.increase(token, amount);
    __dangerousTransferFrom__(token, to, amount);
}

/** @dev Dangerously sends ether or tokens to `to` in a low-level call. */
function dangerousDraw(AccountSystem storage self, address weth, address token, uint amount, address to) {
    self.decrease(token, amount);
    if (token == weth) __dangerousUnwrapEther__(weth, to, amount);
    else SafeTransferLib.safeTransfer(ERC20(token), to, amount);
}

/** @dev Increases an `owner`'s spendable balance. */
function credit(AccountSystem storage self, address owner, address token, uint amount) {
    self.balances[owner][token] += amount;
}

/** @dev Decreases an `owner`'s spendable balance. */
function debit(
    AccountSystem storage self,
    address owner,
    address token,
    uint256 owed
) returns (uint paid, uint remainder) {
    uint balance = self.balances[owner][token];
    console.log("balance", balance);
    console.log("owed", owed);
    if (balance >= owed) {
        paid = owed;
        self.balances[owner][token] -= paid;
        remainder = 0;
    } else {
        paid = balance;
        self.balances[owner][token] -= paid;
        remainder = owed - paid;
    }

    console.log("paid", paid);
    console.log("remainder", remainder);
}

/** @dev Actives a token and increases the reserves. Settlement will pick up this activated token. */
function increase(AccountSystem storage self, address token, uint amount) {
    self.touch(token);
    self.reserves[token] += amount;
}

/** @dev Actives a token and decreases the reserves. Settlement will pick up this activated token. */
function decrease(AccountSystem storage self, address token, uint amount) {
    uint balance = self.reserves[token];
    if (amount > balance) revert InsufficientReserve(balance, amount);

    self.touch(token);
    self.reserves[token] -= amount;
}

/** @notice Settles the difference in balance between tracked tokens and physically held tokens. */
function settle(
    AccountSystem storage self,
    address token,
    address account
) returns (uint credited, uint debited, uint remainder) {
    delete self.cached[token]; // Note: Assumes this token is completely paid for by the end of the transaction.

    int net = self.getNetBalance(token, account);
    if (net > 0) {
        self.credit(msg.sender, token, uint(net));
    } else if (net < 0) {
        remainder = uint(-net);
        (debited, remainder) = self.debit(msg.sender, token, remainder);
        if (debited > 0) self.reserves[token] -= debited; // using a balance means tokens are in contract already.
    }
}

/** @dev Interacting with a token will activate it, adding it to an array of interacted tokens for settlement to loop through. */
function touch(AccountSystem storage self, address token) {
    if (self.settled) self.settled = false; // If tokens are warm, they are not settled.
    if (!self.cached[token]) {
        self.warm.push(token);
        self.cache(token, true);
    }
}

/** @dev Account system is reset after settlement is successful. */
function reset(AccountSystem storage self) {
    assert(self.warm.length == 0);
    self.settled = true;
    delete self.warm;
    delete self.prepared;
}

/** @dev Used to check if a token was already activated after being interacted with again. */
function cache(AccountSystem storage self, address token, bool status) {
    self.cached[token] = status;
}

/** @dev Computes surplus (positive) or deficit (negative) in actual tokens compared to tracked amounts. */
function getNetBalance(AccountSystem storage self, address token, address account) view returns (int256 net) {
    uint internalBalance = self.reserves[token];
    uint physicalBalance = __balanceOf__(token, account);
    net = int256(physicalBalance) - int256(internalBalance);
}
