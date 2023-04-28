// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "../libs/Address.sol";
import "../libs/SafeMath.sol";
import "../libs/SafeERC20.sol";
import "../libs/Counters.sol";
import "../interfaces/IERC20.sol";
import "../types/ERC20Permit.sol";
import "../interfaces/ITaxProcessor.sol";
import "../access/VaultOwned.sol";

contract GAIA is ERC20Permit, VaultOwned {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    mapping(address => IUniswapV2Router02) public routerForPair; //router address corresponding to pair address
    address[] public pairs;
    uint256 public accumulatedTax;

    address public taxProcessor;

    bool private _isInSwap;
    bool public autoSwapEnabled = true;
    uint256 private _numTokensAutoSwap = 1000 * 10**9;
    address private _overrideSwapPair;
    mapping(address => bool) private _isExcludedFromFee;

    uint256 public taxDepository = 150;

    uint256 public taxMarketingBuy = 250;
    uint256 public taxMarketingSell = 400;

    modifier lockTheSwap() {
        _isInSwap = true;
        _;
        _isInSwap = false;
    }

    event Taxes(uint256 tokensSwapped);

    constructor() ERC20("GAIA token", "GAIA", 9) {
        _isExcludedFromFee[msg.sender] = true;
        _isExcludedFromFee[address(this)] = true;
    }

    function setPairs(address[] memory _pairs, address[] memory _routers)
        external
        onlyOwner
    {
        pairs = _pairs;
        for (uint256 i = 0; i < pairs.length; i++) {
            routerForPair[pairs[i]] = IUniswapV2Router02(_routers[i]);
        }
    }

    function setTaxes(
        uint256 _taxMarketingBuy,
        uint256 _taxMarketingSell,
        uint256 _taxDepository
    ) external onlyOwner {
        taxMarketingBuy = _taxMarketingBuy;
        taxMarketingSell = _taxMarketingSell;
        taxDepository = _taxDepository;
    }

    function mint(address account_, uint256 amount_) external onlyVault {
        _mint(account_, amount_);
    }

    function burn(uint256 amount) public virtual {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account_, uint256 amount_) public virtual {
        _burnFrom(account_, amount_);
    }

    function _burnFrom(address account_, uint256 amount_) private {
        uint256 decreasedAllowance_ = allowance(account_, msg.sender).sub(
            amount_,
            "ERC20: burn amount exceeds allowance"
        );

        _approve(account_, msg.sender, decreasedAllowance_);
        _burn(account_, amount_);
    }

    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function isExcludedFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account];
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "ERC20: transfer amount cannot be 0");

        uint256 contractTokenBalance = balanceOf(address(this));
        bool shouldAutoSwap = contractTokenBalance >= _numTokensAutoSwap;

        if (
            shouldAutoSwap &&
            !_isInSwap &&
            !_isDEXPair(sender) &&
            _isDEXPair(recipient) &&
            autoSwapEnabled
        ) {
            address autoSwapPair = recipient;
            if (_overrideSwapPair != address(0))
                autoSwapPair = _overrideSwapPair;
            _processTaxes(autoSwapPair, contractTokenBalance);
        }

        uint256 depository_tax;
        uint256 marketing_tax;

        if (!_isExcludedFromFee[sender] && !_isExcludedFromFee[recipient]) {
            bool isTransferBuy = _isDEXPair(sender);
            bool isTransferSell = _isDEXPair(recipient);

            if (isTransferBuy) {
                depository_tax = amount.mul(taxDepository).div(10000);
                marketing_tax = amount.mul(taxMarketingBuy).div(10000);
            } else if (isTransferSell) {
                depository_tax = amount.mul(taxDepository).div(10000);
                marketing_tax = amount.mul(taxMarketingSell).div(10000);
            }
        }

        _balances[sender] = _balances[sender].sub(
            amount,
            "ERC20: transfer amount exceeds balance"
        );
        _balances[recipient] = _balances[recipient].add(
            amount.sub(marketing_tax).sub(depository_tax)
        );
        _balances[address(this)] = _balances[address(this)]
            .add(marketing_tax)
            .add(depository_tax);
        accumulatedTax = accumulatedTax.add(depository_tax);

        emit Transfer(sender, recipient, amount);
    }

    function setTaxProcessor(address _taxProcessor) external onlyOwner {
        taxProcessor = _taxProcessor;
    }

    function setupTaxesProcessing(
        bool _enabled,
        uint256 _numTokensMin,
        address __overrideSwapPair
    ) public onlyOwner {
        autoSwapEnabled = _enabled;
        _numTokensAutoSwap = _numTokensMin;
        _overrideSwapPair = __overrideSwapPair;
    }

    function manuallyProcessTaxes(address pair) public onlyOwner {
        uint256 contractTokenBalance = balanceOf(address(this));
        _processTaxes(pair, contractTokenBalance);
    }

    function emergencyWithdrawTaxTokens(
        uint256 _newaccumulatedTaxBalance,
        address withdrawToken,
        uint256 withdrawAmount
    ) public onlyOwner {
        IERC20(withdrawToken).safeTransfer(msg.sender, withdrawAmount);
        accumulatedTax = _newaccumulatedTaxBalance;
    }

    function _processTaxes(address pair, uint256 contractTokenBalance)
        private
        lockTheSwap
    {
        IUniswapV2Router02 router = routerForPair[pair];
        address targetToken = _getPairedToken(pair);
        _swapNativeTokens(contractTokenBalance, router, targetToken);
        uint256 tokenBalance = IERC20(targetToken).balanceOf(taxProcessor);
        if (tokenBalance > 100) {
            uint256 depositBalance = tokenBalance.mul(accumulatedTax).div(
                contractTokenBalance
            );
            uint256 marketingBalance = tokenBalance.sub(depositBalance);
            ITaxProcessor(taxProcessor).distributeTaxes(
                depositBalance,
                marketingBalance,
                targetToken
            );
            emit Taxes(contractTokenBalance);
            accumulatedTax = 0;
        }
    }

    function _swapNativeTokens(
        uint256 tokenAmount,
        IUniswapV2Router02 router,
        address targetToken
    ) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = targetToken;

        _approve(address(this), address(router), tokenAmount);

        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            taxProcessor,
            block.timestamp
        );
    }

    function _getPairedToken(address pair) private view returns (address) {
        address pairedToken;
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        pairedToken = token0;
        if (token0 == address(this)) pairedToken = token1;
        return pairedToken;
    }

    function _isDEXPair(address pair) private view returns (bool) {
        for (uint256 i = 0; i < pairs.length; i++) {
            if (pairs[i] == pair) return true;
        }
        return false;
    }
}
