// SPDX-License-Identifier: MIT

pragma solidity >=0.4.23 <0.9.0;

import "../interfaces/IVesting.sol";

contract VestingManager is Ownable {
    //Contains information about the vesting schedule for accounts
    struct Schedule {
        uint256 totalAmount;
        uint256 claimedAmount;
        uint256 startTime;
        uint256 cliffTime;
        uint256 endTime;
        bool isFixed;
        address asset;
    }

    //Contains information about a specific vesting schedule (by schedule ID)
    struct ScheduleInfo {
        uint256 id;
        uint256 cliffTime;
        uint256 endTime;
    }

    // Maps a user address to a schedule ID, which can be used to identify a vesting schedule
    mapping(address => mapping(uint256 => Schedule)) public schedules;
    mapping(address => uint256) public numberOfSchedules;

    mapping(address => uint256) public locked;

    event Claim(address indexed claimer, uint256 amount);
    event Vest(address indexed to, uint256 amount);
    event Cancelled(address account);

    constructor(address initialOwner) {
        transferOwnership(initialOwner);
    }

    /**
     * @notice Sets up a vesting schedule for a set user.
     * @dev Adds a new Schedule to the schedules mapping.
     * @param account The account that a vesting schedule is being set up for. Account will be able to claim tokens post-cliff period
     * @param amount The amount of ERC20 tokens being vested for the user.
     * @param asset The ERC20 asset being vested
     * @param isFixed If true, the vesting schedule cannot be cancelled
     * @param cliffWeeks Important parameter that determines how long the vesting cliff will be. During a cliff, no tokens can be claimed and vesting is paused
     * @param vestingWeeks The number of weeks a token will be vested over (linear in this immplementation)
     * @param startTime The start time for the vesting period
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

        // require the token is present
        require(
            IERC20(asset).balanceOf(address(this)) >= currentLocked + amount,
            "Vesting: Not enough tokens"
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
        numberOfSchedules[account] = currentNumSchedules + 1;
        locked[asset] = currentLocked + amount;
        emit Vest(account, amount);
    }

    /**
     * @notice Can be used to set up multiple vesting schedules at once for a group of accounts
     * @dev Adds a new Schedule to the schedules mapping.
     * @param accounts List of accounts a vesting schedule is being set up for
     *                  Accounts will be able to claim tokens post-cliff period
     * @param amount Array of the amount of tokens being vested for each user.
     * @param asset The ERC20 asset being vested
     * @param isFixed If true, the vesting schedule cannot be cancelled
     * @param cliffWeeks Important parameter that determines how long the vesting cliff will be. During a cliff, no tokens can be claimed and vesting is paused
     * @param vestingWeeks The number of weeks a token will be vested over (linear in this immplementation)
     * @param startTime The start time for the vesting period
     */
    function multiVest(
        address[] calldata accounts,
        uint256[] calldata amount,
        address asset,
        bool isFixed,
        uint256 cliffWeeks,
        uint256 vestingWeeks,
        uint256 startTime
    ) external onlyOwner {
        uint256 numberOfAccounts = accounts.length;
        require(
            amount.length == numberOfAccounts,
            "Vesting: Array lengths differ"
        );
        for (uint256 i = 0; i < numberOfAccounts; i++) {
            vest(
                accounts[i],
                amount[i],
                asset,
                isFixed,
                cliffWeeks,
                vestingWeeks,
                startTime
            );
        }
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
        uint256 amount = calcDistribution(
            schedule.totalAmount,
            block.timestamp,
            schedule.startTime,
            schedule.endTime
        );

        // Cap the amount at the total amount
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
     */
    function rug(address account, uint256 scheduleId) external onlyOwner {
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
    function calcDistribution(
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
    function withdraw(uint256 amount, address asset) external onlyOwner {
        IERC20 token = IERC20(asset);
        require(
            token.balanceOf(address(this)) - locked[asset] >= amount,
            "Vesting: Can't withdraw"
        );
        require(token.transfer(owner(), amount), "Vesting: withdraw failed");
    }
}
