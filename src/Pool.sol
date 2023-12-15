// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract Pool is Ownable, Pausable, ERC4626 {
    uint256 public lastUpdated;

    constructor(IERC20 asset, string memory name_, string memory symbol_)
        Ownable(msg.sender)
        ERC20(name_, symbol_)
        ERC4626(asset)
    {}

    function ping() public {
        // TODO interest accrual logic
        lastUpdated = block.timestamp;
    }
}
