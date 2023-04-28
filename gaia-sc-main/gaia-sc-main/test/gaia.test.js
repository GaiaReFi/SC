const {
    time,
    loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { isCallTrace } = require("hardhat/internal/hardhat-network/stack-traces/message-trace");

describe("Gaia", function () {
    const zeroAddress = "0x0000000000000000000000000000000000000000";
    const DAOAddress = "0xFc057F4Ac537e6c68581177AEa9040e9429412a2";
    // Large number for approval for USDC
    const largeApproval = '100000000000000000000000000000000';
    // USDC bond BCV
    const usdcBondBCV = '70';
    // Bond vesting length in seconds. 432000 seconds = 5 days
    const bondVestingLength = '432000';
    // Min bond price
    const minBondPrice = '1000000';
    // Max bond payout
    const maxBondPayout = '10000';
    // DAO fee for bond
    const bondFee = '150';
    // Max debt bond can take on
    const maxBondDebt = '20000000000000';
    // Initial Bond debt
    const intialBondDebt = '0';

    async function deployGaiaFixture() {
        const [deployer, buyer1, buyer2] = await ethers.getSigners();

        // deploy GAIA token
        const GAIA = await ethers.getContractFactory("GAIA");
        const gaia = await GAIA.deploy();

        // deploy mock USDC token contract
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        const usdc = await MockERC20.deploy("Mock USDC", "USDC");

        await usdc.mint(deployer.address, ethers.utils.parseUnits('1000000', 6));

        const Treasury = await ethers.getContractFactory("GaiaTreasury");
        const treasury = await Treasury.deploy(gaia.address, usdc.address, 0);

        // Deploy bonding calc
        const GaiaBondCalculator = await ethers.getContractFactory('GaiaBondCalculator');
        const gaiaBondCalculator = await GaiaBondCalculator.deploy(gaia.address);

        // Deploy mock USDC bond
        const USDCBond = await ethers.getContractFactory('GaiaBondDepository');
        const usdcBond = await USDCBond.deploy(gaia.address, usdc.address, treasury.address, DAOAddress, zeroAddress);

        // queue and toggle USDC bond reserve depositor
        await treasury.queue('0', usdcBond.address);
        await treasury.toggle('0', usdcBond.address, zeroAddress);

        // Set usdc bond terms
        await usdcBond.initializeBondTerms(usdcBondBCV, minBondPrice, maxBondPayout, bondFee, maxBondDebt, intialBondDebt, bondVestingLength);

        // gaia set treasury as vault
        await gaia.setVault(treasury.address);

        // queue and toggle deployer reserve depositor
        await treasury.queue(0, deployer.address);
        await treasury.toggle(0, deployer.address, zeroAddress);

        // queue and toggle liquidity depositor
        await treasury.queue(4, deployer.address);
        await treasury.toggle(4, deployer.address, zeroAddress);

        // Approve the treasury to spend USDC
        await usdc.approve(treasury.address, largeApproval);

        // Approve USDC bonds to spend deployer's USDC
        await usdc.approve(usdcBond.address, largeApproval);

        // deploy tax processor
        const TaxProcessor = await ethers.getContractFactory("TaxProcessor");
        const taxProcessor = await TaxProcessor.deploy(gaia.address, usdcBond.address, deployer.address, DAOAddress);

        await gaia.setTaxProcessor(taxProcessor.address);

        // Deposit 9,000,000 USDC to treasury, 600,000 GAIA gets minted to deployer and 8,400,000 are in treasury as excesss reserves
        await treasury.deposit(ethers.utils.parseUnits('30000', 6), usdc.address, ethers.utils.parseUnits('28000', 9));

        return { gaia, treasury, usdc, usdcBond, gaiaBondCalculator, deployer, buyer1, buyer2 };
    }

    describe("Deployment", function () {
        it("Success", async function () {
            const { gaia, treasury, usdc, usdcBond, deployer } = await loadFixture(deployGaiaFixture);
            expect(await gaia.name()).to.equal("GAIA token");
            expect(await gaia.symbol()).to.equal("GAIA");
            expect(await gaia.decimals()).to.equal(9);
            expect(await gaia.owner()).to.equal(deployer.address);
            expect(await gaia.totalSupply()).to.equal(ethers.utils.parseUnits('2000', 9));

            expect(await treasury.isReserveToken(usdc.address)).to.be.true;
            expect(await treasury.isReserveDepositor(usdcBond.address)).to.be.true;
            expect(await treasury.isReserveDepositor(deployer.address)).to.be.true;
            expect(await treasury.isLiquidityDepositor(deployer.address)).to.be.true;

            expect((await usdcBond.terms()).fee).to.be.equal(bondFee);
            expect((await usdcBond.terms()).maxPayout).to.be.equal(maxBondPayout);
            expect((await usdcBond.terms()).maxDebt).to.be.equal(maxBondDebt);

            const bondPrice = await usdcBond["bondPriceInUSD()"]();
        });

        it("Deposit USDC", async function () {
            const { gaia, treasury, usdc, usdcBond, deployer } = await loadFixture(deployGaiaFixture);
            const amount = ethers.utils.parseUnits('1', 6);
            const treasuryBalanceBefore = await usdc.balanceOf(treasury.address);
            await expect(usdcBond.deposit(amount, 60000, deployer.address)).to.not.be.reverted;
            expect(await usdc.balanceOf(DAOAddress)).to.be.equal(amount.mul(bondFee).div(10000));
            expect(await usdc.balanceOf(usdcBond.address)).to.be.equal(0);
            const amountWithoutFee = amount.sub(amount.mul(bondFee).div(10000));
            expect(await usdc.balanceOf(treasury.address)).to.be.equal(treasuryBalanceBefore.add(amountWithoutFee));
        });

        it("Redeem GAIA", async function () {
            const { gaia, treasury, usdc, usdcBond, deployer, buyer1 } = await loadFixture(deployGaiaFixture);
            const amount = ethers.utils.parseUnits('1', 6);
            await expect(usdcBond.deposit(amount, 10000000, buyer1.address)).to.not.be.reverted;
            await ethers.provider.send("evm_increaseTime", [3600 * 24 * 2]);
            await ethers.provider.send("evm_mine");
            await expect(usdcBond.redeem(buyer1.address)).to.not.be.reverted;
        });
    });
});