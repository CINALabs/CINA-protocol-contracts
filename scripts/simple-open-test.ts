import { ethers } from "hardhat";

async function main() {
  console.log("🧪 简单开仓测试...\n");

  const [deployer] = await ethers.getSigners();
  console.log("📍 测试账户:", deployer.address);

  const addresses = {
    PoolManager: "0xbb644076500ea106d9029b382c4d49f56225cb82",
    AaveFundingPool: "0xAb20B978021333091CA307BB09E022Cec26E8608",
    USDC: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
  };

  const poolManager = await ethers.getContractAt("PoolManager", addresses.PoolManager);
  const usdc = await ethers.getContractAt("IERC20", addresses.USDC);

  // 检查 USDC 余额
  const balance = await usdc.balanceOf(deployer.address);
  console.log("USDC 余额:", ethers.formatUnits(balance, 6), "USDC\n");

  if (balance === 0n) {
    console.log("❌ USDC 余额为 0，无法测试");
    return;
  }

  // 准备开仓参数
  const testAmount = 1000000n; // 1 USDC
  const debtAmount = 500000n;  // 0.5 USDC worth of fxUSD (18 decimals)
  const debtAmountWei = ethers.parseEther("0.5"); // 0.5 fxUSD
  const positionId = 1n; // 使用固定 ID

  console.log("开仓参数:");
  console.log("  - Pool:", addresses.AaveFundingPool);
  console.log("  - Position ID:", positionId.toString());
  console.log("  - Collateral:", ethers.formatUnits(testAmount, 6), "USDC");
  console.log("  - Debt:", ethers.formatEther(debtAmountWei), "fxUSD\n");

  // 检查并授权
  const allowance = await usdc.allowance(deployer.address, addresses.PoolManager);
  if (allowance < testAmount) {
    console.log("授权 USDC...");
    const tx = await usdc.approve(addresses.PoolManager, ethers.MaxUint256);
    await tx.wait();
    console.log("✅ 授权成功\n");
  }

  // 尝试开仓
  console.log("执行开仓...");
  try {
    const tx = await poolManager["operate(address,uint256,int256,int256)"](
      addresses.AaveFundingPool,
      positionId,
      testAmount,
      debtAmountWei,
      { gasLimit: 500000 }
    );
    console.log("交易已发送:", tx.hash);
    
    const receipt = await tx.wait();
    console.log("✅ 开仓成功!");
    console.log("Gas 使用:", receipt?.gasUsed.toString());
    console.log("区块:", receipt?.blockNumber);

    // 检查仓位
    try {
      const position = await poolManager.getPosition(addresses.AaveFundingPool, positionId);
      console.log("\n仓位信息:");
      console.log("  - Collateral:", ethers.formatUnits(position[0], 6), "USDC");
      console.log("  - Debt:", ethers.formatEther(position[1]), "fxUSD");
    } catch (e) {
      console.log("⚠️  无法读取仓位（可能使用了不同的存储结构）");
    }

  } catch (e: any) {
    console.log("❌ 开仓失败");
    console.log("错误:", e.message.split('\n')[0]);
    
    if (e.data) {
      console.log("错误数据:", e.data);
    }

    // 常见错误原因
    console.log("\n可能的原因:");
    console.log("  1. Price Oracle 未设置 (collateral() reverts)");
    console.log("  2. 池子未正确初始化");
    console.log("  3. Debt ratio 参数不正确");
    console.log("  4. Configuration 未设置");
  }

  console.log("\n✅ 测试完成\n");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

