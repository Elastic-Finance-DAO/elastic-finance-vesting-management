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
    event VestingParamsSet(
        address asset,
        bool isFixed,
        uint256 cliffWeeks,
        uint256 vestingWeeks,
        uint256 startTime
    );

    event vestingTokenWithdrawal(address token, uint256 withdrawalAmount);

    event TempLog(string data, uint256 number);
    event TempLog2(string message);

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

    /* ========== Set Vesting Parameters ========== */

    //Set address of vesting token
    function setVestingTokenAddress(address _vestingTokenAddress)
        public
        onlyOwner
    {
        vestingTokenAddress = _vestingTokenAddress;
        vestingToken = IERC20(vestingTokenAddress);
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
     * @notice Sets the vesting parameters globally. Should be re-set for each stage of vesting
     * @dev This function allows the contract owner to set the parameters used for vesting.
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
        vestingParams = _vestingParams;

        // Emit the event after the vestingParams have been updated
        emit VestingParamsSet(
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

            emit TempLog("Buy Token Amount", _buyTokenAmount);
            emit TempLog("Required Amount", requiredAmount);
        } else {
            require(
                _buyTokenAmount >= requiredAmount,
                "Not enough USDC sent to exchange for vesting token"
            );
        }

        //Logic to determine if purchase amount meets threshold for immediate release of portion of vested tokens

        uint256 vestingAmount;
        uint256 purchaseAmountCalc;

        // Calculate amount to release immediately to the purchaser

        if (_exchangeToken == address(DAI)) {
            purchaseAmountCalc = _buyTokenAmount.div(DAIDecimals);
        } else {
            purchaseAmountCalc = _buyTokenAmount.div(USDCDecimals);
        }

        emit TempLog("Purchase Amount Threshold", purchaseAmountThreshold);
        emit TempLog("Purchase Amount Calc", purchaseAmountCalc);

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

            emit TempLog(
                "Vesting Token Purchase Amount",
                _vestingTokenPurchaseAmount
            );
            emit TempLog("Amount to Release", amountToRelease);

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
            emit TempLog("Vesting Amount", vestingAmount);
        }

        // // Vest the tokens for the user; if not enough tokens are available to vest the transaction will revert
        // _vest(msg.sender, vestingAmount);

        // emit vestingTransactionComplete(msg.sender, vestingAmount);
    }

    function setUpVesting(address vestor, uint256 amount)
        public
        whenVestingActive
        onlyOwner
    {
        uint256 vestingAmount = amount;

        // Vest the tokens for the user; if not enough tokens are available to vest the transaction will revert
        _vest(vestor, vestingAmount);
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
     * @notice Cancel a vesting schedule.
     * @dev If the vesting schedule is cancellable, it transfers the outstanding tokens to the owner of the contract.
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
     * @dev It only allows withdrawing tokens that are not locked in vesting.
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
     * @notice Withdraws vesting tokens from the VestingManager contract.
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

    //End of contract
}
