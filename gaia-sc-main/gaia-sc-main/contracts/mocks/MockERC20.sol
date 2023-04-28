// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockERC20 is ERC20, Ownable {
    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        _setupDecimals(6);
        _mint(owner(), 1_000_000_000_000);
    }

    function mint(address to, uint256 value) public onlyOwner virtual {
        _mint(to, value);
    }

    function burn(address from, uint256 value) public onlyOwner virtual {
        _burn(from, value);
    }
}
