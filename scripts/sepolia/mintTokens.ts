import { ethers } from "hardhat";

/**
 * 铸造测试代币脚本
 * 
 * 使用方法：
 * npx hardhat run scripts/sepolia/mintTokens.ts --network sepolia
 */
async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Minting tokens with account:", deployer.address);
  
  // 从部署文件读取合约地址
  const deploymentPath = "./ignition/deployments/chain-11155111/deployed_addresses.json";
  const fs = await import("fs");
  const deployedAddresses = JSON.parse(fs.readFileSync(deploymentPath, "utf8"));
  
  const mockUSDCAddress = deployedAddresses["SepoliaFxProtocol#MockUSDC"];
  const mockWstETHAddress = deployedAddresses["SepoliaFxProtocol#MockWstETH"];
  
  if (!mockUSDCAddress || !mockWstETHAddress) {
    throw new Error("Mock token addresses not found in deployment file");
  }
  
  console.log("MockUSDC address:", mockUSDCAddress);
  console.log("MockWstETH address:", mockWstETHAddress);
  
  // 获取合约实例
  const mockUSDC = await ethers.getContractAt("MockERC20", mockUSDCAddress);
  const mockWstETH = await ethers.getContractAt("MockERC20", mockWstETHAddress);
  
  // 铸造 USDC (6 decimals)
  const usdcAmount = ethers.parseUnits("10000", 6); // 10,000 USDC
  console.log("\nMinting USDC...");
  const usdcTx = await mockUSDC.mint(deployer.address, usdcAmount);
  await usdcTx.wait();
  console.log("✓ Minted 10,000 USDC");
  
  // 铸造 wstETH (18 decimals)
  const wstETHAmount = ethers.parseEther("10"); // 10 wstETH
  console.log("\nMinting wstETH...");
  const wstETHTx = await mockWstETH.mint(deployer.address, wstETHAmount);
  await wstETHTx.wait();
  console.log("✓ Minted 10 wstETH");
  
  // 查询余额
  const usdcBalance = await mockUSDC.balanceOf(deployer.address);
  const wstETHBalance = await mockWstETH.balanceOf(deployer.address);
  
  console.log("\n=== Balances ===");
  console.log("USDC:", ethers.formatUnits(usdcBalance, 6));
  console.log("wstETH:", ethers.formatEther(wstETHBalance));
  
  console.log("\n✓ Done!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
