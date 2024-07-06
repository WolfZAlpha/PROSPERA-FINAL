import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { Contract, Signer } from "ethers";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("PROSPERA", function () {
  let prospera: Contract;
  let owner: Signer;
  let addr1: Signer;
  let addr2: Signer;
  let addrs: Signer[];

  const TOTAL_SUPPLY = ethers.parseEther("1000000000"); // 1 billion tokens
  const INITIAL_STAKE_AMOUNT = ethers.parseEther("5000"); // 5000 tokens
  const MIN_ICO_BUY = ethers.parseEther("150");
  const MAX_ICO_BUY = ethers.parseEther("500000");

  beforeEach(async function () {
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();

    const PROSPERA = await ethers.getContractFactory("PROSPERA");
    prospera = await upgrades.deployProxy(PROSPERA, [
      ethers.ZeroAddress, // USDC token address
      await owner.getAddress(),
      await owner.getAddress(), // tax wallet
      await owner.getAddress(), // staking wallet
      await owner.getAddress(), // ICO wallet
      await owner.getAddress(), // prosico wallet
      await owner.getAddress(), // liquidity wallet
      await owner.getAddress(), // farming wallet
      await owner.getAddress(), // listing wallet
      await owner.getAddress(), // reserve wallet
      await owner.getAddress(), // marketing wallet
      await owner.getAddress(), // team wallet
      await owner.getAddress(), // dev wallet
    ]);
    await prospera.deployed();
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await prospera.owner()).to.equal(await owner.getAddress());
    });

    it("Should assign the total supply of tokens to the owner", async function () {
      const ownerBalance = await prospera.balanceOf(await owner.getAddress());
      expect(await prospera.totalSupply()).to.equal(ownerBalance);
    });
  });

  describe("Transactions", function () {
    it("Should transfer tokens between accounts", async function () {
      const amount = ethers.parseEther("50");
      await expect(prospera["transfer(address,uint256)"](await addr1.getAddress(), amount))
        .to.emit(prospera, "Transfer")
        .withArgs(await owner.getAddress(), await addr1.getAddress(), amount);

      const addr1Balance = await prospera.balanceOf(await addr1.getAddress());
      expect(addr1Balance).to.equal(amount);

      await expect(prospera.connect(addr1)["transfer(address,uint256)"](await addr2.getAddress(), amount))
        .to.emit(prospera, "Transfer")
        .withArgs(await addr1.getAddress(), await addr2.getAddress(), amount);

      const addr2Balance = await prospera.balanceOf(await addr2.getAddress());
      expect(addr2Balance).to.equal(amount);
    });

    it("Should fail if sender doesn't have enough tokens", async function () {
      const initialOwnerBalance = await prospera.balanceOf(await owner.getAddress());
      await expect(
        prospera.connect(addr1)["transfer(address,uint256)"](await owner.getAddress(), 1)
      ).to.be.revertedWith("ERC20: transfer amount exceeds balance");
      expect(await prospera.balanceOf(await owner.getAddress())).to.equal(initialOwnerBalance);
    });

    it("Should apply tax and burn on transfers", async function () {
      const amount = ethers.parseEther("1000");
      await prospera["transfer(address,uint256)"](await addr1.getAddress(), amount);
      
      const initialBalance = await prospera.balanceOf(await addr1.getAddress());
      const transferAmount = ethers.parseEther("100");
      
      await expect(prospera.connect(addr1)["transfer(address,uint256)"](await addr2.getAddress(), transferAmount))
        .to.emit(prospera, "TransferWithTaxAndBurn");
      
      const finalBalance = await prospera.balanceOf(await addr2.getAddress());
      const expectedAmount = (BigInt(transferAmount) * BigInt(91)) / BigInt(100); // 9% total for tax and burn
      expect(finalBalance).to.equal(expectedAmount);
    });
  });

  describe("Staking", function () {
    beforeEach(async function () {
      await prospera.enableStaking(true);
      await prospera["transfer(address,uint256)"](await addr1.getAddress(), INITIAL_STAKE_AMOUNT);
      await prospera.connect(addr1).approve(prospera.address, INITIAL_STAKE_AMOUNT);
    });

    it("Should allow staking when enabled", async function () {
      await expect(prospera.connect(addr1).stake(INITIAL_STAKE_AMOUNT, false, 0))
        .to.emit(prospera, "Staked")
        .withArgs(await addr1.getAddress(), INITIAL_STAKE_AMOUNT, INITIAL_STAKE_AMOUNT);

      const stakeInfo = await prospera.getStake(await addr1.getAddress());
      expect(stakeInfo.amount).to.equal(INITIAL_STAKE_AMOUNT);
    });

    it("Should not allow staking when disabled", async function () {
      await prospera.enableStaking(false);
      await expect(prospera.connect(addr1).stake(INITIAL_STAKE_AMOUNT, false, 0))
        .to.be.revertedWith("StakingNotEnabled");
    });

    it("Should allow unstaking after minimum duration", async function () {
      await prospera.connect(addr1).stake(INITIAL_STAKE_AMOUNT, true, 90 * 24 * 60 * 60); // 90 days
      await time.increase(91 * 24 * 60 * 60); // 91 days
      await expect(prospera.connect(addr1).unstake(INITIAL_STAKE_AMOUNT))
        .to.emit(prospera, "Unstaked")
        .withArgs(await addr1.getAddress(), INITIAL_STAKE_AMOUNT, expect.anything());
    });

    it("Should not allow unstaking before minimum duration", async function () {
      await prospera.connect(addr1).stake(INITIAL_STAKE_AMOUNT, true, 90 * 24 * 60 * 60); // 90 days
      await time.increase(89 * 24 * 60 * 60); // 89 days
      await expect(prospera.connect(addr1).unstake(INITIAL_STAKE_AMOUNT))
        .to.be.revertedWith("TokensStillLocked");
    });

    it("Should update rewards correctly", async function () {
      await prospera.connect(addr1).stake(INITIAL_STAKE_AMOUNT, false, 0);
      await time.increase(30 * 24 * 60 * 60); // 30 days
      const reward = await prospera.getReward(await addr1.getAddress());
      expect(reward).to.be.gt(0);
    });
  });

  describe("ICO", function () {
    it("Should allow buying tokens during ICO", async function () {
      const buyAmount = ethers.parseEther("1000");
      const ethAmount = ethers.parseEther("20"); // Assuming 1 token = 0.02 ETH in Tier 1
      await expect(prospera.connect(addr1).buyTokens(buyAmount, { value: ethAmount }))
        .to.emit(prospera, "TokensPurchased")
        .withArgs(await addr1.getAddress(), buyAmount, ethAmount);

      expect(await prospera.balanceOf(await addr1.getAddress())).to.equal(buyAmount);
    });

    it("Should not allow buying tokens below minimum", async function () {
      const buyAmount = ethers.parseEther("1000");
      const ethAmount = ethers.parseEther("100"); // Below MIN_ICO_BUY
      await expect(prospera.connect(addr1).buyTokens(buyAmount, { value: ethAmount }))
        .to.be.revertedWith("BelowMinIcoBuyLimit");
    });

    it("Should not allow buying tokens above maximum", async function () {
      const buyAmount = ethers.parseEther("1000000");
      const ethAmount = ethers.parseEther("600000"); // Above MAX_ICO_BUY
      await expect(prospera.connect(addr1).buyTokens(buyAmount, { value: ethAmount }))
        .to.be.revertedWith("ExceedsMaxIcoBuyLimit");
    });

    it("Should transition between ICO tiers", async function () {
      const buyLargeTier1 = async () => {
        const buyAmount = ethers.parseEther("40000000"); // TIER1_TOKENS
        const ethAmount = ethers.parseEther("800000"); // 40,000,000 * 0.02
        await prospera.connect(addr1).buyTokens(buyAmount, { value: ethAmount });
      };

      await buyLargeTier1();
      expect(await prospera.currentTier()).to.equal(1); // IcoTier.Tier2
      await expect(buyLargeTier1()).to.emit(prospera, "IcoTierChanged").withArgs(1);

      await buyLargeTier1();
      expect(await prospera.currentTier()).to.equal(2); // IcoTier.Tier3
      await expect(buyLargeTier1()).to.emit(prospera, "IcoTierChanged").withArgs(2);

      await buyLargeTier1();
      expect(await prospera.icoActive()).to.equal(false);
      await expect(buyLargeTier1()).to.emit(prospera, "IcoEnded");
    });

    it("Should not allow buying tokens after ICO ends", async function () {
      await prospera.endIco();
      const buyAmount = ethers.parseEther("1000");
      const ethAmount = ethers.parseEther("20");
      await expect(prospera.connect(addr1).buyTokens(buyAmount, { value: ethAmount }))
        .to.be.revertedWith("IcoNotActive");
    });
  });

  describe("Blacklisting", function () {
    it("Should allow owner to blacklist an address", async function () {
      await expect(prospera.addToBlacklist(await addr1.getAddress()))
        .to.emit(prospera, "BlacklistUpdated")
        .withArgs(await addr1.getAddress(), true);
    });

    it("Should not allow blacklisted address to transfer tokens", async function () {
      await prospera.addToBlacklist(await addr1.getAddress());
      await expect(prospera["transfer(address,uint256)"](await addr1.getAddress(), 100))
        .to.be.revertedWith("BlacklistedAddress");
    });

    it("Should allow owner to remove address from blacklist", async function () {
      await prospera.addToBlacklist(await addr1.getAddress());
      await expect(prospera.removeFromBlacklist(await addr1.getAddress()))
        .to.emit(prospera, "BlacklistUpdated")
        .withArgs(await addr1.getAddress(), false);
    });
  });

  describe("Vesting", function () {
    it("Should add address to vesting schedule", async function () {
      const vestingAmount = ethers.parseEther("1000000");
      await expect(prospera.addToVesting(await addr1.getAddress(), vestingAmount, 0))
        .to.emit(prospera, "VestingAdded")
        .withArgs(await addr1.getAddress(), expect.anything(), expect.anything(), vestingAmount, 0);

      const vestingInfo = await prospera.vestingSchedules(await addr1.getAddress());
      expect(vestingInfo.active).to.be.true;
      expect(vestingInfo.totalAmount).to.equal(vestingAmount);
    });

    it("Should not allow transfer of vested tokens before vesting period ends", async function () {
      const vestingAmount = ethers.parseEther("1000000");
      await prospera.addToVesting(await addr1.getAddress(), vestingAmount, 0);
      await prospera["transfer(address,uint256)"](await addr1.getAddress(), vestingAmount);

      await expect(prospera.connect(addr1)["transfer(address,uint256)"](await addr2.getAddress(), vestingAmount))
        .to.be.revertedWith("VestedTokensCannotBeTransferred");
    });

    it("Should allow transfer of vested tokens after vesting period ends", async function () {
      const vestingAmount = ethers.parseEther("1000000");
      await prospera.addToVesting(await addr1.getAddress(), vestingAmount, 0);
      await prospera["transfer(address,uint256)"](await addr1.getAddress(), vestingAmount);

      await time.increase(121 * 24 * 60 * 60); // 121 days
      await expect(prospera.connect(addr1)["transfer(address,uint256)"](await addr2.getAddress(), vestingAmount))
        .to.emit(prospera, "Transfer")
        .withArgs(await addr1.getAddress(), await addr2.getAddress(), vestingAmount);
    });

    it("Should release vested tokens", async function () {
      const vestingAmount = ethers.parseEther("1000000");
      await prospera.addToVesting(await addr1.getAddress(), vestingAmount, 0);
      await time.increase(121 * 24 * 60 * 60); // 121 days

      await expect(prospera.releaseVestedTokens(await addr1.getAddress()))
        .to.emit(prospera, "VestingReleased")
        .withArgs(await addr1.getAddress());

      const vestingInfo = await prospera.vestingSchedules(await addr1.getAddress());
      expect(vestingInfo.active).to.be.false;
    });
  });

  describe("Whitelist", function () {
    it("Should allow owner to add address to whitelist", async function () {
      await expect(prospera.addToWhitelist(await addr1.getAddress()))
        .to.emit(prospera, "AddedToWhitelist")
        .withArgs(await addr1.getAddress());

      expect(await prospera.whitelist(await addr1.getAddress())).to.be.true;
    });

    it("Should allow owner to remove address from whitelist", async function () {
      await prospera.addToWhitelist(await addr1.getAddress());
      await expect(prospera.removeFromWhitelist(await addr1.getAddress()))
        .to.emit(prospera, "RemovedFromWhitelist")
        .withArgs(await addr1.getAddress());

      expect(await prospera.whitelist(await addr1.getAddress())).to.be.false;
    });

    it("Should allow whitelisted address to stake when staking is disabled", async function () {
      await prospera.enableStaking(false);
      await prospera.addToWhitelist(await addr1.getAddress());
      await prospera["transfer(address,uint256)"](await addr1.getAddress(), INITIAL_STAKE_AMOUNT);
      await prospera.connect(addr1).approve(prospera.address, INITIAL_STAKE_AMOUNT);

      await expect(prospera.connect(addr1).stake(INITIAL_STAKE_AMOUNT, false, 0))
        .to.emit(prospera, "Staked")
        .withArgs(await addr1.getAddress(), INITIAL_STAKE_AMOUNT, INITIAL_STAKE_AMOUNT);
    });
  });

  describe("Snapshot", function () {
    beforeEach(async function () {
      await prospera.enableStaking(true);
      await prospera["transfer(address,uint256)"](await addr1.getAddress(), ethers.parseEther("70000"));
      await prospera.connect(addr1).stake(ethers.parseEther("70000"), false, 0);
    });

    it("Should take snapshot at quarter start", async function () {
      // Set time to start of a quarter (e.g., July 1, 2023)
      await time.setNextBlockTimestamp(1688169600);
      await expect(prospera.takeSnapshot())
        .to.emit(prospera, "SnapshotTaken")
        .withArgs(1688169600);
    });

    it("Should not allow snapshot outside quarter start", async function () {
      // Set time to middle of a quarter (e.g., August 15, 2023)
      await time.setNextBlockTimestamp(1692057600);
      await expect(prospera.takeSnapshot())
        .to.be.revertedWith("NotQuarterStart");
    });

    it("Should correctly set eligibility for stakers", async function () {
      await time.setNextBlockTimestamp(1688169600);
      await prospera.takeSnapshot();
      expect(await prospera.quarterlyEligible(await addr1.getAddress())).to.be.true;
    });
  });

  describe("Upgradability", function () {
    it("Should allow owner to upgrade the contract", async function () {
      const PROSPERAv2 = await ethers.getContractFactory("PROSPERA");
      const prosperav2 = await upgrades.upgradeProxy(prospera.address, PROSPERAv2);
      expect(prosperav2.address).to.equal(prospera.address);
    });

    it("Should not allow non-owner to upgrade the contract", async function () {
      const PROSPERAv2 = await ethers.getContractFactory("PROSPERA");
      await expect(upgrades.upgradeProxy(prospera.address, PROSPERAv2.connect(addr1)))
        .to.be.revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("Pause and Unpause", function () {
    it("Should allow owner to pause the contract", async function () {
      await expect(prospera.pause())
        .to.emit(prospera, "Paused")
        .withArgs(await owner.getAddress());
      expect(await prospera.paused()).to.be.true;
    });

    it("Should allow owner to unpause the contract", async function () {
      await prospera.pause();
      await expect(prospera.unpause())
        .to.emit(prospera, "Unpaused")
        .withArgs(await owner.getAddress());
      expect(await prospera.paused()).to.be.false;
    });

    it("Should not allow transfers when paused", async function () {
      await prospera.pause();
      await expect(prospera["transfer(address,uint256)"](await addr1.getAddress(), 100))
        .to.be.revertedWith("ERC20Pausable: token transfer while paused");
    });
  });

  describe("Mint", function () {
    it("Should allow owner to mint new tokens", async function () {
      const mintAmount = ethers.parseEther("1000");
      await expect(prospera.mint(await addr1.getAddress(), mintAmount))
        .to.emit(prospera, "Transfer")
        .withArgs(ethers.ZeroAddress, await addr1.getAddress(), mintAmount);
      
      expect(await prospera.balanceOf(await addr1.getAddress())).to.equal(mintAmount);
    });

    it("Should not allow non-owner to mint new tokens", async function () {
      const mintAmount = ethers.parseEther("1000");
      await expect(prospera.connect(addr1).mint(await addr2.getAddress(), mintAmount))
        .to.be.revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("Burn", function () {
    it("Should allow users to burn their own tokens", async function () {
      const burnAmount = ethers.parseEther("100");
      await prospera["transfer(address,uint256)"](await addr1.getAddress(), burnAmount);
      await expect(prospera.connect(addr1).burn(burnAmount))
        .to.emit(prospera, "Transfer")
        .withArgs(await addr1.getAddress(), ethers.ZeroAddress, burnAmount);
      
      expect(await prospera.balanceOf(await addr1.getAddress())).to.equal(0);
    });
  });

  describe("Withdraw ETH", function () {
    it("Should allow owner to withdraw ETH", async function () {
      // First, send some ETH to the contract
      await addr1.sendTransaction({
        to: prospera.address,
        value: ethers.parseEther("1.0")
      });

      const initialBalance = await ethers.provider.getBalance(await owner.getAddress());
      await expect(prospera.withdrawETH())
        .to.emit(prospera, "EthWithdrawn")
        .withArgs(await owner.getAddress(), ethers.parseEther("1.0"));

      const finalBalance = await ethers.provider.getBalance(await owner.getAddress());
      expect(finalBalance - initialBalance).to.be.closeTo(
        ethers.parseEther("1.0"),
        ethers.parseEther("0.01") // Allow for gas costs
      );
    });

    it("Should not allow non-owner to withdraw ETH", async function () {
      await expect(prospera.connect(addr1).withdrawETH())
        .to.be.revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("Fallback and Receive", function () {
    it("Should accept ETH sent to the contract", async function () {
      const sendAmount = ethers.parseEther("1.0");
      await expect(addr1.sendTransaction({
        to: prospera.address,
        value: sendAmount
      })).to.not.be.reverted;

      expect(await ethers.provider.getBalance(prospera.address)).to.equal(sendAmount);
    });
  });
});