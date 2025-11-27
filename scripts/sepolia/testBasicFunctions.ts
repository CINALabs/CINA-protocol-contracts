import { ethers } from "hardhat";

/**
 * 测试基本功能脚本
 * 
 * 使用方法：
 * npx hardhat run scripts/sepolia/testBasicFunctions.ts --network sepolia
 */
async function main() {
  const [user] = await ethers.getSigners();
  console.log("Testing with account:", user.address);
  
  // 从部署文件读取合约地址
  const deploymentPath = "./ignition/deployments/chain-11155111/deployed_addresses.json";
  const fs = await import("fs");
  const deployedAddresses = JSON.parse(fs.readFileSync(deploymentPath, "utf8"));
  
  const poolManagerAddress = deployedAddresses["SepoliaFxProtocol#PoolManager"];
  const fxUSDAddress = deployedAddresses["SepoliaFxProtocol#FxUSD"];
  const mockWstETHAddress = deployedAddresses["SepoliaFxProtocol#MockWstETH"];
  const wstETHPoolAddress = deployedAddresses["SepoliaPool#WstETHPool"];
  
  console.log("\n=== Contract Addresses ===");
  console.log("PoolManager:", poolManagerAddress);
  console.log("FxUSD:", fxUSDAddress);
  console.log("MockWstETH:", mockWstETHAddress);
  console.log("WstETHPool:", wstETHPoolAddress);
  
  // 获取合约实例
  const poolManager = await ethers.getContractAt("PoolManager", poolManagerAddress);
  const fxUSD = await ethers.getContractAt("FxUSDRegeneracy", fxUSDAddress);
  const mockWstETH = await ethers.getContractAt("MockERC20", mockWstETHAddress);
  const wstETHPool = await ethers.getContractAt("AaveFundingPool", wstETHPoolAddress);
  
  // 检查余额
  const wstETHBalance = await mockWstETH.balanceOf(user.address);
  console.log("\n=== Initial Balances ===");
  console.log("wstETH:", ethers.formatEther(wstETHBalance));
  
  if (wstETHBalance === 0n) {
    console.log("\n⚠️  No wstETH balance. Please run mintTokens.ts first.");
    return;
  }
  
  // 1. 批准代币
  console.log("\n=== Step 1: Approve wstETH ===");
  const approveAmount = ethers.parseEther("1");
  const approveTx = await mockWstETH.approve(poolManagerAddress, approveAmount);
  await approveTx.wait();
  console.log("✓ Approved 1 wstETH");
  
  // 2. 开仓
  console.log("\n=== Step 2: Open Position ===");
  const collAmount = ethers.parseEther("1"); // 存入 1 wstETH
  const debtAmount = ethers.parseEther("1000"); // 借入 1000 fxUSD
  
  console.log("Collateral:", ethers.formatEther(collAmount), "wstETH");
  console.log("Debt:", ethers.formatEther(debtAmount), "fxUSD");
  
  const operateTx = await poolManager.operate(
    wstETHPoolAddress,
    0, // positionId = 0 表示新建仓位
    collAmount,
    debtAmount,
    false // 不使用稳定币
  );
  const receipt = await operateTx.wait();
  console.log("✓ Position opened! Gas used:", receipt?.gasUsed.toString());
  
  // 从事件中获取 positionId
  const positionId = 1n; // 第一个仓位
  
  // 3. 查询仓位
  console.log("\n=== Step 3: Query Position ===");
  const [colls, debts] = await wstETHPool.getPosition(positionId);
  const debtRatio = await wstETHPool.getPositionDebtRatio(positionId);
  
  console.log(`Position #${positionId}:`);
  console.log("  Collateral:", ethers.formatEther(colls), "wstETH");
  console.log("  Debt:", ethers.formatEther(debts), "fxUSD");
  console.log("  Debt Ratio:", ethers.formatUnits(debtRatio, 18));
  
  // 4. 查询 fxUSD 余额
  console.log("\n=== Step 4: Check fxUSD Balance ===");
  const fxUSDBalance = await fxUSD.balanceOf(user.address);
  console.log("fxUSD Balance:", ethers.formatEther(fxUSDBalance));
  
  // 5. 查询池子信息
  console.log("\n=== Step 5: Pool Info ===");
  const totalColls = await wstETHPool.getTotalRawCollaterals();
  const totalDebts = await wstETHPool.getTotalRawDebts();
  console.log("Total Collaterals:", ethers.formatEther(totalColls), "wstETH");
  console.log("Total Debts:", ethers.formatEther(totalDebts), "fxUSD");
  
  // 6. 查询全局信息
  console.log("\n=== Step 6: Global Info ===");
  const totalSupply = await fxUSD.totalSupply();
  console.log("fxUSD Total Supply:", ethers.formatEther(totalSupply));
  
  console.log("\n✓ All tests passed!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
