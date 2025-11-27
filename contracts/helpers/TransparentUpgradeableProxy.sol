// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TransparentUpgradeableProxy as OZTransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title TransparentUpgradeableProxy
 * @dev Wrapper for OpenZeppelin's TransparentUpgradeableProxy to make it available for Hardhat Ignition
 */
contract TransparentUpgradeableProxy is OZTransparentUpgradeableProxy {
    constructor(
        address _logic,
        address initialOwner,
        bytes memory _data
    ) OZTransparentUpgradeableProxy(_logic, initialOwner, _data) {}
}
