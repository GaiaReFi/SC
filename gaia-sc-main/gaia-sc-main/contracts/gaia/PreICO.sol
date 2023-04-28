// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

import "../access/Ownable.sol";
import "../libs/SafeMath.sol";
import "../libs/SafeERC20.sol";
import "../interfaces/ITreasury.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract GaiaPreICO is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public GAIA;
    address public USDC;
    address public gaia_usdc_lp;
    address public treasury;

    uint256 public totalAmount; //GAIA available during presale
    uint256 public offeringAmount; //GAIA available during presale
    uint256 public maxAllotmentPerBuyer; //GAIA available to be purchased per wallet (in wei)
    uint256 public salePrice; //USDC per GAIA during presale. Denominated in USDC
    uint256 public openPrice; //planned opening price for GAIA
    uint256 public startOfSale; //when presale starts
    uint256 public endOfWLSale; //when WL presale ends
    uint256 public endOfEntireSale; //when entire presale ends

    uint256 public daoAllocation; //out of 100
    uint256 public treasuryAllocation; //out of 100
    uint256 public LPAllocation; //out of 100

    bool public initialized;
    bool public cancelled;
    bool public finalized;

    mapping(address => bool) public whitelisted;
    mapping(address => uint256) public purchasedAmount;
    address[] buyers;

    constructor(
        address _GAIA,
        address _USDC,
        address _treasury,
        address _gaia_usdc_lp
    ) {
        require(_GAIA != address(0));
        require(_USDC != address(0));
        require(_treasury != address(0));
        require(_gaia_usdc_lp != address(0));

        GAIA = _GAIA;
        USDC = _USDC;
        treasury = _treasury;
        gaia_usdc_lp = _gaia_usdc_lp;
    }

    function saleStarted() public view returns (bool) {
        return initialized && startOfSale <= block.timestamp;
    }

    function saleFinished() public view returns (bool) {
        return block.timestamp >= endOfEntireSale;
    }

    function whitelistBuyers(address[] memory _buyers)
        external
        onlyOwner
        returns (bool)
    {
        require(saleStarted() == false, "Already started");
        for (uint256 i; i < _buyers.length; i++) {
            whitelisted[_buyers[i]] = true;
        }
        return true;
    }

    function initialize(
        uint256 _totalAmount,
        uint256 _salePrice,
        uint256 _openPrice,
        uint256 _saleLength,
        uint256 _wlSaleLength,
        uint256 _startOfSale,
        uint256 _daoAllocation,
        uint256 _treasuryAllocation,
        uint256 _maxAllotmentPerBuyer
    ) external onlyOwner returns (bool) {
        require(initialized == false, "Already initialized");
        initialized = true;
        totalAmount = _totalAmount;
        offeringAmount = _totalAmount;
        salePrice = _salePrice;
        openPrice = _openPrice;
        startOfSale = _startOfSale;
        endOfEntireSale = _startOfSale.add(_saleLength);
        endOfWLSale = _startOfSale.add(_wlSaleLength);
        daoAllocation = _daoAllocation;
        treasuryAllocation = _treasuryAllocation;
        LPAllocation = uint256(100).sub(daoAllocation).sub(treasuryAllocation);
        maxAllotmentPerBuyer = _maxAllotmentPerBuyer;
        return true;
    }

    function purchaseGAIA(uint256 _amountUSDC) external returns (bool) {
        require(saleStarted(), "Not started");
        require(!saleFinished(), "Sale finished");
        require(!finalized, "Sale finalized");
        require(!cancelled, "Sale cancelled");
        require(_amountUSDC > 0, "Must be greater than 0");
        if (block.timestamp < endOfWLSale)
            require(
                whitelisted[msg.sender],
                "Only whitelisted members can buy at the moment"
            );

        uint256 _purchaseAmount = _calculateSaleQuote(_amountUSDC);
        require(
            (purchasedAmount[msg.sender] + _purchaseAmount) <=
                maxAllotmentPerBuyer,
            "Exceeds max allotment per buyer"
        );

        require(_purchaseAmount <= totalAmount, "Sold out!");
        totalAmount = totalAmount.sub(_purchaseAmount);
        purchasedAmount[msg.sender] =
            purchasedAmount[msg.sender] +
            _purchaseAmount;
        buyers.push(msg.sender);
        IERC20(USDC).safeTransferFrom(msg.sender, address(this), _amountUSDC);

        return true;
    }

    function _calculateSaleQuote(uint256 paymentAmount_)
        internal
        view
        returns (uint256)
    {
        return uint256(1e9).mul(paymentAmount_).div(salePrice);
    }

    function calculateSaleQuote(uint256 paymentAmount_)
        external
        view
        returns (uint256)
    {
        return _calculateSaleQuote(paymentAmount_);
    }

    function cancel() external onlyOwner {
        cancelled = true;
        startOfSale = type(uint256).max;
    }

    function updateCoreAddresses(
        address _treasury,
        address _gaia,
        address _lp
    ) external onlyOwner {
        treasury = _treasury;
        GAIA = _gaia;
        gaia_usdc_lp = _lp;
    }

    function withdraw() external {
        require(cancelled, "IDO is not cancelled");
        uint256 amount = purchasedAmount[msg.sender];
        IERC20(USDC).safeTransfer(msg.sender, (amount / 1e9) * salePrice);
    }

    function withdrawEmergency() external onlyOwner {
        uint256 usdcBalance = IERC20(USDC).balanceOf(address(this));
        IERC20(USDC).safeTransfer(msg.sender, usdcBalance);
    }

    function withdrawRemainingGAIA() external onlyOwner {
        uint256 gaiaBalance = IERC20(GAIA).balanceOf(address(this));
        IERC20(GAIA).safeTransfer(msg.sender, gaiaBalance);
    }

    function claim(address _recipient) public {
        require(finalized, "Sale is not finalized yet");
        require(purchasedAmount[_recipient] > 0, "Not purchased");
        uint256 purchased = purchasedAmount[_recipient];
        purchasedAmount[_recipient] = 0;
        IERC20(GAIA).safeTransfer(msg.sender, purchased);
    }

    function addLiquidity(uint256 gaiaAmount, uint256 usdcAmount) private {
        IERC20(GAIA).transfer(gaia_usdc_lp, gaiaAmount);
        IERC20(USDC).transfer(gaia_usdc_lp, usdcAmount);
        IUniswapV2Pair(gaia_usdc_lp).mint(msg.sender);
    }

    function finalize() external onlyOwner {
        uint256 usdcBalance = IERC20(USDC).balanceOf(address(this));
        uint256 gaiaNeeded = usdcBalance.mul(1e9).div(salePrice);
        uint256 usdc_dao = usdcBalance.mul(daoAllocation).div(100);
        uint256 usdc_treasury = usdcBalance.mul(treasuryAllocation).div(100);
        uint256 usdc_liquidity = usdcBalance.sub(usdc_dao).sub(usdc_treasury);
        uint256 gaia_liquidity = usdc_liquidity.mul(1e9).div(openPrice);
        gaiaNeeded = gaiaNeeded + gaia_liquidity;
        gaiaNeeded = gaiaNeeded.mul(102).div(100); //to avoid rounding errors

        //depositing funds into treasury; directing minted GAIA into LP pool
        IERC20(USDC).approve(treasury, usdc_treasury);
        uint256 gaiaTreasuryValuation = usdc_treasury.mul(1e9).div(1e6);
        ITreasury(treasury).deposit(
            usdc_treasury,
            USDC,
            gaiaTreasuryValuation.sub(gaiaNeeded)
        );

        addLiquidity(gaia_liquidity, usdc_liquidity);
        uint256 usdc_left = IERC20(USDC).balanceOf(address(this));
        IERC20(USDC).safeTransfer(msg.sender, usdc_left);

        finalized = true;
    }
}
