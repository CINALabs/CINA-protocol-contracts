#!/bin/bash

# f(x) Protocol Sepolia 部署脚本 - 第二步：部署池子
# 
# 使用方法：
# chmod +x scripts/sepolia/deployStep2.sh
# ./scripts/sepolia/deployStep2.sh

set -e

echo "=========================================="
echo "f(x) Protocol Sepolia Deployment - Step 2"
echo "=========================================="
echo ""

# 检查第一步是否完成
DEPLOYMENT_FILE="ignition/deployments/chain-11155111/deployed_addresses.json"
if [ ! -f "$DEPLOYMENT_FILE" ]; then
    echo "❌ Error: Core protocol not deployed yet"
    echo "   Please run: ./scripts/sepolia/deployStep1.sh first"
    exit 1
fi

echo "📋 Reading deployed addresses..."
echo ""

# 读取已部署的合约地址
POOL_MANAGER=$(jq -r '.["SepoliaFxProtocol#PoolManager"]' $DEPLOYMENT_FILE)
PROXY_ADMIN=$(jq -r '.["SepoliaFxProtocol#ProxyAdmin"]' $DEPLOYMENT_FILE)
MOCK_WSTETH=$(jq -r '.["SepoliaFxProtocol#MockWstETH"]' $DEPLOYMENT_FILE)
MOCK_ETH_ORACLE=$(jq -r '.["SepoliaFxProtocol#MockETHOracle"]' $DEPLOYMENT_FILE)

echo "PoolManager: $POOL_MANAGER"
echo "ProxyAdmin: $PROXY_ADMIN"
echo "MockWstETH: $MOCK_WSTETH"
echo "MockETHOracle: $MOCK_ETH_ORACLE"
echo ""

# 创建临时参数文件
TEMP_PARAMS="ignition/parameters/sepolia-pool-temp.json"
cat > $TEMP_PARAMS << EOF
{
  "SepoliaPool": {
    "PoolManagerProxy": "$POOL_MANAGER",
    "ProxyAdmin": "$PROXY_ADMIN",
    "MockWstETH": "$MOCK_WSTETH",
    "MockETHOracle": "$MOCK_ETH_ORACLE",
    "CollateralCapacity": "1000000000000000000000",
    "DebtCapacity": "500000000000000000000000",
    "DebtRatioLower": "500000000000000000",
    "DebtRatioUpper": "857142857142857142",
    "RebalanceDebtRatio": "800000000000000000",
    "RebalanceBonusRatio": "20000000",
    "LiquidateDebtRatio": "950000000000000000",
    "LiquidateBonusRatio": "40000000"
  }
}
EOF

echo "📋 Deploying wstETH pool..."
echo ""

# 部署池子
npx hardhat ignition deploy ignition/modules/sepolia/SepoliaPool.ts \
  --network sepolia \
  --parameters $TEMP_PARAMS \
  --verify

# 清理临时文件
rm $TEMP_PARAMS

echo ""
echo "✅ Pool deployed successfully!"
echo ""
echo "📝 Deployment addresses saved to:"
echo "   ignition/deployments/chain-11155111/deployed_addresses.json"
echo ""
echo "Next steps:"
echo "1. Run: npx hardhat run scripts/sepolia/mintTokens.ts --network sepolia"
echo "2. Run: npx hardhat run scripts/sepolia/testBasicFunctions.ts --network sepolia"
