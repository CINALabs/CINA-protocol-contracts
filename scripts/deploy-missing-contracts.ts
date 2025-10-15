import { ethers } from "hardhat";

async function main() {
  console.log("🚀 开始部署 Sepolia 缺失的合约...\n");

  const [deployer] = await ethers.getSigners();
  console.log("📍 部署账户:", deployer.address);
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("💰 余额:", ethers.formatEther(balance), "ETH\n");

  const addresses = {
    PoolManager: "0xbb644076500ea106d9029b382c4d49f56225cb82",
    FxUSD: "0x085a1b6da46ae375b35dea9920a276ef571e209c",
    FxUSDBasePool: "0x420D6b8546F14C394A703F5ac167619760A721A9",
    PegKeeper: "0x628648849647722144181c9CB5bbE0CCadd50029",
    ReservePool: "0x3908720b490a2368519318dD15295c22cd494e34",
    RevenuePool: "0x54AC8d19ffc522246d9b87ED956de4Fa0590369A",
    ProxyAdmin: "0x7bc6535d75541125fb3b494decfde10db20c16d8",
    USDC: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
  };

  const deployed: { [key: string]: string } = {};

  // ============ 1. 部署 PoolConfiguration ============
  console.log("═══════════════════════════════════════");
  console.log("1️⃣  部署 PoolConfiguration");
  console.log("═══════════════════════════════════════\n");

  try {
    // 检查是否已存在
    const poolManager = await ethers.getContractAt("PoolManager", addresses.PoolManager);
    const existingConfig = await poolManager.configuration();
    
    if (existingConfig !== ethers.ZeroAddress) {
      console.log("✓ PoolConfiguration 已存在:", existingConfig);
      deployed.PoolConfiguration = existingConfig;
    } else {
      console.log("⚠️  PoolConfiguration 未设置，需要部署...");
      
      // 部署 PoolConfiguration Implementation
      const PoolConfiguration = await ethers.getContractFactory("PoolConfiguration");
      const poolConfigImpl = await PoolConfiguration.deploy(
        addresses.FxUSDBasePool,
        ethers.ZeroAddress, // LendingPool (Aave) - Sepolia 上可能不存在
        addresses.USDC
      );
      await poolConfigImpl.waitForDeployment();
      const poolConfigImplAddr = await poolConfigImpl.getAddress();
      console.log("✓ PoolConfiguration Implementation 已部署:", poolConfigImplAddr);

      // 部署代理
      const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy");
      const initData = PoolConfiguration.interface.encodeFunctionData("initialize", [
        deployer.address,
        ethers.ZeroAddress, // FxUSDPriceOracle - 稍后设置
      ]);
      
      const poolConfigProxy = await TransparentUpgradeableProxy.deploy(
        poolConfigImplAddr,
        addresses.ProxyAdmin,
        initData
      );
      await poolConfigProxy.waitForDeployment();
      const poolConfigProxyAddr = await poolConfigProxy.getAddress();
      
      console.log("✓ PoolConfiguration Proxy 已部署:", poolConfigProxyAddr);
      deployed.PoolConfiguration = poolConfigProxyAddr;

      // 等待确认
      console.log("⏳ 等待交易确认...");
      await new Promise(resolve => setTimeout(resolve, 10000));
    }
  } catch (e: any) {
    console.log("❌ PoolConfiguration 部署失败:", e.message);
  }

  // ============ 2. 部署 Mock Price Oracle ============
  console.log("\n═══════════════════════════════════════");
  console.log("2️⃣  部署 Mock Price Oracle (用于测试)");
  console.log("═══════════════════════════════════════\n");

  try {
    const MockPriceOracle = await ethers.getContractFactory("MockTwapOracle");
    const mockOracle = await MockPriceOracle.deploy();
    await mockOracle.waitForDeployment();
    const mockOracleAddr = await mockOracle.getAddress();
    
    console.log("✓ MockPriceOracle 已部署:", mockOracleAddr);
    deployed.MockPriceOracle = mockOracleAddr;

    // 设置价格 (1 USDC = 1 USD)
    await mockOracle.setPrice(ethers.parseEther("1"));
    console.log("✓ 设置默认价格: 1.0 USD");

    await new Promise(resolve => setTimeout(resolve, 5000));
  } catch (e: any) {
    console.log("❌ MockPriceOracle 部署失败:", e.message);
  }

  // ============ 3. 配置 AaveFundingPool 使用 Mock Oracle ============
  console.log("\n═══════════════════════════════════════");
  console.log("3️⃣  配置 AaveFundingPool");
  console.log("═══════════════════════════════════════\n");

  if (deployed.MockPriceOracle) {
    try {
      const aavePool = await ethers.getContractAt(
        "AaveFundingPool",
        "0xAb20B978021333091CA307BB09E022Cec26E8608"
      );

      // 检查当前 oracle
      const currentOracle = await aavePool.priceOracle();
      console.log("当前 Price Oracle:", currentOracle);

      if (currentOracle === ethers.ZeroAddress) {
        console.log("⚠️  需要更新 Price Oracle");
        console.log("⚠️  注意: AaveFundingPool 可能需要重新部署或升级才能设置 Oracle");
        console.log("   如果合约不支持 updatePriceOracle 方法，需要:");
        console.log("   1. 部署新的 AaveFundingPool Implementation");
        console.log("   2. 使用 ProxyAdmin 升级代理");
      }
    } catch (e: any) {
      console.log("❌ 配置失败:", e.message);
    }
  }

  // ============ 4. 检查是否需要部署 PoolConfiguration 注册的合约 ============
  if (deployed.PoolConfiguration) {
    console.log("\n═══════════════════════════════════════");
    console.log("4️⃣  配置 PoolConfiguration");
    console.log("═══════════════════════════════════════\n");

    try {
      const poolConfig = await ethers.getContractAt("PoolConfiguration", deployed.PoolConfiguration);
      
      // 检查是否需要部署 ProtocolTreasury
      const poolRewardsTreasury = ethers.id("PoolRewardsTreasury");
      try {
        await poolConfig.get(poolRewardsTreasury);
        console.log("✓ PoolRewardsTreasury 已注册");
      } catch {
        console.log("⚠️  需要部署并注册 ProtocolTreasury");
        
        // 部署 ProtocolTreasury
        const ProtocolTreasury = await ethers.getContractFactory("ProtocolTreasury");
        const treasuryImpl = await ProtocolTreasury.deploy();
        await treasuryImpl.waitForDeployment();
        const treasuryImplAddr = await treasuryImpl.getAddress();
        
        const TransparentUpgradeableProxy = await ethers.getContractFactory("TransparentUpgradeableProxy");
        const initData = ProtocolTreasury.interface.encodeFunctionData("initialize", [deployer.address]);
        
        const treasuryProxy = await TransparentUpgradeableProxy.deploy(
          treasuryImplAddr,
          addresses.ProxyAdmin,
          initData
        );
        await treasuryProxy.waitForDeployment();
        const treasuryProxyAddr = await treasuryProxy.getAddress();
        
        console.log("✓ ProtocolTreasury 已部署:", treasuryProxyAddr);
        deployed.ProtocolTreasury = treasuryProxyAddr;

        // 注册到 PoolConfiguration
        await poolConfig.register(poolRewardsTreasury, treasuryProxyAddr);
        console.log("✓ 已注册 PoolRewardsTreasury");

        await new Promise(resolve => setTimeout(resolve, 5000));
      }
    } catch (e: any) {
      console.log("❌ PoolConfiguration 配置失败:", e.message);
    }
  }

  // ============ 总结 ============
  console.log("\n═══════════════════════════════════════");
  console.log("📋 部署总结");
  console.log("═══════════════════════════════════════\n");

  console.log("已部署的合约:");
  Object.entries(deployed).forEach(([name, address]) => {
    console.log(`✓ ${name}: ${address}`);
  });

  console.log("\n⚠️  重要提醒:");
  console.log("1. 检查 AaveFundingPool 是否需要重新部署以支持 Price Oracle");
  console.log("2. 如果需要完整功能，考虑部署 Router 系统");
  console.log("3. Mock Price Oracle 仅用于测试，生产环境需要真实价格源");
  console.log("4. 记得更新 DEPLOYMENT_ADDRESSES.md 文档");
  
  console.log("\n✅ 部署完成!\n");

  // 保存部署地址
  const fs = require("fs");
  const deploymentLog = `
# Sepolia 新部署的合约地址
部署时间: ${new Date().toISOString()}
部署账户: ${deployer.address}

${Object.entries(deployed).map(([name, addr]) => `- **${name}**: \`${addr}\``).join('\n')}
`;
  
  fs.appendFileSync("DEPLOYMENT_ADDRESSES.md", deploymentLog);
  console.log("📝 部署地址已保存到 DEPLOYMENT_ADDRESSES.md");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

