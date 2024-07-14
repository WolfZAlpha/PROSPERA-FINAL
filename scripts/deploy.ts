import { ethers, upgrades } from "hardhat";
import * as dotenv from "dotenv";
import * as fs from 'fs';

dotenv.config();

async function main() {
  // Defines the addresses to be used
  const gnosisSafeWallet = process.env.GNOSIS_SAFE_ADDRESS as string;
  const taxWallet = "0x233AF064cc70D2d575fD8824B3682948dA3aB94F";
  const stakingWallet = "0x93b43c33F4485f8f81fFB2027E51dBa573C393d5";
  const icoWallet = "0xc15C609c4a41D1e247389Cd1B2d8bc4DbDcd4485";
  const liquidityWallet = "0x392f3afA9863baE12CDA1b1E6624E55C8c47A789";
  const farmingWallet = "0x03275e133C6cCE9C066247FA7532D0ab86F17926";
  const listingWallet = "0x63824CfF15D7D50537E7A1d47BDc762192b04538";
  const reserveWallet = "0x666B354F231c6Cfd8cA5aD0944559f0420916BB5";
  const marketingWallet = "0xc0645D8968599A9C8908813174828aca4e9187cE";
  const teamWallet = "0x891e4ce655ea6080266b43B7aDc4878af9500353";
  const devWallet = "0x1a95B003d4bE3abb3825f9544912Dd9a6A47aaC4";
  const prosicoWallet = "0xF1dBbe7e8f5e9e2c463342C17fA35FBEA303762D";

  // Defines the vesting wallets and types (0 for marketing, 1 for team)
  const vestingWallets = [
    { address: "0xb6b6E3a54BCAF861ac456b38D15389dC8E638450", vestingType: 0, amount: ethers.parseEther("600000") },
    { address: "0x0fcD04410E6DA9339c1578C9f7aC1e48AED4B73C", vestingType: 0, amount: ethers.parseEther("1000000") },
    { address: "0x156841B0541F11522656A8FA6d0542B737754E8e", vestingType: 0, amount: ethers.parseEther("60000") },
    { address: "0x87715D8cC9F32e694CB644fce3b86F4C7311aD15", vestingType: 0, amount: ethers.parseEther("60000") },
    { address: "0x4c6A8Ff3bADe54BCFf3c63Aa84Cb8985c68F0A30", vestingType: 0, amount: ethers.parseEther("60000") },
    { address: "0x3bda56ef07bf6f996f8e3defddde6c8109b7e7be", vestingType: 0, amount: ethers.parseEther("60000") },
    { address: "0xA2526C8DD2560ef4ad8D0A8E2d8201819A92Ae96", vestingType: 0, amount: ethers.parseEther("60000") },
    { address: "0x0c45809731a3E88373b63DcA6A1a19dE98843568", vestingType: 0, amount: ethers.parseEther("3000000") },
    { address: "0xC0fF3Af640B344AaDfdC8909BF9826D452bf1718", vestingType: 1, amount: ethers.parseEther("200000") },
    { address: "0xB50516982524DFF3d8d563F46AD54891Aa61944E", vestingType: 1, amount: ethers.parseEther("35000000") },
    { address: "0x89D6a038D902fEAb8c506C3F392b1B91CA8461B7", vestingType: 1, amount: ethers.parseEther("40000000") },
    { address: "0x1a95B003d4bE3abb3825f9544912Dd9a6A47aaC4", vestingType: 1, amount: ethers.parseEther("60000000") },
  ];

  console.log("Deploying PROSPERA contracts with a regular deployer account...");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  async function deployAndSaveProxy(name: string, factory: any, args: any[] = [], initializer = 'initialize') {
    console.log(`Deploying ${name} with args:`, args);
    let contract;
    try {
      contract = await upgrades.deployProxy(factory, args, { initializer: initializer });
      await contract.waitForDeployment();
      const address = await contract.getAddress();
      console.log(`${name} deployed to ${address}`);
      return { contract, address };
    } catch (error) {
      console.error(`Error deploying ${name}:`, error);
      throw error;
    }
  }

  // Deploy PROSPERAMath without initialization
  const MathFactory = await ethers.getContractFactory("PROSPERAMath");
  const mathContract = await upgrades.deployProxy(MathFactory, [], { initializer: false });
  await mathContract.waitForDeployment();
  const mathAddress = await mathContract.getAddress();
  console.log(`PROSPERAMath deployed to ${mathAddress}`);

  // Deploy PROSPERAStaking without initialization
  const StakingFactory = await ethers.getContractFactory("PROSPERAStaking");
  const stakingContract = await upgrades.deployProxy(StakingFactory, [], { initializer: false });
  await stakingContract.waitForDeployment();
  const stakingAddress = await stakingContract.getAddress();
  console.log(`PROSPERAStaking deployed to ${stakingAddress}`);

  // Deploy PROSPERAICO without initialization
  const ICOFactory = await ethers.getContractFactory("PROSPERAICO");
  const icoContract = await upgrades.deployProxy(ICOFactory, [], { initializer: false });
  await icoContract.waitForDeployment();
  const icoAddress = await icoContract.getAddress();
  console.log(`PROSPERAICO deployed to ${icoAddress}`);

  // Deploy PROSPERAVesting without initialization
  const VestingFactory = await ethers.getContractFactory("PROSPERAVesting");
  const vestingContract = await upgrades.deployProxy(VestingFactory, [], { initializer: false });
  await vestingContract.waitForDeployment();
  const vestingAddress = await vestingContract.getAddress();
  console.log(`PROSPERAVesting deployed to ${vestingAddress}`);

  // Deploy main PROSPERA contract
  const PROSPERAFactory = await ethers.getContractFactory("PROSPERA");
  const { contract: prospera, address: prosperaAddress } = await deployAndSaveProxy("PROSPERA", PROSPERAFactory, [{
    deployerWallet: deployer.address,
    taxWallet: taxWallet,
    stakingWallet: stakingWallet,
    icoWallet: icoWallet,
    prosicoWallet: prosicoWallet,
    liquidityWallet: liquidityWallet,
    farmingWallet: farmingWallet,
    listingWallet: listingWallet,
    reserveWallet: reserveWallet,
    marketingWallet: marketingWallet,
    teamWallet: teamWallet,
    devWallet: devWallet,
    stakingContract: stakingAddress,
    vestingContract: vestingAddress,
    icoContract: icoAddress,
    mathContract: mathAddress
  }]);

  console.log("PROSPERA main contract initialized");

  // Initialize child contracts with PROSPERA address
  await mathContract.initialize(prosperaAddress);
  console.log("PROSPERAMath initialized with PROSPERA address");

  await stakingContract.initialize(prosperaAddress);
  console.log("PROSPERAStaking initialized with PROSPERA address");

  await icoContract.initialize(prosperaAddress, icoWallet, prosicoWallet);
  console.log("PROSPERAICO initialized with PROSPERA address");

  await vestingContract.initialize(prosperaAddress);
  console.log("PROSPERAVesting initialized with PROSPERA address");

  // Verify token minting and distribution
  const wallets = [
    { name: "Staking", address: stakingWallet },
    { name: "Liquidity", address: liquidityWallet },
    { name: "Farming", address: farmingWallet },
    { name: "Listing", address: listingWallet },
    { name: "Reserve", address: reserveWallet },
    { name: "Marketing", address: marketingWallet },
    { name: "Team", address: teamWallet },
    { name: "Dev", address: devWallet },
    { name: "Prosico", address: prosicoWallet },
  ];

  for (const wallet of wallets) {
    const balance = await prospera.balanceOf(wallet.address);
    console.log(`${wallet.name} wallet balance: ${ethers.formatEther(balance)} PROS`);
    if (balance.isZero()) {
      console.error(`Warning: ${wallet.name} wallet has zero balance!`);
    }
  }

  // Add vesting wallets with their respective types and amounts
  for (const wallet of vestingWallets) {
    const tx = await prospera.addToVesting(wallet.address, wallet.amount, wallet.vestingType);
    await tx.wait();
    console.log(`Added ${wallet.address} to vesting schedule with type ${wallet.vestingType} and amount ${ethers.formatEther(wallet.amount)} PROS`);
  }

  // Transfer ownership of all contracts to the Gnosis Safe wallet
  const contracts = [prospera, mathContract, stakingContract, icoContract, vestingContract];
  for (const contract of contracts) {
    const currentOwner = await contract.owner();
    if (currentOwner !== gnosisSafeWallet) {
      console.log(`Transferring ownership of ${await contract.getAddress()} from ${currentOwner} to ${gnosisSafeWallet}`);
      const transferTx = await contract.transferOwnership(gnosisSafeWallet);
      await transferTx.wait();
      console.log(`Ownership of ${await contract.getAddress()} transferred to Gnosis Safe wallet: ${gnosisSafeWallet}`);
    } else {
      console.log(`${await contract.getAddress()} is already owned by ${gnosisSafeWallet}`);
    }
  }

  // Verify total supply
  const totalSupply = await prospera.totalSupply();
  console.log(`Total supply: ${ethers.formatEther(totalSupply)} PROS`);

  // Save proxy addresses
  const proxyAddresses = {
    PROSPERA: prosperaAddress,
    PROSPERAMath: mathAddress,
    PROSPERAStaking: stakingAddress,
    PROSPERAICO: icoAddress,
    PROSPERAVesting: vestingAddress
  };

  fs.writeFileSync('proxyAddresses.json', JSON.stringify(proxyAddresses, null, 2));
  console.log("Proxy addresses saved to proxyAddresses.json");

  console.log("PROSPERA deployment and initialization completed successfully.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
