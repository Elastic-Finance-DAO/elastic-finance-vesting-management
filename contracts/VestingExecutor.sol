// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.9;

import "./VestingManager.sol";

contract VestingExecutor is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== State Variables ========== */

    address payable immutable TREASURY =
        payable(0xf950a86013bAA227009771181a885E369e158da3);

    IERC20 public immutable DAI =
        IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    IERC20 public immutable USDC =
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address vestingTokenAddress;

    IERC20 public vestingToken = IERC20(vestingTokenAddress);

    uint256 public constant vestingTokenDecimals = 10**18;

    uint256 public constant USDCDecimals = 10**6;

    uint256 public constant DAIDecimals = 10**18;

    uint256 public vestingTokenPrice; // In USD

    uint256 public purchaseAmountThreshold; // Amount of vesting token that must be purchased to trigger immediate release of coins

    uint256 public releasePercentage; // Percentage of total amount that will be released

    address public authorizedSwapTokenAddress; //Token that can be swapped for vesting token (which will be vested on behalf of the user)

    IERC20 public swapToken = IERC20(authorizedSwapTokenAddress);

    uint256 public ratioNumerator; // Numeroator of ratio that will determine how many swap tokens can be exchanged for vesting tokens
    uint256 public ratioDenominator; // Numerator of ratio that will determine how many swap tokens can be exchanged for vesting tokens

    VestingManager public vestingManager; // Vesting Manager contract

    /* ========== Structs ========== */

    /**
     * @notice Vesting parameters struct.
     * @dev This struct holds all necessary parameters for vesting.
     * @param asset The asset that the users are being vested.
     * @param isFixed If true, the vesting schedule cannot be cancelled
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

    event vestingTransactionComplete(address vester, uint256 vestedAssetAmount);
    event vestingParamsSet(
        address asset,
        bool isFixed,
        uint256 cliffWeeks,
        uint256 vestingWeeks,
        uint256 startTime
    );

    event vestingTokenWithdrawal(address token, uint256 withdrawalAmount);

    event processLog(string description, uint256 number);
    event processLog2(string message);
    event processLog3(address address2);

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

    function transferERC20(
        IERC20 token,
        address to,
        uint256 amount
    ) external onlyOwner {
        uint256 erc20balance = token.balanceOf(address(this));
        require(amount <= erc20balance, "Balance too low to transfer token.");
        token.transfer(to, amount);
    }

    /* ========== Manage vesting/swap status ========== */

    //Vesting status options
    enum vestingStatus {
        vestingActive, //0
        vestingInactive //1
    }

    //Default vesting status: Active
    vestingStatus public current_vesting_status = vestingStatus.vestingActive;

    //Pause/unpause vesting
    function setVestingStatus(uint256 _value) public onlyOwner {
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

    //Swapping status options
    enum swappingStatus {
        swappingActive, //0
        swappingInactive //1
    }

    //Default vesting status: Inactive
    swappingStatus public current_swapping_status =
        swappingStatus.swappingInactive;

    //Pause/unpause swapping
    function setSwappingStatus(uint256 _value) public onlyOwner {
        current_swapping_status = swappingStatus(_value);
    }

    //Get current contract swapping status
    function getCurrentSwappingStatus() public view returns (swappingStatus) {
        return current_swapping_status;
    }

    // Modifier to only allow swapping when swapping is active
    modifier whenSwappingActive() {
        require(
            current_swapping_status == swappingStatus.swappingActive,
            "Swapping is not active"
        );
        _;
    }

    /* ========== Set Vesting Parameters ========== */

    /**
     * @notice Changes the address of the vesting token
     * @dev Can only be executed by the owner of the contract
     * @param _vestingTokenAddress The address of the new vesting token
     */
    function setVestingTokenAddress(address _vestingTokenAddress)
        public
        onlyOwner
    {
        vestingTokenAddress = _vestingTokenAddress;
        vestingToken = IERC20(vestingTokenAddress);
    }

    /**
     * @notice Changes the address of the swap token
     * @dev Can only be executed by the owner of the contract
     * @param _swapTokenAddress The address of the new swap token
     */
    function setSwapTokenAddress(address _swapTokenAddress) public onlyOwner {
        authorizedSwapTokenAddress = _swapTokenAddress;
        swapToken = IERC20(vestingTokenAddress);
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
     * @notice Sets the swap ratio for the vesting to swap token conversion
     * @dev Can only be executed by the owner of the contract
     * @param _ratioNumerator The numerator part of the ratio
     * @param _ratioDenominator The denominator part of the ratio
     */
    function setSwapRatio(uint256 _ratioNumerator, uint256 _ratioDenominator)
        public
        onlyOwner
    {
        ratioNumerator = _ratioNumerator;
        ratioDenominator = _ratioDenominator;
    }

    /**
     * @notice Sets the vesting parameters globally. Should be re-set for each stage of vesting
     * @dev This function allows the contract owner to set the parameters used for vesting. Can only be executed by the owner of the contract
     * @param _vestingParams A struct containing the vesting parameters. The struct should have
     *        the following structure:
     *        ```
     *        {
     *          "asset": "<ADDRESS>", // The address of the token being vested
     *          "isFixed": <BOOLEAN>, // A flag indicating if the vesting schedule is fixed (can be adjusted)
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
        // Ensure cliff is shorter than vesting (vesting includes the cliff duration)
        require(
            _vestingParams.vestingWeeks > 0 &&
                _vestingParams.vestingWeeks >= _vestingParams.cliffWeeks,
            "Vesting: invalid vesting params set"
        );

        vestingParams = _vestingParams;

        // Emit the event after the vestingParams have been updated
        emit vestingParamsSet(
            _vestingParams.asset,
            _vestingParams.isFixed,
            _vestingParams.cliffWeeks,
            _vestingParams.vestingWeeks,
            _vestingParams.startTime
        );
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

    /**
     * @notice Allows user to purchase tokens with DAI or USDC, which are then vested.
     * @dev Tokens being bought must be either DAI or USDC. Transfers funds from purchaser to Treasury. Only available when vesting is active.
     * If the purchase amount meets the threshold, a portion of tokens is immediately released.
     * The rest of the tokens are vested; if not enough tokens are available to vest the transaction will revert.
     * @param _buyTokenAmount The amount of tokens being bought
     * @param _vestingTokenPurchaseAmount The amount of vesting tokens to be purchased
     * @param _exchangeToken The token used for the purchase, either DAI or USDC
     * @param _vestingAsset The asset to be vested
     */
    function purchaseVestingToken(
        uint256 _buyTokenAmount,
        uint256 _vestingTokenPurchaseAmount,
        address _exchangeToken,
        address _vestingAsset
    ) public payable whenVestingActive {
        require(
            _exchangeToken == address(DAI) || _exchangeToken == address(USDC),
            "Exchange token must be DAI or USDC"
        );

        uint256 requiredAmount = (_exchangeToken == address(DAI))
            ? vestingTokenPrice.mul(_vestingTokenPurchaseAmount).mul(
                DAIDecimals
            )
            : vestingTokenPrice.mul(_vestingTokenPurchaseAmount).mul(
                USDCDecimals
            );

        if (_exchangeToken == address(DAI)) {
            require(
                _buyTokenAmount >= requiredAmount,
                "Not enough DAI sent to exchange for vesting token"
            );

            emit processLog("Buy Token Amount Calculated", _buyTokenAmount);
            emit processLog("Required Amount Calculated", requiredAmount);
        } else {
            require(
                _buyTokenAmount >= requiredAmount,
                "Not enough USDC sent to exchange for vesting token"
            );
        }

        //Logic to determine if purchase amount meets threshold for immediate release of portion of vested token asset

        uint256 vestingAmount;
        uint256 purchaseAmountCalc;

        // Calculate amount to release immediately to the purchaser

        if (_exchangeToken == address(DAI)) {
            purchaseAmountCalc = _buyTokenAmount.div(DAIDecimals);
        } else {
            purchaseAmountCalc = _buyTokenAmount.div(USDCDecimals);
        }

        emit processLog("Purchase Amount Calculated", purchaseAmountCalc);

        //Transfer funds from purchaser to Treasury

        IERC20(_exchangeToken).safeTransferFrom(
            msg.sender,
            TREASURY,
            _buyTokenAmount
        );

        // Complete vesting operations

        if (purchaseAmountCalc >= purchaseAmountThreshold) {
            uint256 amountToRelease = _vestingTokenPurchaseAmount
                .mul(releasePercentage)
                .div(100);

            emit processLog("Amount to Release Calculated", amountToRelease);

            // Withdraw amount from vesting contract and send to purchaser

            if (amountToRelease > 0) {
                _withdrawBonusTokens(
                    amountToRelease.mul(vestingTokenDecimals),
                    _vestingAsset,
                    msg.sender
                );
            }

            // Calculate the remaining amount to vest
            vestingAmount = _vestingTokenPurchaseAmount
                .mul(vestingTokenDecimals)
                .sub(amountToRelease.mul(vestingTokenDecimals));
            emit processLog("Vesting Amount Calculated", vestingAmount);
        }

        // Vest the tokens for the user; if not enough tokens are available to vest the transaction will revert
        _vest(msg.sender, vestingAmount);

        emit vestingTransactionComplete(msg.sender, vestingAmount);
    }

    /**
     * @notice Sets up a standard token vesting schedule for the provided vestor
     * @dev Available only when vesting is active and only the owner can execute this function.
     *      If not enough tokens are available to vest, the transaction will be reverted.
     * @param vestor The address of the participant in the vesting process
     * @param amount The amount of tokens to be vested for the participant
     */
    function standardVesting(address vestor, uint256 amount)
        public
        whenVestingActive
        onlyOwner
    {
        uint256 vestingAmount = amount;
        _vest(vestor, vestingAmount);

        emit vestingTransactionComplete(msg.sender, vestingAmount);
    }

    /**
     * @notice Sets up a vesting schedule for a user using the Vesting contract.
     * @param account The account that a vesting schedule is being set up for.
     * @param amount The amount of tokens being vested for the user.
     */

    function _vest(address account, uint256 amount) internal {
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
     * @notice Swaps a specified amount of tokens for a corresponding amount of vesting tokens, then vests those tokens to a specified address.
     * @dev Can only be called when swapping is active. Tokens to be swapped must be the authorized swap token.
     * Swapped tokens are sent to the burn address.
     * If not enough tokens are available to vest, the transaction will revert.
     * @param vestor The address that will receive the vested tokens
     * @param swapTokenAmount The amount of swap tokens to be swapped and burned
     * @param tokenToSwap The token that is being swapped. Must be the authorized swap token.
     */
    function swapAndVest(
        address vestor,
        uint256 swapTokenAmount,
        uint256 swapTokenDecimals,
        address tokenToSwap
    ) public whenSwappingActive {
        emit processLog3(tokenToSwap);

        require(
            tokenToSwap == authorizedSwapTokenAddress,
            "Token must be authorized swap token"
        );

        uint256 vestingAmount = swapTokenAmount.mul(ratioNumerator).div(ratioDenominator);

        emit processLog("Vesting Amount Calculated", vestingAmount);

        uint256 swapTokenAmountScaled = swapTokenAmount.mul(swapTokenDecimals);

        IERC20(tokenToSwap).safeTransferFrom(
            msg.sender,
            address(this),
            swapTokenAmountScaled
        );

        emit processLog("Swap Token Processed", swapTokenAmountScaled);

        _vest(vestor, vestingAmount);

        emit vestingTransactionComplete(msg.sender, vestingAmount);
    }

    //Claim vested tokens
    function claimTokens(uint256 scheduleId, address vestor) external {
        vestingManager.claim(scheduleId, vestor);
    }

    /**
     * @notice Cancel an individual vesting schedule.
     * @dev If the indiviudal vesting schedule is cancellable, it transfers the outstanding tokens to the VestingExecutor. Can only be called by the owner of the contract.
     * @param account The account to cancel vesting for.
     * @param scheduleId The id of the vesting schedule being canceled.
     */
    function cancelVesting(address account, uint256 scheduleId)
        external
        onlyOwner
    {
        vestingManager.cancelVesting(account, scheduleId);
    }

    /**
     * @notice Withdraws vesting tokens from the VestingManager contract.
     * @dev It only allows withdrawing tokens that are not locked in vesting. Can only be called by owner.
     * @param amount The amount to withdraw.
     * @param asset The token to withdraw.
     */
    function withdrawVestingTokens(uint256 amount, address asset)
        external
        onlyOwner
    {
        vestingManager.withdrawVestingTokens(amount, asset);

        _transferERC20(IERC20(asset), owner(), amount);

        emit vestingTokenWithdrawal(asset, amount);
    }

    /**
     * @notice Withdraws vesting tokens from the VestingManager contract (during token purchase transactions)
     * @dev It only allows withdrawing tokens that are not locked in vesting.
     * @param amount The amount to withdraw.
     * @param asset The token to withdraw.
     */
    function _withdrawBonusTokens(
        uint256 amount,
        address asset,
        address receipent
    ) internal {
        vestingManager.withdrawVestingTokens(amount, asset);

        _transferERC20(IERC20(asset), receipent, amount);
    }

    function retrieveScheduleInfo(address account)
        public
        view
        returns (VestingManager.ScheduleInfo[] memory)
    {
        VestingManager.ScheduleInfo[] memory schedules = vestingManager
            .getScheduleInfo(account);
        return schedules;
    }

    //End of contract
}
