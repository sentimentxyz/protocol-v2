// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IOracle} from "src/interfaces/IOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IterableMapAddress} from "src/lib/IterableMapAddress.sol";

abstract contract LoanManager is Ownable, IOracle {
    using IterableMapAddress for IterableMapAddress.IterableMapAddressStorage;

    error InvalidLTV();
    error InvalidOracle();

    IterableMapAddress.IterableMapAddressStorage private oracle;
    mapping(address => uint256) public loanToValueBP;

    function setOracle(address asset, address _oracle, uint256 _ltv) external onlyOwner {
        if (_ltv > 10000 || _ltv == 0) revert InvalidLTV();
        if (_oracle == address(0)) revert InvalidOracle();

        oracle.set(asset, _oracle);
        loanToValueBP[asset] = _ltv;
    }

    function removeOracle(address asset) external onlyOwner {
        oracle.remove(asset);
        loanToValueBP[asset] = 0;
    }

    function value(address asset, uint256 amount) public view override returns (uint256) {
        return IOracle(oracle.get(asset)).value(asset, amount);
    }


    function oracleFor(address asset) external view returns (IOracle) {
        return IOracle(oracle.get(asset));
    }

    function supportedTokens() external view returns (address[] memory) {
        return oracle.getKeys();
    }

    function ltv(address asset) external view returns (uint256) {
        return loanToValueBP[asset];
    }
}