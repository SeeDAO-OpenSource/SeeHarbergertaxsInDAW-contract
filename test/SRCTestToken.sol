// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";


contract SRCToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20("SRC", "SRC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}