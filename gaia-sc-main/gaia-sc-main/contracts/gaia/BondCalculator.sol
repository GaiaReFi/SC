// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.7.5;

import "../libs/SafeMath.sol";
import "../libs/FixedPoint.sol";
import "../libs/Address.sol";
import "../libs/SafeERC20.sol";

import "../interfaces/IERC20.sol";
import "../interfaces/IBondCalculator.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract GaiaBondCalculator is IBondCalculator {
    using FixedPoint for *;
    using SafeMath for uint256;
    using SafeMath for uint112;

    address public immutable GAIA;

    constructor(address _GAIA) {
        require(_GAIA != address(0));
        GAIA = _GAIA;
    }

    function getKValue(address _pair) public view returns (uint256 k_) {
        uint256 token0 = IERC20(IUniswapV2Pair(_pair).token0()).decimals();
        uint256 token1 = IERC20(IUniswapV2Pair(_pair).token1()).decimals();
        uint256 tokenDecimals = token0.add(token1);
        uint256 pairDecimals = IERC20(_pair).decimals();
        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(_pair)
            .getReserves();
        k_ = reserve0.mul(reserve1);
        if (tokenDecimals > pairDecimals) {
            k_ = k_.div(10**(tokenDecimals - pairDecimals));
        } else if (tokenDecimals < pairDecimals) {
            k_ = k_.mul(10**(pairDecimals - tokenDecimals));
        }
    }

    function getTotalValue(address _pair) public view returns (uint256 _value) {
        _value = getKValue(_pair).sqrrt().mul(2);
    }

    function valuation(address _pair, uint256 amount_)
        external
        view
        override
        returns (uint256 _value)
    {
        uint256 totalValue = getTotalValue(_pair);
        uint256 totalSupply = IUniswapV2Pair(_pair).totalSupply();

        _value = totalValue
            .mul(FixedPoint.fraction(amount_, totalSupply).decode112with18())
            .div(1e18);
    }

    function markdown(address _pair) external view override returns (uint256) {
        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(_pair)
            .getReserves();

        uint256 reserve;
        if (IUniswapV2Pair(_pair).token0() == GAIA) {
            reserve = reserve1;
        } else {
            reserve = reserve0;
        }
        return
            reserve.mul(2 * (10**IERC20(GAIA).decimals())).div(
                getTotalValue(_pair)
            );
    }
}
