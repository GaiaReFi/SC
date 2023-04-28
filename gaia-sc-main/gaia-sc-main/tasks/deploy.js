task("deploy", "Deploy tokenomic", async (_taskArgs, hre) => {
    const [deployer] = await ethers.getSigners();
    console.log('Deploying contracts with the account: ' + deployer.address);
    // Ethereum 0 address, used when toggling changes in treasury
    const zeroAddress = '0x0000000000000000000000000000000000000000';
    // USDC address(mainnet)
    // const USDCAddress = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
    // USDC address(Goerli testnet)
    const USDCAddress = "0x07865c6e87b9f70255377e024ace6630c1eaa37f";
    // DAO address
    const DAOAddress = "0xFc057F4Ac537e6c68581177AEa9040e9429412a2";
    // Large number for approval for USDC
    const largeApproval = '100000000000000000000000000000000';
    // USDC bond BCV
    const usdcBondBCV = '70';
    // LP bond BCV
    const lpBondBCV = '30';
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
    const initialBondDebt = '0';

    // get usdc contract from abi
    const usdcAbi = require("../helpers/abis/USDC.js");
    const usdc = new ethers.Contract(USDCAddress, usdcAbi, deployer);

    // deploy mock USDC token contract
    // const MockERC20 = await ethers.getContractFactory("MockERC20");
    // const usdc = await MockERC20.deploy("Mock USDC", "USDC");

    // await usdc.mint(deployer.address, ethers.utils.parseUnits('1000000', 6));

    // Deploy GAIA
    const GAIA = await ethers.getContractFactory('GAIA');
    const gaia = await GAIA.deploy();

    // Deploy circulating supply
    const CirculatingSupply = await ethers.getContractFactory('CirculatingSupply');
    const circSupply = await CirculatingSupply.deploy();

    // Deploy treasury
    const Treasury = await ethers.getContractFactory('GaiaTreasury');
    const treasury = await Treasury.deploy(gaia.address, usdc.address, 0);

    // Deploy bonding calc
    const GaiaBondCalculator = await ethers.getContractFactory('GaiaBondCalculator');
    const gaiaBondCalculator = await GaiaBondCalculator.deploy(gaia.address);

    // Deploy LP bond
    const LpBond = await ethers.getContractFactory('GaiaBondDepository');
    const lpBond = await LpBond.deploy(gaia.address, process.env.GAIA_USDC_LP, treasury.address, DAOAddress, gaiaBondCalculator.address);
    // Set LP bond terms
    await lpBond.initializeBondTerms(lpBondBCV, minBondPrice, maxBondPayout, bondFee, maxBondDebt, initialBondDebt, bondVestingLength);

    // Deploy USDC bond
    const USDCBond = await ethers.getContractFactory('GaiaBondDepository');
    const usdcBond = await USDCBond.deploy(gaia.address, usdc.address, treasury.address, DAOAddress, zeroAddress);
    // Set usdc bond terms
    await usdcBond.initializeBondTerms(usdcBondBCV, minBondPrice, maxBondPayout, bondFee, maxBondDebt, initialBondDebt, bondVestingLength);

    // Set treasury for GAIA token
    await gaia.setVault(treasury.address);

    // Approve the treasury to spend USDC
    await usdc.approve(treasury.address, largeApproval);

    // Approve USDC bonds to spend deployer's USDC
    await usdc.approve(usdcBond.address, largeApproval);

    // deploy tax processor
    const TaxProcessor = await ethers.getContractFactory("TaxProcessor");
    const taxProcessor = await TaxProcessor.deploy(gaia.address, usdcBond.address, deployer.address, DAOAddress);

    await gaia.setTaxProcessor(taxProcessor.address);

    console.log("USDC: " + usdc.address);
    console.log("GAIA: " + gaia.address);
    console.log("Circulating Supply: " + circSupply.address);
    console.log("Treasury: " + treasury.address);
    console.log("Bond Calculator: " + gaiaBondCalculator.address);
    console.log("LP Bond Depository: " + lpBond.address);
    console.log("USDC Bond Depository: " + usdcBond.address);
    console.log("TaxProcessor: " + taxProcessor.address);

    // To wait 5 blocks
    await taxProcessor.deployTransaction.wait(5);

    //verify gaia token smart contract code with etherscan
    await hre.run("verify:verify", {
        address: gaia.address,
        constructorArguments: []
    });

    //verify circulating supply smart contract code with etherscan
    await hre.run("verify:verify", {
        address: circSupply.address,
        constructorArguments: []
    });

    //verify treasury smart contract code with etherscan
    await hre.run("verify:verify", {
        address: treasury.address,
        constructorArguments: [gaia.address, usdc.address, 0]
    });

    //verify bond calculator smart contract code with etherscan
    await hre.run("verify:verify", {
        address: gaiaBondCalculator.address,
        constructorArguments: [gaia.address]
    });

    //verify usdc bond depository smart contract code with etherscan
    await hre.run("verify:verify", {
        address: usdcBond.address,
        constructorArguments: [gaia.address, usdc.address, treasury.address, DAOAddress, zeroAddress]
    });

    //verify LP bond depository smart contract code with etherscan
    await hre.run("verify:verify", {
        address: lpBond.address,
        constructorArguments: [gaia.address, process.env.GAIA_USDC_LP, treasury.address, DAOAddress, gaiaBondCalculator.address]
    });

    // verify tax processor smart contract code with etherscan
    await hre.run("verify:verify", {
        address: taxProcessor.address,
        constructorArguments: [gaia.address, usdcBond.address, deployer.address, DAOAddress]
    });
});

task("queue", "Queue address in the GaiaTreasury contract")
    .addParam("id", "Managing id")
    .addParam("address", "an address to be queued")
    .setAction(async (_taskArgs, hre) => {
        const [deployer] = await ethers.getSigners();
        const treasuryArtifact = artifacts.readArtifactSync("GaiaTreasury");
        const treasury = new ethers.Contract(process.env.TREASURY_ADDRESS, treasuryArtifact.abi, deployer);
        await treasury.queue(_taskArgs.id, _taskArgs.address);
    });

task("toggle", "Toggle address in the GaiaTreasury contract")
    .addParam("id", "Managing id")
    .addParam("address", "an address to be queued")
    .addParam("bondcalc","address of bond calculator")
    .setAction(async (_taskArgs, hre) => {
        const [deployer] = await ethers.getSigners();
        const treasuryArtifact = artifacts.readArtifactSync("GaiaTreasury");
        const treasury = new ethers.Contract(process.env.TREASURY_ADDRESS, treasuryArtifact.abi, deployer);
        await treasury.toggle(_taskArgs.id, _taskArgs.address, _taskArgs.bondcalc);
    });

task("deposit", "Deposit USDC in the GaiaTreasury contract")
    .addParam("usdc", "USDC amount to deposit")
    .addParam("profit", "excess reserves")
    .setAction(async (_taskArgs, hre) => {
        const [deployer] = await ethers.getSigners();
        const treasuryArtifact = artifacts.readArtifactSync("GaiaTreasury");
        const treasury = new ethers.Contract(process.env.TREASURY_ADDRESS, treasuryArtifact.abi, deployer);
        // Deposit 30 USDC to treasury, 2 GAIA gets minted to deployer and 28 are in treasury as excesss reserves
        await treasury.deposit(ethers.utils.parseUnits(_taskArgs.usdc, 6), process.env.USDC_ADDRESS, ethers.utils.parseUnits(_taskArgs.profit, 9));
    });

task("deployICO", "Deploy ICO", async (_taskArgs, hre) => {
    const [deployer] = await ethers.getSigners();
    console.log('Deploying contracts with the account: ' + deployer.address);
    const GAIA_ADDRESS = process.env.GAIA_ADDRESS;
    const USDC_ADDRESS = process.env.USDC_ADDRESS;
    const TREASURY_ADDRESS = process.env.TREASURY_ADDRESS;
    const LP_ADDRESS = process.env.LP_ADDRESS;
    // Deploy ICO
    const PreICO = await ethers.getContractFactory('GaiaPreICO');
    const preICO = await PreICO.deploy(GAIA_ADDRESS, USDC_ADDRESS, TREASURY_ADDRESS, LP_ADDRESS);
    await preICO.deployed();

    console.log("ICO address:", preICO.address);
    // To wait 5 blocks
    await preICO.deployTransaction.wait(5);

    //verify smart contract code with etherscan
    await hre.run("verify:verify", {
        address: preICO.address,
        constructorArguments: [GAIA_ADDRESS, USDC_ADDRESS, TREASURY_ADDRESS, LP_ADDRESS]
    });
});
