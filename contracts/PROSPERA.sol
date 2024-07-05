// SPDX-License-Identifier: PROPRIETARY
pragma solidity 0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";

/// @custom:security-contact security@prosperadefi.com
contract PROSPERA is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, ERC20PausableUpgradeable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {

/// @notice Total supply of tokens
    uint256 private constant TOTAL_SUPPLY = 1e9 * 10**18;

    /// @notice Tokens allocated for staking rewards
    uint256 private constant STAKING_SUPPLY = TOTAL_SUPPLY * 10000 / 100000; // 10%

    /// @notice Tokens allocated for liquidity
    uint256 private constant LIQUIDITY_SUPPLY = TOTAL_SUPPLY * 20000 / 100000; // 20%

    /// @notice Tokens allocated for farming
    uint256 private constant FARMING_SUPPLY = TOTAL_SUPPLY * 10000 / 100000; // 10%

    /// @notice Tokens allocated for listing on exchanges
    uint256 private constant LISTING_SUPPLY = TOTAL_SUPPLY * 12000 / 100000; // 12%

    /// @notice Tokens allocated for reserves
    uint256 private constant RESERVE_SUPPLY = TOTAL_SUPPLY * 5025 / 100000; // 5.025%

    /// @notice Tokens allocated for marketing
    uint256 private constant MARKETING_SUPPLY = TOTAL_SUPPLY * 5000 / 100000; // 5%

    /// @notice Tokens allocated for team wallet
    uint256 private constant TEAM_SUPPLY = TOTAL_SUPPLY * 11600 / 100000; // 11.6%

    /// @notice Tokens allocated for dev wallet
    uint256 private constant DEV_SUPPLY = TOTAL_SUPPLY * 11000 / 100000; // 11%

    /// @notice Enum to define ICO tiers
    enum IcoTier { Tier1, Tier2, Tier3 }

    /// @notice Tokens allocated for the ICO
    uint256 private constant ICO_SUPPLY = TOTAL_SUPPLY * 15375 / 100000; // 15.375%

    /// @notice Tokens allocated for Tier 1 of the ICO
    uint256 public constant TIER1_TOKENS = 40000000 * 10**18;

    /// @notice Tokens allocated for Tier 2 of the ICO
    uint256 public constant TIER2_TOKENS = 50000000 * 10**18;

    /// @notice Tokens allocated for Tier 3 of the ICO
    uint256 public constant TIER3_TOKENS = 63750000 * 10**18;

    /// @notice Price per token in Tier 1 of the ICO
    uint256 public constant TIER1_PRICE = 0.02 ether;

    /// @notice Price per token in Tier 2 of the ICO
    uint256 public constant TIER2_PRICE = 0.08 ether;

    /// @notice Price per token in Tier 3 of the ICO
    uint256 public constant TIER3_PRICE = 0.16 ether;

    /// @notice Number of tokens sold in Tier 1 of the ICO
    uint256 public tier1Sold;

    /// @notice Number of tokens sold in Tier 2 of the ICO
    uint256 public tier2Sold;

    /// @notice Number of tokens sold in Tier 3 of the ICO
    uint256 public tier3Sold;

    /// @notice Indicates if the ICO is active
    bool public icoActive = true;

    /// @notice Current tier of the ICO
    IcoTier public currentTier = IcoTier.Tier1;

    /// @notice USDC token used for revenue sharing
    address public usdcToken;

    /// @notice Wallet address for tax collection
    address public taxWallet;

    /// @notice Wallet address for ICO funds
    address public icoWallet;

    /// @notice Wallet address for ICO supply
    address public prosicoWallet;

    /// @notice Wallet address for staking funds
    address public stakingWallet;

    // Storage slot for staking wallet
    bytes32 private constant STAKING_WALLET_SLOT = bytes32(uint256(keccak256("stakingWalletSlot")) - 1);

    // Storage slot for liquidity wallet
    bytes32 private constant LIQUIDITY_WALLET_SLOT = bytes32(uint256(keccak256("liquidityWalletSlot")) - 1);

    // Storage slot for farming wallet
    bytes32 private constant FARMING_WALLET_SLOT = bytes32(uint256(keccak256("farmingWalletSlot")) - 1);

    // Storage slot for listing wallet
    bytes32 private constant LISTING_WALLET_SLOT = bytes32(uint256(keccak256("listingWalletSlot")) - 1);

    // Storage slot for reserve wallet
    bytes32 private constant RESERVE_WALLET_SLOT = bytes32(uint256(keccak256("reserveWalletSlot")) - 1);

    // Storage slot for marketing wallet
    bytes32 private constant MARKETING_WALLET_SLOT = bytes32(uint256(keccak256("marketingWalletSlot")) - 1);

    // Storage slot for team wallet
    bytes32 private constant TEAM_WALLET_SLOT = bytes32(uint256(keccak256("teamWalletSlot")) - 1);

    // Storage slot for dev wallet
    bytes32 private constant DEV_WALLET_SLOT = bytes32(uint256(keccak256("devWalletSlot")) - 1);

    /// @notice Burn rate applied on token transfers (percentage)
    uint256 public constant BURN_RATE = 3;

    /// @notice Tax rate applied on token transfers (percentage)
    uint256 public constant TAX_RATE = 6;

    /// @notice Tax rate applied during the ICO (percentage)
    uint256 public constant ICO_TAX_RATE = 9;

    /// @notice Minimum amount of ETH required to participate in the ICO
    uint256 public constant MIN_ICO_BUY = 150 ether;

    /// @notice Maximum amount of ETH that can be used by a single wallet to buy tokens in the ICO
    uint256 public constant MAX_ICO_BUY = 500000 ether;

    /// @notice Number of seconds in a day, represented in 64.64 fixed point
    int128 private constant SECONDS_PER_DAY = 0x545ac0000000000000; // 86400 in 64x64 fixed point

    /// @notice Offset for Unix epoch in Julian days, represented in 64.64 fixed point
    int128 private constant OFFSET19700101 = 0x24bd0000000000000000; // 2440588 in 64x64 fixed point

    /// @notice Indicates if staking is enabled
    bool public isStakingEnabled;

    /// @notice Mapping of blacklisted addresses
    mapping(address user => bool isBlacklisted) private _blacklist;

    /// @notice Mapping of staker details
    mapping(address staker => Stake stakeInfo) private _stakes;

    /// @notice Mapping of rewards for stakers
    mapping(address staker => uint256 rewardAmount) private _stakeRewards;

    /// @notice Mapping of ICO purchases
    mapping(address buyer => uint256 purchaseAmount) private _icoBuys;

    /// @notice Tracks if a staker is eligible for quarterly revenue share
    mapping(address staker => bool isEligible) public quarterlyEligible;

    /// @notice Tracks the number of active stakers in each tier
    mapping(uint8 tier => uint256 stakerCount) public activeStakers;

    /// @notice Tracks addresses of stakers in each tier
    mapping(uint8 tier => address[] stakerAddresses) private stakersInTier;

    /// @notice Mapping of vesting schedules for addresses
    mapping(address user => Vesting[] schedules) public vestingSchedules;

    /// @notice Mapping of whitelisted addresses
    mapping(address user => bool isWhitelisted) public whitelist;

    /// @notice List of holders
    address[] internal holders;

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

    /// @notice Decimal precision
    uint256 private constant DECIMAL_PRECISION = 10**18;

    /// @notice Multiplier in basis points for each tier
    uint8[TIER_COUNT] public tierBonuses = [50, 50, 150, 175, 100, 125, 175];

    /// @notice List of cases
    Case[4] public cases;

    /// @notice Current case being used
    uint8 public currentCase;

    /// @notice Struct to define a case
    struct Case {
        uint256 maxWallets;
        uint256[7] maxWalletsPerTier;
        uint256[7] dailyYieldPercentage;
    }
    
    /// @notice Struct to define a stake
    struct Stake {
        uint256 amount;
        uint256 timestamp;
        uint8 tier;
        bool lockedUp;
        uint256 lockupDuration;
    }

    /// @notice Struct to define a vesting schedule
    struct Vesting {
        uint256 startTime;
        uint256 endTime;
        bool active;
        uint8 vestingType; // 0 for marketing, 1 for team
    }

    /// @notice Struct for high-precision integer arithmetic
    struct Int512 {
    int256 high;
    int256 low;
    }

    /// @notice Leap second table (Unix timestamps of leap seconds)
    uint256[] private leapSeconds = [
        78796800, 94694400, 126230400, 157766400, 189302400, 220924800, 252460800, 283996800, 315532800,
        362793600, 394329600, 425865600, 489024000, 567993600, 631152000, 662688000, 709948800, 741484800,
        773020800, 820454400, 867715200, 915148800, 1136073600, 1230768000, 1341100800, 1435708800, 1483228800
    ];

    // Events
    /// @notice Emitted when a user is added or removed from the blacklist
    /// @param user The address of the user
    /// @param value The new blacklist status
    event BlacklistUpdated(address indexed user, bool value);

    /// @notice Emitted when staking is enabled or disabled
    /// @param enabled The new staking status
    event StakingEnabled(bool indexed enabled);

    /// @notice Emitted when revenue is shared
    /// @param user The address of the user
    /// @param amount The amount of revenue shared
    event RevenueShared(address indexed user, uint256 amount);

    /// @notice Emitted when tokens are purchased during the ICO
    /// @param buyer The address of the buyer
    /// @param amount The amount of tokens purchased
    /// @param price The price of the tokens
    event TokensPurchased(address indexed buyer, uint256 amount, uint256 price);

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

    /// @notice Emitted when the contract is initialized
    /// @param deployer The address of the deployer
    event Initialized(address indexed deployer);

    /// @notice Emitted when the ICO ends
    event IcoEnded();

    /// @notice Emitted when tokens are transferred with tax and burn applied
    /// @param sender The address of the sender
    /// @param recipient The address of the recipient
    /// @param amount The amount of tokens transferred
    /// @param burnAmount The amount of tokens burned
    /// @param taxAmount The amount of tokens taxed
    event TransferWithTaxAndBurn(address indexed sender, address indexed recipient, uint256 amount, uint256 burnAmount, uint256 taxAmount);

    /// @notice Emitted when the ICO tier changes
    /// @param newTier The new ICO tier
    event IcoTierChanged(IcoTier indexed newTier);

    /// @notice Emitted when a user's ICO purchase is updated
    /// @param buyer The address of the buyer
    /// @param newBuyAmount The new ICO purchase amount
    event IcoBuyUpdated(address indexed buyer, uint256 newBuyAmount);

    /// @notice Emitted when the state of a variable is updated
    /// @param variable The name of the variable
    /// @param account The address of the account (if applicable)
    /// @param value The new value of the variable
    event StateUpdated(string variable, address indexed account, bool value);

    /// @notice Emitted when the number of tokens sold in an ICO tier is updated
    /// @param tier The ICO tier
    /// @param soldAmount The number of tokens sold
    event TierSoldUpdated(IcoTier indexed tier, uint256 soldAmount);

    /// @notice Emitted when the current ICO tier is updated
    /// @param newTier The new ICO tier
    event CurrentTierUpdated(IcoTier indexed newTier);

    /// @notice Emitted when a snapshot is taken for a user
    /// @param user The address of the user
    /// @param isEligible Whether the user is eligible for the snapshot
    event SnapshotTaken(address indexed user, bool isEligible);

    /// @notice Emitted when rewards are distributed to a user
    /// @param user The address of the user
    /// @param reward The amount of reward distributed
    event RewardsDistributed(address indexed user, uint256 reward);

    /// @notice Emitted when the current case is updated
    /// @param currentCase The new current case
    event CurrentCaseUpdated(uint8 indexed currentCase);

    /// @notice Emitted when a user's reward is updated
    /// @param user The address of the user
    /// @param reward The new reward amount
    event RewardUpdated(address indexed user, uint256 reward);

    /// @notice Emitted when the tier capacity is checked
    /// @param tier The tier number
    /// @param hasCapacity Whether the tier has capacity
    event TierCapacityChecked(uint8 indexed tier, bool hasCapacity);

    /// @notice Emitted when a wallet address is set
    /// @param walletType The type of wallet
    /// @param walletAddress The address of the wallet
    event WalletAddressSet(string indexed walletType, address indexed walletAddress);

    /// @notice Emitted when a vesting schedule is added
    /// @param user The address of the user
    /// @param startTime The start time of the vesting
    /// @param endTime The end time of the vesting
    event VestingAdded(address indexed user, uint256 startTime, uint256 endTime);

    /// @notice Emitted when vested tokens are released
    /// @param user The address of the user
    event VestingReleased(address indexed user);

    /// @notice Emitted when a user is added to the whitelist
    /// @param user The address of the user
    event AddedToWhitelist(address indexed user);

    /// @notice Emitted when a user is removed from the whitelist
    /// @param user The address of the user
    event RemovedFromWhitelist(address indexed user);

    /// @notice Emitted when ETH is transferred during the ICO process
    /// @param recipient The address receiving the ETH
    /// @param amount The amount of ETH transferred
    event EthTransferred(address indexed recipient, uint256 amount);

    /// @notice Emitted when ETH is withdrawn from the contract
    /// @param recipient The address receiving the ETH
    /// @param amount The amount of ETH withdrawn
    event EthWithdrawn(address indexed recipient, uint256 amount);

    // Errors
    /// @notice Error for blacklisted address
    /// @param account The blacklisted address
    error BlacklistedAddress(address account);

    /// @notice Error for staking not enabled
    error StakingNotEnabled();

    /// @notice Error for adding a zero address to the blacklist
    error BlacklistZeroAddress();

    /// @notice Error for removing a zero address from the blacklist
    error RemoveFromBlacklistZeroAddress();

    /// @notice Error for staking zero tokens
    error CannotStakeZeroTokens();

    /// @notice Error for unstaking zero tokens
    error CannotUnstakeZeroTokens();

    /// @notice Error for insufficient staked amount
    /// @param available The available staked amount
    /// @param required The required staked amount
    error InsufficientStakedAmount(uint256 available, uint256 required);

    /// @notice Error for tokens still locked
    error TokensStillLocked();

    /// @notice Error for locking zero tokens
    error CannotLockZeroTokens();

    /// @notice Error for lock duration too short
    error LockDurationTooShort();

    /// @notice Error for ICO not active
    error IcoNotActive();

    /// @notice Error for below minimum ICO buy limit
    error BelowMinIcoBuyLimit();

    /// @notice Error for exceeding maximum ICO buy limit
    error ExceedsMaxIcoBuyLimit();

    /// @notice Error for invalid ICO tier
    error InvalidIcoTier();

    /// @notice Error for incorrect ETH amount sent
    error IncorrectETHAmountSent();

    /// @notice Error for when there are insufficient funds to make a purchase
    error InsufficientFundsForPurchase();

    /// @notice Error for ETH transfer failed
    error EthTransferFailed();

    /// @notice Error for Invalid recipient address
    error InvalidRecipientAddress();

    /// @notice Error for insufficient balance in the contract
    error InsufficientBalance();

    /// @notice Error for when there's no ETH to withdraw
    error NoEthToWithdraw();

    /// @notice Error for transfer from zero address
    error TransferFromZeroAddress();

    /// @notice Error for transfer to zero address
    error TransferToZeroAddress();

    /// @notice Error for invalid lockup duration
    error InvalidLockupDuration();

    /// @notice Error for insufficient staking wallet balance
    error InsufficientStakingWalletBalance();

    /// @notice Error for minimum staking amount not met
    error MinimumStakingAmount();

    /// @notice Error for not quarter start
    error NotQuarterStart();

    /// @notice Error for fallback function only accepts ETH
    error FallbackFunctionOnlyAcceptsETH();

    /// @notice Error for invalid address
    error InvalidAddress();

    /// @notice Error for vesting not being active
    error VestingNotActive();

    /// @notice Error for vesting period not ended
    error VestingPeriodNotEnded();

    /// @notice Error for attempting to transfer vested tokens
    error VestedTokensCannotBeTransferred();

    /// @notice Error for division by zero
    error DivisionByZero();

    /// @notice Error for overflow in tier cost calculation
    error OverflowInTierCostCalculation();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract with the specified parameters
     * @param _usdcToken Address of the USDC token contract
     * @param _deployerWallet Address of the deployer wallet
     * @param _taxWallet Address of the tax wallet
     * @param _stakingWallet Address of the staking wallet
     * @param _icoWallet Address of the ICO wallet
     * @param _prosicoWallet Address of the prosico wallet
     * @param _liquidityWallet Address of the liquidity wallet
     * @param _farmingWallet Address of the farming wallet
     * @param _listingWallet Address of the listing wallet
     * @param _reserveWallet Address of the reserve wallet
     * @param _marketingWallet Address of the marketing wallet
     * @param _teamWallet Address of the team wallet
     * @param _devWallet Address of the dev wallet
     */
    function initialize(
        address _usdcToken,
        address _deployerWallet,
        address _taxWallet,
        address _stakingWallet,
        address _icoWallet,
        address _prosicoWallet,
        address _liquidityWallet,
        address _farmingWallet,
        address _listingWallet,
        address _reserveWallet,
        address _marketingWallet,
        address _teamWallet,
        address _devWallet
    ) initializer external {
        __ERC20_init("PROSPERA", "PROS");
        emit Initialized(_deployerWallet);

        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __Ownable_init(_deployerWallet);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        usdcToken = _usdcToken;
        taxWallet = _taxWallet;
        stakingWallet = _stakingWallet;
        icoWallet = _icoWallet;
        prosicoWallet = _prosicoWallet;

        StorageSlot.getAddressSlot(STAKING_WALLET_SLOT).value = _stakingWallet;
        StorageSlot.getAddressSlot(LIQUIDITY_WALLET_SLOT).value = _liquidityWallet;
        StorageSlot.getAddressSlot(FARMING_WALLET_SLOT).value = _farmingWallet;
        StorageSlot.getAddressSlot(LISTING_WALLET_SLOT).value = _listingWallet;
        StorageSlot.getAddressSlot(RESERVE_WALLET_SLOT).value = _reserveWallet;
        StorageSlot.getAddressSlot(MARKETING_WALLET_SLOT).value = _marketingWallet;
        StorageSlot.getAddressSlot(TEAM_WALLET_SLOT).value = _teamWallet;
        StorageSlot.getAddressSlot(DEV_WALLET_SLOT).value = _devWallet;

        _mint(_deployerWallet, TOTAL_SUPPLY);

        emit WalletAddressSet("USDC Token", usdcToken);
        emit WalletAddressSet("Tax Wallet", taxWallet);
        emit WalletAddressSet("Staking Wallet", stakingWallet);
        emit WalletAddressSet("ICO Wallet", icoWallet);
        emit WalletAddressSet("Prosico Wallet", prosicoWallet);
        emit WalletAddressSet("Liquidity Wallet", _liquidityWallet);
        emit WalletAddressSet("Farming Wallet", _farmingWallet);
        emit WalletAddressSet("Listing Wallet", _listingWallet);
        emit WalletAddressSet("Reserve Wallet", _reserveWallet);
        emit WalletAddressSet("Marketing Wallet", _marketingWallet);
        emit WalletAddressSet("Team Wallet", _teamWallet);
        emit WalletAddressSet("Dev Wallet", _devWallet);
        
        //initialize the cases
        cases[0] = Case({
            maxWallets: 1500,
            maxWalletsPerTier: [150, type(uint256).max, type(uint256).max, type(uint256).max, 150, 23, 8],
            dailyYieldPercentage: [uint256(0.0005 * 10**18), uint256(0.0005 * 10**18), uint256(0.00075 * 10**18), uint256(0.0015 * 10**18), uint256(0.00175 * 10**18), uint256(0.00225 * 10**18), uint256(0.00275 * 10**18)]
        });
        emit StateUpdated("Case", address(0), true);

        cases[1] = Case({
            maxWallets: 3000,
            maxWalletsPerTier: [300, type(uint256).max, type(uint256).max, type(uint256).max, 300, 45, 15],
            dailyYieldPercentage: [uint256(0.00025 * 10**18), uint256(0.00035 * 10**18), uint256(0.00055 * 10**18), uint256(0.00085 * 10**18), uint256(0.00135 * 10**18), uint256(0.00125 * 10**18), uint256(0.00175 * 10**18)]
        });
        emit StateUpdated("Case", address(0), true);

        cases[2] = Case({
            maxWallets: 10000,
            maxWalletsPerTier: [1000, type(uint256).max, type(uint256).max, type(uint256).max, 1000, 150, 50],
            dailyYieldPercentage: [uint256(0.000075 * 10**18), uint256(0.00009 * 10**18), uint256(0.000125 * 10**18), uint256(0.00035 * 10**18), uint256(0.00095 * 10**18), uint256(0.00115 * 10**18), uint256(0.00135 * 10**18)]
        });
        emit StateUpdated("Case", address(0), true);

        cases[3] = Case({
            maxWallets: 20000,
            maxWalletsPerTier: [2000, type(uint256).max, type(uint256).max, type(uint256).max, 2000, 300, 100],
            dailyYieldPercentage: [uint256(0.00005 * 10**18), uint256(0.000075 * 10**18), uint256(0.0001 * 10**18), uint256(0.00025 * 10**18), uint256(0.00075 * 10**18), uint256(0.00095 * 10**18), uint256(0.00115 * 10**18)]
        });
        emit StateUpdated("Case", address(0), true);

        // Disable initializers to prevent re-initialization
        _disableInitializers();
        emit StateUpdated("initializersDisabled", address(0), true);

        emit Initialized(_deployerWallet);
    }

    /**
     * @notice Authorizes an upgrade to a new implementation
     * @dev This function is left empty but is required by the UUPSUpgradeable contract
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @notice Pauses all token transfers
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses all token transfers
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Mints a specified amount of tokens to a given address
     * @param to The address to receive the minted tokens
     * @param amount The number of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
        emit Transfer(address(0), to, amount);
    }

    /**
     * @notice Adds an address to the blacklist
     * @param account The address to be blacklisted
     */
    function addToBlacklist(address account) external onlyOwner {
        if (account == address(0)) revert BlacklistZeroAddress();
        _blacklist[account] = true;
        emit BlacklistUpdated(account, true);
        emit StateUpdated("blacklist", account, true);
    }

    /**
     * @notice Removes an address from the blacklist
     * @param account The address to be removed from the blacklist
     */
    function removeFromBlacklist(address account) external onlyOwner {
        if (account == address(0)) revert RemoveFromBlacklistZeroAddress();
        _blacklist[account] = false;
        emit BlacklistUpdated(account, false);
        emit StateUpdated("blacklist", account, false);
    }

    /**
     * @notice Adds an address to the whitelist
     * @param account The address to be added
     */
    function addToWhitelist(address account) external onlyOwner {
        whitelist[account] = true;
        emit AddedToWhitelist(account);
        emit StateUpdated("whitelist", account, true);
    }

    /**
     * @notice Removes an address from the whitelist
     * @param account The address to be removed
     */
    function removeFromWhitelist(address account) external onlyOwner {
        whitelist[account] = false;
        emit RemovedFromWhitelist(account);
        emit StateUpdated("whitelist", account, false);
    }

    /**
     * @notice Enables or disables staking
     * @param _enabled The new staking status (true to enable, false to disable)
     */
    function enableStaking(bool _enabled) external onlyOwner {
        isStakingEnabled = _enabled;
        emit StakingEnabled(_enabled);
        emit StateUpdated("isStakingEnabled", address(0), _enabled);
    }

    /**
     * @notice Stakes a specified amount of tokens
     * @param stakeAmount The number of tokens to stake
     * @param isLockedUp Indicates if the tokens are locked up
     * @param lockDuration The duration for which tokens are locked up (in seconds)
     */
    function stake(uint256 stakeAmount, bool isLockedUp, uint256 lockDuration) external nonReentrant whenNotPaused {
        if (_blacklist[_msgSender()]) revert BlacklistedAddress(_msgSender());

        Vesting[] storage vestings = vestingSchedules[_msgSender()];
        uint256 vestingsLength = vestings.length;
        bool hasActiveVesting;

        for (uint256 i; i < vestingsLength;) {
            if (vestings[i].active) {
                hasActiveVesting = true;
                break;
            }
            unchecked { ++i; }
        }
    
        // Allow staking if: 
        // 1. Staking is enabled for everyone, OR
        // 2. The wallet has an active vesting schedule, OR
        // 3. The wallet is whitelisted
        if (!isStakingEnabled && !hasActiveVesting && !whitelist[_msgSender()]) revert StakingNotEnabled();
    
        if (stakeAmount == 0) revert CannotStakeZeroTokens();
        if (isLockedUp && (lockDuration < MIN_STAKE_DURATION || lockDuration > MAX_STAKE_DURATION)) revert InvalidLockupDuration();

        uint8 tier = _getTierByStakeAmount(stakeAmount);

        _burn(_msgSender(), stakeAmount);

        if (_stakes[_msgSender()].amount > 0) {
            _updateReward(_msgSender());
        } else {
            stakersInTier[tier].push(_msgSender());
            emit StateUpdated("stakersInTier", _msgSender(), true);
        }

        _stakes[_msgSender()] = Stake({
            amount: stakeAmount,
            timestamp: block.timestamp,
            tier: tier,
            lockedUp: isLockedUp,
            lockupDuration: lockDuration
        });
        ++activeStakers[tier];
        emit StateUpdated("activeStakers", _msgSender(), true);

        if (!_isHolder(_msgSender())) {
            holders.push(_msgSender());
            emit StateUpdated("holders", _msgSender(), true);
        }

        _updateCurrentCase();

        emit Staked(_msgSender(), stakeAmount, _stakes[_msgSender()].amount);
        emit StateUpdated("stake", _msgSender(), true);
    }

    /**
     * @notice Unstakes a specified amount of tokens
     * @param unstakeAmount The number of tokens to unstake
     */
    function unstake(uint256 unstakeAmount) external nonReentrant whenNotPaused {
        if (_blacklist[_msgSender()]) revert BlacklistedAddress(_msgSender());
        if (!isStakingEnabled) revert StakingNotEnabled();
        if (unstakeAmount == 0) revert CannotUnstakeZeroTokens();
        Stake memory stakeInfo = _stakes[_msgSender()];
        if (stakeInfo.amount < unstakeAmount) revert InsufficientStakedAmount(stakeInfo.amount, unstakeAmount);
        if (stakeInfo.lockedUp && block.timestamp < stakeInfo.timestamp + stakeInfo.lockupDuration) revert TokensStillLocked();

        uint256 reward = _stakeRewards[_msgSender()];

        uint8 tier = stakeInfo.tier;

        stakeInfo.amount -= unstakeAmount;
        if (stakeInfo.amount == 0) {
            delete _stakes[_msgSender()];
            delete _stakeRewards[_msgSender()];
            --activeStakers[tier];
            _removeStakerFromTier(tier, _msgSender());
        } else {
            _stakes[_msgSender()] = stakeInfo;
        }

        _updateCurrentCase();

        if (balanceOf(stakingWallet) < unstakeAmount + reward) revert InsufficientStakingWalletBalance();
        uint256 totalAmount = unstakeAmount + reward;
        uint256 burnAmount = totalAmount * BURN_RATE / 100;
        totalAmount -= burnAmount;

        _transfer(stakingWallet, _msgSender(), totalAmount);
        _burn(stakingWallet, burnAmount);

        emit Unstaked(_msgSender(), unstakeAmount, reward);
        emit StateUpdated("unstake", _msgSender(), true);
    }

    /**
     * @notice Locks a specified amount of tokens
     * @param lockAmount The number of tokens to lock
     * @param lockDuration The duration for which tokens are locked (in seconds)
     */
    function lockTokens(uint256 lockAmount, uint256 lockDuration) external nonReentrant whenNotPaused {
        if (_blacklist[_msgSender()]) revert BlacklistedAddress(_msgSender());
        if (!isStakingEnabled) revert StakingNotEnabled();
        if (lockAmount == 0) revert CannotLockZeroTokens();
        if (lockDuration < MIN_STAKE_DURATION || lockDuration > MAX_STAKE_DURATION) revert LockDurationTooShort();

        Stake storage stakeInfo = _stakes[_msgSender()];
        stakeInfo.amount += lockAmount;
        stakeInfo.lockedUp = true;
        stakeInfo.lockupDuration = lockDuration;
        stakeInfo.timestamp = block.timestamp;

        emit TokensLocked(_msgSender(), lockAmount, lockDuration);
        emit StateUpdated("lockTokens", _msgSender(), true);
    }

    /**
     * @notice Adds an address to the vesting schedule
     * @param account The address to be added
     * @param vestingType The type of vesting (0 for marketing, 1 for team)
     */
    function addToVesting(address account, uint8 vestingType) external onlyOwner {
        if (account == address(0)) revert InvalidAddress();
    
        uint256 startTime = block.timestamp;
        uint256 endTime;
        bool isActive = true; // Explicitly define the boolean value

        if (vestingType == 0) {
            endTime = startTime + 120 days; // 4 months for marketing
        } else {
            endTime = startTime + 90 days; // 3 months for team
        }

        Vesting memory newVesting = Vesting({
            startTime: startTime,
            endTime: endTime,
            active: isActive,
            vestingType: vestingType
        });

        vestingSchedules[account].push(newVesting);
    
        emit VestingAdded(account, startTime, endTime);
        emit StateUpdated("vesting", account, isActive);
    }

    /**
     * @notice Releases vested tokens for an address
     * @param account The address to release tokens for
     */
    function releaseVestedTokens(address account) external {
        Vesting[] storage vestings = vestingSchedules[account];
        uint256 vestingsLength = vestings.length; // Store the length in a local variable
        for (uint256 i; i < vestingsLength; ++i) {
            Vesting storage vesting = vestings[i];
            if (!vesting.active) continue;
            if (block.timestamp < vesting.endTime) revert VestingPeriodNotEnded();
            vesting.active = false;
            emit VestingReleased(account);
            emit StateUpdated("vesting", account, false);
        }
    }

    /**
     * @notice Updates the reward for a staker based on the current case and tier
     * @param stakerAddress The address of the staker
     */
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

        // Apply burn rate to the reward if the stake is not locked up
        if (!_stakes[stakerAddress].lockedUp) {
            uint256 burnAmount = calculatedReward * BURN_RATE / 100;
            calculatedReward -= burnAmount;
            _burn(stakingWallet, burnAmount);
        }

        _stakeRewards[stakerAddress] = calculatedReward;

        emit RewardUpdated(stakerAddress, calculatedReward);
        emit StateUpdated("reward", stakerAddress, true);
    }

    /**
     * @notice Calculates the reward for Case 0 (up to 1,500 wallets)
     * @param amount The amount of tokens staked
     * @param tier The tier of the staker
     * @param stakedDuration The duration for which the tokens have been staked (in days)
     * @return reward The calculated reward in tokens
     */
    function _calculateCase0Reward(uint256 amount, uint8 tier, uint256 stakedDuration) private view returns (uint256 reward) {
        uint256 dailyYieldDecimal = cases[0].dailyYieldPercentage[tier];
        uint256 stakedAmount = amount; // Explicitly use amount
        reward = ((stakedAmount * dailyYieldDecimal) * stakedDuration) / 10**18;
    }

    /**
     * @notice Calculates the reward for Case 1 (up to 3,000 wallets)
     * @param amount The amount of tokens staked
     * @param tier The tier of the staker
     * @param stakedDuration The duration for which the tokens have been staked (in days)
     * @return reward The calculated reward in tokens
     */
    function _calculateCase1Reward(uint256 amount, uint8 tier, uint256 stakedDuration) private view returns (uint256 reward) {
        uint256 dailyYieldDecimal = cases[1].dailyYieldPercentage[tier];
        uint256 stakedAmount = amount; // Explicitly use amount
        reward = ((stakedAmount * dailyYieldDecimal) * stakedDuration) / 10**18;
    }

    /**
     * @notice Calculates the reward for Case 2 (up to 10,000 wallets)
     * @param amount The amount of tokens staked
     * @param tier The tier of the staker
     * @param stakedDuration The duration for which the tokens have been staked (in days)
     * @return reward The calculated reward in tokens
     */
    function _calculateCase2Reward(uint256 amount, uint8 tier, uint256 stakedDuration) private view returns (uint256 reward) {
        uint256 dailyYieldDecimal = cases[2].dailyYieldPercentage[tier];
        uint256 stakedAmount = amount; // Explicitly use amount
        reward = ((stakedAmount * dailyYieldDecimal) * stakedDuration) / 10**18;
    }

    /**
     * @notice Calculates the reward for Case 3 (up to 20,000 wallets)
     * @param amount The amount of tokens staked
     * @param tier The tier of the staker
     * @param stakedDuration The duration for which the tokens have been staked (in days)
     * @return reward The calculated reward in tokens
     */
    function _calculateCase3Reward(uint256 amount, uint8 tier, uint256 stakedDuration) private view returns (uint256 reward) {
        uint256 dailyYieldDecimal = cases[3].dailyYieldPercentage[tier];
        uint256 stakedAmount = amount; // Explicitly use amount
        reward = ((stakedAmount * dailyYieldDecimal) * stakedDuration) / 10**18;
    }

    /**
     * @notice Determines the tier based on the stake amount
     * @param amount The amount staked
     * @return tier The tier number
     */
    function _getTierByStakeAmount(uint256 amount) private pure returns (uint8 tier) {
        if (amount < 5000 * 10**18) revert MinimumStakingAmount();

        if (amount < 57143 * 10**18) {
            tier = 1;
        } else if (amount < 200000 * 10**18) {
            tier = 2;
        } else if (amount < 500000 * 10**18) {
            tier = 3;
        } else if (amount < 1500000 * 10**18) {
            tier = 4;
        } else if (amount < 10000000 * 10**18) {
            tier = 5;
        } else {
            tier = 6;
        }
    }

    /**
     * @notice Updates the current case based on the number of active stakers
     */
    function _updateCurrentCase() private {
        uint256 totalStakers;
        for (uint8 i; i < TIER_COUNT; ++i) {
            totalStakers += activeStakers[i];
        }

        if (totalStakers <= cases[0].maxWallets) {
            currentCase = 0;
        } else if (totalStakers <= cases[1].maxWallets) {
            currentCase = 1;
        } else if (totalStakers <= cases[2].maxWallets) {
            currentCase = 2;
        } else {
            currentCase = 3;
        }

        emit CurrentCaseUpdated(currentCase);
        emit StateUpdated("currentCase", address(0), true);
    }

    /**
     * @notice Adjusts the timestamp for leap seconds
     * @param timestamp The timestamp to adjust
     * @return The adjusted timestamp
     */
    function adjustForLeapSeconds(uint256 timestamp) private view returns (uint256) {
        uint256 leapSecondsCount;
        uint256 leapSecondsLength = leapSeconds.length;
        for (uint256 i; i < leapSecondsLength;) {
            if (timestamp > leapSeconds[i]) {
                unchecked {
                    ++leapSecondsCount;
                }
            } else {
                break;
            }
            unchecked {
                ++i;
            }
        }
        return timestamp - leapSecondsCount;
    }

    /**
     * @notice Checks if the current timestamp is the start of a new quarter
     * @param timestamp The timestamp to check
     * @return isQuarterStart True if it is the start of a new quarter, false otherwise
     */
    function _isQuarterStart(uint256 timestamp) private view returns (bool) {
        (uint256 year, uint256 month, uint256 day, , , ,) = _timestampToDate(timestamp);
        return (month == 1 || month == 4 || month == 7 || month == 10) && day == 1;
    }

    /**
     * @notice Converts a timestamp to a date with maximum precision
     * @param timestamp The timestamp to convert (in seconds since Unix epoch)
     * @return year The year
     * @return month The month (1-12)
     * @return day The day of the month (1-31)
     * @return hour The hour (0-23)
     * @return minute The minute (0-59)
     * @return second The second (0-59)
     * @return millisecond The millisecond (0-999)
     */
    function _timestampToDate(uint256 timestamp) private view returns (
        uint256 year, uint256 month, uint256 day, 
        uint256 hour, uint256 minute, uint256 second, uint256 millisecond
    ) {
        timestamp = adjustForLeapSeconds(timestamp);

        uint256 wholeSeconds = timestamp / 1000;
        millisecond = timestamp % 1000;

        Int512 memory julianDay = addInt512(
            divideInt512(
                multiplyInt512(Int512(0, int256(wholeSeconds)), Int512(0, int256(86400))),
                Int512(0, int256(86400))
            ),
            Int512(0, int256(2440588))
        );

        Int512 memory j = addInt512(julianDay, Int512(0, 32044));
        Int512 memory g = divideInt512(j, Int512(0, 146097));
        Int512 memory dg = subtractInt512(j, multiplyInt512(Int512(0, 146097), g));
        Int512 memory c = divideInt512(
            multiplyInt512(subtractInt512(dg, Int512(0, 1)), Int512(0, 3)),
            Int512(0, 4)
        );
        Int512 memory d = subtractInt512(dg, multiplyInt512(c, Int512(0, 4)));
        Int512 memory m = divideInt512(
            multiplyInt512(subtractInt512(d, Int512(0, 1)), Int512(0, 5)),
            Int512(0, 153)
        );
        Int512 memory n = addInt512(
            multiplyInt512(Int512(0, 100), g),
            divideInt512(m, Int512(0, 16))
        );
        Int512 memory _year = subtractInt512(n, Int512(0, 4800));
        Int512 memory _month = subtractInt512(
            subtractInt512(m, Int512(0, 2)),
            multiplyInt512(Int512(0, 12), divideInt512(m, Int512(0, 10)))
        );
        Int512 memory _day = subtractInt512(
            subtractInt512(d, multiplyInt512(Int512(0, 153), m)),
            Int512(0, 2)
        );

        year = uint256(_year.low);
        month = uint256(_month.low);
        day = uint256(_day.low);

        uint256 secondsOfDay = wholeSeconds % 86400;
        hour = secondsOfDay / 3600;
        minute = (secondsOfDay % 3600) / 60;
        second = secondsOfDay % 60;
    }
    
    // Helper functions for Int512 arithmetic
    function addInt512(Int512 memory a, Int512 memory b) private pure returns (Int512 memory) {
        int256 lowSum = a.low + b.low;
        int256 highSum = a.high + b.high + (lowSum < a.low ? int256(1) : int256(0));
        return Int512(highSum, lowSum);
    }

    function subtractInt512(Int512 memory a, Int512 memory b) private pure returns (Int512 memory) {
        int256 lowDiff = a.low - b.low;
        int256 highDiff = a.high - b.high - (lowDiff > a.low ? int256(-1) : int256(0));
        return Int512(highDiff, lowDiff);
    }

    function multiplyInt512(Int512 memory a, Int512 memory b) private pure returns (Int512 memory) {
        int256 low = a.low * b.low;
        int256 high = a.high * b.low + a.low * b.high + ((a.low >> 128) * (b.low >> 128));
        return Int512(high, low);
    }

    function divideInt512(Int512 memory a, Int512 memory b) private pure returns (Int512 memory) {
        if (b.high == 0 && b.low == 0) revert DivisionByZero();
        int256 aAbs = a.high < 0 ? -a.high : a.high;
        int256 bAbs = b.high < 0 ? -b.high : b.high;
        int256 quot = (aAbs << 128 | (a.low < 0 ? -a.low : a.low)) / (bAbs << 128 | (b.low < 0 ? -b.low : b.low));
        bool negative = (a.high < 0) != (b.high < 0);
        return Int512(negative ? -int256(uint256(quot) >> 128) : int256(uint256(quot) >> 128), negative ? -int256(uint256(quot) & ((1 << 128) - 1)) : int256(uint256(quot) & ((1 << 128) - 1)));
    }

    /**
     * @notice Takes a snapshot to determine eligibility for quarterly revenue share
     */
    function takeSnapshot() external nonReentrant {
        if (!_isQuarterStart(block.timestamp)) revert NotQuarterStart();

        // Emit the contract-wide snapshot event with the current timestamp
        emit SnapshotTaken(block.timestamp);

        for (uint8 i; i < TIER_COUNT; ++i) {
            address[] memory stakers = stakersInTier[i];
            uint256 stakersLength = stakers.length;
            for (uint256 j; j < stakersLength; ++j) {
                bool isEligible = _checkEligibility(stakers[j]);
                quarterlyEligible[stakers[j]] = isEligible;

                // Emit the user-specific snapshot event
                emit SnapshotTaken(stakers[j], isEligible);
                emit StateUpdated("snapshot", stakers[j], true);
            }
        }
    }

    /**
     * @notice Removes a staker from a tier
     * @param tier The tier number
     * @param stakerAddress The address of the staker
     */
    function _removeStakerFromTier(uint8 tier, address stakerAddress) private {
        uint256 length = stakersInTier[tier].length;
        for (uint256 i; i < length; ++i) {
            if (stakersInTier[tier][i] == stakerAddress) {
                stakersInTier[tier][i] = stakersInTier[tier][length - 1];
                stakersInTier[tier].pop();
                emit StateUpdated("stakersInTier", stakerAddress, false);
                break;
            }
        }
    }

    /**
     * @notice Checks if a staker is eligible for quarterly revenue share
     * @param stakerAddress The address of the staker
     * @return isEligible True if eligible, false otherwise
     */
    function _checkEligibility(address stakerAddress) private view returns (bool isEligible) {
        Stake memory stakeInfo = _stakes[stakerAddress];
        uint256 currentQuarterStart = block.timestamp - (block.timestamp % (90 days));

        if (stakeInfo.lockedUp) {
            // Eligibility criteria for locked-up stakes
            isEligible = stakeInfo.amount >= 60000 * 10**18;
        } else {
            // Eligibility criteria for non-locked-up stakes
            isEligible = stakeInfo.amount >= 70000 * 10**18 && stakeInfo.timestamp <= currentQuarterStart;
        }
    }

    /**
     * @notice Returns the stake details for a given staker
     * @param stakerAddress The address of the staker
     * @return amount The amount staked
     * @return timestamp The timestamp when staked
     * @return tier The tier number
     */
    function getStake(address stakerAddress) external view returns (uint256 amount, uint256 timestamp, uint8 tier) {
        Stake memory stakeInfo = _stakes[stakerAddress];
        amount = stakeInfo.amount;
        timestamp = stakeInfo.timestamp;
        tier = stakeInfo.tier;
    }

    /**
     * @notice Returns the reward for a given staker
     * @param stakerAddress The address of the staker
     * @return reward The reward amount
     */
    function getReward(address stakerAddress) external view returns (uint256 reward) {
        reward = _stakeRewards[stakerAddress];
    }

    /**
     * @notice Handles normal buy and sell transactions with tax and burn
     * @param senderAddress The address sending the tokens
     * @param recipientAddress The address receiving the tokens
     * @param amount The amount of tokens being transferred
     */
    function handleNormalBuySell(address senderAddress, address recipientAddress, uint256 amount) private {
        uint256 ethTaxAmount = amount * TAX_RATE / 100;
        uint256 burnAmount = amount * BURN_RATE / 100;
        uint256 transferAmount = amount - burnAmount;

        _burn(senderAddress, burnAmount);
        _transfer(senderAddress, recipientAddress, transferAmount);

        // State changes before external calls
        _safeTransferETH(taxWallet, ethTaxAmount);

        emit TransferWithTaxAndBurn(senderAddress, recipientAddress, amount, burnAmount, ethTaxAmount);
    }

    /**
     * @notice Determines if a transfer is a buy/sell transaction
     * @param from The address sending the tokens
     * @param to The address receiving the tokens
     * @return True if it is a buy/sell transaction, false otherwise
     */
    function isBuySell(address from, address to) private view returns (bool) {
        return from == taxWallet || to == taxWallet || from == icoWallet || to == icoWallet;
    }

    /// @notice Purchases tokens during the ICO
    /// @dev This function handles the token purchase process, including tax calculation and dynamic tier transitions
    /// @param tokenAmount The number of tokens to purchase
    function buyTokens(uint256 tokenAmount) external payable nonReentrant whenNotPaused {
        if (_blacklist[_msgSender()]) revert BlacklistedAddress(_msgSender());
        if (!icoActive) revert IcoNotActive();
    
        uint256 ethValue = msg.value;

        // Check minimum and maximum buy limit
        if (ethValue < MIN_ICO_BUY) revert BelowMinIcoBuyLimit();
        if (_icoBuys[_msgSender()] + ethValue > MAX_ICO_BUY) revert ExceedsMaxIcoBuyLimit();

        // Calculate the ICO tax
        uint256 totalTaxAmount = ethValue * ICO_TAX_RATE / 100;
        uint256 remainingEth = ethValue - totalTaxAmount;

        uint256 remainingTokens = tokenAmount;
        uint256 totalCost;
        uint256 totalTokensBought;

        while (remainingTokens > 0 && icoActive) {
            (uint256 tokensBought, uint256 tierCost) = buyFromCurrentTier(remainingTokens, remainingEth - totalCost);
    
            if (tokensBought == 0) break; // Not enough ETH to buy more tokens

            totalTokensBought += tokensBought;
            totalCost += tierCost;
            remainingTokens -= tokensBought;
        }

        if (totalTokensBought == 0) revert InsufficientFundsForPurchase();
        if (remainingEth < totalCost) revert IncorrectETHAmountSent();

        // Update state
        _icoBuys[_msgSender()] += totalCost;
        emit IcoBuyUpdated(_msgSender(), _icoBuys[_msgSender()]);

        _transfer(prosicoWallet, _msgSender(), totalTokensBought);
        emit TokensPurchased(_msgSender(), totalTokensBought, totalCost);
        emit StateUpdated("IcoPurchase", _msgSender(), true);

        // Perform external interactions last
        _safeTransferETH(icoWallet, totalCost);
        _safeTransferETH(taxWallet, totalTaxAmount);

        // Emit event for ETH transfers
        emit EthTransferred(icoWallet, totalCost);
        emit EthTransferred(taxWallet, totalTaxAmount);
    }

    /// @notice Buys tokens from the current ICO tier
    /// @dev This function handles purchasing from a single tier and transitions to the next if necessary
    /// @param tokensToBuy The number of tokens attempting to buy
    /// @param availableEth The amount of ETH available for the purchase
    /// @return tokensBought The number of tokens successfully purchased
    /// @return tierCost The cost of the purchased tokens
    function buyFromCurrentTier(uint256 tokensToBuy, uint256 availableEth) private returns (uint256 tokensBought, uint256 tierCost) {
        uint256 tierTokens;
        uint256 tierSold;
        uint256 tierPrice;

        if (currentTier == IcoTier.Tier1) {
            tierTokens = TIER1_TOKENS;
            tierSold = tier1Sold;
            tierPrice = TIER1_PRICE;
        } else if (currentTier == IcoTier.Tier2) {
            tierTokens = TIER2_TOKENS;
            tierSold = tier2Sold;
            tierPrice = TIER2_PRICE;
        } else if (currentTier == IcoTier.Tier3) {
            tierTokens = TIER3_TOKENS;
            tierSold = tier3Sold;
            tierPrice = TIER3_PRICE;
        } else {
            revert InvalidIcoTier();
        }

        uint256 availableTokens = tierTokens - tierSold;
        tokensBought = (tokensToBuy < availableTokens) ? tokensToBuy : availableTokens;
    
        // Check for potential overflow
        if (tokensBought > type(uint256).max / tierPrice) {
            revert OverflowInTierCostCalculation();
        }
        uint256 tierCostPrecise = tokensBought * tierPrice;
        tierCost = tierCostPrecise / DECIMAL_PRECISION;

        if (tierCost > availableEth) {
            // Recalculate tokensBought based on availableEth
            uint256 maxTokens = availableEth * DECIMAL_PRECISION / tierPrice;
            tokensBought = (maxTokens < tokensBought) ? maxTokens : tokensBought;

            // Recalculate tierCost
            if (tokensBought > type(uint256).max / tierPrice) {
                revert OverflowInTierCostCalculation();
            }
            tierCostPrecise = tokensBought * tierPrice;
            tierCost = tierCostPrecise / DECIMAL_PRECISION;
        }

        if (currentTier == IcoTier.Tier1) {
            tier1Sold += tokensBought;
            emit TierSoldUpdated(IcoTier.Tier1, tier1Sold);
            if (tier1Sold >= TIER1_TOKENS) updateIcoTier(IcoTier.Tier2);
        } else if (currentTier == IcoTier.Tier2) {
            tier2Sold += tokensBought;
            emit TierSoldUpdated(IcoTier.Tier2, tier2Sold);
            if (tier2Sold >= TIER2_TOKENS) updateIcoTier(IcoTier.Tier3);
        } else if (currentTier == IcoTier.Tier3) {
            tier3Sold += tokensBought;
            emit TierSoldUpdated(IcoTier.Tier3, tier3Sold);
            if (tier3Sold >= TIER3_TOKENS) endIco();
        }
    }

    /// @notice Updates the ICO tier
    /// @param newTier The new ICO tier to set
    function updateIcoTier(IcoTier newTier) private {
        currentTier = newTier;
        emit IcoTierChanged(newTier);
        emit CurrentTierUpdated(newTier);
        emit StateUpdated("CurrentTier", address(0), true);
    }

    /// @notice Ends the ICO
    function endIco() private {
        icoActive = false;
        emit IcoEnded();
        emit StateUpdated("icoActive", address(0), false);
    }
    
    /**
     * @notice Withdraws all ETH from the contract to the owner's address
     */
    function withdrawETH() external onlyOwner nonReentrant {
        address payable ownerPayable = payable(owner());
        uint256 balance = address(this).balance;
    
        if (balance == 0) revert NoEthToWithdraw();
    
        _safeTransferETH(ownerPayable, balance);
    
        emit EthWithdrawn(ownerPayable, balance);
    }

    /// @notice Fallback function to receive ETH
    receive() external payable {}

    /// @notice Fallback function to handle unexpected calls
    fallback() external payable {
        if (_msgData().length != 0) revert FallbackFunctionOnlyAcceptsETH();
    }

    /**
     * @notice Checks if an address is a holder
     * @param accountAddress The address to check
     * @return isHolder True if the address is a holder, false otherwise
     */
    function _isHolder(address accountAddress) private view returns (bool isHolder) {
        uint256 holdersLength = holders.length;
        for (uint256 i; i < holdersLength; ++i) {
            if (holders[i] == accountAddress) {
                isHolder = true;
            }
        }
        isHolder = false;
    }

    /**
     * @notice Safely transfers ETH to an address
     * @param recipientAddress The address to receive the ETH
     * @param amount The amount of ETH to transfer
     */
    function _safeTransferETH(address recipientAddress, uint256 amount) private nonReentrant {
        // Checks
        if (address(this).balance < amount) revert InsufficientBalance();
        if (recipientAddress == address(0)) revert InvalidRecipientAddress();

        // Effects (update state variables before external calls)
        // but in this case we don't have any

        // Interactions (perform the external call last)
        (bool success, ) = recipientAddress.call{value: amount}("");
        if (!success) revert EthTransferFailed();

        // Event Emission after the transfer
        emit EthTransferred(recipientAddress, amount);
    }

    /**
     * @notice Transfers tokens with tax and burn applied
     * @param senderAddress The address sending the tokens
     * @param recipientAddress The address receiving the tokens
     * @param amount The amount of tokens being transferred
     */
    function _transferWithTaxAndBurn(address senderAddress, address recipientAddress, uint256 amount) private {
        if (senderAddress == address(0)) revert TransferFromZeroAddress();
        if (recipientAddress == address(0)) revert TransferToZeroAddress();

        uint256 burnAmount = amount * BURN_RATE / 100;
        uint256 taxAmount = amount * TAX_RATE / 100;
        uint256 transferAmount = amount - burnAmount - taxAmount;

        _burn(senderAddress, burnAmount);
        _transfer(senderAddress, recipientAddress, transferAmount);

        _safeTransferETH(taxWallet, taxAmount);

        emit TransferWithTaxAndBurn(senderAddress, recipientAddress, amount, burnAmount, taxAmount);
    }

    /**
     * @notice Updates the internal state during transfers
     * @param from The address sending the tokens
     * @param to The address receiving the tokens
     * @param value The amount of tokens being transferred
     */
    function _update(address from, address to, uint256 value) internal override(ERC20Upgradeable, ERC20PausableUpgradeable) {
        super._update(from, to, value);
    }

    /**
     * @notice Transfers tokens with vesting check and normal buy/sell handling
     * @param from The address sending the tokens
     * @param to The address receiving the tokens
     * @param amount The amount of tokens being transferred
     */
    function _transfer(address from, address to, uint256 amount) internal override {
        Vesting[] storage vestings = vestingSchedules[from];
        uint256 vestingsLength = vestings.length;
        for (uint256 i; i < vestingsLength; ++i) {
            if (vestings[i].active && block.timestamp < vestings[i].endTime) {
                revert VestedTokensCannotBeTransferred();
            }
        }

        // Handle normal buy/sell transactions
        if (isBuySell(from, to)) {
            handleNormalBuySell(from, to, amount);
        } else {
            // Handle simple transfers without tax and burn
            super._transfer(from, to, amount);
        }
    }
}