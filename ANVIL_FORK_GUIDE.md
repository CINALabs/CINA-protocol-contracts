# Anvil Fork 使用指南

本指南说明如何使用 Foundry Anvil 在本地 fork 以太坊主网进行开发和测试。

## 快速开始

### 1. 启动 Anvil Fork

```bash
./start-fork.sh
```

这将启动一个本地以太坊主网 fork，监听在 `http://127.0.0.1:8545`

### 2. 部署合约

```bash
npx hardhat run deploy-fork.ts --network localhost
```

### 3. 与合约交互

```bash
npx hardhat console --network localhost
```

## Anvil 运行状态

当前 Anvil 正在后台运行：
- **RPC**: http://127.0.0.1:8545
- **Chain ID**: 31337
- **Fork Block**: 23534412
- **状态**: 运行中 ✅

## 管理 Anvil

### 查看 Anvil 进程
```bash
ps aux | grep anvil
```

### 停止 Anvil
```bash
# 查找进程 ID
ps aux | grep anvil

# 终止进程
kill <PID>
```

或者使用 pkill:
```bash
pkill -f anvil
```

### 重启 Anvil
```bash
# 停止当前运行的 Anvil
pkill -f anvil

# 等待几秒
sleep 2

# 重新启动
./start-fork.sh
```

## 常用操作

### 使用 Hardhat 交互

```javascript
// 连接到 localhost
npx hardhat console --network localhost

// 在控制台中
const [deployer] = await ethers.getSigners();
console.log("Address:", deployer.address);
console.log("Balance:", await ethers.provider.getBalance(deployer.address));

// 连接到已部署的合约
const poolManager = await ethers.getContractAt(
  "PoolManager",
  "0x66713e76897CdC363dF358C853df5eE5831c3E5a"
);
```

### 使用 Cast (Foundry)

```bash
# 检查区块高度
cast block-number --rpc-url http://127.0.0.1:8545

# 检查余额
cast balance 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url http://127.0.0.1:8545

# 调用合约
cast call 0x66713e76897CdC363dF358C853df5eE5831c3E5a "owner()" --rpc-url http://127.0.0.1:8545

# 发送交易
cast send <CONTRACT> "function(args)" --rpc-url http://127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### 使用 Curl 调用 RPC

```bash
# 获取最新区块号
curl -X POST http://127.0.0.1:8545 \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# 获取账户余额
curl -X POST http://127.0.0.1:8545 \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_getBalance","params":["0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266","latest"],"id":1}'
```

## 测试账户

Anvil 提供 10 个预充值账户，每个账户有 10,000 ETH：

| 账户 | 地址 |
|------|------|
| #0 (部署账户) | 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 |
| #1 | 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 |
| #2 | 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC |
| #3 | 0x90F79bf6EB2c4f870365E785982E1f101E93b906 |
| #4 | 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65 |

**默认助记词**: `test test test test test test test test test test test junk`

## 已部署合约

### 核心合约

```javascript
// PoolManager (Proxy)
const poolManager = "0x66713e76897CdC363dF358C853df5eE5831c3E5a";

// FxUSDBasePool (Proxy)
const fxUSDBasePool = "0x6384D5F8999EaAC8bcCfae137D4e535075b47494";

// PegKeeper (Proxy)
const pegKeeper = "0xA157711624f837865F0a3b503dD6864E7eD36759";

// FxUSD (使用现有主网合约)
const fxUSD = "0x085780639CC2cACd35E474e71f4d000e2405d8f6";
```

完整的合约地址列表请参考 `LOCALHOST_FORK_DEPLOYMENT.md`

## Anvil 特性

### 1. 瞬时挖矿
每笔交易会自动挖出一个新区块，无需等待。

### 2. 零 Gas 费
Gas price 设置为 0，方便测试。

### 3. 状态快照
```bash
# 保存状态
cast rpc evm_snapshot --rpc-url http://127.0.0.1:8545

# 恢复状态
cast rpc evm_revert <snapshot_id> --rpc-url http://127.0.0.1:8545
```

### 4. 时间操纵
```bash
# 增加时间（秒）
cast rpc evm_increaseTime 3600 --rpc-url http://127.0.0.1:8545

# 设置下一个区块时间戳
cast rpc evm_setNextBlockTimestamp <timestamp> --rpc-url http://127.0.0.1:8545

# 挖矿
cast rpc evm_mine --rpc-url http://127.0.0.1:8545
```

### 5. 模拟账户
```bash
# 模拟任意地址发送交易
cast rpc anvil_impersonateAccount 0x... --rpc-url http://127.0.0.1:8545

# 停止模拟
cast rpc anvil_stopImpersonatingAccount 0x... --rpc-url http://127.0.0.1:8545
```

### 6. 设置余额
```bash
# 设置账户余额
cast rpc anvil_setBalance 0x... 0x56BC75E2D63100000 --rpc-url http://127.0.0.1:8545
```

## 在 MetaMask 中使用

1. 打开 MetaMask
2. 添加网络：
   - **网络名称**: Anvil Localhost
   - **RPC URL**: http://127.0.0.1:8545
   - **Chain ID**: 31337
   - **货币符号**: ETH
3. 导入账户（使用上面的私钥）

## 注意事项

⚠️ **重要提醒**:

1. **不要在主网使用这些私钥** - 这些是公开的测试私钥
2. **Fork 是临时的** - 停止 Anvil 后所有状态都会丢失
3. **Fork 不会同步** - Fork 从特定区块开始，不会自动更新
4. **内存占用** - Fork 会占用一定内存，长时间运行可能需要重启

## 故障排除

### 端口已被占用
```bash
# 查找占用 8545 端口的进程
lsof -i :8545

# 终止进程
kill -9 <PID>
```

### Anvil 无响应
```bash
# 终止所有 anvil 进程
pkill -9 -f anvil

# 重新启动
./start-fork.sh
```

### RPC 连接错误
```bash
# 测试连接
curl http://127.0.0.1:8545

# 检查 Anvil 是否运行
ps aux | grep anvil
```

## 相关文档

- [Foundry Anvil 文档](https://book.getfoundry.sh/anvil/)
- [Hardhat 网络配置](https://hardhat.org/hardhat-network/)
- [完整部署信息](./LOCALHOST_FORK_DEPLOYMENT.md)

## 下一步

1. ✅ Anvil Fork 已启动并运行
2. ✅ 合约已成功部署
3. 📝 开始编写测试
4. 🧪 与合约交互并测试功能
5. 🔍 调试和优化
