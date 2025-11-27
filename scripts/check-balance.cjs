const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  
  console.log("Deployer address:", deployer.address);
  console.log("Balance:", hre.ethers.formatEther(balance), "ETH");
  
  if (balance === 0n) {
    console.log("\n⚠️  WARNING: Account has no ETH!");
    console.log("Please get test ETH from:");
    console.log("  - https://sepoliafaucet.com/");
    console.log("  - https://www.alchemy.com/faucets/ethereum-sepolia");
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
