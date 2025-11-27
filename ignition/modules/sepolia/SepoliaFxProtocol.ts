import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { ZeroAddress } from "ethers";

/**
 * Sepolia 测试网简化部署模块
 * 
 * 这个模块部署 f(x) Protocol 的核心合约到 Sepolia 测试网
 * 包括：FxUSD, PoolManager, FxUSDBasePool, PegKeeper
 */
export default buildModule("SepoliaFxProtocol", (m) => {
  const admin = m.getAccount(0);
  
  // ============================================
  // 1. 部署基础设施
  // ============================================
  const ProxyAdmin = m.contract("ProxyAdmin", [admin], { id: "ProxyAdmin" });
  const EmptyContract = m.contract("EmptyContract", [], { id: "EmptyContract" });
  
  // ============================================
  // 2. 部署 Mock 代币（使用主网代币名称）
  // ============================================
  const MockUSDC = m.contract("MockERC20", ["USD Coin", "USDC", 6], { id: "MockUSDC" });
  const MockWstETH = m.contract("MockERC20", ["Wrapped liquid staked Ether 2.0", "wstETH", 18], { id: "MockWstETH" });
  
  // 给部署者铸造 10^15 个代币
  const mintAmountUSDC = 1000000000000000n * 1000000n; // 10^15 USDC (6 decimals)
  const mintAmountWstETH = 1000000000000000n * 1000000000000000000n; // 10^15 wstETH (18 decimals)
  
  m.call(MockUSDC, "mint", [admin, mintAmountUSDC], { 
    id: "MockUSDC_mint",
    after: [MockUSDC]
  });
  
  m.call(MockWstETH, "mint", [admin, mintAmountWstETH], { 
    id: "MockWstETH_mint",
    after: [MockWstETH]
  });
  
  // ============================================
  // 3. 部署 Mock 价格预言机
  // ============================================
  // USDC/USD = $1.00 (8 decimals)
  const MockUSDCOracle = m.contract("MockAggregatorV3Interface", [
    8,
    100000000n, // $1.00
  ], { id: "MockUSDCOracle" });
  
  // ETH/USD = $3000.00 (8 decimals)
  const MockETHOracle = m.contract("MockAggregatorV3Interface", [
    8,
    300000000000n, // $3000.00
  ], { id: "MockETHOracle" });
  
  // ============================================
  // 4. 部署代理合约（使用 EmptyContract 作为初始实现）
  // 注意：使用 v4 版本的 TransparentUpgradeableProxy，因为它允许我们指定已存在的 ProxyAdmin
  // ============================================
  const PoolManagerProxy = m.contract("TransparentUpgradeableProxyV4", 
    [EmptyContract, ProxyAdmin, "0x"], 
    { id: "PoolManagerProxy" }
  );
  
  const FxUSDBasePoolProxy = m.contract("TransparentUpgradeableProxyV4", 
    [EmptyContract, ProxyAdmin, "0x"], 
    { id: "FxUSDBasePoolProxy" }
  );
  
  const PegKeeperProxy = m.contract("TransparentUpgradeableProxyV4", 
    [EmptyContract, ProxyAdmin, "0x"], 
    { id: "PegKeeperProxy" }
  );
  
  const FxUSDProxy = m.contract("TransparentUpgradeableProxyV4", 
    [EmptyContract, ProxyAdmin, "0x"], 
    { id: "FxUSDProxy" }
  );
  
  // ============================================
  // 5. 先部署 PoolManager 实现合约（不初始化）
  // ============================================
  const PoolManagerImplementation = m.contract("PoolManager", 
    [FxUSDProxy, FxUSDBasePoolProxy, PegKeeperProxy, ZeroAddress, ZeroAddress], // configuration, whitelist
    { id: "PoolManagerImplementation" }
  );
  
  // ============================================
  // 6. 部署 ReservePool 和 RevenuePool（使用 PoolManagerProxy 地址）
  // ============================================
  const ReservePool = m.contract("ReservePool", [admin, PoolManagerProxy], { 
    id: "ReservePool",
    after: [PoolManagerImplementation]
  });
  const RevenuePool = m.contract("RevenuePool", [admin, admin, admin], { 
    id: "RevenuePool",
    after: [PoolManagerImplementation]
  });
  
  // ============================================
  // 7. 初始化 PoolManager
  // ============================================
  const PoolManagerInitializer = m.encodeFunctionCall(
    PoolManagerImplementation, 
    "initialize", 
    [
      admin,
      0n, // initial protocol fee ratio
      m.getParameter("HarvesterRatio", 100000000n), // 10%
      m.getParameter("FlashLoanFeeRatio", 1000000n), // 0.1%
      admin, // Treasury address
      RevenuePool,
      ReservePool,
    ]
  );
  
  const PoolManagerUpgradeCall = m.call(ProxyAdmin, "upgradeAndCall", 
    [PoolManagerProxy, PoolManagerImplementation, PoolManagerInitializer],
    { 
      id: "PoolManagerProxy_upgradeAndCall",
      after: [ReservePool, RevenuePool]
    }
  );
  
  // ============================================
  // 8. 部署并初始化 FxUSDBasePool
  // ============================================
  // 编码 Chainlink 价格源
  // 格式: | 32 bits heartbeat | 64 bits scale | 160 bits price_feed |
  // 对于测试，我们使用: heartbeat=86400 (1天), scale=1e18, price_feed=MockUSDCOracle地址
  // 注意：这里我们直接传递 MockUSDCOracle 地址，因为在测试环境中不需要复杂的编码
  const FxUSDBasePoolImplementation = m.contract("FxUSDBasePool", [
    PoolManagerProxy,
    PegKeeperProxy,
    FxUSDProxy,
    MockUSDC,
    MockUSDCOracle, // 直接传递 oracle 地址
  ], { id: "FxUSDBasePoolImplementation" });
  
  const FxUSDBasePoolInitializer = m.encodeFunctionCall(
    FxUSDBasePoolImplementation, 
    "initialize", 
    [
      admin,
      "fxUSD Save",
      "fxBASE",
      m.getParameter("StableDepegPrice", 990000000000000000n), // 0.99
      m.getParameter("RedeemCoolDownPeriod", 3600n), // 1 hour
    ]
  );
  
  const FxUSDBasePoolUpgradeCall = m.call(ProxyAdmin, "upgradeAndCall", 
    [FxUSDBasePoolProxy, FxUSDBasePoolImplementation, FxUSDBasePoolInitializer],
    { 
      id: "FxUSDBasePoolProxy_upgradeAndCall",
      after: [PoolManagerUpgradeCall]
    }
  );
  
  // ============================================
  // 9. 部署并初始化 PegKeeper
  // ============================================
  const PegKeeperImplementation = m.contract("PegKeeper", [FxUSDBasePoolProxy], {
    id: "PegKeeperImplementation",
    after: [FxUSDBasePoolUpgradeCall]
  });
  
  const PegKeeperInitializer = m.encodeFunctionCall(
    PegKeeperImplementation, 
    "initialize", 
    [
      admin,
      ZeroAddress, // converter - 暂时不设置
      ZeroAddress, // curve pool - 暂时不设置
    ]
  );
  
  const PegKeeperUpgradeCall = m.call(ProxyAdmin, "upgradeAndCall", 
    [PegKeeperProxy, PegKeeperImplementation, PegKeeperInitializer],
    { 
      id: "PegKeeperProxy_upgradeAndCall",
      after: [FxUSDBasePoolUpgradeCall]
    }
  );
  
  // ============================================
  // 10. 部署并初始化 FxUSD
  // ============================================
  const FxUSDImplementation = m.contract("FxUSDRegeneracy", [
    PoolManagerProxy,
    MockUSDC,
    PegKeeperProxy,
  ], { 
    id: "FxUSDImplementation",
    after: [PegKeeperUpgradeCall]
  });
  
  const FxUSDInitializer = m.encodeFunctionCall(
    FxUSDImplementation, 
    "initialize", 
    ["f(x) USD", "fxUSD"]
  );
  
  const FxUSDUpgradeCall = m.call(ProxyAdmin, "upgradeAndCall", 
    [FxUSDProxy, FxUSDImplementation, FxUSDInitializer],
    { 
      id: "FxUSDProxy_upgradeAndCall",
      after: [PegKeeperUpgradeCall]
    }
  );
  
  // ============================================
  // 11. 配置 PoolManager 参数
  // ============================================
  const PoolManager = m.contractAt("PoolManager", PoolManagerProxy, { id: "PoolManager" });
  
  m.call(PoolManager, "updateExpenseRatio", [
    m.getParameter("RewardsExpenseRatio", 200000000n), // 20%
    m.getParameter("FundingExpenseRatio", 200000000n), // 20%
    m.getParameter("LiquidationExpenseRatio", 200000000n), // 20%
  ], { 
    id: "PoolManager_updateExpenseRatio",
    after: [FxUSDUpgradeCall] 
  });
  
  m.call(PoolManager, "updateRedeemFeeRatio", [
    m.getParameter("RedeemFeeRatio", 5000000n) // 0.5%
  ], { 
    id: "PoolManager_updateRedeemFeeRatio",
    after: [FxUSDUpgradeCall] 
  });
  
  // ============================================
  // 12. 返回部署的合约
  // ============================================
  return {
    // 基础设施
    ProxyAdmin,
    EmptyContract,
    
    // Mock 代币
    MockUSDC,
    MockWstETH,
    MockUSDCOracle,
    MockETHOracle,
    
    // 核心合约（代理）
    PoolManager,
    FxUSDBasePool: m.contractAt("FxUSDBasePool", FxUSDBasePoolProxy, { id: "FxUSDBasePool" }),
    PegKeeper: m.contractAt("PegKeeper", PegKeeperProxy, { id: "PegKeeper" }),
    FxUSD: m.contractAt("FxUSDRegeneracy", FxUSDProxy, { id: "FxUSD" }),
    
    // 实现合约
    PoolManagerImplementation,
    FxUSDBasePoolImplementation,
    PegKeeperImplementation,
    FxUSDImplementation,
    
    // 辅助合约
    ReservePool,
    RevenuePool,
  };
});
