import { ethers } from "hardhat";

async function main() {
  console.log("🔍 检查 AaveFundingPool 初始化状态...\n");

  const addresses = {
    AaveFundingPoolProxy: "0xAb20B978021333091CA307BB09E022Cec26E8608",
    AaveFundingPoolImpl: "0x33263fF0D348427542ee4dBF9069d411ac43718E",
    ProxyAdmin: "0x7bc6535d75541125fb3b494deCfdE10Db20C16d8",
  };

  const [deployer] = await ethers.getSigners();
  console.log("📍 检查账户:", deployer.address);

  // ============ 检查代理配置 ============
  console.log("═══════════════════════════════════════");
  console.log("1️⃣  检查代理配置");
  console.log("═══════════════════════════════════════\n");

  try {
    const proxyAdmin = await ethers.getContractAt("ProxyAdmin", addresses.ProxyAdmin);
    
    // 获取当前实现地址
    const implementation = await proxyAdmin.getProxyImplementation(addresses.AaveFundingPoolProxy);
    console.log("✓ 当前实现地址:", implementation);
    console.log("  期望地址:", addresses.AaveFundingPoolImpl);
    console.log("  ", implementation.toLowerCase() === addresses.AaveFundingPoolImpl.toLowerCase() ? "✅ 匹配" : "❌ 不匹配");

    // 获取代理管理员
    const admin = await proxyAdmin.getProxyAdmin(addresses.AaveFundingPoolProxy);
    console.log("\n✓ 代理管理员:", admin);
    console.log("  期望地址:", addresses.ProxyAdmin);
    console.log("  ", admin.toLowerCase() === addresses.ProxyAdmin.toLowerCase() ? "✅ 匹配" : "❌ 不匹配");

  } catch (error: any) {
    console.log("❌ 检查代理配置失败:", error.message);
  }

  // ============ 检查合约代码 ============
  console.log("\n═══════════════════════════════════════");
  console.log("2️⃣  检查合约代码");
  console.log("═══════════════════════════════════════\n");

  const proxyCode = await ethers.provider.getCode(addresses.AaveFundingPoolProxy);
  const implCode = await ethers.provider.getCode(addresses.AaveFundingPoolImpl);

  console.log("✓ 代理合约代码大小:", proxyCode.length, "bytes");
  console.log("✓ 实现合约代码大小:", implCode.length, "bytes");

  if (proxyCode === "0x" || implCode === "0x") {
    console.log("\n❌ 错误: 合约代码不存在!");
    return;
  }

  // ============ 尝试读取状态变量 ============
  console.log("\n═══════════════════════════════════════");
  console.log("3️⃣  尝试读取合约状态");
  console.log("═══════════════════════════════════════\n");

  // 使用最基本的 ABI
  const basicAbi = [
    "function collateral() view returns (address)",
    "function poolManager() view returns (address)",
    "function priceOracle() view returns (address)",
    "function hasRole(bytes32,address) view returns (bool)",
  ];

  try {
    const aavePool = await ethers.getContractAt(basicAbi, addresses.AaveFundingPoolProxy);

    console.log("尝试读取基本信息...");

    try {
      const collateral = await aavePool.collateral();
      console.log("✅ collateral():", collateral);
    } catch (e: any) {
      console.log("❌ collateral() 失败:", e.message.split('\n')[0]);
    }

    try {
      const poolManager = await aavePool.poolManager();
      console.log("✅ poolManager():", poolManager);
    } catch (e: any) {
      console.log("❌ poolManager() 失败:", e.message.split('\n')[0]);
    }

    try {
      const priceOracle = await aavePool.priceOracle();
      console.log("✅ priceOracle():", priceOracle);
    } catch (e: any) {
      console.log("❌ priceOracle() 失败:", e.message.split('\n')[0]);
    }

    try {
      const hasRole = await aavePool.hasRole(ethers.ZeroHash, deployer.address);
      console.log("✅ hasRole(DEFAULT_ADMIN_ROLE):", hasRole);
    } catch (e: any) {
      console.log("❌ hasRole() 失败:", e.message.split('\n')[0]);
    }

  } catch (error: any) {
    console.log("❌ 无法连接到合约:", error.message);
  }

  // ============ 尝试直接调用实现合约 ============
  console.log("\n═══════════════════════════════════════");
  console.log("4️⃣  直接检查实现合约");
  console.log("═══════════════════════════════════════\n");

  try {
    const implContract = await ethers.getContractAt("AaveFundingPool", addresses.AaveFundingPoolImpl);
    
    console.log("尝试从实现合约读取...");

    try {
      const poolManager = await implContract.poolManager();
      console.log("✅ poolManager():", poolManager);
    } catch (e: any) {
      console.log("❌ poolManager() 失败:", e.message.split('\n')[0]);
    }

  } catch (error: any) {
    console.log("❌ 无法连接到实现合约:", error.message);
  }

  // ============ 分析和建议 ============
  console.log("\n═══════════════════════════════════════");
  console.log("📋 诊断总结");
  console.log("═══════════════════════════════════════\n");

  console.log("如果上述所有读取都失败，可能的原因:");
  console.log("1. 合约未正确初始化");
  console.log("2. 代理未正确指向实现");
  console.log("3. 实现合约有bug或编译问题");
  console.log("4. Storage layout 不匹配");

  console.log("\n建议的解决方案:");
  console.log("1. 重新部署 AaveFundingPool Implementation");
  console.log("2. 使用 ProxyAdmin 升级代理");
  console.log("3. 如果是新部署，使用 upgradeAndCall 同时初始化");

  console.log("\n示例修复命令:");
  console.log("```bash");
  console.log("# 1. 部署新的实现");
  console.log("npx hardhat run scripts/redeploy-aave-impl.ts --network sepolia");
  console.log("");
  console.log("# 2. 升级并初始化");
  console.log("npx hardhat run scripts/upgrade-aave-pool.ts --network sepolia");
  console.log("```");

  console.log("\n✅ 检查完成!\n");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

