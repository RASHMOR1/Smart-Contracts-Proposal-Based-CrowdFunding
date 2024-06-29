// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUsdtContract is ERC20 {
    constructor(uint256 initialSupply, address recipient) ERC20("Tether", "USDT") {
        _mint(recipient, initialSupply);
        //transfer(recipient, initialSupply);
    }
}
