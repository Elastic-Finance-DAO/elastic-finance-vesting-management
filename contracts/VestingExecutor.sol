// SPDX-License-Identifier: MIT

pragma solidity >=0.4.23 <0.9.0;

import "./VestingManager.sol";

contract VestingExecutor is Ownable {
    using SafeMath for uint256;

    // Deploy instance of the VestingManager contract
    VestingManager public vestingManager;

    /* ========== State Variables ========== */

    //Treasury account
    address payable immutable TREASURY =
        payable(0xa9f55E03FE7411501d06532111C92c58ebcA1D83);

    IERC20 public immutable DAI =
        IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    IERC20 public immutable USDC =
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address payable vestingTokenAddress;

    IERC20 public vestingToken = IERC20(vestingTokenAddress);

    uint256 public USDCtoVestingTokenExchangeRate;
    uint256 public DAItoVestingTokenExchangeRate;

    uint256 public constant vestingTokenDecimals = 10**18;
    uint256 public constant USDCDecimals = 10**6;
    uint256 public constant DAIDecimals = 10**18;

    uint256 public vestingTokenPrice; // In USD

    uint256 public purchaseAmountThreshold;

    uint256 public releasePercentage;

    /* ========== Structs ========== */

    /**
     * @notice Vesting parameters struct.
     * @dev This struct holds all necessary parameters for vesting.
     * @param asset The asset that the users are being vested.
     * @param isFixed A flag indicating if these vesting schedules are fixed or not.
     * @param cliffWeeks The number of weeks that the cliff will be present at.
     * @param vestingWeeks The number of weeks the tokens will vest over (linearly).
     * @param startTime The timestamp for when this vesting should have started.
     */

    struct VestingParams {
        address asset;
        bool isFixed;
        uint256 cliffWeeks;
        uint256 vestingWeeks;
        uint256 startTime;
    }

    VestingParams public vestingParams;

    /* ========== Events ========== */

    event vestingOccured(uint256 vestingFee, address vestingRecipient);

    /* ========== Constructor ========== */

    /**
     * @notice Deploys the VestingManager contract and sets the VestingExecutor as the owner of the VestingManager.
     * @dev The VestingExecutor contract initializes the VestingManager contract during its own deployment.
     */
    constructor() {
        // Deploy a new instance of VestingManager, setting VestingExecutor (this contract) as the owner
        vestingManager = new VestingManager(address(this));
    }

    /* ========== Transfer ERC20 tokens ========== */

    //Transfer ERC20 tokens
    function _transferERC20(
        IERC20 token,
        address to,
        uint256 amount
    ) internal {
        uint256 erc20balance = token.balanceOf(address(this));
        require(amount <= erc20balance, "Balance too low to transfer token.");
        token.transfer(to, amount);
    }

    /* ========== Manage minting status ========== */

    //Mint status options
    enum vestingStatus {
        vestingActive, //0
        vestingInactive //1
    }

    //Default mint status: Active
    vestingStatus public current_vesting_status = vestingStatus.vestingActive;

    //Pause/unpause vesting
    function setMintStatus(uint256 _value) public onlyOwner {
        current_vesting_status = vestingStatus(_value);
    }

    //Get current contract vesting status
    function getCurrentVestingStatus() public view returns (vestingStatus) {
        return current_vesting_status;
    }

    // Modifier to only allow vesting when vesting is active
    modifier whenVestingActive() {
        require(
            current_vesting_status == vestingStatus.vestingActive,
            "Vesting is not active"
        );
        _;
    }

    /* ========== Set Vesting Parameters ========== */

    //Set address of vesting token
    function setVestingTokenAddress(address payable _vestingTokenAddress)
        public
        onlyOwner
    {
        vestingTokenAddress = _vestingTokenAddress;
    }

    /**
     * @notice Sets the threshold for the amount of vesting tokens to be purchased.
     * @dev Allows the owner to set a threshold for vesting token purchase. If a user's purchase amount exceeds this threshold, a specified percentage of purchased tokens will be instantly transferred to the user.
     * @param _threshold The new threshold for the amount of vesting tokens to be purchased.
     */

    function setPurchaseAmountThreshold(uint256 _threshold) public onlyOwner {
        purchaseAmountThreshold = _threshold;
    }

    /**
     * @notice Sets the percentage of purchased vesting tokens to be instantly transferred to the user, if a user's purchase amount exceeds the threshold.
     * @dev Allows the owner to set a certain percentage. The percentage is set as a whole number, i.e. for 25%, this would be set to 25. It should not exceed 100.
     * @param _percentage The new percentage of purchased vesting tokens to be instantly transferred to the user, if the purchase amount exceeds the threshold.
     */
    function setReleasePercentage(uint256 _percentage) public onlyOwner {
        require(_percentage <= 100, "Percentage cannot be more than 100");
        releasePercentage = _percentage;
    }

    /**
     * @notice Sets the vesting parameters.
     * @dev This function allows the contract owner to set the parameters used for vesting.
     * @param _vestingParams A struct containing the vesting parameters. The struct should have
     *        the following structure:
     *        ```
     *        {
     *          "asset": "<ADDRESS>", // The address of the token being vested
     *          "isFixed": <BOOLEAN>, // A flag indicating if the vesting schedule is fixed
     *          "cliffWeeks": <NUMBER>, // The number of weeks for the cliff period
     *          "vestingWeeks": <NUMBER>, // The number of weeks over which the tokens will vest
     *          "startTime": <UNIX_TIMESTAMP> // The start timestamp for the vesting
     *        }
     *        ```
     */
    function setVestingParams(VestingParams memory _vestingParams)
        public
        onlyOwner
    {
        vestingParams = _vestingParams;
    }

    /* ========== Set Vesting Token Price and Exchange Rates ========== */

    /**
     * @notice Sets the price of the vesting token.
     * @dev Allows the owner of the contract to set a new price for the vesting token.
     * @param _price The new price of the vesting token.
     */
    function setVestingTokenPrice(uint256 _price) public onlyOwner {
        vestingTokenPrice = _price;
    }

    /* ========== Purchase and Vesting Functions ========== */

    function getVestingManagerAddress() public view returns (address) {
        return address(vestingManager);
    }

    function purchaseVestingToken(uint256 amount, address exchangeToken)
        public
    {
        require(
            exchangeToken == address(DAI) || exchangeToken == address(USDC),
            "Exchange token must be DAI or USDC"
        );

        uint256 requiredAmount = (exchangeToken == address(DAI))
            ? vestingTokenPrice.mul(vestingTokenDecimals).div(DAIDecimals)
            : vestingTokenPrice.mul(vestingTokenDecimals).div(USDCDecimals);

        require(
            amount >= requiredAmount,
            "Not enough tokens sent to exchange for vesting token"
        );

        // Transfer exchangeToken from user to Treasury
        IERC20 token = IERC20(exchangeToken);
        token.transferFrom(msg.sender, TREASURY, amount);

        // Compute purchase amount of vesting token
        uint256 purchaseAmount = amount.mul(vestingTokenDecimals).div(requiredAmount);
        uint256 vestingAmount = purchaseAmount;

        // Check if there are enough vesting tokens in the VestingManager contract
        require(
            IERC20(vestingToken).balanceOf(address(vestingManager)) >=
                purchaseAmount,
            "Not enough vesting tokens available"
        );

        if (purchaseAmount > purchaseAmountThreshold) {
            uint256 amountToRelease = purchaseAmount.mul(releasePercentage).div(100); // Calculate amount to release
            IERC20(vestingToken).transfer(msg.sender, amountToRelease);
            vestingAmount = purchaseAmount.sub(amountToRelease);
        }

        // Vest the tokens for the user
        _vest(msg.sender, vestingAmount);
    }

    /**
     * @notice Sets up a vesting schedule for a user using the Vesting contract.
     * @param account The account that a vesting schedule is being set up for.
     * @param amount The amount of tokens being vested for the user.
     */

    function _vest(address account, uint256 amount) internal whenVestingActive {
        vestingManager.vest(
            account,
            amount,
            vestingParams.asset,
            vestingParams.isFixed,
            vestingParams.cliffWeeks,
            vestingParams.vestingWeeks,
            vestingParams.startTime
        );
    }

    /**
     * @notice Cancel a vesting schedule.
     * @dev If the vesting schedule is cancellable, it transfers the outstanding tokens to the owner of the contract.
     * @param account The account to cancel vesting for.
     * @param scheduleId The id of the vesting schedule.
     */
    function cancelVesting(address account, uint256 scheduleId)
        external
        onlyOwner
    {
        vestingManager.cancelVesting(account, scheduleId);
    }

    /**
     * @notice Withdraws vesting tokens from the VestingManager contract.
     * @dev It only allows withdrawing tokens that are not locked in vesting.
     * @param amount The amount to withdraw.
     * @param asset The token contract address to withdraw from.
     */
    function withdrawVestingTokens(uint256 amount, address asset)
        external
        onlyOwner
    {
        vestingManager.withdrawVestingTokens(amount, asset);
    }

    //End of contract
}
