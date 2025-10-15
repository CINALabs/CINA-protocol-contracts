# Sepolia 测试网部署诊断报告

**诊断时间**: 2025-10-15  
**诊断工具**: `scripts/diagnose-sepolia-readonly.ts`

## 📊 当前部署状态总览

### ✅ 已成功部署的合约 (10/10)

| 合约名称 | 地址 | 状态 |
|---------|------|------|
| FxUSD | `0x085a1b6da46aE375b35Dea9920a276Ef571E209c` | ✅ 已部署 |
| PoolManager | `0xBb644076500Ea106d9029B382C4d49f56225cB82` | ✅ 已部署 |
| FxUSDBasePool | `0x420D6b8546F14C394A703F5ac167619760A721A9` | ✅ 已部署 |
| PegKeeper | `0x628648849647722144181c9CB5bbE0CCadd50029` | ✅ 已部署 |
| AaveFundingPool | `0xAb20B978021333091CA307BB09E022Cec26E8608` | ✅ 已部署 |
| ReservePool | `0x3908720b490a2368519318dD15295c22cd494e34` | ✅ 已部署 |
| RevenuePool | `0x54AC8d19ffc522246d9b87ED956de4Fa0590369A` | ✅ 已部署 |
| PoolConfiguration | `0x35456038942C91eb16fe2E33C213135E75f8d188` | ✅ 已部署 |
| ProxyAdmin | `0x7bc6535d75541125fb3b494deCfdE10Db20C16d8` | ✅ 已部署 |
| AaveFundingPoolImpl | `0x33263fF0D348427542ee4dBF9069d411ac43718E` | ✅ 已部署 |

## 🔴 严重问题

### 1. **PoolManager Configuration 未设置** 🔥🔥🔥

**问题**: PoolManager.configuration() 返回 `0x0000...0000`  
**影响**: 这会导致所有需要配置的操作失败，包括开仓、平仓等  
**优先级**: **最高 - 必须立即修复**

**解决方案**:
```typescript
// 需要调用 PoolManager 的管理员方法设置 configuration
await poolManager.updateConfiguration("0x35456038942C91eb16fe2E33C213135E75f8d188");
```

### 2. **AaveFundingPool 调用失败** 🔥🔥

**问题**: 无法调用 `collateral()` 等方法，返回 missing revert data  
**可能原因**:
- 合约未正确初始化
- 合约代码有bug
- 代理配置问题

**影响**: 无法使用 AaveFundingPool 进行任何操作  
**优先级**: **高 - 需要紧急检查**

**建议调查步骤**:
1. 检查合约是否已正确初始化
2. 验证代理是否指向正确的实现
3. 检查合约 ABI 是否匹配

### 3. **PoolConfiguration 调用失败** 🔥🔥

**问题**: 无法调用 `fxUSDPriceOracle()` 等方法  
**可能原因**: 类似 AaveFundingPool，可能是初始化或代理配置问题

### 4. **PoolManager 中 fxUSD 地址不匹配** ⚠️

**当前值**: `0x085a1b6da46aE375b35Dea9920a276Ef571E209c`  
**期望值**: `0x085a1b6da46ae375b35dea9920a276ef571e209c` (小写)

这可能只是大小写问题，需要确认。

## ❌ 缺失的主网合约

### 1. **Router (Diamond Proxy)** 🔥🔥

**主网地址**: `0x33636D49FbefBE798e15e7F356E8DBef543CC708`  
**状态**: Sepolia 未部署  
**用途**: 
- 提供用户友好的前端交互接口
- 支持闪电贷开仓
- 批量操作

**部署建议**: 
- 使用现有的 `ignition/modules/Router.ts`
- 需要先部署 ERC2535 Facets

### 2. **StETHPriceOracle** 🔥🔥

**主网地址**: `0x3716352d57C2e48EEdB56Ee0712Ef29E0c2f3069`  
**状态**: Sepolia 未部署  
**用途**: 
- 为 wstETH 池提供价格源
- 整合 Chainlink 和 Curve 价格

**部署挑战**:
- Sepolia 上可能缺少 Curve stETH/ETH 池
- 需要 Chainlink ETH/USD 价格源
- **建议**: 部署 Mock Price Oracle 用于测试

### 3. **WstETHPool** 🔥

**主网地址**: `0x6Ecfa38FeE8a5277B91eFdA204c235814F0122E8`  
**状态**: Sepolia 未部署  
**用途**: 
- 提供 wstETH 作为抵押品的长仓功能

**依赖**:
- StETHPriceOracle (或 Mock 版本)
- PoolManager 和 PoolConfiguration 正常工作

## 📋 建议的修复和部署计划

### **阶段 1: 紧急修复（必须）** 🔥🔥🔥

#### 1.1 修复 PoolManager Configuration
```bash
# 创建修复脚本
npx hardhat run scripts/fix-pool-manager-config.ts --network sepolia
```

**操作**:
- 调用 PoolManager 设置 configuration 地址
- 验证设置成功

#### 1.2 诊断 AaveFundingPool 问题
```bash
# 检查初始化状态
npx hardhat run scripts/check-aave-pool-init.ts --network sepolia
```

**可能需要的操作**:
- 重新部署 AaveFundingPool Implementation
- 通过 ProxyAdmin 升级
- 重新初始化（如果支持）

#### 1.3 修复 PoolConfiguration
类似 AaveFundingPool，检查并修复初始化问题

### **阶段 2: 部署 Router 系统（强烈推荐）** 🔥🔥

```bash
# 1. 部署 ERC2535 Facets
npx hardhat ignition deploy ignition/modules/ERC2535.ts --network sepolia

# 2. 部署 Router (Diamond)
npx hardhat ignition deploy ignition/modules/Router.ts --network sepolia \
  --parameters ignition/parameters/sepolia-router.json
```

**好处**:
- 改善用户体验
- 支持高级功能（闪电贷开仓等）
- 更接近主网环境

### **阶段 3: 部署价格预言机和 WstETH 池（可选）** 🔥

#### 选项 A: 部署 Mock Oracle（推荐用于测试）

```bash
# 部署简单的 Mock Price Oracle
npx hardhat run scripts/deploy-mock-oracle.ts --network sepolia
```

**优点**:
- 快速部署
- 不依赖外部服务
- 价格可控，便于测试

**缺点**:
- 不真实反映市场价格
- 仅用于测试

#### 选项 B: 部署真实 Price Oracle（接近生产环境）

**挑战**:
- Sepolia 上 Curve stETH/ETH 池可能不存在
- 需要找到替代的价格源
- 配置更复杂

**建议**: 先使用 Mock Oracle，后续需要时再升级

### **阶段 4: 扩展功能（低优先级）**

- 部署 WstETHPool
- 部署短仓系统 (ShortPoolManager)
- 部署其他辅助合约

## 🛠️ 立即行动清单

### 今天必须完成:

1. ✅ **执行诊断** - 已完成
2. ⏳ **创建修复脚本** - 进行中
3. ⏳ **修复 PoolManager Configuration**
4. ⏳ **诊断 AaveFundingPool 问题**

### 本周完成:

5. ⏳ **部署 Router 系统**
6. ⏳ **部署 Mock Price Oracle**
7. ⏳ **测试完整的开仓流程**

### 可选（根据需求）:

8. ⏳ **部署 WstETHPool**
9. ⏳ **部署短仓系统**
10. ⏳ **部署真实 Price Oracle**

## 💡 关键建议

### 1. 优先修复而非扩展
**当前最重要的是修复已部署合约的配置问题，而不是部署新合约。**

### 2. 使用 Mock 合约加速测试
对于 Sepolia 测试网：
- 使用 Mock Price Oracle 代替真实的 Chainlink/Curve
- 使用简化的配置
- 专注于功能测试而非价格准确性

### 3. 逐步部署，充分测试
- 每个阶段完成后进行充分测试
- 确保基础功能正常后再扩展
- 保留详细的部署和测试日志

### 4. 注意 Sepolia 与主网的差异

| 特性 | 主网 | Sepolia 测试网 |
|------|------|--------------|
| Curve 池 | 丰富 | 很少或不存在 |
| Chainlink 价格源 | 完整 | 有限 |
| 流动性 | 充足 | 测试代币 |
| Gas 成本 | 真实 ETH | 免费测试 ETH |

### 5. 文档化所有更改
- 记录每次部署的合约地址
- 记录配置参数
- 记录遇到的问题和解决方案

## 📞 需要用户输入

1. **是否需要部署 Router？** - 强烈推荐，但会增加 gas 成本
2. **是否需要真实价格源？** - 还是 Mock Oracle 足够用于测试
3. **是否需要完整的短仓功能？** - 还是只测试长仓

## 🔗 有用的资源

- 诊断脚本: `scripts/diagnose-sepolia-readonly.ts`
- 部署模块: `ignition/modules/`
- 部署参数: `ignition/parameters/`
- 主网部署记录: `ignition/deployments/ethereum/deployed_addresses.json`

---

**下一步**: 创建修复脚本并执行阶段 1 的紧急修复

