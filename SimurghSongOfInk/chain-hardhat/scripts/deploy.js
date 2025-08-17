const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with:", deployer.address);
  const SIM = await hre.ethers.getContractFactory("SIMToken");
  const sim = await SIM.deploy(deployer.address, hre.ethers.parseEther("1000000"));
  await sim.waitForDeployment();
  console.log("SIM deployed:", await sim.getAddress());
}

main().catch((e) => { console.error(e); process.exit(1); });
