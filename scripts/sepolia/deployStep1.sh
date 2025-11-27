#!/bin/bash

# f(x) Protocol Sepolia 部署脚本 - 第一步：核心协议
# 
# 使用方法：
# chmod +x scripts/sepolia/deployStep1.sh
# ./scripts/sepolia/deployStep1.sh

set -e

echo "=========================================="
echo "f(x) Protocol Sepolia Deployment - Step 1"
echo "=========================================="
echo ""

# 检查环境变量
if [ -z "$PRIVATE_KEY" ]; then
    echo "❌ Error: PRIVATE_KEY not set in .env file"
    exit 1
fi

echo "📋 Deploying core protocol contracts..."
echo ""

# 部署核心协议
npx hardhat ignition deploy ignition/modules/sepolia/SepoliaFxProtocol.ts \
  --network sepolia \
  --parameters ignition/parameters/sepolia.json \
  --verify

echo ""
echo "✅ Core protocol deployed successfully!"
echo ""
echo "📝 Deployment addresses saved to:"
echo "   ignition/deployments/chain-11155111/deployed_addresses.json"
echo ""
echo "Next steps:"
echo "1. Run: ./scripts/sepolia/deployStep2.sh (deploy pool)"
echo "2. Run: npx hardhat run scripts/sepolia/mintTokens.ts --network sepolia"
echo "3. Run: npx hardhat run scripts/sepolia/testBasicFunctions.ts --network sepolia"
