import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * 只部署 Mock 代币模块
 * 使用主网代币名称，并给部署者铸造 10^15 个代币
 */
export default buildModule("MockTokensOnly", (m) => {
  const admin = m.getAccount(0);
  
  // ============================================
  // 部署 Mock 代币（使用主网代币名称）
  // ============================================
  console.log("Deploying Mock Tokens with mainnet names...");
  
  // USDC - USD Coin (6 decimals)
  const MockUSDC = m.contract("MockERC20", ["USD Coin", "USDC", 6], { id: "MockUSDC" });
  
  // wstETH - Wrapped liquid staked Ether 2.0 (18 decimals)
  const MockWstETH = m.contract("MockERC20", ["Wrapped liquid staked Ether 2.0", "wstETH", 18], { id: "MockWstETH" });
  
  // ============================================
  // 给部署者铸造 10^15 个代币
  // ============================================
  console.log("Minting 10^15 tokens to deployer...");
  
  // 10^15 USDC (6 decimals) = 1,000,000,000,000,000 USDC
  const mintAmountUSDC = 1000000000000000n * 1000000n;
  
  // 10^15 wstETH (18 decimals) = 1,000,000,000,000,000 wstETH
  const mintAmountWstETH = 1000000000000000n * 1000000000000000000n;
  
  m.call(MockUSDC, "mint", [admin, mintAmountUSDC], { 
    id: "MockUSDC_mint",
    after: [MockUSDC]
  });
  
  m.call(MockWstETH, "mint", [admin, mintAmountWstETH], { 
    id: "MockWstETH_mint",
    after: [MockWstETH]
  });
  
  console.log("Mock tokens deployed and minted!");
  
  return {
    MockUSDC,
    MockWstETH,
  };
});
