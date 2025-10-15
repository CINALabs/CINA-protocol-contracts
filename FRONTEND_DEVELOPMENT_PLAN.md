# 👨‍💻 前端开发工程师工作计划

> **项目**: CINA Protocol - Sepolia 测试网前端  
> **开发周期**: 3-4 周  
> **技术栈**: React + TypeScript + Wagmi + Viem  
> **状态**: 准备开始

---

## 📅 开发时间线

```
Week 1: 基础设施 + 核心功能
Week 2: 开仓/关仓功能
Week 3: 仓位管理 + 数据展示
Week 4: 优化 + 测试 + 部署
```

---

## 👥 团队配置建议

### 方案 A: 小团队 (推荐)

| 角色 | 人数 | 职责 |
|------|------|------|
| **全栈工程师** | 1-2 人 | 完整功能开发 |
| **UI/UX 设计师** | 1 人 | 界面设计 |

**总人数**: 2-3 人  
**开发周期**: 3-4 周

### 方案 B: 标准团队

| 角色 | 人数 | 职责 |
|------|------|------|
| **前端 Leader** | 1 人 | 架构设计 + 核心功能 |
| **前端工程师** | 2 人 | 功能开发 |
| **UI/UX 设计师** | 1 人 | 界面设计 |
| **测试工程师** | 1 人 | 测试 + QA |

**总人数**: 5 人  
**开发周期**: 2-3 周

---

## 📋 第一周任务 (基础设施)

### Day 1-2: 项目搭建

**负责人**: 前端 Leader  
**预计时间**: 2 天

**任务清单**:

- [ ] **项目初始化**
  ```bash
  # 创建 Next.js 项目
  npx create-next-app@latest cina-protocol-frontend
  
  # 或使用 Vite
  npm create vite@latest cina-protocol-frontend -- --template react-ts
  ```

- [ ] **安装核心依赖**
  ```json
  {
    "dependencies": {
      "ethers": "^6.13.3",
      "wagmi": "^2.0.0",
      "viem": "^2.0.0",
      "@rainbow-me/rainbowkit": "^2.0.0",
      "@tanstack/react-query": "^5.0.0",
      "zustand": "^4.5.0",
      "react-hot-toast": "^2.4.1"
    },
    "devDependencies": {
      "@types/react": "^18.3.0",
      "typescript": "^5.0.0",
      "tailwindcss": "^3.4.0",
      "eslint": "^8.57.0"
    }
  }
  ```

- [ ] **配置文件结构**
  ```
  src/
  ├── components/
  │   ├── common/        # 通用组件
  │   ├── position/      # 仓位相关
  │   ├── pool/          # 池子相关
  │   └── wallet/        # 钱包相关
  ├── hooks/             # 自定义 hooks
  ├── config/            # 配置文件
  ├── utils/             # 工具函数
  ├── types/             # TypeScript 类型
  ├── abi/               # 合约 ABI
  └── styles/            # 样式文件
  ```

- [ ] **环境配置**
  ```typescript
  // .env.local
  NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=xxx
  NEXT_PUBLIC_CHAIN_ID=11155111
  NEXT_PUBLIC_RPC_URL=https://rpc2.sepolia.org
  ```

**交付物**:
- ✅ 可运行的项目框架
- ✅ 配置好的开发环境
- ✅ 基础文件结构

---

### Day 3: 钱包连接

**负责人**: 前端工程师 #1  
**预计时间**: 1 天

**任务清单**:

- [ ] **配置 Wagmi + RainbowKit**
  ```typescript
  // app/providers.tsx
  import { RainbowKitProvider, getDefaultConfig } from '@rainbow-me/rainbowkit';
  import { WagmiProvider } from 'wagmi';
  import { sepolia } from 'wagmi/chains';
  import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
  
  const config = getDefaultConfig({
    appName: 'CINA Protocol',
    projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID!,
    chains: [sepolia],
  });
  
  const queryClient = new QueryClient();
  
  export function Providers({ children }: { children: React.ReactNode }) {
    return (
      <WagmiProvider config={config}>
        <QueryClientProvider client={queryClient}>
          <RainbowKitProvider>
            {children}
          </RainbowKitProvider>
        </QueryClientProvider>
      </WagmiProvider>
    );
  }
  ```

- [ ] **创建钱包组件**
  ```typescript
  // components/wallet/ConnectButton.tsx
  import { ConnectButton } from '@rainbow-me/rainbowkit';
  
  export function WalletConnect() {
    return (
      <ConnectButton
        label="连接钱包"
        accountStatus="address"
        chainStatus="icon"
        showBalance={true}
      />
    );
  }
  ```

- [ ] **网络切换提示**
  ```typescript
  // components/wallet/NetworkGuard.tsx
  import { useNetwork, useSwitchNetwork } from 'wagmi';
  
  export function NetworkGuard({ children }) {
    const { chain } = useNetwork();
    const { switchNetwork } = useSwitchNetwork();
    
    if (chain?.id !== 11155111) {
      return (
        <div className="network-warning">
          <p>请切换到 Sepolia 测试网</p>
          <button onClick={() => switchNetwork?.(11155111)}>
            切换网络
          </button>
        </div>
      );
    }
    
    return <>{children}</>;
  }
  ```

**交付物**:
- ✅ 可工作的钱包连接
- ✅ 网络切换功能
- ✅ 用户地址显示

---

### Day 4-5: 合约集成基础

**负责人**: 前端 Leader  
**预计时间**: 2 天

**任务清单**:

- [ ] **复制合约 ABI**
  ```bash
  # 从 artifacts-hardhat 复制 ABI
  cp artifacts-hardhat/contracts/interfaces/IPoolManager.sol/IPoolManager.json \
     src/abi/PoolManager.json
  
  cp artifacts-hardhat/contracts/interfaces/IERC20.sol/IERC20.json \
     src/abi/ERC20.json
  ```

- [ ] **创建合约配置**
  ```typescript
  // config/contracts.ts
  import { Address } from 'viem';
  
  export const CONTRACTS = {
    PoolManager: '0xBb644076500Ea106d9029B382C4d49f56225cB82' as Address,
    Router: '0xB8B3e6C7D0f0A9754F383107A6CCEDD8F19343Ec' as Address,
    FxUSD: '0x085a1b6da46aE375b35Dea9920a276Ef571E209c' as Address,
    USDC: '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238' as Address,
    AaveFundingPool: '0xAb20B978021333091CA307BB09E022Cec26E8608' as Address,
  } as const;
  
  export const POOLS = [
    {
      address: CONTRACTS.AaveFundingPool,
      name: 'USDC Leveraged Pool',
      collateral: 'USDC',
      collateralDecimals: 6,
    },
  ] as const;
  ```

- [ ] **创建基础 Hooks**
  ```typescript
  // hooks/useBalances.ts
  import { useAccount, useBalance } from 'wagmi';
  import { CONTRACTS } from '@/config/contracts';
  
  export function useUserBalances() {
    const { address } = useAccount();
    
    const { data: ethBalance } = useBalance({
      address,
    });
    
    const { data: usdcBalance } = useContractRead({
      address: CONTRACTS.USDC,
      abi: ERC20_ABI,
      functionName: 'balanceOf',
      args: [address!],
      enabled: !!address,
    });
    
    return {
      eth: ethBalance?.value || 0n,
      usdc: usdcBalance || 0n,
    };
  }
  ```

**交付物**:
- ✅ 合约配置文件
- ✅ 基础查询 Hooks
- ✅ 余额显示组件

---

## 📋 第二周任务 (核心功能)

### Day 6-7: 池子信息展示

**负责人**: 前端工程师 #2  
**预计时间**: 2 天

**任务清单**:

- [ ] **创建池子查询 Hook**
  ```typescript
  // hooks/usePoolInfo.ts
  export function usePoolInfo(poolAddress: Address) {
    return useContractRead({
      address: CONTRACTS.PoolManager,
      abi: PoolManagerABI,
      functionName: 'getPoolInfo',
      args: [poolAddress],
      watch: true,
    });
  }
  ```

- [ ] **池子卡片组件**
  ```typescript
  // components/pool/PoolCard.tsx
  export function PoolCard({ pool }) {
    const { data: poolInfo } = usePoolInfo(pool.address);
    
    return (
      <div className="pool-card">
        <h3>{pool.name}</h3>
        <div className="stats">
          <Stat label="TVL" value={formatTVL(poolInfo)} />
          <Stat label="APY" value="12.5%" />
          <Stat label="使用率" value={calculateUtilization(poolInfo)} />
        </div>
        <button>开仓</button>
      </div>
    );
  }
  ```

- [ ] **池子列表页面**

**交付物**:
- ✅ 池子信息展示
- ✅ TVL 计算
- ✅ 使用率显示

---

### Day 8-10: 开仓功能

**负责人**: 前端 Leader + 工程师 #1  
**预计时间**: 3 天

**任务清单**:

- [ ] **开仓模态框** (1 天)
  - 抵押品输入
  - 借款金额计算
  - 健康度显示
  - 手续费估算

- [ ] **授权流程** (0.5 天)
  ```typescript
  // hooks/useApprove.ts
  export function useApproveUSDC() {
    const { writeAsync: approve } = useContractWrite({
      address: CONTRACTS.USDC,
      abi: ERC20_ABI,
      functionName: 'approve',
    });
    
    return {
      approve: () => approve({
        args: [CONTRACTS.PoolManager, maxUint256],
      }),
    };
  }
  ```

- [ ] **开仓交易** (1 天)
  ```typescript
  // hooks/useOpenPosition.ts
  export function useOpenPosition() {
    const { writeAsync: operate } = useContractWrite({
      address: CONTRACTS.PoolManager,
      abi: PoolManagerABI,
      functionName: 'operate',
    });
    
    return {
      openPosition: (params) => operate({
        args: [
          params.poolAddress,
          params.positionId,
          params.collateralAmount,
          params.debtAmount,
        ],
      }),
    };
  }
  ```

- [ ] **交易状态追踪** (0.5 天)
  - 等待确认
  - 成功/失败提示
  - Etherscan 链接

**交付物**:
- ✅ 完整的开仓流程
- ✅ 授权 + 交易
- ✅ 状态反馈

---

## 📋 第三周任务 (仓位管理)

### Day 11-13: 仓位查询和展示

**负责人**: 前端工程师 #2  
**预计时间**: 3 天

**任务清单**:

- [ ] **仓位查询** (1 天)
  ```typescript
  // hooks/useUserPositions.ts
  export function useUserPositions() {
    const { address } = useAccount();
    
    // 方法1: 监听事件获取 positionIds
    // 方法2: 从后端 API 获取
    // 方法3: 本地存储 + 合约验证
    
    const positionIds = useLocalPositions(address);
    
    return positionIds.map(id => ({
      id,
      ...usePosition(CONTRACTS.AaveFundingPool, id),
    }));
  }
  ```

- [ ] **仓位列表** (1 天)
  - 显示所有仓位
  - 健康度颜色编码
  - 盈亏计算
  - 操作按钮

- [ ] **仓位详情** (1 天)
  - 详细信息展示
  - 历史记录
  - 操作日志

**交付物**:
- ✅ 仓位列表
- ✅ 仓位详情页
- ✅ 实时数据更新

---

### Day 14-15: 关仓功能

**负责人**: 前端工程师 #1  
**预计时间**: 2 天

**任务清单**:

- [ ] **关仓模态框**
  - 部分/全部关闭选项
  - 需要归还的 fxUSD 计算
  - 可提取抵押品显示

- [ ] **关仓交易**
  ```typescript
  // hooks/useClosePosition.ts
  export function useClosePosition() {
    return useContractWrite({
      address: CONTRACTS.PoolManager,
      abi: PoolManagerABI,
      functionName: 'operate',
    });
  }
  ```

**交付物**:
- ✅ 完整关仓流程
- ✅ 部分/全部关闭
- ✅ 交易确认

---

## 📋 第四周任务 (优化和部署)

### Day 16-17: UI/UX 优化

**负责人**: UI/UX 设计师 + 全员  
**预计时间**: 2 天

**任务清单**:

- [ ] **响应式设计**
  - 移动端适配
  - 平板适配
  - 桌面端优化

- [ ] **加载状态**
  - Skeleton 屏幕
  - 加载动画
  - 错误处理

- [ ] **用户体验**
  - Toast 通知
  - 确认对话框
  - 帮助提示

**交付物**:
- ✅ 响应式界面
- ✅ 流畅的交互
- ✅ 友好的提示

---

### Day 18-19: 测试

**负责人**: 测试工程师 + 全员  
**预计时间**: 2 天

**任务清单**:

- [ ] **功能测试**
  - [ ] 钱包连接/断开
  - [ ] 网络切换
  - [ ] 余额显示
  - [ ] 池子信息
  - [ ] 开仓流程
  - [ ] 关仓流程
  - [ ] 仓位查询

- [ ] **边界测试**
  - [ ] 余额不足
  - [ ] 授权失败
  - [ ] 交易失败
  - [ ] 网络错误

- [ ] **性能测试**
  - [ ] 页面加载速度
  - [ ] 交互响应时间
  - [ ] 数据刷新频率

**交付物**:
- ✅ 测试报告
- ✅ Bug 列表
- ✅ 修复计划

---

### Day 20: 部署

**负责人**: 前端 Leader  
**预计时间**: 1 天

**任务清单**:

- [ ] **构建优化**
  ```bash
  # Next.js
  npm run build
  
  # Vite
  npm run build
  ```

- [ ] **部署到 Vercel**
  ```bash
  vercel --prod
  ```

- [ ] **配置域名**

- [ ] **环境变量设置**

**交付物**:
- ✅ 生产环境部署
- ✅ 域名配置
- ✅ 部署文档

---

## 🎯 关键里程碑

| 里程碑 | 日期 | 交付物 |
|--------|------|--------|
| **M1: 基础搭建** | Week 1 结束 | 钱包连接 + 合约集成 |
| **M2: 核心功能** | Week 2 结束 | 开仓 + 池子展示 |
| **M3: 完整功能** | Week 3 结束 | 仓位管理 + 关仓 |
| **M4: 上线** | Week 4 结束 | 测试 + 部署 |

---

## 📊 工作量估算

### 按模块

| 模块 | 工作量 (人天) | 优先级 |
|------|--------------|--------|
| 项目搭建 | 2 | P0 |
| 钱包连接 | 1 | P0 |
| 合约集成 | 2 | P0 |
| 池子展示 | 2 | P1 |
| 开仓功能 | 3 | P0 |
| 仓位查询 | 3 | P1 |
| 关仓功能 | 2 | P1 |
| UI 优化 | 2 | P2 |
| 测试 | 2 | P1 |
| 部署 | 1 | P1 |
| **总计** | **20 人天** | - |

### 按人员

**方案 A (2-3 人)**:
- 全栈工程师 (2人): 各 10 人天 = 20 人天
- UI/UX (1人): 5 人天

**总时间**: 3-4 周

**方案 B (5 人)**:
- 前端 Leader (1人): 6 人天
- 前端工程师 (2人): 各 7 人天 = 14 人天
- UI/UX (1人): 5 人天
- 测试 (1人): 3 人天

**总时间**: 2-3 周

---

## 🛠️ 技术栈详细说明

### 必选

| 技术 | 用途 | 版本 |
|------|------|------|
| React | 前端框架 | 18.3+ |
| TypeScript | 类型安全 | 5.0+ |
| Wagmi | 以太坊交互 | 2.0+ |
| Viem | 底层库 | 2.0+ |
| RainbowKit | 钱包连接 | 2.0+ |
| TanStack Query | 数据管理 | 5.0+ |

### 推荐

| 技术 | 用途 | 备选 |
|------|------|------|
| Next.js | React 框架 | Vite |
| Tailwind CSS | 样式 | styled-components |
| shadcn/ui | 组件库 | Ant Design |
| Zustand | 状态管理 | Redux |
| React Hook Form | 表单 | Formik |

---

## 📝 每日站会建议

### 时间
每天 10:00 AM，15 分钟

### 内容模板
```
1. 昨天完成了什么？
2. 今天计划做什么？
3. 遇到什么阻碍？
4. 需要谁的帮助？
```

### 周会
每周五 16:00，1 小时

**议题**:
- 本周进度回顾
- 下周计划
- 技术难点讨论
- 代码 Review

---

## ✅ 质量检查清单

### 代码质量

- [ ] TypeScript 严格模式
- [ ] ESLint 无错误
- [ ] 代码格式化 (Prettier)
- [ ] 组件拆分合理
- [ ] Hooks 使用正确
- [ ] 错误处理完善

### 用户体验

- [ ] 加载状态明确
- [ ] 错误提示友好
- [ ] 交互响应快速 (<200ms)
- [ ] 页面加载快速 (<3s)
- [ ] 移动端体验良好

### 功能完整性

- [ ] 所有 P0 功能完成
- [ ] 边界情况处理
- [ ] 错误恢复机制
- [ ] 数据持久化

---

## 🎓 团队培训建议

### Week 0: 准备周

**培训内容**:
1. **Web3 基础** (4 小时)
   - 钱包工作原理
   - 交易流程
   - Gas 机制

2. **Wagmi + Viem** (4 小时)
   - 基础概念
   - Hooks 使用
   - 最佳实践

3. **项目业务** (2 小时)
   - CINA Protocol 介绍
   - 杠杆借贷原理
   - 合约架构

**培训方式**:
- 内部分享会
- 代码示例演示
- 实战练习

---

## 📦 交付清单

### 代码

- [ ] GitHub 仓库
- [ ] README 文档
- [ ] 环境配置说明
- [ ] 部署文档

### 文档

- [ ] 技术设计文档
- [ ] API 使用文档
- [ ] 组件文档
- [ ] 测试报告

### 部署

- [ ] Vercel 部署链接
- [ ] 域名配置
- [ ] Analytics 配置
- [ ] 错误监控

---

## 🔥 风险提示

### 技术风险

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|---------|
| 合约接口变更 | 低 | 高 | 版本锁定 + 测试 |
| 钱包兼容问题 | 中 | 中 | 多钱包测试 |
| Gas 费用过高 | 低 | 低 | Sepolia 测试网 |
| RPC 不稳定 | 中 | 中 | 备用 RPC |

### 进度风险

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|---------|
| 需求变更 | 中 | 高 | 敏捷开发 |
| 人员不足 | 低 | 高 | 提前招聘 |
| 技术难题 | 中 | 中 | 技术预研 |

---

## 💰 预算建议

### 人员成本 (以天计)

| 角色 | 日薪 (估算) | 工作日 | 小计 |
|------|------------|--------|------|
| 前端 Leader | $500 | 12 | $6,000 |
| 前端工程师 x2 | $400 | 28 | $11,200 |
| UI/UX | $350 | 10 | $3,500 |
| 测试 | $300 | 5 | $1,500 |
| **总计** | - | - | **$22,200** |

### 工具成本

| 工具 | 月费 | 说明 |
|------|------|------|
| Vercel Pro | $20 | 部署托管 |
| Sentry | $26 | 错误监控 |
| WalletConnect | $0 | 免费 |
| **总计** | **~$50/月** | - |

---

**文档版本**: v1.0  
**创建日期**: 2025-10-15  
**最后更新**: 2025-10-15  
**状态**: ✅ 准备实施

