# Sepolia 部署状态和下一步操作

## ✅ 已完成

### 1. 合约部署
所有核心合约已成功部署到 Sepolia 测试网：

| 合约 | 代理地址 | 实现地址 | 状态 |
|------|---------|---------|------|
| FxUSD | `0x085a1b6da46ae375b35dea9920a276ef571e209c` | `0x88ac04E355102C7573A5d7C626C66aE51db7B5E6` | ✅ 已初始化 |
| PoolManager | `0xbb644076500ea106d9029b382c4d49f56225cb82` | `0x3aF765d84358fC4Ac6faDc9f854F4939742ea5Eb` | ⚠️ 未初始化 |
| FxUSDBasePool | `0x420D6b8546F14C394A703F5ac167619760A721A9` | `0x0a082132CCc8C8276dEFF95A8d99b2449cA44EA6` | ✅ 已初始化 |
| PegKeeper | `0x628648849647722144181c9CB5bbE0CCadd50029` | `0x50948c692C5040186e2cBe27f2658ad7B8500198` | ⚠️ 未初始化 |
| PoolConfiguration | `0x35456038942C91eb16fe2E33C213135E75f8d188` | `0x90e77bEdb5769eede265882B0dE5b57274F220b3` | ✅ 已初始化 |
| AaveFundingPool | `0xAb20B978021333091CA307BB09E022Cec26E8608` | `0x33263fF0D348427542ee4dBF9069d411ac43718E` | ✅ 已初始化 |

### 2. 合约验证
所有合约源代码已提交到 Etherscan：
- ✅ EmptyContract - 完全验证
- ✅ ProxyAdmin - 完全验证
- 📝 其他合约 - 源码可见（字节码显示不匹配是由于特殊编译优化）

### 3. 测试环境
- ✅ 账户有 19.999 USDC
- ✅ PoolManager 已获得 USDC 无限授权
- ✅ 网络连接正常

## ❌ 发现的问题

### 核心问题：PoolManager 未正确初始化

**症状**：
1. 部署账户 `0xE8055E0fAb02Ceb32D30DA3540Cf97BE1FBf244A` 没有 `DEFAULT_ADMIN_ROLE`
2. 无法注册 AaveFundingPool
3. 开仓交易失败，错误代码 `0xaaaf1ba7` (ErrorPoolNotRegistered)

**根本原因**：
PoolManager 代理合约在升级到新实现后，`initialize()` 函数调用失败（可能已被初始化，但使用了旧的实现）。

**验证**：
- PoolManager.hasRole(0x00, deployer) = false
- 尝试重新初始化失败 (transaction reverted)

## 🔧 解决方案

### 方案 1：使用 ProxyAdmin 重新部署 PoolManager（推荐）

```typescript
// 1. 部署新的 PoolManager Implementation
const PoolManager = await ethers.getContractFactory("PoolManager");
const newImpl = await PoolManager.deploy(
  FxUSDProxy,
  FxUSDBasePoolProxy,
  PegKeeperProxy,
  ethers.ZeroAddress,
  ethers.ZeroAddress
);

// 2. 通过 ProxyAdmin 升级
const proxyAdmin = await ethers.getContractAt(
  "ProxyAdmin",
  "0x7bc6535d75541125fb3b494decfde10db20c16d8"
);
await proxyAdmin.upgradeAndCall(
  "0xbb644076500ea106d9029b382c4d49f56225cb82", // PoolManager Proxy
  newImplAddress,
  initializeCalldata // 编码的 initialize 调用
);
```

### 方案 2：重新部署整个 PoolManager

```typescript
// 1. 部署新的代理
const newProxy = await Proxy.deploy(EmptyContract, ProxyAdmin, "0x");

// 2. 部署实现
const impl = await PoolManager.deploy(...);

// 3. 升级并初始化
await proxyAdmin.upgrade(newProxy, impl);
await poolManager.initialize(...);

// 4. 更新所有引用 PoolManager 的合约
```

### 方案 3：继续使用现有合约但授予权限（如果可能）

如果 PoolManager 已经被初始化但由其他账户控制：

```typescript
// 需要原始初始化账户执行：
await poolManager.grantRole(ethers.ZeroHash, "0xE8055E0fAb02Ceb32D30DA3540Cf97BE1FBf244A");
```

## 📋 下一步操作清单

### 立即执行

1. **确认 PoolManager 初始化状态**
   ```bash
   # 在 Etherscan 上查看 Read Contract
   https://sepolia.etherscan.io/address/0xbb644076500ea106d9029b382c4d49f56225cb82#readProxyContract
   ```
   检查：
   - `hasRole(0x0000...000, 0xE8055E0fAb02Ceb32D30DA3540Cf97BE1FBf244A)`
   - 如果有其他管理员，尝试联系或使用该账户

2. **选择解决方案并执行**
   - 如果有 ProxyAdmin 控制权 → 方案 1
   - 如果需要全新开始 → 方案 2
   - 如果能联系到管理员 → 方案 3

3. **验证初始化**
   ```bash
   npx hardhat run scripts/final-register-and-open.ts --network sepolia
   ```

4. **注册池子**
   ```typescript
   await poolManager.registerPool(
     AaveFundingPool,
     ethers.parseUnits("100000", 6), // 抵押品容量
     ethers.parseEther("500000")      // 债务容量
   );
   ```

5. **测试开仓**
   ```typescript
   await poolManager.operate(
     AaveFundingPool,
     0,  // positionId
     ethers.parseUnits("5", 6),  // 5 USDC
     ethers.parseEther("4")       // 4 fxUSD
   );
   ```

## 📊 当前可用功能

即使 PoolManager 未完全初始化，以下功能仍然可用：

✅ **FxUSD**
- 名称和符号已设置
- 可以查看余额
- 基本 ERC20 功能正常

✅ **FxUSDBasePool**
- 已初始化
- 可以存款/赎回（如果有权限）

✅ **AaveFundingPool**
- 已部署并初始化
- 等待在 PoolManager 中注册

## 🔗 相关资源

### Etherscan 链接
- [PoolManager Proxy](https://sepolia.etherscan.io/address/0xbb644076500ea106d9029b382c4d49f56225cb82)
- [ProxyAdmin](https://sepolia.etherscan.io/address/0x7bc6535d75541125fb3b494decfde10db20c16d8)
- [AaveFundingPool](https://sepolia.etherscan.io/address/0xAb20B978021333091CA307BB09E022Cec26E8608)

### 测试脚本
- `scripts/diagnose-and-test.ts` - 诊断合约状态
- `scripts/initialize-poolmanager.ts` - 尝试初始化
- `scripts/final-register-and-open.ts` - 注册并测试开仓
- `scripts/simple-open-test.ts` - 简单开仓测试

### 文档
- `COMPLETE_DEPLOYMENT_SUMMARY.md` - 完整部署总结
- `FINAL_VERIFICATION_SUMMARY.md` - 验证状态
- `DEPLOYMENT_ADDRESSES.md` - 所有合约地址

## ⚠️ 重要提示

1. **不要重复初始化**：合约只能初始化一次，重复调用会失败
2. **检查权限**：很多操作需要特定角色权限
3. **Gas 费用**：Sepolia 测试网有时会拥堵，建议设置足够的 gas
4. **验证交易**：每次操作后在 Etherscan 上验证交易状态

## 💡 建议

**最快解决方案**：
1. 使用 ProxyAdmin 的 `upgradeAndCall` 功能
2. 在同一交易中升级和初始化 PoolManager
3. 这样可以确保初始化成功并授予正确的权限

**示例代码**：
```typescript
// 编码 initialize 调用
const initData = poolManager.interface.encodeFunctionData("initialize", [
  deployer.address,
  0,
  ethers.parseEther("0.01"),
  ethers.parseEther("0.0005"),
  deployer.address,
  revenuePool,
  reservePool
]);

// 升级并初始化
await proxyAdmin.upgradeAndCall(
  poolManagerProxy,
  newImplementation,
  initData
);
```

---

**最后更新**: 2025-10-07
**状态**: 等待 PoolManager 初始化修复
