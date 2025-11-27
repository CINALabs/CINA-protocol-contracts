#!/bin/bash
echo "yes" | npx hardhat ignition deploy ignition/modules/sepolia/SepoliaFxProtocol.ts --network sepolia --parameters ignition/parameters/sepolia.json --deployment-id sepolia-test
