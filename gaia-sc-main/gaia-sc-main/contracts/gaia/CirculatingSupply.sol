// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

import "../libs/SafeMath.sol";
import "../interfaces/IERC20.sol";

contract CirculatingSupply {
    using SafeMath for uint256;

    bool public isInitialized;

    address public GAIA;
    address public owner;
    address[] public nonCirculatingGAIAAddresses;

    constructor() {
        owner = msg.sender;
    }

    function initialize(address _gaia) external returns (bool) {
        require(msg.sender == owner, "Sender is not owner");
        require(isInitialized == false);

        GAIA = _gaia;

        isInitialized = true;

        return true;
    }

    function GAIACirculatingSupply() external view returns (uint256) {
        uint256 _totalSupply = IERC20(GAIA).totalSupply();

        uint256 _circulatingSupply = _totalSupply.sub(getNonCirculatingGAIA());

        return _circulatingSupply;
    }

    function getNonCirculatingGAIA() public view returns (uint256) {
        uint256 _nonCirculatingGAIA;

        for (
            uint256 i = 0;
            i < nonCirculatingGAIAAddresses.length;
            i = i.add(1)
        ) {
            _nonCirculatingGAIA = _nonCirculatingGAIA.add(
                IERC20(GAIA).balanceOf(nonCirculatingGAIAAddresses[i])
            );
        }

        return _nonCirculatingGAIA;
    }

    function setNonCirculatingGAIAAddresses(
        address[] calldata _nonCirculatingAddresses
    ) external returns (bool) {
        require(msg.sender == owner, "Sender is not owner");
        nonCirculatingGAIAAddresses = _nonCirculatingAddresses;

        return true;
    }

    function transferOwnership(address _owner) external returns (bool) {
        require(msg.sender == owner, "Sender is not owner");

        owner = _owner;

        return true;
    }
}
