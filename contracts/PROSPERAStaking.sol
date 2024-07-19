// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title PROSPERA Staking Contract
/// @notice This contract handles staking functionality for the PROSPERA token
/// @custom:security-contact security@prosperadefi.com
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

    /// @notice List of cases for staking rewards
    Case[4] public cases;

    /// @notice Current case being used
    uint8 public currentCase;

    /// @notice Emitted when staking is enabled or disabled
    event StakingEnabled(bool indexed enabled);

    /// @notice Emitted when tokens are staked
    event Staked(address indexed user, uint256 amount, uint256 total);

    /// @notice Emitted when tokens are unstaked
    event Unstaked(address indexed user, uint256 amount, uint256 total);

    /// @notice Emitted when tokens are locked
    event TokensLocked(address indexed user, uint256 amount, uint256 lockDuration);

    /// @notice Emitted when a snapshot is taken
    event SnapshotTaken(uint256 indexed timestamp);

    /// @notice Emitted when a user's snapshot is taken
    event UserSnapshotTaken(address indexed user, bool isEligible);

    /// @notice Emitted when the current case is updated
    event CurrentCaseUpdated(uint8 indexed currentCase);

    /// @notice Emitted when the case update process is completed
    /// @param currentCase The current case after the update
    /// @param totalStakers The total number of stakers across all tiers
    event CaseUpdateProcessCompleted(uint8 indexed currentCase, uint256 totalStakers);

    /// @notice Emitted when a user's reward is updated
    event RewardUpdated(address indexed user, uint256 reward);

    /// @notice Emitted when the contract is initialized
    event StakingInitialized(address indexed prosperaContract);

    /// @notice Emitted when a staker is added to a tier
    event StakerAddedToTier(address indexed staker, uint8 indexed tier);

    /// @notice Emitted when a staker is removed from a tier
    event StakerRemovedFromTier(address indexed staker, uint8 indexed tier);

    /// @notice Emitted when the number of active stakers in a tier is updated
    event ActiveStakersUpdated(uint8 indexed tier, uint256 count);

    /// @notice Emitted when a case is initialized
    event CaseInitialized(uint8 indexed caseIndex, uint256 maxWallets);

    /// @notice Emitted when a stake is updated
    event StakeUpdated(address indexed staker, uint256 amount, uint8 tier, bool lockedUp, uint256 lockupDuration);

    /// @notice Error for when the caller is not the PROSPERA contract
    error NotPROSPERAContract();

    /// @notice Error for when staking is not enabled
    error StakingNotEnabled();

    /// @notice Error for invalid stake amount
    error InvalidStakeAmount();

    /// @notice Error for invalid lock duration
    error InvalidLockDuration();

    /// @notice Error for insufficient staked amount
    error InsufficientStakedAmount(uint256 available, uint256 required);

    /// @notice Error for when tokens are still locked
    error TokensStillLocked();

    /// @notice Error for invalid tier
    error InvalidTier(uint8 tier);

    /// @notice Error for invalid index range
    error InvalidIndexRange();

    /// @notice Error for end index out of bounds
    error EndIndexOutOfBounds();

    /// @notice Error for addition overflow
    error AdditionOverflow();

    /// @notice Error for subtraction underflow
    error SubtractionUnderflow();

    /// @notice Error for multiplication overflow
    error MultiplicationOverflow();

    /// @notice Error for division by zero
    error DivisionByZero();

    /// @notice Error for modulus by zero
    error ModulusByZero();

    /// @notice Error for invalid address
    error InvalidAddress();

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
    /// @dev This function is called once by the deployer to set up the contract
    /// @param _prosperaContract Address of the PROSPERA token contract
    function initialize(address _prosperaContract) external initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        prosperaContract = _prosperaContract;

        // Initialize cases array
        uint256[4] memory maxWallets = [uint256(1500), uint256(3000), uint256(10000), uint256(20000)];
        uint256[7][4] memory maxWalletsPerTier = [
            [uint256(150), type(uint256).max, type(uint256).max, type(uint256).max, uint256(150), uint256(23), uint256(8)],
            [uint256(300), type(uint256).max, type(uint256).max, type(uint256).max, uint256(300), uint256(45), uint256(15)],
            [uint256(1000), type(uint256).max, type(uint256).max, type(uint256).max, uint256(1000), uint256(150), uint256(50)],
            [uint256(2000), type(uint256).max, type(uint256).max, type(uint256).max, uint256(2000), uint256(300), uint256(100)]
        ];
        uint256[7][4] memory dailyYieldPercentage = [
            [uint256(0.0005 * 10**18), uint256(0.0005 * 10**18), uint256(0.00075 * 10**18), uint256(0.0015 * 10**18), uint256(0.00175 * 10**18), uint256(0.00225 * 10**18), uint256(0.00275 * 10**18)],
            [uint256(0.00025 * 10**18), uint256(0.00035 * 10**18), uint256(0.00055 * 10**18), uint256(0.00085 * 10**18), uint256(0.00135 * 10**18), uint256(0.00125 * 10**18), uint256(0.00175 * 10**18)],
            [uint256(0.000075 * 10**18), uint256(0.00009 * 10**18), uint256(0.000125 * 10**18), uint256(0.00035 * 10**18), uint256(0.00095 * 10**18), uint256(0.00115 * 10**18), uint256(0.00135 * 10**18)],
            [uint256(0.00005 * 10**18), uint256(0.000075 * 10**18), uint256(0.0001 * 10**18), uint256(0.00025 * 10**18), uint256(0.00075 * 10**18), uint256(0.00095 * 10**18), uint256(0.00115 * 10**18)]
        ];

        for (uint8 i = 0; i < 4; ++i) {
            cases[i].maxWallets = maxWallets[i];
            for (uint8 j = 0; j < 7; ++j) {
                cases[i].maxWalletsPerTier[j] = maxWalletsPerTier[i][j];
                cases[i].dailyYieldPercentage[j] = dailyYieldPercentage[i][j];
            }
            emit CaseInitialized(i, cases[i].maxWallets);
        }

        emit StakingInitialized(_prosperaContract);
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
        // Checks
        if (!isStakingEnabled) revert StakingNotEnabled();
        if (stakeAmount == 0) revert InvalidStakeAmount();
        if (isLockedUp && (lockDuration < MIN_STAKE_DURATION || lockDuration > MAX_STAKE_DURATION)) revert InvalidLockDuration();

        uint8 tier = _getTierByStakeAmount(stakeAmount);

        // Effects
        if (_stakes[staker].amount > 0) {
            _updateReward(staker);
        } else {
            stakersInTier[tier].push(staker);
            emit StakerAddedToTier(staker, tier);
        }

    _stakes[staker] = Stake({
        amount: stakeAmount,
        timestamp: block.timestamp,
        tier: tier,
        lockedUp: isLockedUp,
        lockupDuration: lockDuration
    });

    uint256 newActiveStakers = _add(activeStakers[tier], 1);
    activeStakers[tier] = newActiveStakers;

    // Interactions
    _updateCurrentCase();

    // Events
    emit ActiveStakersUpdated(tier, newActiveStakers);
    emit Staked(staker, stakeAmount, _stakes[staker].amount);
    emit StakeUpdated(staker, stakeAmount, tier, isLockedUp, lockDuration);
}

    /// @notice Unstakes a specified amount of tokens
    /// @param staker The address of the staker
    /// @param unstakeAmount The number of tokens to unstake
    /// @return amountToTransfer The total amount to transfer back to the staker
    function unstake(address staker, uint256 unstakeAmount) external onlyPROSPERA nonReentrant returns (uint256) {
        // Checks
        if (staker == address(0)) revert InvalidAddress();
        if (!isStakingEnabled) revert StakingNotEnabled();
        if (unstakeAmount == 0) revert InvalidStakeAmount();
        Stake memory stakeInfo = _stakes[staker];
        if (stakeInfo.amount < unstakeAmount) revert InsufficientStakedAmount(stakeInfo.amount, unstakeAmount);
        if (stakeInfo.lockedUp && block.timestamp < stakeInfo.timestamp + stakeInfo.lockupDuration) revert TokensStillLocked();

        // Effects
        uint256 reward = _stakeRewards[staker];
        uint8 tier = stakeInfo.tier;

        stakeInfo.amount = _sub(stakeInfo.amount, unstakeAmount);
        uint256 amountToTransfer = _add(unstakeAmount, reward);

        if (stakeInfo.amount == 0) {
            delete _stakes[staker];
            delete _stakeRewards[staker];
            uint256 newActiveStakers = _sub(activeStakers[tier], 1);
            activeStakers[tier] = newActiveStakers;
            _removeStakerFromTier(tier, staker);
            emit ActiveStakersUpdated(tier, newActiveStakers);
        } else {
            _stakes[staker] = stakeInfo;
        }   

        // Interactions
        _updateCurrentCase();

        // Events
        emit Unstaked(staker, unstakeAmount, reward);
        emit StakeUpdated(staker, stakeInfo.amount, stakeInfo.tier, stakeInfo.lockedUp, stakeInfo.lockupDuration);

        return amountToTransfer;
    }

    /// @notice Locks a specified amount of tokens
    /// @param staker The address of the staker
    /// @param lockAmount The number of tokens to lock
    /// @param lockDuration The duration for which tokens are locked (in seconds)
    function lockTokens(address staker, uint256 lockAmount, uint256 lockDuration) external onlyPROSPERA nonReentrant {
        // Checks
        if (!isStakingEnabled) revert StakingNotEnabled();
        if (lockAmount == 0) revert InvalidStakeAmount();
        if (lockDuration < MIN_STAKE_DURATION || lockDuration > MAX_STAKE_DURATION) revert InvalidLockDuration();

        // Effects
        Stake storage stakeInfo = _stakes[staker];
        stakeInfo.amount = _add(stakeInfo.amount, lockAmount);
        stakeInfo.lockedUp = true;
        stakeInfo.lockupDuration = lockDuration;
        stakeInfo.timestamp = block.timestamp;

        // Events
        emit TokensLocked(staker, lockAmount, lockDuration);
        emit StakeUpdated(staker, stakeInfo.amount, stakeInfo.tier, stakeInfo.lockedUp, stakeInfo.lockupDuration);
    }

    /// @notice Takes a snapshot to determine eligibility for quarterly revenue share
    function takeSnapshot() external onlyPROSPERA nonReentrant {
        uint256 currentTimestamp = block.timestamp;
        emit SnapshotTaken(currentTimestamp);

        for (uint8 i; i < TIER_COUNT; ++i) {
            address[] memory stakers = stakersInTier[i];
            uint256 stakersLength = stakers.length;
            for (uint256 j; j < stakersLength; ++j) {
                bool isEligible = _checkEligibility(stakers[j], currentTimestamp);
                quarterlyEligible[stakers[j]] = isEligible;
                emit UserSnapshotTaken(stakers[j], isEligible);
            }
        }
    }

    /// @notice Updates the reward for a staker based on the current case and tier
    /// @param stakerAddress The address of the staker
    function _updateReward(address stakerAddress) private {
        uint256 stakedDuration = _div(_sub(block.timestamp, _stakes[stakerAddress].timestamp), REWARD_INTERVAL);
        uint8 stakerTier = _stakes[stakerAddress].lockedUp ? _stakes[stakerAddress].tier : 0;
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
    /// @return The calculated reward in tokens
    function _calculateCase0Reward(uint256 amount, uint8 tier, uint256 stakedDuration) private view returns (uint256) {
        uint256 dailyYieldDecimal = cases[0].dailyYieldPercentage[tier];
        return Math.mulDiv(Math.mulDiv(amount, dailyYieldDecimal, 10**18), stakedDuration, 1);
    }

    /// @notice Calculates the reward for Case 1 (up to 3,000 wallets)
    /// @param amount The amount of tokens staked
    /// @param tier The tier of the staker
    /// @param stakedDuration The duration for which the tokens have been staked (in days)
    /// @return The calculated reward in tokens
    function _calculateCase1Reward(uint256 amount, uint8 tier, uint256 stakedDuration) private view returns (uint256) {
        uint256 dailyYieldDecimal = cases[1].dailyYieldPercentage[tier];
        return Math.mulDiv(Math.mulDiv(amount, dailyYieldDecimal, 10**18), stakedDuration, 1);
    }

    /// @notice Calculates the reward for Case 2 (up to 10,000 wallets)
    /// @param amount The amount of tokens staked
    /// @param tier The tier of the staker
    /// @param stakedDuration The duration for which the tokens have been staked (in days)
    /// @return The calculated reward in tokens
    function _calculateCase2Reward(uint256 amount, uint8 tier, uint256 stakedDuration) private view returns (uint256) {
        uint256 dailyYieldDecimal = cases[2].dailyYieldPercentage[tier];
        return Math.mulDiv(Math.mulDiv(amount, dailyYieldDecimal, 10**18), stakedDuration, 1);
    }

    /// @notice Calculates the reward for Case 3 (up to 20,000 wallets)
    /// @param amount The amount of tokens staked
    /// @param tier The tier of the staker
    /// @param stakedDuration The duration for which the tokens have been staked (in days)
    /// @return The calculated reward in tokens
    function _calculateCase3Reward(uint256 amount, uint8 tier, uint256 stakedDuration) private view returns (uint256) {
        uint256 dailyYieldDecimal = cases[3].dailyYieldPercentage[tier];
        return Math.mulDiv(Math.mulDiv(amount, dailyYieldDecimal, 10**18), stakedDuration, 1);
    }

    /// @notice Determines the tier based on the stake amount
    /// @param amount The amount staked
    /// @return The tier number
    function _getTierByStakeAmount(uint256 amount) private view returns (uint8) {
        for (uint8 i; i < TIER_COUNT - 1; ++i) {
            if (amount < tierLimits[i]) {
                return i + 1;
            }
        }
        return TIER_COUNT;
    }

    /// @notice Updates the current case based on the number of active stakers
    function _updateCurrentCase() private {
        uint256 totalStakers;
        uint256 gasLimit = gasleft();
        for (uint8 i; i < TIER_COUNT; ++i) {
            if (gasleft() < gasLimit / 10) break; 
            totalStakers = _add(totalStakers, activeStakers[i]);
        }

        uint8 newCase = 3;
        for (uint8 i; i < 4; ++i) {
            if (totalStakers <= cases[i].maxWallets) {
                newCase = i;
                break;
            }
        }   

        emit CurrentCaseUpdated(newCase);

        if (newCase != currentCase) {
            currentCase = newCase;
        }

        emit CaseUpdateProcessCompleted(newCase, totalStakers);
    }

    /// @notice Removes a staker from a tier
    /// @param tier The tier number
    /// @param stakerAddress The address of the staker
    function _removeStakerFromTier(uint8 tier, address stakerAddress) private {
        uint256 length = stakersInTier[tier].length;
        uint256 maxIterations = 75; 
        for (uint256 i; i < length && i < maxIterations; ++i) {
            if (stakersInTier[tier][i] == stakerAddress) {
                stakersInTier[tier][i] = stakersInTier[tier][length - 1];
                stakersInTier[tier].pop();
                emit StakerRemovedFromTier(stakerAddress, tier);
                break;
            }
        }
    }

    /// @notice Checks if a staker is eligible for quarterly revenue share
    /// @param stakerAddress The address of the staker
    /// @param currentTimestamp The current timestamp
    /// @return Whether the staker is eligible
    function _checkEligibility(address stakerAddress, uint256 currentTimestamp) private view returns (bool) {
        Stake memory stakeInfo = _stakes[stakerAddress];
        uint256 currentQuarterStart = _sub(currentTimestamp, _mod(currentTimestamp, 90 days));

        if (stakeInfo.lockedUp) {
            return stakeInfo.amount >= 60000 * 10**18;
        } else {
            return stakeInfo.amount >= 70000 * 10**18 && stakeInfo.timestamp <= currentQuarterStart;
        }
    }

    /// @notice Returns the stake details for a given staker
    /// @param stakerAddress The address of the staker
    /// @return The stake details (amount, timestamp, tier, lockedUp, lockupDuration)
    function getStake(address stakerAddress) external view returns (uint256, uint256, uint8, bool, uint256) {
        Stake memory stakeInfo = _stakes[stakerAddress];
        return (stakeInfo.amount, stakeInfo.timestamp, stakeInfo.tier, stakeInfo.lockedUp, stakeInfo.lockupDuration);
    }

    /// @notice Returns the reward for a given staker
    /// @param stakerAddress The address of the staker
    /// @return The reward amount
    function getReward(address stakerAddress) external view returns (uint256) {
        return _stakeRewards[stakerAddress];
    }

    /// @notice Returns the current case and total number of stakers
    /// @return The current case number and total number of stakers
    function getCurrentCaseAndTotalStakers() external view returns (uint8, uint256) {
        uint256 totalStakers;
        for (uint8 i; i < TIER_COUNT; ++i) {
            totalStakers = _add(totalStakers, activeStakers[i]);
        }
        return (currentCase, totalStakers);
    }

    /// @notice Returns the total number of stakers in a specific tier
    /// @param tier The tier number
    /// @return The number of stakers in the tier
    function getTotalStakersInTier(uint8 tier) external view returns (uint256) {
        if (tier >= TIER_COUNT) revert InvalidTier(tier);
        return stakersInTier[tier].length;
    }

    /// @notice Returns a range of staker addresses in a specific tier
    /// @param tier The tier number
    /// @param startIndex The starting index of the range
    /// @param endIndex The ending index of the range
    /// @return An array of staker addresses in the specified range
    function getStakersInTier(uint8 tier, uint256 startIndex, uint256 endIndex) external view returns (address[] memory) {
        if (tier >= TIER_COUNT) revert InvalidTier(tier);
        if (startIndex >= endIndex) revert InvalidIndexRange();
        if (endIndex > stakersInTier[tier].length) revert EndIndexOutOfBounds();

        address[] memory stakers = new address[](_sub(endIndex, startIndex));
        for (uint256 i = startIndex; i < endIndex; ++i) {
            stakers[_sub(i, startIndex)] = stakersInTier[tier][i];
        }
        return stakers;
    }

    /// @notice Checks if a staker is in a specific tier
    /// @param staker The address of the staker
    /// @param tier The tier number
    /// @return Whether the staker is in the specified tier
    function isStakerInTier(address staker, uint8 tier) external view returns (bool) {
        if (tier >= TIER_COUNT) revert InvalidTier(tier);
        return _stakes[staker].tier == tier;
    }

    /// @notice Safely adds two numbers
    /// @param a The first number
    /// @param b The second number
    /// @return The sum of a and b
    function _add(uint256 a, uint256 b) private pure returns (uint256) {
        (bool success, uint256 result) = Math.tryAdd(a, b);
        if (!success) revert AdditionOverflow();
        return result;
    }

    /// @notice Safely subtracts two numbers
    /// @param a The first number
    /// @param b The second number
    /// @return The difference between a and b
    function _sub(uint256 a, uint256 b) private pure returns (uint256) {
        (bool success, uint256 result) = Math.trySub(a, b);
        if (!success) revert SubtractionUnderflow();
        return result;
    }

    /// @notice Safely multiplies two numbers
    /// @param a The first number
    /// @param b The second number
    /// @return The product of a and b
    function _mul(uint256 a, uint256 b) private pure returns (uint256) {
        (bool success, uint256 result) = Math.tryMul(a, b);
        if (!success) revert MultiplicationOverflow();
        return result;
    }

    /// @notice Safely divides two numbers
    /// @param a The first number
    /// @param b The second number
    /// @return The quotient of a divided by b
    function _div(uint256 a, uint256 b) private pure returns (uint256) {
        (bool success, uint256 result) = Math.tryDiv(a, b);
        if (!success) revert DivisionByZero();
        return result;
    }

    /// @notice Safely calculates the modulus of two numbers
    /// @param a The first number
    /// @param b The second number
    /// @return The remainder of a divided by b
    function _mod(uint256 a, uint256 b) private pure returns (uint256) {
        (bool success, uint256 result) = Math.tryMod(a, b);
        if (!success) revert ModulusByZero();
        return result;
    }
}