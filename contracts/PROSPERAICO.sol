// SPDX-License-Identifier: PROPRIETARY
pragma solidity 0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title PROSPERA ICO Contract
/// @notice This contract handles ICO functionality for the PROSPERA token
/// @dev This contract is upgradeable and uses the UUPS proxy pattern
/// @custom:security-contact security@prosperadefi.com
contract PROSPERAICO is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {

    /// @notice Address of the main PROSPERA contract
    address public prosperaContract;

    /// @notice Enum to define ICO tiers
    enum IcoTier { Tier1, Tier2, Tier3 }

    /// @notice Tokens allocated for the ICO
    uint256 private constant ICO_SUPPLY = 1e9 * 10**18 * 15375 / 100000; // 15.375% of total supply

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

    /// @notice Wallet address for ICO funds
    address public icoWallet;

    /// @notice Wallet address for ICO supply
    address public prosicoWallet;

    /// @notice Tax rate applied during the ICO (percentage)
    uint256 public constant ICO_TAX_RATE = 9;

    /// @notice Minimum amount of ETH required to participate in the ICO
    uint256 public constant MIN_ICO_BUY = 150 ether;

    /// @notice Maximum amount of ETH that can be used by a single wallet to buy tokens in the ICO
    uint256 public constant MAX_ICO_BUY = 500000 ether;

    /// @notice Mapping of ICO purchases
    mapping(address buyer => uint256 purchaseAmount) private _icoBuys;

    // Events
    /// @notice Emitted when tokens are purchased during the ICO
    /// @param buyer The address of the buyer
    /// @param amount The amount of tokens purchased
    /// @param price The price of the tokens
    event TokensPurchased(address indexed buyer, uint256 amount, uint256 price);

    /// @notice Emitted when the ICO ends
    event IcoEnded();

    /// @notice Emitted when the ICO tier changes
    /// @param newTier The new ICO tier
    event IcoTierChanged(IcoTier indexed newTier);

    /// @notice Emitted when a user's ICO purchase is updated
    /// @param buyer The address of the buyer
    /// @param newBuyAmount The new ICO purchase amount
    event IcoBuyUpdated(address indexed buyer, uint256 newBuyAmount);

    /// @notice Emitted when the number of tokens sold in an ICO tier is updated
    /// @param tier The ICO tier
    /// @param soldAmount The number of tokens sold
    event TierSoldUpdated(IcoTier indexed tier, uint256 soldAmount);

    /// @notice Emitted when the current ICO tier is updated
    /// @param newTier The new ICO tier
    event CurrentTierUpdated(IcoTier indexed newTier);

    // Errors
    /// @notice Error for not the PROSPERA contract
    error NotProsperaContract();

    /// @notice Error for not active ICO
    error IcoNotActive();

    /// @notice Error for below minimum ICO buy limit
    error BelowMinIcoBuyLimit();

    /// @notice Error for exceeding maximum ICO buy limit
    error ExceedsMaxIcoBuyLimit();

    /// @notice Error for invalid ICO tier
    error InvalidIcoTier();

    /// @notice Error for incorrect ETH amount sent
    error IncorrectETHAmountSent();

    /// @notice Error for insufficient funds for purchase
    error InsufficientFundsForPurchase();

    /// @notice Error for invalid address
    error InvalidAddress();

    /// @notice Ensures that only the PROSPERA contract can call the function
    modifier onlyPROSPERA() {
        if (msg.sender != prosperaContract) revert NotProsperaContract();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract
     * @param _prosperaContract Address of the PROSPERA token contract
     * @param _icoWallet Address of the ICO wallet
     * @param _prosicoWallet Address of the prosico wallet
     */
    function initialize(address _prosperaContract, address _icoWallet, address _prosicoWallet) initializer public {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        if (_prosperaContract == address(0) || _icoWallet == address(0) || _prosicoWallet == address(0)) revert InvalidAddress();
        prosperaContract = _prosperaContract;
        icoWallet = _icoWallet;
        prosicoWallet = _prosicoWallet;
    }

    /**
     * @notice Authorizes an upgrade to a new implementation
     * @dev This function is left empty but is required by the UUPSUpgradeable contract
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Purchases tokens during the ICO
     * @dev This function handles the token purchase process, including tax calculation and dynamic tier transitions
     * @param buyer The address of the buyer
     * @param tokenAmount The number of tokens to purchase
     * @return tokensBought The number of tokens bought
     * @return totalCost The total cost in ETH
     */
    function buyTokens(address buyer, uint256 tokenAmount) external payable onlyPROSPERA nonReentrant returns (uint256 tokensBought, uint256 totalCost) {
        if (!icoActive) revert IcoNotActive();
    
        uint256 ethValue = msg.value;

        // Check minimum and maximum buy limit
        if (ethValue < MIN_ICO_BUY) revert BelowMinIcoBuyLimit();
        if (_icoBuys[buyer] + ethValue > MAX_ICO_BUY) revert ExceedsMaxIcoBuyLimit();

        // Calculate the ICO tax
        uint256 totalTaxAmount = ethValue * ICO_TAX_RATE / 100;
        uint256 remainingEth = ethValue - totalTaxAmount;

        (tokensBought, totalCost) = buyFromCurrentTier(tokenAmount, remainingEth);

        if (tokensBought == 0) revert InsufficientFundsForPurchase();
        if (remainingEth < totalCost) revert IncorrectETHAmountSent();

        // Update state
        _icoBuys[buyer] += totalCost;
        emit IcoBuyUpdated(buyer, _icoBuys[buyer]);

        emit TokensPurchased(buyer, tokensBought, totalCost);

        // Transfer ETH to ICO wallet and tax wallet
        payable(icoWallet).transfer(totalCost);
        payable(owner()).transfer(totalTaxAmount); // Assuming owner is the tax wallet

        // Return excess ETH if any
        if (remainingEth > totalCost) {
            payable(buyer).transfer(remainingEth - totalCost);
        }
    }

    /**
     * @notice Buys tokens from the current ICO tier and handles transitions between tiers
     * @dev This function handles purchasing across multiple tiers if necessary
     * @param tokensToBuy The number of tokens attempting to buy
     * @param availableEth The amount of ETH available for the purchase
     * @return totalTokensBought The total number of tokens successfully purchased
     * @return totalTierCost The total cost of the purchased tokens
     */
    function buyFromCurrentTier(uint256 tokensToBuy, uint256 availableEth) private returns (uint256 totalTokensBought, uint256 totalTierCost) {
        while (tokensToBuy > 0 && availableEth > 0 && icoActive) {
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
            uint256 tokensBought = (tokensToBuy < availableTokens) ? tokensToBuy : availableTokens;
        
            uint256 tierCost = (tokensBought * tierPrice + 10**18 - 1) / 10**18;

            if (tierCost > availableEth) {
                tokensBought = (availableEth * 10**18 + tierPrice - 1) / tierPrice;
                tierCost = (tokensBought * tierPrice + 10**18 - 1) / 10**18;
            }

            totalTokensBought += tokensBought;
            totalTierCost += tierCost;
            tokensToBuy -= tokensBought;
            availableEth -= tierCost;

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
    }

    /// @notice Updates the ICO tier
    /// @param newTier The new ICO tier to set
    function updateIcoTier(IcoTier newTier) private {
        currentTier = newTier;
        emit IcoTierChanged(newTier);
        emit CurrentTierUpdated(newTier);
    }

    /// @notice Ends the ICO
    function endIco() public onlyOwner {
        icoActive = false;
        emit IcoEnded();
    }

    /**
     * @notice Gets the current ICO state
     * @return _icoActive Whether the ICO is active
     * @return _currentTier The current ICO tier
     * @return _tier1Sold The number of tokens sold in Tier 1
     * @return _tier2Sold The number of tokens sold in Tier 2
     * @return _tier3Sold The number of tokens sold in Tier 3
     */
    function getIcoState() external view returns (
        bool _icoActive,
        IcoTier _currentTier,
        uint256 _tier1Sold,
        uint256 _tier2Sold,
        uint256 _tier3Sold
    ) {
        return (icoActive, currentTier, tier1Sold, tier2Sold, tier3Sold);
    }

    /**
     * @notice Gets the total amount of ETH a buyer has spent in the ICO
     * @param buyer The address of the buyer
     * @return amount The total amount spent by the buyer
     */
    function getBuyerPurchaseAmount(address buyer) external view returns (uint256 amount) {
        return _icoBuys[buyer];
    }
}