import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "@typechain/hardhat";
import * as dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.20",
        settings: {
          optimizer: {
            enabled: true, // Enable optimizer
            runs: 200, 
            details: {
              yul: true, // Enable Yul optimizer
              yulDetails: {
                stackAllocation: true, // Enable stack allocation in Yul optimizer
                optimizerSteps: "u", // Enable the IR-based optimizer
              },
            },
          },
        },
      },
    ],
  },
  typechain: {
    outDir: "typechain", 
    target: "ethers-v6", 
  },
  defender: {
    apiKey: process.env.DEFENDER_KEY as string, // Defender API key from environment variables
    apiSecret: process.env.DEFENDER_SECRET as string, // Defender API secret from environment variables
  },
  networks: {
    arbitrum: {
      url: "https://arb1.arbitrum.io/rpc", 
      chainId: 42161,
    },
  },
};

export default config;
