import { ethers, defender } from "hardhat";
import * as dotenv from "dotenv";

dotenv.config();

async function main() {
  // Define the addresses to be used
  const usdcTokenAddress = "0x22760ae19110018b44337521A41F648e025AcDc4"; // USDC token address on Arbitrum One
  const gnosisSafeWallet = process.env.GNOSIS_SAFE_ADDRESS as string; // Gnosis Safe multi-sig wallet
  const taxWallet = "0x233AF064cc70D2d575fD8824B3682948dA3aB94F"; // Tax Wallet Address
  const stakingWallet = "0xA8d59C804456F1b56b38Fb569641210229Fe051b"; // Staking Rewards Wallet Address
  const icoWallet = "0x04E7a54f579cb7e9D4c95a7FB7aE8c1A0181F846"; // ICO Wallet Address
  const liquidityWallet = "0x392f3afA9863baE12CDA1b1E6624E55C8c47A789"; // Liquidity Wallet Address
  const farmingWallet = "0x03275e133C6cCE9C066247FA7532D0ab86F17926"; // Farming Wallet Address
  const listingWallet = "0x63824CfF15D7D50537E7A1d47BDc762192b04538"; // Listing Wallet Address
  const reserveWallet = "0x666B354F231c6Cfd8cA5aD0944559f0420916BB5"; // Reserve Wallet Address
  const marketingWallet = "0xc0645D8968599A9C8908813174828aca4e9187cE"; // Marketing wallet address
  const teamWallet = "0x891e4ce655ea6080266b43B7aDc4878af9500353"; // Team wallet address
  const devWallet = "0xd0eecB3E6ba57E5b15051882A19413732809c872"; // Dev wallet address
  const prosicoWallet = "0x1234567890123456789012345678901234567890"; // Replace with actual prosico wallet address

  // Define the vesting wallets and types (0 for marketing, 1 for team)
  const vestingWallets = [
    { address: "0xb6b6E3a54BCAF861ac456b38D15389dC8E638450", vestingType: 0 }, // mi1
    { address: "0x0fcD04410E6DA9339c1578C9f7aC1e48AED4B73C", vestingType: 0 }, // bns
    { address: "0x156841B0541F11522656A8FA6d0542B737754E8e", vestingType: 0 }, // Mch
    { address: "0xB50516982524DFF3d8d563F46AD54891Aa61944E", vestingType: 1 }, // fl
    { address: "0x89D6a038D902fEAb8c506C3F392b1B91CA8461B7", vestingType: 1 }, // 7w
    { address: "0x810999FAAe498DCb4e46736c6f901DDCd51D3a01", vestingType: 1 }, // z
  ];

  console.log("Deploying contracts with the Gnosis Safe as the deployer...");

  // Deploy PROSPERAMath
  const MathFactory = await ethers.getContractFactory("PROSPERAMath");
  const mathDeployment = await defender.deployProxy(MathFactory, [], {
    initializer: "initialize",
    redeployImplementation: "always",
  });
  await mathDeployment.waitForDeployment();
  const mathAddress = await mathDeployment.getAddress();
  console.log(`PROSPERAMath deployed to ${mathAddress}`);

  // Deploy PROSPERAStaking
  const StakingFactory = await ethers.getContractFactory("PROSPERAStaking");
  const stakingDeployment = await defender.deployProxy(StakingFactory, [], {
    initializer: "initialize",
    redeployImplementation: "always",
  });
  await stakingDeployment.waitForDeployment();
  const stakingAddress = await stakingDeployment.getAddress();
  console.log(`PROSPERAStaking deployed to ${stakingAddress}`);

  // Deploy PROSPERAICO
  const ICOFactory = await ethers.getContractFactory("PROSPERAICO");
  const icoDeployment = await defender.deployProxy(ICOFactory, [], {
    initializer: "initialize",
    redeployImplementation: "always",
  });
  await icoDeployment.waitForDeployment();
  const icoAddress = await icoDeployment.getAddress();
  console.log(`PROSPERAICO deployed to ${icoAddress}`);

  // Deploy PROSPERAVesting
  const VestingFactory = await ethers.getContractFactory("PROSPERAVesting");
  const vestingDeployment = await defender.deployProxy(VestingFactory, [], {
    initializer: "initialize",
    redeployImplementation: "always",
  });
  await vestingDeployment.waitForDeployment();
  const vestingAddress = await vestingDeployment.getAddress();
  console.log(`PROSPERAVesting deployed to ${vestingAddress}`);

  // Deploy main PROSPERA contract
  const PROSPERAFactory = await ethers.getContractFactory("PROSPERA");
  const prosperaDeployment = await defender.deployProxy(
    PROSPERAFactory,
    [{
      deployerWallet: gnosisSafeWallet,
      usdcToken: usdcTokenAddress,
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
    }],
    {
      initializer: "initialize",
      redeployImplementation: "always",
    }
  );

  await prosperaDeployment.waitForDeployment();
  const prosperaAddress = await prosperaDeployment.getAddress();
  console.log(`PROSPERA main contract deployed to ${prosperaAddress}`);

  // Get the deployed contract instances
  const prospera = await ethers.getContractAt("PROSPERA", prosperaAddress);
  const prosperaVesting = await ethers.getContractAt("PROSPERAVesting", vestingAddress);

  // Initialize child contracts with PROSPERA address
  const mathContract = await ethers.getContractAt("PROSPERAMath", mathAddress);
  await mathContract.initialize(prosperaAddress);
  console.log("PROSPERAMath initialized");

  const stakingContract = await ethers.getContractAt("PROSPERAStaking", stakingAddress);
  await stakingContract.initialize(prosperaAddress);
  console.log("PROSPERAStaking initialized");

  const icoContract = await ethers.getContractAt("PROSPERAICO", icoAddress);
  await icoContract.initialize(prosperaAddress, icoWallet, prosicoWallet);
  console.log("PROSPERAICO initialized");

  await prosperaVesting.initialize(prosperaAddress);
  console.log("PROSPERAVesting initialized");

  // Add vesting wallets with their respective types
  for (const wallet of vestingWallets) {
    const tx = await prospera.addToVesting(wallet.address, 0, wallet.vestingType);
    await tx.wait();
    console.log(`Added ${wallet.address} to vesting schedule with type ${wallet.vestingType}`);
  }

  // Transfer ownership of all contracts to the Gnosis Safe wallet
  const contracts = [prospera, mathContract, stakingContract, icoContract, prosperaVesting];
  for (const contract of contracts) {
    if ((await contract.owner()) !== gnosisSafeWallet) {
      const transferTx = await contract.transferOwnership(gnosisSafeWallet);
      await transferTx.wait();
      console.log(`Ownership of ${await contract.getAddress()} transferred to Gnosis Safe wallet: ${gnosisSafeWallet}`);
    }
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});