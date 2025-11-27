// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ProxyAdmin as OZProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @title ProxyAdmin
 * @dev Wrapper for OpenZeppelin's ProxyAdmin to make it available for Hardhat Ignition
 */
contract ProxyAdmin is OZProxyAdmin {
    constructor(address initialOwner) OZProxyAdmin(initialOwner) {}
}
