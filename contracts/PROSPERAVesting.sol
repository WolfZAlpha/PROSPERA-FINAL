// SPDX-License-Identifier: PROPRIETARY
pragma solidity 0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title PROSPERA Vesting Contract
/// @notice This contract handles vesting functionality for the PROSPERA token
/// @dev This contract is upgradeable and uses the UUPS proxy pattern
/// @custom:security-contact security@prosperadefi.com
contract PROSPERAVesting is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {

    /// @notice Address of the PROSPERA token contract
    address public prosperaToken;

    /// @notice Struct to define a vesting schedule
    /// @param startTime The start time of the vesting period
    /// @param endTime The end time of the vesting period
    /// @param active Whether the vesting schedule is active
    /// @param vestingType The type of vesting schedule (0 for marketing team, 1 for PROSPERA team)
    /// @param totalAmount The total amount of tokens to be vested
    /// @param releasedAmount The amount of tokens already released
    struct Vesting {
        uint256 startTime;
        uint256 endTime;
        bool active;
        uint8 vestingType;
        uint256 totalAmount;
        uint256 releasedAmount;
    }

    /// @notice Mapping of vesting schedules for addresses
    mapping(address user => Vesting vestingInfo) public vestingSchedules;

    // Events
    /// @notice Emitted when a vesting schedule is added
    event VestingAdded(address indexed user, uint256 startTime, uint256 endTime, uint256 amount, uint8 vestingType);

    /// @notice Emitted when vested tokens are released
    event VestingReleased(address indexed user, uint256 amount);

    // Errors
    /// @notice Error for vesting not being active
    error VestingNotActive();
    
    /// @notice Error for vesting period not ended
    error VestingPeriodNotEnded();

    /// @notice Error for invalid vesting type
    error InvalidVestingType();

    /// @notice Error for attempting to transfer vested tokens before vesting is complete
    error VestedTokensCannotBeTransferred();

    /// @notice Error for caller not being the PROSPERA contract
    error CallerNotProsperaContract();

    /// @notice Error for invalid address
    error InvalidAddress();

    /// @notice Error for no tokens to release
    error NoTokensToRelease();

    /// @notice Ensures that only the PROSPERA contract can call the function
    modifier onlyPROSPERA() {
        if (msg.sender != prosperaToken) revert CallerNotProsperaContract();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract
     * @param _prosperaToken Address of the PROSPERA token contract
     */
    function initialize(address _prosperaToken) initializer public {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        if (_prosperaToken == address(0)) revert InvalidAddress();
        prosperaToken = _prosperaToken;
    }

    /**
     * @notice Authorizes an upgrade to a new implementation
     * @dev This function is left empty but is required by the UUPSUpgradeable contract
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Adds an address to the vesting schedule
     * @dev Can only be called by the PROSPERA contract
     * @param account The address to be added to the vesting schedule
     * @param amount The amount of tokens to be vested
     * @param vestingType The type of vesting schedule (0 for marketing team, 1 for PROSPERA team)
     * @return success True if the address was successfully added to the vesting schedule
     */
    function addToVesting(address account, uint256 amount, uint8 vestingType) external onlyPROSPERA nonReentrant returns (bool success) {
        if (account == address(0)) revert InvalidAddress();

        uint256 startTime = block.timestamp;
        uint256 endTime;

        if (vestingType == 0) {
            endTime = startTime + 120 days; // 4 months for marketing team
        } else if (vestingType == 1) {
            endTime = startTime + 90 days; // 3 months for PROSPERA team
        } else {
            revert InvalidVestingType();
        }

        vestingSchedules[account] = Vesting({
            startTime: startTime,
            endTime: endTime,
            active: true,
            vestingType: vestingType,
            totalAmount: amount,
            releasedAmount: 0
        });

        emit VestingAdded(account, startTime, endTime, amount, vestingType);

        success = true;
    }

    /**
     * @notice Calculates the vested amount for a given account
     * @param account The address for which to calculate the vested amount
     * @return vestedAmount The amount of tokens that have vested for the given account
     */
    function _vestedAmount(address account) private view returns (uint256 vestedAmount) {
        Vesting memory vesting = vestingSchedules[account];
        if (!vesting.active || block.timestamp < vesting.startTime) {
            vestedAmount = 0;
        } else if (block.timestamp >= vesting.endTime) {
            vestedAmount = vesting.totalAmount;
        } else {
            vestedAmount = (vesting.totalAmount * (block.timestamp - vesting.startTime)) / (vesting.endTime - vesting.startTime);
        }
        vestedAmount = vestedAmount - vesting.releasedAmount;
    }

    /**
     * @notice Releases vested tokens for an address
     * @dev Can only be called by the PROSPERA contract
     * @param account The address to release tokens for
     * @return amountToRelease The amount of tokens released
    */
    function releaseVestedTokens(address account) external onlyPROSPERA nonReentrant returns (uint256 amountToRelease) {
        Vesting storage vesting = vestingSchedules[account];
        if (!vesting.active) revert VestingNotActive();
        
        amountToRelease = _vestedAmount(account);
        if (amountToRelease == 0) revert NoTokensToRelease();

        vesting.releasedAmount += amountToRelease;
        if (vesting.releasedAmount >= vesting.totalAmount) {
            vesting.active = false;
        }

        emit VestingReleased(account, amountToRelease);
    }

    /**
     * @notice Checks if a token transfer is allowed based on vesting schedule
     * @param account The address to check
     * @return isVested True if the tokens are vested and can be transferred, false otherwise
     */
    function isVestedTokenTransfer(address account) external view returns (bool isVested) {
        Vesting memory vesting = vestingSchedules[account];
        isVested = !vesting.active || block.timestamp >= vesting.endTime;
    }

    /**
     * @notice Gets the vesting schedule for a given account
     * @param account The address to check
     * @return startTime The start time of the vesting schedule
     * @return endTime The end time of the vesting schedule
     * @return active Whether the vesting schedule is active
     * @return vestingType The type of vesting schedule
     * @return totalAmount The total amount of tokens to be vested
     * @return releasedAmount The amount of tokens already released
     */
    function getVestingSchedule(address account) external view returns (
        uint256 startTime,
        uint256 endTime,
        bool active,
        uint8 vestingType,
        uint256 totalAmount,
        uint256 releasedAmount
    ) {
        Vesting memory vesting = vestingSchedules[account];
        return (
            vesting.startTime,
            vesting.endTime,
            vesting.active,
            vesting.vestingType,
            vesting.totalAmount,
            vesting.releasedAmount
        );
    }

    /**
     * @notice Calculates the current vested amount for a given account
     * @param account The address to check
     * @return vestedAmount The current vested amount
     */
    function getCurrentVestedAmount(address account) external view returns (uint256 vestedAmount) {
        vestedAmount = _vestedAmount(account);
    }
}