// SPDX-License-Identifier: PROPRIETARY
pragma solidity 0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";

/// @title PROSPERA Math Contract
/// @notice This contract handles complex mathematical operations for the PROSPERA ecosystem
/// @dev This contract is upgradeable and uses the UUPS proxy pattern
/// @custom:security-contact security@prosperadefi.com
contract PROSPERAMath is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {

    /// @notice Address of the main PROSPERA contract
    address public prosperaContract;

    /// @notice Struct for high-precision integer arithmetic
    struct Int512 {
        int256 high;
        int256 low;
    }

    /// @notice Number of seconds in a day, represented in 64.64 fixed point
    int128 private constant SECONDS_PER_DAY = 0x545ac0000000000000; // 86400 in 64x64 fixed point

    /// @notice Offset for Unix epoch in Julian days, represented in 64.64 fixed point
    int128 private constant OFFSET19700101 = 0x24bd0000000000000000; // 2440588 in 64x64 fixed point

    /// @notice Leap second table (Unix timestamps of leap seconds)
    uint256[] private leapSeconds;

    // Errors
    error NotProsperaContract();
    error DivisionByZero();

    /// @notice Ensures that only the PROSPERA contract can call the function
    modifier onlyPROSPERA() {
        if (msg.sender != prosperaContract) revert NotProsperaContract();
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

        // Initialize leap seconds table
        leapSeconds = [
            78796800, 94694400, 126230400, 157766400, 189302400, 220924800, 252460800, 283996800, 315532800,
            362793600, 394329600, 425865600, 489024000, 567993600, 631152000, 662688000, 709948800, 741484800,
            773020800, 820454400, 867715200, 915148800, 1136073600, 1230768000, 1341100800, 1435708800, 1483228800
        ];
    }

    /// @notice Authorizes an upgrade to a new implementation
    /// @dev This function is left empty but is required by the UUPSUpgradeable contract
    /// @param newImplementation Address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice Converts a timestamp to a date with maximum precision
    /// @param timestamp The timestamp to convert (in seconds since Unix epoch)
    /// @return year The year
    /// @return month The month (1-12)
    /// @return day The day of the month (1-31)
    /// @return hour The hour (0-23)
    /// @return minute The minute (0-59)
    /// @return second The second (0-59)
    /// @return millisecond The millisecond (0-999)
    function timestampToDate(uint256 timestamp) public view onlyPROSPERA returns (
        uint256 year,
        uint256 month,
        uint256 day,
        uint256 hour,
        uint256 minute,
        uint256 second,
        uint256 millisecond
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

        Int512 memory j = addInt512(julianDay, Int512(0, int256(32044)));
        Int512 memory g = divideInt512(j, Int512(0, int256(146097)));
        Int512 memory dg = subtractInt512(j, multiplyInt512(Int512(0, int256(146097)), g));

        (year, month, day) = calculateYearMonthDay(g, dg);

        uint256 secondsOfDay = wholeSeconds % 86400;
        hour = secondsOfDay / 3600;
        minute = (secondsOfDay % 3600) / 60;
        second = secondsOfDay % 60;
    }

    /// @notice Calculates the year, month, and day from Julian day components
    /// @param g A component of the Julian day calculation
    /// @param dg Another component of the Julian day calculation
    /// @return year The calculated year
    /// @return month The calculated month (1-12)
    /// @return day The calculated day of the month (1-31)
    function calculateYearMonthDay(Int512 memory g, Int512 memory dg) public pure returns (uint256 year, uint256 month, uint256 day) {
        Int512 memory c = divideInt512(
            multiplyInt512(subtractInt512(dg, Int512(0, int256(1))), Int512(0, int256(3))),
            Int512(0, int256(4))
        );
        Int512 memory d = subtractInt512(dg, multiplyInt512(c, Int512(0, int256(4))));
        Int512 memory m = divideInt512(
            multiplyInt512(subtractInt512(d, Int512(0, int256(1))), Int512(0, int256(5))),
            Int512(0, int256(153))
        );
        Int512 memory n = addInt512(
            multiplyInt512(Int512(0, int256(100)), g),
            divideInt512(m, Int512(0, int256(16)))
        );
        Int512 memory _year = subtractInt512(n, Int512(0, int256(4800)));
        Int512 memory _month = subtractInt512(
            subtractInt512(m, Int512(0, int256(2))),
            multiplyInt512(Int512(0, int256(12)), divideInt512(m, Int512(0, int256(10))))
        );
        Int512 memory _day = subtractInt512(
            subtractInt512(d, multiplyInt512(Int512(0, int256(153)), m)),
            Int512(0, int256(2))
        );

        year = uint256(_year.low);
        month = uint256(_month.low);
        day = uint256(_day.low);
    }

    /// @notice Adds two Int512 numbers
    /// @param a The first Int512 number
    /// @param b The second Int512 number
    /// @return The result of a + b as an Int512
    function addInt512(Int512 memory a, Int512 memory b) public pure returns (Int512 memory) {
        int256 lowSum = a.low + b.low;
        int256 highSum = a.high + b.high + (lowSum < a.low ? int256(1) : int256(0));
        return Int512(highSum, lowSum);
    }

    /// @notice Subtracts one Int512 number from another
    /// @param a The Int512 number to subtract from
    /// @param b The Int512 number to subtract
    /// @return The result of a - b as an Int512
    function subtractInt512(Int512 memory a, Int512 memory b) public pure returns (Int512 memory) {
        int256 lowDiff = a.low - b.low;
        int256 highDiff = a.high - b.high - (lowDiff > a.low ? int256(1) : int256(0));
        return Int512(highDiff, lowDiff);
    }

    /// @notice Multiplies two Int512 numbers
    /// @param a The first Int512 number
    /// @param b The second Int512 number
    /// @return The result of a * b as an Int512
    function multiplyInt512(Int512 memory a, Int512 memory b) public pure returns (Int512 memory) {
        int256 low = a.low * b.low;
        int256 high = a.high * b.low + a.low * b.high + ((a.low >> 128) * (b.low >> 128));
        return Int512(high, low);
    }

    /// @notice Divides one Int512 number by another
    /// @param a The Int512 number to be divided
    /// @param b The Int512 number to divide by
    /// @return The result of a / b as an Int512
    function divideInt512(Int512 memory a, Int512 memory b) public pure returns (Int512 memory) {
        if (b.high == 0 && b.low == 0) revert DivisionByZero();
        int256 aAbs = a.high < 0 ? -a.high : a.high;
        int256 bAbs = b.high < 0 ? -b.high : b.high;
        int256 quot = (aAbs << 128 | (a.low < 0 ? -a.low : a.low)) / (bAbs << 128 | (b.low < 0 ? -b.low : b.low));
        bool negative = (a.high < 0) != (b.high < 0);
        return Int512(negative ? -int256(uint256(quot) >> 128) : int256(uint256(quot) >> 128), negative ? -int256(uint256(quot) & ((1 << 128) - 1)) : int256(uint256(quot) & ((1 << 128) - 1)));
    }

    /// @notice Adjusts a timestamp for leap seconds
    /// @param timestamp The timestamp to adjust
    /// @return adjustedTimestamp The timestamp adjusted for leap seconds
    function adjustForLeapSeconds(uint256 timestamp) public view returns (uint256 adjustedTimestamp) {
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
        adjustedTimestamp = timestamp - leapSecondsCount;
    }

    /// @notice Checks if the current timestamp is the start of a new quarter
    /// @param timestamp The timestamp to check
    /// @return quarterStart True if it is the start of a new quarter, false otherwise
    function isQuarterStart(uint256 timestamp) public view onlyPROSPERA returns (bool quarterStart) {
        (uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second, uint256 millisecond) = timestampToDate(timestamp);

        bool isQuarterMonth = (month == 1 || month == 4 || month == 7 || month == 10);
        bool isFirstDay = (day == 1);

        if (isLeapYear(year)) {
            if (month == 4 && day == 1) {
                quarterStart = hour == 0 && minute == 0 && second == 0 && millisecond == 0;
                return quarterStart;
            }
        }

        quarterStart = isQuarterMonth && isFirstDay && hour == 0 && minute == 0 && second == 0 && millisecond == 0;
    }

    /// @notice Checks if a given year is a leap year
    /// @param year The year to check
    /// @return True if it's a leap year, false otherwise
    function isLeapYear(uint256 year) public pure returns (bool) {
        return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
    }
}