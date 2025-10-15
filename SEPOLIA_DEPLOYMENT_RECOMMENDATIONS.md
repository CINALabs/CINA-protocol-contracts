# Sepolia 测试网部署建议方案

> **基于以太坊主网部署，为 Sepolia 测试网提供的部署建议**  
> **日期**: 2025-10-15  
> **状态**: 待执行

## 📊 现状总结

### ✅ 已完成
- 10个核心合约已部署到 Sepolia
- 基础架构完整（ProxyAdmin, EmptyContract 等）
- AaveFundingPool 已注册到 PoolManager

### ❌ 存在的问题
1. **PoolManager.configuration() = 0x0** (严重)
2. **AaveFundingPool 调用失败** (严重)  
3. **PoolConfiguration 调用失败** (严重)
4. **缺少 3 个主网合约** (Router, StETHPriceOracle, WstETHPool)

## 🎯 推荐方案

### **方案 A: 最小修复 + 测试验证** ⭐⭐⭐⭐⭐ (强烈推荐)

**目标**: 修复当前问题，确保基本功能可用

**步骤**:

#### 1. 紧急修复（1-2小时）

```bash
# 步骤 1: 检查并修复 PoolManager Configuration
npx hardhat run scripts/fix-pool-manager-config.ts --network sepolia

# 步骤 2: 诊断 AaveFundingPool 问题
npx hardhat run scripts/check-aave-pool-init.ts --network sepolia

# 步骤 3: 根据诊断结果采取行动（可能需要重新部署）
```

**预期结果**:
- PoolManager Configuration 正确设置
- 了解 AaveFundingPool 问题根源
- 决定是否需要重新部署

#### 2. 功能验证（30分钟）

```bash
# 测试基本的开仓功能
npx hardhat run scripts/test-open-position-simple.ts --network sepolia
```

**成功标准**:
- 能够成功开仓（即使金额很小）
- 能够查询仓位状态
- 能够关闭仓位

**优点**:
- 快速见效
- 风险低
- Gas 成本最小

**缺点**:
- 功能受限
- 没有 Router（用户体验较差）

---

### **方案 B: 完整部署 + Router 系统** ⭐⭐⭐⭐ (推荐用于完整测试)

**目标**: 提供接近主网的完整功能

**步骤**:

#### 1. 完成方案 A 的所有步骤

#### 2. 部署 Router 系统（2-3小时）

```bash
# 步骤 1: 部署所有 ERC2535 Facets
npx hardhat ignition deploy ignition/modules/ERC2535.ts --network sepolia

# 步骤 2: 创建参数文件
cat > ignition/parameters/sepolia-router.json << 'EOF'
{
  "Router": {
    "Treasury": "0xE8055E0fAb02Ceb32D30DA3540Cf97BE1FBf244A"
  }
}
EOF

# 步骤 3: 部署 Router (Diamond)
npx hardhat ignition deploy ignition/modules/Router.ts \
  --network sepolia \
  --parameters ignition/parameters/sepolia-router.json
```

**包含的 Facets**:
- DiamondCutFacet
- DiamondLoupeFacet  
- OwnershipFacet
- RouterManagementFacet
- FlashLoanCallbackFacet
- PositionOperateFlashLoanFacet
- MigrateFacet
- FxUSDBasePoolFacet

#### 3. 配置 Router（30分钟）

```bash
# 授予 Router OPERATOR_ROLE
npx hardhat run scripts/grant-router-role.ts --network sepolia
```

**优点**:
- 用户体验好
- 支持闪电贷开仓
- 批量操作
- 接近主网环境

**缺点**:
- 部署时间长
- Gas 成本较高（估计 0.02-0.05 ETH）

---

### **方案 C: 最大化功能 + 价格预言机** ⭐⭐⭐ (仅在需要时)

**目标**: 复刻主网所有功能

**步骤**:

#### 1. 完成方案 B 的所有步骤

#### 2. 部署 Mock Price Oracle（1小时）

```bash
# 部署 Mock Oracle（用于测试）
npx hardhat run scripts/deploy-mock-price-oracle.ts --network sepolia
```

**或** 部署真实 Price Oracle（需要调查外部依赖）

#### 3. 部署 WstETH Pool（1-2小时）

```bash
# 创建参数文件
cat > ignition/parameters/sepolia-wsteth-pool.json << 'EOF'
{
  "WstETHPool": {
    "Name": "f(x) wstETH Leveraged Position",
    "Symbol": "xwstETH",
    "DebtRatioLower": "500000000000000000",
    "DebtRatioUpper": "800000000000000000",
    "RebalanceDebtRatio": "900000000000000000",
    "RebalanceBonusRatio": "25000000",
    "LiquidateDebtRatio": "950000000000000000",
    "LiquidateBonusRatio": "50000000",
    "OpenRatio": "900000000000000000",
    "OpenRatioStep": "10000000000000000",
    "CloseFeeRatio": "500000",
    "FundingRatio": "10000000",
    "CollateralCapacity": "1000000000000000000000",
    "DebtCapacity": "5000000000000000000000",
    "RateProvider": "0x0000000000000000000000000000000000000000"
  }
}
EOF

# 部署 WstETH Pool
npx hardhat ignition deploy ignition/modules/pools/WstETHPool.ts \
  --network sepolia \
  --parameters ignition/parameters/sepolia-wsteth-pool.json
```

**优点**:
- 功能完整
- 多种抵押品选择
- 真实模拟主网

**缺点**:
- 部署复杂
- Gas 成本高（估计 0.05-0.1 ETH）
- Sepolia 上可能缺少外部依赖（Curve 池、Chainlink 价格源等）

---

## 💰 Gas 成本估算

| 方案 | 预估 Gas 成本 (Sepolia ETH) | 时间投入 |
|------|----------------------------|---------|
| 方案 A | 0.005 - 0.01 | 1-2 小时 |
| 方案 B | 0.02 - 0.05 | 3-5 小时 |
| 方案 C | 0.05 - 0.1 | 5-8 小时 |

*注: Sepolia ETH 可免费从水龙头获取*

## 🚀 推荐执行计划

### **第1天: 紧急修复**
```bash
# 1. 修复 PoolManager Configuration
npx hardhat run scripts/fix-pool-manager-config.ts --network sepolia

# 2. 检查 AaveFundingPool
npx hardhat run scripts/check-aave-pool-init.ts --network sepolia

# 3. 测试基本功能
npx hardhat run scripts/test-open-position-simple.ts --network sepolia
```

**预期产出**: 
- 基本功能可用
- 了解所有问题
- 决定下一步方向

### **第2天: 部署 Router** (可选)
```bash
# 1. 部署 Facets
npx hardhat ignition deploy ignition/modules/ERC2535.ts --network sepolia

# 2. 部署 Router
npx hardhat ignition deploy ignition/modules/Router.ts --network sepolia

# 3. 配置和测试
npx hardhat run scripts/test-router-operations.ts --network sepolia
```

**预期产出**:
- Router 系统可用
- 支持高级功能
- 改善用户体验

### **第3天: 扩展功能** (可选)
```bash
# 1. 部署 Mock Oracle
npx hardhat run scripts/deploy-mock-price-oracle.ts --network sepolia

# 2. 部署 WstETH Pool
npx hardhat ignition deploy ignition/modules/pools/WstETHPool.ts --network sepolia

# 3. 全面测试
npx hardhat run scripts/comprehensive-test.ts --network sepolia
```

**预期产出**:
- 多种抵押品支持
- 完整功能集
- 接近生产环境

## ⚠️ 重要注意事项

### Sepolia 与主网的关键差异

| 组件 | 主网 | Sepolia | 解决方案 |
|------|------|---------|---------|
| **USDC** | 真实 USDC | 测试 USDC | ✅ 已配置测试 USDC |
| **Curve 池** | 丰富流动性 | 很少或不存在 | ⚠️ 使用 Mock Oracle |
| **Chainlink** | 完整价格源 | 有限支持 | ⚠️ 使用 Mock Oracle |
| **wstETH** | Lido 官方 | 可能不存在 | ⚠️ 可能需要 Mock ERC20 |
| **Aave** | 完整协议 | Sepolia 版本 | ✅ 地址需确认 |

### 必须检查的配置

1. **环境变量** (.env):
   ```bash
   PRIVATE_KEY=your_private_key_here
   SEPOLIA_RPC_URL=https://eth-sepolia.public.blastapi.io
   ETHERSCAN_API_KEY=your_etherscan_key
   ```

2. **账户余额**:
   - 至少 0.1 Sepolia ETH 用于部署
   - 可从水龙头获取: https://sepoliafaucet.com/

3. **合约地址验证**:
   - 所有引用的外部合约地址必须在 Sepolia 上存在
   - USDC, Chainlink Price Feeds 等

## 📝 执行检查清单

### 开始之前
- [ ] `.env` 文件已配置
- [ ] 账户有足够的 Sepolia ETH
- [ ] 已阅读诊断报告 (`SEPOLIA_DEPLOYMENT_ANALYSIS.md`)
- [ ] 了解 Sepolia 与主网的差异

### 方案 A - 最小修复
- [ ] 运行诊断脚本
- [ ] 修复 PoolManager Configuration
- [ ] 检查 AaveFundingPool 状态
- [ ] 测试基本开仓功能
- [ ] 记录所有更改和问题

### 方案 B - 部署 Router
- [ ] 完成方案 A
- [ ] 部署 ERC2535 Facets
- [ ] 部署 Router (Diamond)
- [ ] 配置 Router 权限
- [ ] 测试 Router 功能
- [ ] 更新部署文档

### 方案 C - 完整功能
- [ ] 完成方案 B
- [ ] 部署 Price Oracle (Mock 或真实)
- [ ] 部署 WstETH Pool
- [ ] 注册新池到 PoolManager
- [ ] 全面功能测试
- [ ] 编写测试报告

## 🔗 相关文件

- **诊断报告**: `SEPOLIA_DEPLOYMENT_ANALYSIS.md`
- **诊断脚本**: `scripts/diagnose-sepolia-readonly.ts`
- **修复脚本**: `scripts/fix-pool-manager-config.ts`
- **检查脚本**: `scripts/check-aave-pool-init.ts`
- **部署模块**: `ignition/modules/`
- **参数示例**: `ignition/parameters/`

## 💡 最终建议

### 如果您的目标是...

**快速验证基本功能** → 选择 **方案 A**  
- 最快速度
- 最低成本  
- 足够进行基本测试

**提供完整的测试环境** → 选择 **方案 B**  
- 平衡的选择
- 良好的用户体验
- 支持大部分功能

**完全复刻主网环境** → 选择 **方案 C**  
- 功能最完整
- 最接近生产环境
- 需要较多时间和精力

### 我的推荐

**对于大多数测试场景，方案 B 是最佳选择**:
- 提供足够的功能用于测试
- 包含 Router 改善用户体验
- 部署时间和成本可接受
- 后续可轻松扩展到方案 C

---

**准备好开始了吗？** 

运行以下命令开始第一步:
```bash
npx hardhat run scripts/diagnose-sepolia-readonly.ts
```

然后根据诊断结果决定执行哪个方案！

