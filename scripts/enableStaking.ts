// enableStaking.ts

import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Enabling staking with the account:", deployer.address);

  // Get the deployed PROSPERA contract
  const PROSPERA = await ethers.getContractFactory("PROSPERA");
  const prosperaAddress = "YOUR_DEPLOYED_PROSPERA_CONTRACT_ADDRESS";
  const prospera = PROSPERA.attach(prosperaAddress);

  // Enable staking
  await prospera.enableStaking(true);
  console.log("Staking has been enabled");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });