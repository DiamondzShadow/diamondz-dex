// This script would be used with Hardhat to deploy all contracts
const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // Use existing token
  const existingTokenAddress = "0x0e5BDba7B52f7ed1245DaCC9E1105792856ca3df";
  console.log("Using existing token at:", existingTokenAddress);

  // Deploy WETH
  console.log("Deploying WETH...");
  const WETH = await ethers.getContractFactory("WETH");
  const weth = await WETH.deploy();
  await weth.deployed();
  console.log("WETH deployed to:", weth.address);

  // Deploy DiamondFactory
  console.log("Deploying DiamondFactory...");
  const DiamondFactory = await ethers.getContractFactory("DiamondFactory");
  const diamondFactory = await DiamondFactory.deploy();
  await diamondFactory.deployed();
  console.log("DiamondFactory deployed to:", diamondFactory.address);

  // Set fee recipient to deployer
  await diamondFactory.setFeeTo(deployer.address);
  console.log("Set fee recipient to:", deployer.address);

  // Deploy DiamondRouter
  console.log("Deploying DiamondRouter...");
  const DiamondRouter = await ethers.getContractFactory("DiamondRouter");
  const diamondRouter = await DiamondRouter.deploy(diamondFactory.address, weth.address);
  await diamondRouter.deployed();
  console.log("DiamondRouter deployed to:", diamondRouter.address);

  // Create initial pair
  console.log("Creating initial pair...");
  await diamondFactory.createPair(weth.address, existingTokenAddress);
  const pairAddress = await diamondFactory.getPair(weth.address, existingTokenAddress);
  console.log("Initial pair created at:", pairAddress);

  // Update the config file with the deployed addresses
  console.log("\nUpdate your lib/chain-config.ts file with these addresses:");
  console.log(`
export const contractAddresses = {
  diamondRouter: "${diamondRouter.address}",
  diamondFactory: "${diamondFactory.address}",
  diamondToken: "${existingTokenAddress}",
  WETH: "${weth.address}",
}
`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
