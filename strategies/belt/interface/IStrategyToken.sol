// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IStrategyToken {
    function deposit(uint256 _pid, uint256 _amount) external;
}