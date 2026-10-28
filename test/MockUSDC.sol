// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockUSDC {
    string public constant name = "USD Coin";
    string public constant symbol = "USDC";
    uint8 public constant decimals = 6;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) public blocked; // mimics Arc/USDC blocklist

    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function setBlocked(address a, bool b) external { blocked[a] = b; }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transfer(address to, uint256 a) external returns (bool) { _t(msg.sender, to, a); return true; }
    function transferFrom(address f, address to, uint256 a) external returns (bool) {
        uint256 al = allowance[f][msg.sender];
        require(al >= a, "allowance");
        if (al != type(uint256).max) allowance[f][msg.sender] = al - a;
        _t(f, to, a);
        return true;
    }
    function _t(address f, address to, uint256 a) internal {
        require(!blocked[f] && !blocked[to], "blocklisted");
        require(to != address(0), "Zero address not allowed");
        require(balanceOf[f] >= a, "balance");
        balanceOf[f] -= a;
        balanceOf[to] += a;
    }
}
