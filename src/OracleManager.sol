// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IOracle} from "src/interfaces/IOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IterableMapAddress} from "src/lib/IterableMapAddress.sol";

abstract contract OracleManager is Ownable, IOracle {
    using IterableMapAddress for IterableMapAddress.IterableMapAddressStorage;

    IterableMapAddress.IterableMapAddressStorage private oracle;
    
    function setOracle(address asset, IOracle _oracle) external onlyOwner {
        oracle.set(asset, address(_oracle));
    }

    function value(address asset, uint256 amount) external view override returns (uint256) {
        return IOracle(oracle.get(asset)).value(asset, amount);
    }


    function oracleFor(address asset) external view returns (IOracle) {
        return IOracle(oracle.get(asset));
    }

    function supportedTokens() external view returns (address[] memory) {
        return oracle.getKeys();
    }
}