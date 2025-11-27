import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { ZeroAddress } from "ethers";

/**
 * Sepolia 测试网池子部署模块
 * 
 * 部署一个 wstETH 池子用于测试
 */
export default buildModule("SepoliaPool", (m) => {
  const admin = m.getAccount(0);
  
  // ============================================
  // 1. 获取已部署的合约地址
  // ============================================
  const PoolManagerAddress = m.getParameter("PoolManagerProxy");
  const ProxyAdminAddress = m.getParameter("ProxyAdmin");
  const MockWstETHAddress = m.getParameter("MockWstETH");
  const MockETHOracleAddress = m.getParameter("MockETHOracle");
  
  const PoolManager = m.contractAt("PoolManager", PoolManagerAddress);
  const ProxyAdmin = m.contractAt("ProxyAdmin", ProxyAdminAddress);
  const MockWstETH = m.contractAt("MockERC20", MockWstETHAddress);
  const MockETHOracle = m.contractAt("MockAggregatorV3Interface", MockETHOracleAddress);
  
  // ============================================
  // 2. 部署价格预言机
  // ============================================
  const WstETHPriceOracle = m.contract("ETHPriceOracle", [
    MockETHOracle, // spot price oracle
    MockETHOracle, // chainlink price feed
    ZeroAddress,   // rate provider (不使用)
    50000000000000000n, // 5% 最大价格偏差
  ], { id: "WstETHPriceOracle" });
  
  // ============================================
  // 3. 部署 Pool 实现合约
  // ============================================
  const AaveFundingPoolImplementation = m.contract("AaveFundingPool", [
    PoolManagerAddress,
    ZeroAddress, // 不使用 PoolConfiguration
  ], { id: "AaveFundingPoolImplementation" });
  
  // ============================================
  // 4. 创建初始化数据
  // ============================================
  const PoolInitializer = m.encodeFunctionCall(
    AaveFundingPoolImplementation,
    "initialize",
    [
      admin,
      "f(x) wstETH Position",
      "xwstETH",
      MockWstETHAddress,
      WstETHPriceOracle,
    ]
  );
  
  // ============================================
  // 5. 部署代理合约
  // ============================================
  const WstETHPoolProxy = m.contract("TransparentUpgradeableProxy", [
    AaveFundingPoolImplementation,
    ProxyAdmin,
    PoolInitializer,
  ], { id: "WstETHPoolProxy" });
  
  const WstETHPool = m.contractAt("AaveFundingPool", WstETHPoolProxy, { id: "WstETHPool" });
  
  // ============================================
  // 6. 配置池子参数
  // ============================================
  
  // 6.1 设置债务比率范围（50% - 85.7%）
  const UpdateDebtRatioRangeCall = m.call(WstETHPool, "updateDebtRatioRange", [
    m.getParameter("DebtRatioLower", 500000000000000000n),      // 50%
    m.getParameter("DebtRatioUpper", 857142857142857142n),      // 85.7%
  ], { id: "WstETHPool_updateDebtRatioRange" });
  
  // 6.2 设置再平衡参数
  m.call(WstETHPool, "updateRebalanceRatios", [
    m.getParameter("RebalanceDebtRatio", 800000000000000000n),  // 80%
    m.getParameter("RebalanceBonusRatio", 20000000n),           // 2%
  ], { 
    id: "WstETHPool_updateRebalanceRatios",
    after: [UpdateDebtRatioRangeCall]
  });
  
  // 6.3 设置清算参数
  m.call(WstETHPool, "updateLiquidateRatios", [
    m.getParameter("LiquidateDebtRatio", 950000000000000000n),  // 95%
    m.getParameter("LiquidateBonusRatio", 40000000n),           // 4%
  ], { 
    id: "WstETHPool_updateLiquidateRatios",
    after: [UpdateDebtRatioRangeCall]
  });
  
  // 6.4 开启借贷和赎回
  m.call(WstETHPool, "updateBorrowAndRedeemStatus", [true, true], { 
    id: "WstETHPool_updateBorrowAndRedeemStatus",
    after: [UpdateDebtRatioRangeCall]
  });
  
  // ============================================
  // 7. 在 PoolManager 中注册池子
  // ============================================
  m.call(PoolManager, "registerPool", [
    WstETHPoolProxy,
    m.getParameter("CollateralCapacity", 1000000000000000000000n),  // 1000 wstETH
    m.getParameter("DebtCapacity", 500000000000000000000000n),      // 500,000 fxUSD
  ], { 
    id: "PoolManager_registerPool",
    after: [UpdateDebtRatioRangeCall]
  });
  
  // ============================================
  // 8. 返回部署的合约
  // ============================================
  return {
    WstETHPriceOracle,
    WstETHPool,
    AaveFundingPoolImplementation,
  };
});
