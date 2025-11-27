import hre from "hardhat";

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Account balance:", (await hre.ethers.provider.getBalance(deployer.address)).toString());

  // 部署 EmptyContract
  const EmptyContract = await hre.ethers.getContractFactory("EmptyContract");
  const emptyContract = await EmptyContract.deploy();
  await emptyContract.waitForDeployment();
  console.log("EmptyContract deployed to:", await emptyContract.getAddress());

  // 部署 ProxyAdmin
  const ProxyAdmin = await hre.ethers.getContractFactory("ProxyAdmin");
  const proxyAdmin = await ProxyAdmin.deploy(deployer.address);
  await proxyAdmin.waitForDeployment();
  console.log("ProxyAdmin deployed to:", await proxyAdmin.getAddress());

  // 部署代理合约
  const TransparentUpgradeableProxy = await hre.ethers.getContractFactory("TransparentUpgradeableProxy");
  
  const poolManagerProxy = await TransparentUpgradeableProxy.deploy(
    await emptyContract.getAddress(),
    await proxyAdmin.getAddress(),
    "0x"
  );
  await poolManagerProxy.waitForDeployment();
  console.log("PoolManagerProxy deployed to:", await poolManagerProxy.getAddress());

  const fxUSDBasePoolProxy = await TransparentUpgradeableProxy.deploy(
    await emptyContract.getAddress(),
    await proxyAdmin.getAddress(),
    "0x"
  );
  await fxUSDBasePoolProxy.waitForDeployment();
  console.log("FxUSDBasePoolProxy deployed to:", await fxUSDBasePoolProxy.getAddress());

  const pegKeeperProxy = await TransparentUpgradeableProxy.deploy(
    await emptyContract.getAddress(),
    await proxyAdmin.getAddress(),
    "0x"
  );
  await pegKeeperProxy.waitForDeployment();
  console.log("PegKeeperProxy deployed to:", await pegKeeperProxy.getAddress());

  const fxUSDProxy = await TransparentUpgradeableProxy.deploy(
    await emptyContract.getAddress(),
    await proxyAdmin.getAddress(),
    "0x"
  );
  await fxUSDProxy.waitForDeployment();
  console.log("FxUSDProxy deployed to:", await fxUSDProxy.getAddress());

  // 部署 PoolManager 实现
  const PoolManager = await hre.ethers.getContractFactory("PoolManager");
  const poolManagerImpl = await PoolManager.deploy(
    await fxUSDProxy.getAddress(),
    await fxUSDBasePoolProxy.getAddress(),
    await pegKeeperProxy.getAddress(),
    hre.ethers.ZeroAddress,
    hre.ethers.ZeroAddress
  );
  await poolManagerImpl.waitForDeployment();
  console.log("PoolManagerImplementation deployed to:", await poolManagerImpl.getAddress());

  // 部署 ReservePool 和 RevenuePool
  const ReservePool = await hre.ethers.getContractFactory("ReservePool");
  const reservePool = await ReservePool.deploy(deployer.address, await poolManagerProxy.getAddress());
  await reservePool.waitForDeployment();
  console.log("ReservePool deployed to:", await reservePool.getAddress());

  const RevenuePool = await hre.ethers.getContractFactory("RevenuePool");
  const revenuePool = await RevenuePool.deploy(deployer.address, deployer.address, deployer.address);
  await revenuePool.waitForDeployment();
  console.log("RevenuePool deployed to:", await revenuePool.getAddress());

  // 编码初始化数据
  const initData = poolManagerImpl.interface.encodeFunctionData("initialize", [
    deployer.address,
    0n,
    100000000n, // 10%
    1000000n, // 0.1%
    deployer.address,
    await revenuePool.getAddress(),
    await reservePool.getAddress(),
  ]);

  console.log("\nAttempting to upgrade PoolManagerProxy...");
  try {
    const tx = await proxyAdmin.upgradeAndCall(
      await poolManagerProxy.getAddress(),
      await poolManagerImpl.getAddress(),
      initData
    );
    await tx.wait();
    console.log("✅ PoolManagerProxy upgraded successfully!");
  } catch (error: any) {
    console.error("❌ Failed to upgrade PoolManagerProxy:");
    console.error(error.message);
    if (error.data) {
      console.error("Error data:", error.data);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
