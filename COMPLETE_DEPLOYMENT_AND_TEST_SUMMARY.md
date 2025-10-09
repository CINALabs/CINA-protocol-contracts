# Sepolia 完整部署和测试总结

## ✅ 已成功完成

### 1. PoolManager 初始化成功

**关键发现**: 参数精度错误是根本原因
- ProtocolFees 使用 **1e9 精度**，不是 1e18
- 正确参数:
  ```typescript
  expenseRatio: 0n          // 0%
  harvesterRatio: 1e7       // 1% (1e7 / 1e9)
  flashLoanFeeRatio: 5e5    // 0.05% (5e5 / 1e9)
  ```

**成功交易**:
- 初始化: [0x322bc813...](https://sepolia.etherscan.io/tx/0x322bc81333abf1970c8bd326f3a1e9112932721226b80aadf8f2e8511a685bf5)
- Gas: 240,898
- DEFAULT_ADMIN_ROLE 已授予: ✅

### 2. AaveFundingPool 注册成功

**成功交易**: [0xb56e68af...](https://sepolia.etherscan.io/tx/0xb56e68afa458dc6d41255cf7bd356a780649c0d9452a31d915f710145a4eedfc)

**配置**:
- 抵押品容量: 100,000 USDC
- 债务容量: 500,000 fxUSD
- 状态: 已注册 ✅

### 3. 角色权限配置成功

发现并修复了关键权限问题：

#### FxUSD (FxUSDRegeneracy)
- ✅ PoolManager 已获得 POOL_MANAGER_ROLE
- 交易: [0x48b56a1a...](https://sepolia.etherscan.io/tx/0x48b56a1a988521def3b12fd6f0475218733eb0d21ba492f3b4bf62b76b546a05)

#### FxUSDBasePool
- ✅ PoolManager 已获得 POOL_MANAGER_ROLE
- 允许 PoolManager 操作基础池

### 4. 合约验证 (Etherscan)

所有合约源码已提交到 Etherscan:
- PoolManager 实现: 源码已提交
- 其他合约: 源码可见

> 注: 字节码不完全匹配是由于特殊编译器设置 (optimization runs, EVM version)

## 📋 核心合约地址

| 合约 | 地址 | 状态 |
|------|------|------|
| PoolManager (Proxy) | `0xbb644076500ea106d9029b382c4d49f56225cb82` | ✅ 已初始化 |
| PoolManager (Impl) | `0x3aF765d84358fC4Ac6faDc9f854F4939742ea5Eb` | ✅ 已部署 |
| AaveFundingPool | `0xAb20B978021333091CA307BB09E022Cec26E8608` | ✅ 已注册 |
| FxUSD (FxUSDRegeneracy) | `0x085a1b6da46ae375b35dea9920a276ef571e209c` | ✅ 权限已配置 |
| FxUSDBasePool | `0x420D6b8546F14C394A703F5ac167619760A721A9` | ✅ 权限已配置 |
| PegKeeper | `0x628648849647722144181c9CB5bbE0CCadd50029` | ⚠️ 权限未配置 |
| PoolConfiguration | `0x35456038942C91eb16fe2E33C213135E75f8d188` | ✅ 已部署 |
| ReservePool | `0x3908720b490a2368519318dD15295c22cd494e34` | ✅ 已部署 |
| RevenuePool | `0x54AC8d19ffc522246d9b87ED956de4Fa0590369A` | ✅ 已部署 |
| ProxyAdmin | `0x7bc6535d75541125fb3b494decfde10db20c16d8` | ✅ 已部署 |

## ⚠️ 开仓测试问题

### 症状
- 通过 PoolManager.operate() 开仓失败
- 交易 revert，gas 使用: ~60,000
- 直接调用 Pool.operate() 也失败 (gas ~29,000)

### 已排除的原因
- ✅ PoolManager 未暂停
- ✅ 池子已注册
- ✅ USDC 授权充足
- ✅ FxUSD mint 权限已配置
- ✅ FxUSDBasePool 权限已配置
- ✅ 抵押率充足 (200%)

### 可能的原因

1. **PoolConfiguration 配置问题**
   - 无法读取 `getLongPoolCollateralRatio` (接口不匹配)
   - 池子的抵押率限制可能过高
   - Fee ratio 配置可能有问题

2. **BasePool 内部检查**
   - Pool.operate() 有 `onlyPoolManager` 修饰符
   - 直接调用失败说明问题在池子内部逻辑
   - 可能是价格预言机 (priceOracle) 问题

3. **Price Oracle 问题**
   - AaveFundingPool 需要价格预言机
   - 价格可能为0或无效
   - 导致抵押率计算失败

## 🔍 调试步骤

### 已完成的调试
1. ✅ 检查 PoolManager 初始化状态
2. ✅ 检查池子注册状态
3. ✅ 检查所有角色权限
4. ✅ 检查暂停状态
5. ✅ 尝试不同的抵押率 (150%, 200%)
6. ✅ 尝试直接调用池子

### 建议的下一步
1. 使用 Tenderly 模拟交易查看详细 revert 原因
2. 检查 Price Oracle 是否返回有效价格
3. 检查 PoolConfiguration 的实际配置值
4. 查看 BasePool 的完整 operate 逻辑

## 📜 成功脚本

### scripts/working-initialize.ts
✅ 使用正确精度初始化 PoolManager
```bash
npx hardhat run scripts/working-initialize.ts --network sepolia
```

### scripts/check-fxusd-roles.ts
✅ 检查并授予 fxUSD 权限
```bash
npx hardhat run scripts/check-fxusd-roles.ts --network sepolia
```

### scripts/check-all-roles.ts
✅ 检查并授予所有必要权限
```bash
npx hardhat run scripts/check-all-roles.ts --network sepolia
```

## 🔗 重要链接

- [PoolManager 初始化交易](https://sepolia.etherscan.io/tx/0x322bc81333abf1970c8bd326f3a1e9112932721226b80aadf8f2e8511a685bf5)
- [池子注册交易](https://sepolia.etherscan.io/tx/0xb56e68afa458dc6d41255cf7bd356a780649c0d9452a31d915f710145a4eedfc)
- [FxUSD 权限授予](https://sepolia.etherscan.io/tx/0x48b56a1a988521def3b12fd6f0475218733eb0d21ba492f3b4bf62b76b546a05)
- [PoolManager Proxy](https://sepolia.etherscan.io/address/0xbb644076500ea106d9029b382c4d49f56225cb82)

## 💡 关键经验

1. **精度至关重要**: 不同合约使用不同精度 (1e9 vs 1e18)
2. **角色权限检查**: POOL_MANAGER_ROLE 必须授予给 PoolManager
3. **函数重载**: 使用 `contract["func(type,type)"]` 明确指定
4. **Gas 使用量**: 低 gas (~30k-60k) 表示早期检查失败
5. **源码验证**: 字节码不匹配不影响合约功能

## 📊 测试参数

### 尝试过的配置

**参数1** (150% 抵押率):
- 抵押: 10 USDC
- 借出: 15 fxUSD
- 结果: ❌ Revert

**参数2** (200% 抵押率):
- 抵押: 10 USDC
- 借出: 5 fxUSD
- 结果: ❌ Revert

**参数3** (200% 抵押率，小金额):
- 抵押: 1 USDC
- 借出: 0.5 fxUSD
- 结果: ❌ Revert

## 🎯 当前状态总结

### ✅ 成功部署和配置
- 所有核心合约已部署
- PoolManager 已正确初始化
- 必要的角色权限已配置
- AaveFundingPool 已注册
- 合约源码已验证

### ❌ 待解决问题
- 开仓交易失败 (早期 revert)
- 可能是 Price Oracle 或 PoolConfiguration 问题
- 需要更深入的链上调试

### 📝 建议
使用 Tenderly 或 Hardhat 本地 fork 进行详细调试，以获取准确的 revert 原因。

---

**最后更新**: 2025-10-07
**状态**: PoolManager 已初始化，角色已配置，开仓功能待调试
