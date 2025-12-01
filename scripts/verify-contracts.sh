#!/bin/bash
# 合约验证脚本 - 在 Sepolia Etherscan 上开源合约代码
# 使用方法: ./scripts/verify-contracts.sh

set -e
source .env

echo "=== 验证 PoolManager 合约 ==="
echo "地址: 0x7fb8dab92da4336302ccdfa2d515f5ec546b93f7"

forge verify-contract \
  0x7fb8dab92da4336302ccdfa2d515f5ec546b93f7 \
  contracts/core/PoolManager.sol:PoolManager \
  --chain sepolia \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --watch

echo ""
echo "=== 验证 MockERC20 代币 ==="

# USDT
echo "验证 USDT..."
forge verify-contract \
  0xbe0aed886D89bB704261B676282CE98482F83520 \
  contracts/mocks/MockERC20.sol:MockERC20 \
  --chain sepolia \
  --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "Tether USD" "USDT" 6) \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --watch

# DAI
echo "验证 DAI..."
forge verify-contract \
  0xCf0D56b2f39Cc32F3A8a85c1B3417a0580E82B09 \
  contracts/mocks/MockERC20.sol:MockERC20 \
  --chain sepolia \
  --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "Dai Stablecoin" "DAI" 18) \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --watch

# FRAX
echo "验证 FRAX..."
forge verify-contract \
  0x815A12A97Fb438C194642B46B8AE54c53Fc9A914 \
  contracts/mocks/MockERC20.sol:MockERC20 \
  --chain sepolia \
  --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "Frax" "FRAX" 18) \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --watch

# stETH
echo "验证 stETH..."
forge verify-contract \
  0xEf65EC861967Ae97203858F5e7653e38d5811e3D \
  contracts/mocks/MockERC20.sol:MockERC20 \
  --chain sepolia \
  --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "Lido Staked Ether" "stETH" 18) \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --watch

# rETH
echo "验证 rETH..."
forge verify-contract \
  0xc82741f814150304A5ab049A3cF104C2CCC566e1 \
  contracts/mocks/MockERC20.sol:MockERC20 \
  --chain sepolia \
  --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "Rocket Pool ETH" "rETH" 18) \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --watch

# cbETH
echo "验证 cbETH..."
forge verify-contract \
  0x9348Fb6077E43787Ea03e175934F1CA2D85890C4 \
  contracts/mocks/MockERC20.sol:MockERC20 \
  --chain sepolia \
  --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "Coinbase Wrapped Staked ETH" "cbETH" 18) \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --watch

# ezETH
echo "验证 ezETH..."
forge verify-contract \
  0x489Db3ec0322Dd1Cc82E800aD844f5De880f8e90 \
  contracts/mocks/MockERC20.sol:MockERC20 \
  --chain sepolia \
  --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "Renzo Restaked ETH" "ezETH" 18) \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --watch

# weETH
echo "验证 weETH..."
forge verify-contract \
  0x6D74fF9320198c48285D0C3dE25df2d06056b37D \
  contracts/mocks/MockERC20.sol:MockERC20 \
  --chain sepolia \
  --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "Wrapped eETH" "weETH" 18) \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --watch

# rsETH
echo "验证 rsETH..."
forge verify-contract \
  0x6B386e20d5eeE4e6298D755bb0B15Ea89a02eeA4 \
  contracts/mocks/MockERC20.sol:MockERC20 \
  --chain sepolia \
  --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "KelpDAO Restaked ETH" "rsETH" 18) \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --watch

# WBTC
echo "验证 WBTC..."
forge verify-contract \
  0x69986580089DCae38F0Dcf004d0ddc7803E7b614 \
  contracts/mocks/MockERC20.sol:MockERC20 \
  --chain sepolia \
  --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "Wrapped BTC" "WBTC" 8) \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --watch

# tBTC
echo "验证 tBTC..."
forge verify-contract \
  0x5d2a6F8Da95eB1AD53F67cAb321A609733987ac3 \
  contracts/mocks/MockERC20.sol:MockERC20 \
  --chain sepolia \
  --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "tBTC v2" "tBTC" 18) \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --watch

echo ""
echo "=== 验证 MockAggregatorV3Interface 预言机 ==="

# USDT Oracle ($1.00)
echo "验证 USDT Oracle..."
forge verify-contract \
  0xc851302f5Dbf579Fd18d9700aeC06260E93818c5 \
  contracts/mocks/MockAggregatorV3Interface.sol:MockAggregatorV3Interface \
  --chain sepolia \
  --constructor-args $(cast abi-encode "constructor(uint8,int256)" 8 100000000) \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --watch

echo ""
echo "=== 验证完成 ==="
