// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";


/**
 * Vesting contract core functionality from standard Myceleium 
 (formerly Tracer DAO) vesting contract. Original source code 
 available at: https://github.com/tracer-protocol/vesting/blob/master/contracts/Vesting.sol.

 Vesting manager can vest multiple tokens and set up varied vesting schedules based on address. 
 */

contract VestingManager is Ownable {
    /* ========== Structs ========== */

    /**
     * @dev Represents a vesting schedule for an account.
     *
     * @param totalAmount Total amount of tokens that will be vested.
     * @param claimedAmount Amount of tokens that have already been claimed.
     * @param startTime Unix timestamp for the start of the vesting schedule.
     * @param cliffTime The timestamp at which the cliff period ends. No tokens can be claimed before the cliff.
     * @param endTime The timestamp at which the vesting schedule ends. All tokens can be claimed after endTime.
     * @param isFixed Flag indicating if the vesting schedule is fixed or can be modified.
     * @param asset The address of the token being vested.
     */
    struct Schedule {
        uint256 totalAmount;
        uint256 claimedAmount;
        uint256 startTime;
        uint256 cliffTime;
        uint256 endTime;
        bool isFixed;
        address asset;
    }

    /**
     * @dev Represents a summary of a vesting schedule.
     *
     * @param id Unique identifier for the vesting schedule.
     * @param cliffTime The timestamp at which the cliff period ends. No tokens can be claimed before the cliff.
     * @param endTime The timestamp at which the vesting schedule ends. All tokens can be claimed after endTime.
     */
    struct ScheduleInfo {
        uint256 id;
        uint256 cliffTime;
        uint256 endTime;
    }

    /* ========== Mappings ========== */

    // Maps a user address to a schedule ID, which can be used to identify a vesting schedule
    mapping(address => mapping(uint256 => Schedule)) public schedules;

    // Maps a user address to number of schedules created for the account
    mapping(address => uint256) public numberOfSchedules;

    //Provides number of total tokens locked for a specific asset
    mapping(address => uint256) public locked;

    /* ========== Events ========== */

    event Claim(address indexed claimer, uint256 amount);
    event Vest(address indexed to, uint256 amount);
    event Cancelled(address account);

    /* ========== Constructor ========== */
    // Owner will be set to VestingExecutor
    constructor(address initialOwner) {
        transferOwnership(initialOwner);
    }

    /* ========== Vesting Functions ========== */

    /**
     * @notice Sets up a vesting schedule for a set user.
     * @dev Adds a new Schedule to the schedules mapping.
     * @param account The account that a vesting schedule is being set up for. Account will be able to claim tokens post-cliff period
     * @param amount The amount of ERC20 tokens being vested for the user.
     * @param asset The ERC20 asset being vested
     * @param isFixed If true, the vesting schedule cannot be cancelled
     * @param cliffWeeks Important parameter that determines how long the vesting cliff will be. During a cliff, no tokens can be claimed and vesting is paused
     * @param vestingWeeks The number of weeks a token will be vested over (linear in this immplementation)
     * @param startTime The start time for the vesting period ( in UNIX)
     */
    function vest(
        address account,
        uint256 amount,
        address asset,
        bool isFixed,
        uint256 cliffWeeks,
        uint256 vestingWeeks,
        uint256 startTime
    ) public onlyOwner {
        // ensure cliff is shorter than vesting
        require(
            vestingWeeks > 0 && vestingWeeks >= cliffWeeks && amount > 0,
            "Vesting: invalid vesting params"
        );

        uint256 currentLocked = locked[asset];

        // require enough unlocked token is present to vest the desired amount 
        require(
            IERC20(asset).balanceOf(address(this)) >= currentLocked + amount,
            "Vesting: Not enough unlocked supply available to to vest desired amount of tokens"
        );

        // create the schedule
        uint256 currentNumSchedules = numberOfSchedules[account];
        schedules[account][currentNumSchedules] = Schedule(
            amount,
            0,
            startTime,
            startTime + (cliffWeeks * 1 weeks),
            startTime + (vestingWeeks * 1 weeks),
            isFixed,
            asset
        );

        numberOfSchedules[account] = currentNumSchedules + 1; //Update number of schedules
        locked[asset] = currentLocked + amount; //Update amount of asset locked in vesting schedule

        emit Vest(account, amount);
    }

    /**
     * @notice Returns information about all vesting schedules for a given account
     * @param account The address of the account for which to return vesting schedule information
     * @return An array of ScheduleInfo structs, each containing the ID, cliff timestamp, and end timestamp for a vesting schedule (related to the account)
     */
    function getScheduleInfo(address account)
        public
        view
        returns (ScheduleInfo[] memory)
    {
        uint256 count = numberOfSchedules[account];
        ScheduleInfo[] memory scheduleInfoList = new ScheduleInfo[](count);
        for (uint256 i = 0; i < count; i++) {
            scheduleInfoList[i] = ScheduleInfo(
                i,
                schedules[account][i].cliffTime,
                schedules[account][i].endTime
            );
        }
        return scheduleInfoList;
    }

    /**
     * @notice Post-cliff period, users can claim their tokens
     * @param scheduleNumber which schedule the user is claiming against
     */
    function claim(uint256 scheduleNumber) external {
        Schedule storage schedule = schedules[msg.sender][scheduleNumber];
        require(
            schedule.cliffTime <= block.timestamp,
            "Vesting: cliff not reached"
        );
        require(schedule.totalAmount > 0, "Vesting: Token not claimable");

        // Get the amount to be distributed
        uint256 amount = calcVestingDistribution(
            schedule.totalAmount,
            block.timestamp,
            schedule.startTime,
            schedule.endTime
        );

        // Caps the claim amount to the total amount allocated to be vested to the address 
        amount = amount > schedule.totalAmount ? schedule.totalAmount : amount;
        uint256 amountToTransfer = amount - schedule.claimedAmount;
        schedule.claimedAmount = amount; // set new claimed amount based off the curve
        locked[schedule.asset] = locked[schedule.asset] - amountToTransfer;
        require(
            IERC20(schedule.asset).transfer(msg.sender, amountToTransfer),
            "Vesting: transfer failed"
        );
        emit Claim(msg.sender, amount);
    }

    /**
     * @notice Allows a vesting schedule to be cancelled.
     * @dev Any outstanding tokens are returned to the system.
     * @param account the account of the user whos vesting schedule is being cancelled.
     * @param scheduleId the schedule ID of the vesting schedule being cancelled
     */
    function cancelVesting(address account, uint256 scheduleId)
        external
        onlyOwner
    {
        Schedule storage schedule = schedules[account][scheduleId];
        require(!schedule.isFixed, "Vesting: Account is fixed");
        uint256 outstandingAmount = schedule.totalAmount -
            schedule.claimedAmount;
        require(outstandingAmount != 0, "Vesting: no outstanding tokens");
        schedule.totalAmount = 0;
        locked[schedule.asset] = locked[schedule.asset] - outstandingAmount;
        require(
            IERC20(schedule.asset).transfer(owner(), outstandingAmount),
            "Vesting: transfer failed"
        );
        emit Cancelled(account);
    }

    /**
     * @return calculates the amount of tokens to distribute to an account at any instance in time, based off some
     *         total claimable amount.
     * @param amount the total outstanding amount to be claimed for this vesting schedule.
     * @param currentTime the current timestamp.
     * @param startTime the timestamp this vesting schedule started.
     * @param endTime the timestamp this vesting schedule ends.
     */
    function calcVestingDistribution(
        uint256 amount,
        uint256 currentTime,
        uint256 startTime,
        uint256 endTime
    ) public pure returns (uint256) {
        // avoid uint underflow
        if (currentTime < startTime) {
            return 0;
        }

        // if endTime < startTime, this will throw. Since endTime should never be
        // less than startTime in safe operation, this is fine.
        return (amount * (currentTime - startTime)) / (endTime - startTime);
    }

    /**
     * @notice Withdraws vesting tokens from the contract.
     * @dev blocks withdrawing locked tokens.
     */
    function withdrawVestingTokens(uint256 amount, address asset)
        external
        onlyOwner
    {
        IERC20 token = IERC20(asset);
        require(
            token.balanceOf(address(this)) - locked[asset] >= amount,
            "Vesting: Can't withdraw"
        );
        require(token.transfer(owner(), amount), "Vesting: withdraw failed");
    }

    //End of contract
}
