// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.7.5;

import "../access/Policy.sol";
import "../libs/SafeERC20.sol";

contract TaxProcessor is Policy {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address GAIA;
    address DAO;
    address depository;
    address marketingAddress;

    //out of 10000
    uint256 public bondDeposit = 500;
    uint256 public bondMarketing = 500;

    modifier onlyNativeTokenOrPolicy() {
        require(msg.sender == GAIA || msg.sender == _policy);
        _;
    }

    constructor(
        address _GAIA,
        address _depository,
        address _marketingAddress,
        address _DAO
    ) {
        require(_GAIA != address(0));
        GAIA = _GAIA;
        depository = _depository;
        marketingAddress = _marketingAddress;
        DAO = _DAO;
    }

    function distributeBondProceeds(uint256 _amount) external {
        uint256 depositBalance = _amount.mul(bondDeposit).div(10000);
        uint256 marketingBalance = _amount.mul(bondMarketing).div(10000);
        uint256 daoBalance = _amount.sub(depositBalance).sub(marketingBalance);
        transferTokens(GAIA, depository, depositBalance);
        transferTokens(GAIA, marketingAddress, marketingBalance);
        transferTokens(GAIA, DAO, daoBalance);
    }

    function distributeTaxes(
        uint256 depositBalance,
        uint256 marketingBalance,
        address targetToken
    ) public onlyNativeTokenOrPolicy {
        transferTokens(targetToken, depository, depositBalance);
        transferTokens(targetToken, marketingAddress, marketingBalance);
    }

    function emergencyWithdrawTaxTokens(
        address withdrawToken,
        uint256 withdrawAmount
    ) public onlyPolicy {
        IERC20(withdrawToken).safeTransfer(msg.sender, withdrawAmount);
    }

    function transferTokens(
        address targetToken,
        address recipientAddress,
        uint256 amount
    ) internal {
        uint256 tokenBalance = IERC20(targetToken).balanceOf(address(this));
        if (tokenBalance >= amount) {
            IERC20(targetToken).safeTransfer(recipientAddress, amount);
        }
    }
}
