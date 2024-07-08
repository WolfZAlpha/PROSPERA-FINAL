// SPDX-License-Identifier: PROPRIETARY
pragma solidity 0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title PROSPERA Staking Contract
/// @notice This contract handles staking functionality for the PROSPERA token
/// @dev This contract is upgradeable and uses the UUPS proxy pattern
contract PROSPERAStaking is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    /// @notice Address of the main PROSPERA contract
    address public prosperaContract;

    /// @notice Struct to define a stake
    struct Stake {
        uint256 amount;
        uint256 timestamp;
        uint8 tier;
        bool lockedUp;
        uint256 lockupDuration;
    }

    /// @notice Struct to define a case for staking rewards
    struct Case {
        uint256 maxWallets;
        uint256[7] maxWalletsPerTier;
        uint256[7] dailyYieldPercentage;
    }

    /// @notice Indicates if staking is enabled
    bool public isStakingEnabled;

    /// @notice Mapping of staker details
    mapping(address staker => Stake stakeInfo) private _stakes;

    /// @notice Mapping of rewards for stakers
    mapping(address staker => uint256 rewardAmount) private _stakeRewards;

    /// @notice Tracks if a staker is eligible for quarterly revenue share
    mapping(address staker => bool isEligible) public quarterlyEligible;

    /// @notice Tracks the number of active stakers in each tier
    mapping(uint8 tier => uint256 stakerCount) public activeStakers;

    /// @notice Tracks addresses of stakers in each tier
    mapping(uint8 tier => address[] stakerAddresses) private stakersInTier;

    /// @notice Daily reward interval
    uint256 public constant REWARD_INTERVAL = 1 days;

    /// @notice Minimum stake duration
    uint256 public constant MIN_STAKE_DURATION = 90 days;

    /// @notice Maximum stake duration
    uint256 public constant MAX_STAKE_DURATION = 1095 days;

    /// @notice Number of tiers
    uint8 public constant TIER_COUNT = 7;

    /// @notice Tier limits
    uint256[TIER_COUNT] public tierLimits = [57143, 200000, 500000, 1500000, 10000000, 50000000];

    /// @notice Multiplier in basis points for each tier
    uint8[TIER_COUNT] public tierBonuses = [50, 50, 150, 175, 100, 125, 175];

    /// @notice List of cases for staking rewards
    Case[4] public cases;

    /// @notice Current case being used
    uint8 public currentCase;

    // Events
    /// @notice Emitted when staking is enabled or disabled
    /// @param enabled The new staking status
    event StakingEnabled(bool indexed enabled);

    /// @notice Emitted when tokens are staked
    /// @param user The address of the user
    /// @param amount The amount of tokens staked
    /// @param total The total amount of tokens staked by the user
    event Staked(address indexed user, uint256 amount, uint256 total);

    /// @notice Emitted when tokens are unstaked
    /// @param user The address of the user
    /// @param amount The amount of tokens unstaked
    /// @param total The total amount of tokens unstaked by the user
    event Unstaked(address indexed user, uint256 amount, uint256 total);

    /// @notice Emitted when tokens are locked
    /// @param user The address of the user
    /// @param amount The amount of tokens locked
    /// @param lockDuration The duration for which the tokens are locked    
    event TokensLocked(address indexed user, uint256 amount, uint256 lockDuration);

    /// @notice Emitted when a snapshot is taken
    /// @param timestamp The timestamp of the snapshot
    event SnapshotTaken(uint256 indexed timestamp);

    /// @notice User snapshot taken
    /// @param user The address of the user
    /// @param isEligible Whether the user is eligible for quarterly revenue share
    event UserSnapshotTaken(address indexed user, bool isEligible);

    /// @notice Emitted when the current case is updated
    /// @param currentCase The new current case
    event CurrentCaseUpdated(uint8 indexed currentCase);

    /// @notice Emitted when a user's reward is updated
    /// @param user The address of the user
    /// @param reward The new reward amount
    event RewardUpdated(address indexed user, uint256 reward);

    // Errors
    /// @notice Error message for not being a PROSPERA contract
    error NotPROSPERAContract();

    /// @notice Error message for not being staking enabled
    error StakingNotEnabled();

    /// @notice Error message for invalid stake amount
    error InvalidStakeAmount();

    /// @notice Error message for invalid lock duration
    error InvalidLockDuration();

    /// @notice Error message for insufficient staked amount
    error InsufficientStakedAmount(uint256 available, uint256 required);

    /// @notice Error message for tokens still locked
    error TokensStillLocked();

    /// @notice Ensures that only the PROSPERA contract can call the function
    modifier onlyPROSPERA() {
        if (msg.sender != prosperaContract) revert NotPROSPERAContract();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param _prosperaContract Address of the PROSPERA token contract
    function initialize(address _prosperaContract) initializer public {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        prosperaContract = _prosperaContract;

        // Initialize cases for staking rewards
        cases[0] = Case({
            maxWallets: 1500,
            maxWalletsPerTier: [150, type(uint256).max, type(uint256).max, type(uint256).max, 150, 23, 8],
            dailyYieldPercentage: [uint256(0.0005 * 10**18), uint256(0.0005 * 10**18), uint256(0.00075 * 10**18), uint256(0.0015 * 10**18), uint256(0.00175 * 10**18), uint256(0.00225 * 10**18), uint256(0.00275 * 10**18)]
        });

        cases[1] = Case({
            maxWallets: 3000,
            maxWalletsPerTier: [300, type(uint256).max, type(uint256).max, type(uint256).max, 300, 45, 15],
            dailyYieldPercentage: [uint256(0.00025 * 10**18), uint256(0.00035 * 10**18), uint256(0.00055 * 10**18), uint256(0.00085 * 10**18), uint256(0.00135 * 10**18), uint256(0.00125 * 10**18), uint256(0.00175 * 10**18)]
        });

        cases[2] = Case({
            maxWallets: 10000,
            maxWalletsPerTier: [1000, type(uint256).max, type(uint256).max, type(uint256).max, 1000, 150, 50],
            dailyYieldPercentage: [uint256(0.000075 * 10**18), uint256(0.00009 * 10**18), uint256(0.000125 * 10**18), uint256(0.00035 * 10**18), uint256(0.00095 * 10**18), uint256(0.00115 * 10**18), uint256(0.00135 * 10**18)]
        });

        cases[3] = Case({
            maxWallets: 20000,
            maxWalletsPerTier: [2000, type(uint256).max, type(uint256).max, type(uint256).max, 2000, 300, 100],
            dailyYieldPercentage: [uint256(0.00005 * 10**18), uint256(0.000075 * 10**18), uint256(0.0001 * 10**18), uint256(0.00025 * 10**18), uint256(0.00075 * 10**18), uint256(0.00095 * 10**18), uint256(0.00115 * 10**18)]
        });
    }

    /// @notice Authorizes an upgrade to a new implementation
    /// @dev This function is left empty but is required by the UUPSUpgradeable contract
    /// @param newImplementation Address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice Enables or disables staking
    /// @param _enabled The new staking status (true to enable, false to disable)
    function enableStaking(bool _enabled) external onlyPROSPERA {
        isStakingEnabled = _enabled;
        emit StakingEnabled(_enabled);
    }

    /// @notice Stakes a specified amount of tokens
    /// @param staker The address of the staker
    /// @param stakeAmount The number of tokens to stake
    /// @param isLockedUp Indicates if the tokens are locked up
    /// @param lockDuration The duration for which tokens are locked up (in seconds)
    function stake(address staker, uint256 stakeAmount, bool isLockedUp, uint256 lockDuration) external onlyPROSPERA nonReentrant {
        if (!isStakingEnabled) revert StakingNotEnabled();
        if (stakeAmount == 0) revert InvalidStakeAmount();
        if (isLockedUp && (lockDuration < MIN_STAKE_DURATION || lockDuration > MAX_STAKE_DURATION)) revert InvalidLockDuration();

        uint8 tier = _getTierByStakeAmount(stakeAmount);

        if (_stakes[staker].amount > 0) {
            _updateReward(staker);
        } else {
            stakersInTier[tier].push(staker);
        }

        _stakes[staker] = Stake({
            amount: stakeAmount,
            timestamp: block.timestamp,
            tier: tier,
            lockedUp: isLockedUp,
            lockupDuration: lockDuration
        });
        ++activeStakers[tier];

        _updateCurrentCase();

        emit Staked(staker, stakeAmount, _stakes[staker].amount);
    }

    /// @notice Unstakes a specified amount of tokens
    /// @param staker The address of the staker
    /// @param unstakeAmount The number of tokens to unstake
    /// @return amountToTransfer The total amount to transfer back to the staker
    function unstake(address staker, uint256 unstakeAmount) external onlyPROSPERA nonReentrant returns (uint256 amountToTransfer) {
        if (!isStakingEnabled) revert StakingNotEnabled();
        if (unstakeAmount == 0) revert InvalidStakeAmount();
        Stake memory stakeInfo = _stakes[staker];
        if (stakeInfo.amount < unstakeAmount) revert InsufficientStakedAmount(stakeInfo.amount, unstakeAmount);
        if (stakeInfo.lockedUp && block.timestamp < stakeInfo.timestamp + stakeInfo.lockupDuration) revert TokensStillLocked();

        uint256 reward = _stakeRewards[staker];

        uint8 tier = stakeInfo.tier;

        stakeInfo.amount -= unstakeAmount;
        if (stakeInfo.amount == 0) {
            delete _stakes[staker];
            delete _stakeRewards[staker];
            --activeStakers[tier];
            _removeStakerFromTier(tier, staker);
        } else {
            _stakes[staker] = stakeInfo;
        }

        _updateCurrentCase();

        amountToTransfer = unstakeAmount + reward;

        emit Unstaked(staker, unstakeAmount, reward);
    }

    /// @notice Locks a specified amount of tokens
    /// @param staker The address of the staker
    /// @param lockAmount The number of tokens to lock
    /// @param lockDuration The duration for which tokens are locked (in seconds)
    function lockTokens(address staker, uint256 lockAmount, uint256 lockDuration) external onlyPROSPERA nonReentrant {
        if (!isStakingEnabled) revert StakingNotEnabled();
        if (lockAmount == 0) revert InvalidStakeAmount();
        if (lockDuration < MIN_STAKE_DURATION || lockDuration > MAX_STAKE_DURATION) revert InvalidLockDuration();

        Stake storage stakeInfo = _stakes[staker];
        stakeInfo.amount += lockAmount;
        stakeInfo.lockedUp = true;
        stakeInfo.lockupDuration = lockDuration;
        stakeInfo.timestamp = block.timestamp;

        emit TokensLocked(staker, lockAmount, lockDuration);
    }

    /// @notice Takes a snapshot to determine eligibility for quarterly revenue share
    function takeSnapshot() external onlyPROSPERA nonReentrant {
        uint256 currentTimestamp = block.timestamp;
        emit SnapshotTaken(currentTimestamp);

        for (uint8 i = 0; i < TIER_COUNT; i++) {
            address[] memory stakers = stakersInTier[i];
            uint256 stakersLength = stakers.length;
            for (uint256 j = 0; j < stakersLength; j++) {
                bool isEligible = _checkEligibility(stakers[j], currentTimestamp);
                quarterlyEligible[stakers[j]] = isEligible;
                emit UserSnapshotTaken(stakers[j], isEligible);
            }
        }
    }

    /// @notice Updates the reward for a staker based on the current case and tier
    /// @param stakerAddress The address of the staker
    function _updateReward(address stakerAddress) private {
        uint256 stakedDuration = (block.timestamp - _stakes[stakerAddress].timestamp) / REWARD_INTERVAL;
        uint8 stakerTier = _stakes[stakerAddress].lockedUp ? _stakes[stakerAddress].tier : 0; // Tier 0 if not locked up
        uint256 calculatedReward;

        if (currentCase == 0) {
            calculatedReward = _calculateCase0Reward(_stakes[stakerAddress].amount, stakerTier, stakedDuration);
        } else if (currentCase == 1) {
            calculatedReward = _calculateCase1Reward(_stakes[stakerAddress].amount, stakerTier, stakedDuration);
        } else if (currentCase == 2) {
            calculatedReward = _calculateCase2Reward(_stakes[stakerAddress].amount, stakerTier, stakedDuration);
        } else if (currentCase == 3) {
            calculatedReward = _calculateCase3Reward(_stakes[stakerAddress].amount, stakerTier, stakedDuration);
        }

        _stakeRewards[stakerAddress] = calculatedReward;

        emit RewardUpdated(stakerAddress, calculatedReward);
    }

    /// @notice Calculates the reward for Case 0 (up to 1,500 wallets)
    /// @param amount The amount of tokens staked
    /// @param tier The tier of the staker
    /// @param stakedDuration The duration for which the tokens have been staked (in days)
    /// @return reward The calculated reward in tokens
    function _calculateCase0Reward(uint256 amount, uint8 tier, uint256 stakedDuration) private view returns (uint256 reward) {
        uint256 dailyYieldDecimal = cases[0].dailyYieldPercentage[tier];
        uint256 stakedAmount = amount;
        reward = ((stakedAmount * dailyYieldDecimal) * stakedDuration) / 10**18;
    }

    /// @notice Calculates the reward for Case 1 (up to 3,000 wallets)
    /// @param amount The amount of tokens staked
    /// @param tier The tier of the staker
    /// @param stakedDuration The duration for which the tokens have been staked (in days)
    /// @return reward The calculated reward in tokens
function _calculateCase1Reward(uint256 amount, uint8 tier, uint256 stakedDuration) private view returns (uint256 reward) {
        uint256 dailyYieldDecimal = cases[1].dailyYieldPercentage[tier];
        uint256 stakedAmount = amount;
        reward = ((stakedAmount * dailyYieldDecimal) * stakedDuration) / 10**18;
    }

    /// @notice Calculates the reward for Case 2 (up to 10,000 wallets)
    /// @param amount The amount of tokens staked
    /// @param tier The tier of the staker
    /// @param stakedDuration The duration for which the tokens have been staked (in days)
    /// @return reward The calculated reward in tokens
    function _calculateCase2Reward(uint256 amount, uint8 tier, uint256 stakedDuration) private view returns (uint256 reward) {
        uint256 dailyYieldDecimal = cases[2].dailyYieldPercentage[tier];
        uint256 stakedAmount = amount;
        reward = ((stakedAmount * dailyYieldDecimal) * stakedDuration) / 10**18;
    }

    /// @notice Calculates the reward for Case 3 (up to 20,000 wallets)
    /// @param amount The amount of tokens staked
    /// @param tier The tier of the staker
    /// @param stakedDuration The duration for which the tokens have been staked (in days)
    /// @return reward The calculated reward in tokens
    function _calculateCase3Reward(uint256 amount, uint8 tier, uint256 stakedDuration) private view returns (uint256 reward) {
        uint256 dailyYieldDecimal = cases[3].dailyYieldPercentage[tier];
        uint256 stakedAmount = amount;
        reward = ((stakedAmount * dailyYieldDecimal) * stakedDuration) / 10**18;
    }

    /// @notice Determines the tier based on the stake amount
    /// @param amount The amount staked
    /// @return tier The tier number
    function _getTierByStakeAmount(uint256 amount) private view returns (uint8 tier) {
        for (uint8 i = 0; i < TIER_COUNT - 1; i++) {
            if (amount < tierLimits[i]) {
                return i + 1;
            }
        }
        return TIER_COUNT;
    }

    /// @notice Updates the current case based on the number of active stakers
    function _updateCurrentCase() private {
        uint256 totalStakers = 0;
        for (uint8 i = 0; i < TIER_COUNT; i++) {
            totalStakers += activeStakers[i];
        }

        for (uint8 i = 0; i < 4; i++) {
            if (totalStakers <= cases[i].maxWallets) {
                currentCase = i;
                emit CurrentCaseUpdated(currentCase);
                return;
            }
        }

        // If we reach here, use the last case
        currentCase = 3;
        emit CurrentCaseUpdated(currentCase);
    }

    /// @notice Removes a staker from a tier
    /// @param tier The tier number
    /// @param stakerAddress The address of the staker
    function _removeStakerFromTier(uint8 tier, address stakerAddress) private {
        uint256 length = stakersInTier[tier].length;
        for (uint256 i = 0; i < length; i++) {
            if (stakersInTier[tier][i] == stakerAddress) {
                stakersInTier[tier][i] = stakersInTier[tier][length - 1];
                stakersInTier[tier].pop();
                break;
            }
        }
    }

    /// @notice Checks if a staker is eligible for quarterly revenue share
    /// @param stakerAddress The address of the staker
    /// @param currentTimestamp The current timestamp
    /// @return isEligible True if eligible, false otherwise
    function _checkEligibility(address stakerAddress, uint256 currentTimestamp) private view returns (bool isEligible) {
        Stake memory stakeInfo = _stakes[stakerAddress];
        uint256 currentQuarterStart = currentTimestamp - (currentTimestamp % (90 days));

        if (stakeInfo.lockedUp) {
            // Eligibility criteria for locked-up stakes
            isEligible = stakeInfo.amount >= 60000 * 10**18;
        } else {
            // Eligibility criteria for non-locked-up stakes
            isEligible = stakeInfo.amount >= 70000 * 10**18 && stakeInfo.timestamp <= currentQuarterStart;
        }
    }

    /// @notice Returns the stake details for a given staker
    /// @param stakerAddress The address of the staker
    /// @return amount The amount staked
    /// @return timestamp The timestamp when staked
    /// @return tier The tier number
    /// @return lockedUp Whether the stake is locked up
    /// @return lockupDuration The duration of the lockup
    function getStake(address stakerAddress) external view returns (uint256 amount, uint256 timestamp, uint8 tier, bool lockedUp, uint256 lockupDuration) {
        Stake memory stakeInfo = _stakes[stakerAddress];
        return (stakeInfo.amount, stakeInfo.timestamp, stakeInfo.tier, stakeInfo.lockedUp, stakeInfo.lockupDuration);
    }

    /// @notice Returns the reward for a given staker
    /// @param stakerAddress The address of the staker
    /// @return reward The reward amount
    function getReward(address stakerAddress) external view returns (uint256 reward) {
        return _stakeRewards[stakerAddress];
    }

    /// @notice Returns the current case and total number of stakers
    /// @return currentCaseNumber The current case number
    /// @return totalStakers The total number of stakers across all tiers
    function getCurrentCaseAndTotalStakers() external view returns (uint8 currentCaseNumber, uint256 totalStakers) {
        currentCaseNumber = currentCase;
        for (uint8 i = 0; i < TIER_COUNT; i++) {
            totalStakers += activeStakers[i];
        }
    }
}