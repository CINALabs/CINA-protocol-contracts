import { ethers } from "hardhat";

async function main() {
  console.log("🔍 开始诊断 Sepolia 部署状态...\n");

  const addresses = {
    FxUSD: "0x085a1b6da46ae375b35dea9920a276ef571e209c",
    PoolManager: "0xbb644076500ea106d9029b382c4d49f56225cb82",
    FxUSDBasePool: "0x420D6b8546F14C394A703F5ac167619760A721A9",
    PegKeeper: "0x628648849647722144181c9CB5bbE0CCadd50029",
    AaveFundingPool: "0xAb20B978021333091CA307BB09E022Cec26E8608",
    ReservePool: "0x3908720b490a2368519318dD15295c22cd494e34",
    RevenuePool: "0x54AC8d19ffc522246d9b87ED956de4Fa0590369A",
  };

  const [deployer] = await ethers.getSigners();
  console.log("📍 检查账户:", deployer.address);
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("💰 余额:", ethers.formatEther(balance), "ETH\n");

  // ============ 检查 PoolManager ============
  console.log("═══════════════════════════════════════");
  console.log("📊 PoolManager 检查");
  console.log("═══════════════════════════════════════");
  
  try {
    const poolManager = await ethers.getContractAt("PoolManager", addresses.PoolManager);
    
    // 检查初始化
    const hasAdminRole = await poolManager.hasRole(ethers.ZeroHash, deployer.address);
    console.log("✓ DEFAULT_ADMIN_ROLE:", hasAdminRole ? "✅" : "❌");

    // 检查 configuration
    try {
      const config = await poolManager.configuration();
      console.log("✓ Configuration 地址:", config);
      
      if (config === ethers.ZeroAddress) {
        console.log("  ⚠️  警告: Configuration 未设置");
      }
    } catch (e) {
      console.log("❌ 无法读取 configuration");
    }

    // 检查 counterparty
    try {
      const counterparty = await poolManager.counterparty();
      console.log("✓ Counterparty (PegKeeper):", counterparty);
    } catch (e) {
      console.log("❌ 无法读取 counterparty");
    }

    // 检查注册的池子
    try {
      const poolInfo = await poolManager.getPoolInfo(addresses.AaveFundingPool);
      console.log("✓ AaveFundingPool 注册状态:");
      console.log("  - Collateral Capacity:", ethers.formatUnits(poolInfo.collateralCapacity, 6), "USDC");
      console.log("  - Debt Capacity:", ethers.formatEther(poolInfo.debtCapacity), "fxUSD");
    } catch (e: any) {
      console.log("❌ AaveFundingPool 未注册或读取失败:", e.message);
    }

  } catch (e: any) {
    console.log("❌ PoolManager 检查失败:", e.message);
  }

  // ============ 检查 AaveFundingPool ============
  console.log("\n═══════════════════════════════════════");
  console.log("🏦 AaveFundingPool 检查");
  console.log("═══════════════════════════════════════");
  
  try {
    const aavePool = await ethers.getContractAt("AaveFundingPool", addresses.AaveFundingPool);
    
    // 检查 Price Oracle
    try {
      const oracle = await aavePool.priceOracle();
      console.log("✓ Price Oracle 地址:", oracle);
      
      if (oracle === ethers.ZeroAddress) {
        console.log("  ❌ 致命问题: Price Oracle 未设置!");
      } else {
        // 尝试获取价格
        try {
          const [price, valid] = await aavePool.getPrice();
          console.log("  ✓ 当前价格:", ethers.formatEther(price));
          console.log("  ✓ 价格有效性:", valid ? "✅" : "❌");
        } catch (e: any) {
          console.log("  ❌ 无法获取价格:", e.message);
        }
      }
    } catch (e: any) {
      console.log("❌ 无法读取 Price Oracle:", e.message);
    }

    // 检查池子参数
    try {
      const params = await aavePool.getPoolParameters();
      console.log("✓ 池子参数:");
      console.log("  - Open Ratio:", ethers.formatEther(params.openRatio));
      console.log("  - Close Fee:", ethers.formatUnits(params.closeFeeRatio, 9));
    } catch (e: any) {
      console.log("❌ 无法读取池子参数:", e.message);
    }

    // 检查 Debt Ratio 范围
    try {
      const [lower, upper] = await aavePool.getDebtRatioRange();
      console.log("✓ Debt Ratio 范围:");
      console.log("  - Lower:", ethers.formatEther(lower));
      console.log("  - Upper:", ethers.formatEther(upper));
    } catch (e: any) {
      console.log("❌ 无法读取 Debt Ratio 范围:", e.message);
    }

    // 检查借贷状态
    try {
      const canBorrow = await aavePool.canBorrow();
      const canRedeem = await aavePool.canRedeem();
      console.log("✓ 借贷状态:");
      console.log("  - Can Borrow:", canBorrow ? "✅" : "❌");
      console.log("  - Can Redeem:", canRedeem ? "✅" : "❌");
    } catch (e: any) {
      console.log("❌ 无法读取借贷状态:", e.message);
    }

  } catch (e: any) {
    console.log("❌ AaveFundingPool 检查失败:", e.message);
  }

  // ============ 检查 FxUSD ============
  console.log("\n═══════════════════════════════════════");
  console.log("💵 FxUSD 检查");
  console.log("═══════════════════════════════════════");
  
  try {
    const fxUSD = await ethers.getContractAt("FxUSDRegeneracy", addresses.FxUSD);
    
    const poolManagerRole = ethers.keccak256(ethers.toUtf8Bytes("POOL_MANAGER_ROLE"));
    const hasRole = await fxUSD.hasRole(poolManagerRole, addresses.PoolManager);
    console.log("✓ PoolManager 拥有 POOL_MANAGER_ROLE:", hasRole ? "✅" : "❌");
    
    if (!hasRole) {
      console.log("  ⚠️  需要授予权限!");
    }

  } catch (e: any) {
    console.log("❌ FxUSD 检查失败:", e.message);
  }

  // ============ 检查 FxUSDBasePool ============
  console.log("\n═══════════════════════════════════════");
  console.log("🏊 FxUSDBasePool 检查");
  console.log("═══════════════════════════════════════");
  
  try {
    const basePool = await ethers.getContractAt("FxUSDBasePool", addresses.FxUSDBasePool);
    
    const poolManagerRole = ethers.keccak256(ethers.toUtf8Bytes("POOL_MANAGER_ROLE"));
    const hasRole = await basePool.hasRole(poolManagerRole, addresses.PoolManager);
    console.log("✓ PoolManager 拥有 POOL_MANAGER_ROLE:", hasRole ? "✅" : "❌");

    try {
      const totalAssets = await basePool.totalAssets();
      console.log("✓ Total Assets:", ethers.formatEther(totalAssets), "fxUSD");
    } catch (e: any) {
      console.log("❌ 无法读取 totalAssets:", e.message);
    }

  } catch (e: any) {
    console.log("❌ FxUSDBasePool 检查失败:", e.message);
  }

  // ============ 检查缺失的合约 ============
  console.log("\n═══════════════════════════════════════");
  console.log("🔎 检查主网存在但 Sepolia 缺失的合约");
  console.log("═══════════════════════════════════════");

  const missingContracts = [];

  // 检查 Router (Diamond)
  try {
    const code = await ethers.provider.getCode("0x33636D49FbefBE798e15e7F356E8DBef543CC708");
    if (code === "0x") {
      missingContracts.push("Router (Diamond Proxy)");
    } else {
      console.log("✓ Router 已部署");
    }
  } catch {
    missingContracts.push("Router (Diamond Proxy)");
  }

  // 检查 StETHPriceOracle
  try {
    const code = await ethers.provider.getCode("0x3716352d57C2e48EEdB56Ee0712Ef29E0c2f3069");
    if (code === "0x") {
      missingContracts.push("StETHPriceOracle");
    } else {
      console.log("✓ StETHPriceOracle 已部署");
    }
  } catch {
    missingContracts.push("StETHPriceOracle");
  }

  // 检查 WstETHPool
  const wstETHPoolAddress = "0x6Ecfa38FeE8a5277B91eFdA204c235814F0122E8";
  try {
    const code = await ethers.provider.getCode(wstETHPoolAddress);
    if (code === "0x") {
      missingContracts.push("WstETHPool (Long Pool)");
    } else {
      console.log("✓ WstETHPool 已部署");
    }
  } catch {
    missingContracts.push("WstETHPool (Long Pool)");
  }

  console.log("\n❌ 缺失的合约:");
  if (missingContracts.length === 0) {
    console.log("  ✅ 所有主要合约都已部署");
  } else {
    missingContracts.forEach(contract => {
      console.log(`  - ${contract}`);
    });
  }

  // ============ 总结 ============
  console.log("\n═══════════════════════════════════════");
  console.log("📋 诊断总结");
  console.log("═══════════════════════════════════════");
  console.log("\n建议的下一步操作:");
  console.log("1. 检查 PoolManager 的 configuration 是否已设置");
  console.log("2. 验证 AaveFundingPool 的 Price Oracle 配置");
  console.log("3. 确认所有必要的角色权限已授予");
  console.log("4. 考虑部署缺失的合约（Router, WstETHPool 等）");
  console.log("\n完成诊断 ✓\n");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

