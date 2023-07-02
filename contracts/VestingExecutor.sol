// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.9;

import "./VestingManager.sol";
import "./TokenLock.sol";

/**
 * Vesting Executor contract interacts with, and is the owner, of Vesting Manager. 
 Contract executes:
- Purchasing of vested tokens at varying prices. After purchase, asset is vested on behalf of user
- Swapping of asset for a vested asset (at a pre-defined ratio); after swap, asset is vested on behalf of swapper
- Standard vesting transaction: Assign a vesting schedule to an account 
- Cancellation of individual vesting schedules (limited to multisig)
- Withdrawal of unlocked tokens from Vesting Manager account (limited to multisig)
- Vesting and swapping are only possible when vesting/swapping is active 
- Asset claiming at end of cliff period on behalf of vestors 

Contract allows for multiple: 
- Assets to be vested simultaneously 
- Tokens to be used to purchase vested assets 
- Tokens to be used to swap for vested assets 
 */

contract VestingExecutor is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== State Variables ========== */

    address payable immutable TREASURY =
        payable(0xf950a86013bAA227009771181a885E369e158da3);

    uint256 public purchaseAmountThreshold; // Amount of vesting token that must be purchased to trigger immediate release of coins
    uint256 public releasePercentage; // Percentage of total amount that will be released
    address public authorizedSwapTokenAddress; //Token that can be swapped for vesting token (which will be vested on behalf of the user)
    IERC20 public swapToken = IERC20(authorizedSwapTokenAddress);
    uint256 public swapRatio; // Ratio that will determine how many swap tokens can be exchanged for vesting tokens
    VestingManager public vestingManager; // Vesting Manager contract
    TokenLock public tokenLock; // Contract where swapped tokens are deposited; Contract has no owner or withdraw functions

    /* ========== Structs and Mappings ========== */

    /**
     * @notice Vesting parameters struct.
     * @dev This struct holds necessary parameters for vesting.
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

    /**
     * @dev Struct to represent approved purchase tokens
     * @param token IERC20 token that has been approved for purchase
     * @param decimals Number of decimals the token uses
     */
    struct approvedPurchaseTokens {
        IERC20 token;
        uint256 decimals;
        uint256 numDecimals;
    }

    mapping(address => approvedPurchaseTokens) public purchaseTokens;

    /**
     * @dev Struct to represent tokens available for vesting
     * @param token IERC20 token that is available for vesting
     * @param decimals Number of decimals the token uses
     */
    struct VestingTokens {
        IERC20 token;
        uint256 decimals;
        uint256 numDecimals;
        uint256 price;
    }

    mapping(address => VestingTokens) public vestingTokens;

    /**
     * @dev Struct to represent authorized swap tokens
     * @param token IERC20 token that has been authorized for swap
     * @param decimals Number of decimals the token uses
     */
    struct AuthorizedSwapTokens {
        IERC20 token;
        uint256 decimals;
    }

    mapping(address => AuthorizedSwapTokens) public authorizedSwapTokens;

    /* ========== Events ========== */

    event vestingTransactionComplete(address vester, uint256 vestedAssetAmount);
    event vestingTokenWithdrawal(address token, uint256 withdrawalAmount);
    event processLog(string description, uint256 number);
    event processLog2(string message);
    event processLog3(address address2);

    /* ========== Constructor ========== */

    /**
     * @notice Deploys the Vesting Manager contract and sets the Vesting Executor as the owner of the VestingManager.
     Also deploys the Token Lock contract, which has no owner and no withdrawal functions; used to "burn" tokens swapped for vesting assets
     * @dev The VestingExecutor contract initializes the VestingManager contract during its own deployment.
     Constructor also sets the default purchase tokens: DAI and USDC.
     */
    constructor() {
        // Deploy a new instance of VestingManager, setting VestingExecutor (this contract) as the owner
        vestingManager = new VestingManager(address(this));
        tokenLock = new TokenLock();

        // Add initial valid purchase tokens to list
        purchaseTokens[
            address(0x6B175474E89094C44Da98b954EedeAC495271d0F) //DAI
        ] = approvedPurchaseTokens({
            token: IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F),
            decimals: 10**18,
            numDecimals: 18
        });

        purchaseTokens[
            address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) //USDC
        ] = approvedPurchaseTokens({
            token: IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48),
            decimals: 10**6,
            numDecimals: 6
        });
    }

    /* ========== Views ========== */

    /**
     * @notice Fetches locked amount of a specific asset.
     * @param assetAddress The address of the asset.
     * @return The amount of the asset currently locked.
     */
    function viewLockedAmount(address assetAddress)
        public
        view
        returns (uint256)
    {
        return vestingManager.getLockedAmount(assetAddress);
    }

    /**
     * @notice Returns information about all vesting schedules for a given account
     * @param account The address of the account for which to return vesting schedule information
     * @return An array of ScheduleInfo structs, each containing the ID, cliff timestamp, and end timestamp for a vesting schedule (related to the account)
     */
    function retrieveScheduleInfo(address account)
        public
        view
        returns (VestingManager.ScheduleInfo[] memory)
    {
        VestingManager.ScheduleInfo[] memory schedules = vestingManager
            .getScheduleInfo(account);
        return schedules;
    }

    /**
     * @notice Fetches the current vesting status of the contract.
     * @dev Uses the contract's stored `current_vesting_status` state variable.
     * @return The current vesting status of the contract.
     */
    function getCurrentVestingStatus() public view returns (vestingStatus) {
        return current_vesting_status;
    }

    /**
     * @notice Fetches the current swapping status of the contract.
     * @dev Uses the contract's stored `current_swapping_status` state variable.
     * @return The current swapping status of the contract.
     */
    function getCurrentSwappingStatus() public view returns (swappingStatus) {
        return current_swapping_status;
    }

    /**
     * @notice Fetches the current token locking status of the contract.
     * @dev Uses the contract's stored `current_swapping_status` state variable.
     * @return The current swapping status of the contract.
     */
    function getCurrentTokenLockStatus() public view returns (tokenLockStatus) {
        return current_token_lock_status;
    }

    /* ========== Transfer ERC20 Tokens ========== */

    /**
     * @notice Transfers a specific amount of ERC20 tokens to an address.
     * @dev The token transfer is executed using the input token's transfer function. It checks there are enough tokens on
     * the contract's balance before performing the transfer.
     * @param token The address of the ERC20 token contract that we want to make the transfer with.
     * @param to The recipient's address of the tokens.
     * @param amount The amount of tokens to be transferred.
     */
    function _transferERC20(
        IERC20 token,
        address to,
        uint256 amount
    ) internal {
        uint256 erc20balance = token.balanceOf(address(this));
        require(amount <= erc20balance, "Balance too low to transfer token");
        token.transfer(to, amount);
    }

    function transferERC20(
        IERC20 token,
        address to,
        uint256 amount
    ) external onlyOwner {
        uint256 erc20balance = token.balanceOf(address(this));
        require(amount <= erc20balance, "Balance too low to transfer token");
        token.transfer(to, amount);
    }

    /* ========== Manage Vesting/Swap Status ========== */

    //Vesting status options
    enum vestingStatus {
        vestingActive, //0
        vestingInactive //1
    }

    //Default vesting status: Active
    vestingStatus public current_vesting_status = vestingStatus.vestingActive;

    /**
     * @notice Changes the vesting status of the contract
     * @dev Can only be called by the contract owner. Changes the status to the input value
     * @param value The new vesting status
     */
    function setVestingStatus(uint256 value) public onlyOwner {
        current_vesting_status = vestingStatus(value);
    }

    /**
     * @notice Modifier to only allow certain function calls when vesting is active
     * @dev Reverts if the current vesting status is not active. Used to restrict function calling
     */
    modifier whenVestingActive() {
        require(
            current_vesting_status == vestingStatus.vestingActive,
            "Vesting not active"
        );
        _;
    }

    //Swapping status options
    enum swappingStatus {
        swappingActive, //0
        swappingInactive //1
    }

    //Default swapping status: Inactive
    swappingStatus public current_swapping_status =
        swappingStatus.swappingInactive;

    /**
     * @notice Changes the swapping status of the contract
     * @dev Can only be called by the contract owner. Changes the status to the input value
     * @param value The new swapping status
     */
    function setSwappingStatus(uint256 value) public onlyOwner {
        current_swapping_status = swappingStatus(value);
    }

    /**
     * @notice Modifier to enforce that swapping is active
     * @dev Reverts if the current swapping status is not active.
     */
    modifier whenSwappingActive() {
        require(
            current_swapping_status == swappingStatus.swappingActive,
            "Swapping not active"
        );
        _;
    }

    //Token lock options

    enum tokenLockStatus {
        tokenLockActive, //0
        tokenLockInactive //1
    }

    //Default token lock status: Inactive
    tokenLockStatus public current_token_lock_status =
        tokenLockStatus.tokenLockActive;

    /**
     * @notice Changes the token lock status of the contract
     * @dev Can only be called by the contract owner. Changes the status to the input value
     * @param value The new token locking status
     */
    function setTokenLockStatus(uint256 value) public onlyOwner {
        current_token_lock_status = tokenLockStatus(value);
    }

    /* ========== Set/Get Approved Purchase Tokens ========== */

    /**
     * @notice Adds a new token to the approved purchase tokens list
     * @dev Can only be called by the contract owner. Reverts if the token already exists on the list or if the address is invalid
     * @param tokenAddress The address of the new token to add
     * @param decimals The decimals of the new token
     * @param numDecimals Decimals of the token
     */
    function addPurchaseToken(
        address tokenAddress,
        uint256 decimals,
        uint256 numDecimals
    ) public onlyOwner {
        require(tokenAddress != address(0), "Invalid token address");
        require(
            address(purchaseTokens[tokenAddress].token) == address(0),
            "Purchase token on list"
        );

        purchaseTokens[tokenAddress] = approvedPurchaseTokens({
            token: IERC20(tokenAddress),
            decimals: decimals,
            numDecimals: numDecimals
        });
    }

    /**
     * @notice Removes a token from the approved purchase tokens list
     * @dev Can only be called by the contract owner. Reverts if the token is not currently on the list.
     * @param tokenAddress The address of the token to remove
     */
    function removePurchaseToken(address tokenAddress) public onlyOwner {
        require(
            address(purchaseTokens[tokenAddress].token) != address(0),
            "Purchase token not on list"
        );

        delete purchaseTokens[tokenAddress];
    }

    /* ========== Set/Get Approved Vesting Tokens ========== */

    /**
     * @notice Adds a new token to the approved vesting tokens list
     * @dev Can only be called by the contract owner. Reverts if the token already exists on the list or if the address is invalid
     * @param tokenAddress The address of the new token to add
     * @param decimals The decimals of the new token
     * @param price The USD price of the new token (multiply by 10^4 before sending to contract)
     * @param numDecimals Decimals of the token
     */
    function addVestingToken(
        address tokenAddress,
        uint256 decimals,
        uint256 price,
        uint256 numDecimals
    ) public onlyOwner {
        require(tokenAddress != address(0), "Invalid token address");
        require(
            address(vestingTokens[tokenAddress].token) == address(0),
            "Vesting token on list"
        );

        vestingTokens[tokenAddress] = VestingTokens({
            token: IERC20(tokenAddress),
            decimals: decimals,
            price: price,
            numDecimals: numDecimals
        });
    }

    /**
     * @notice Removes a token from the approved vesting tokens list
     * @dev Can only be called by the contract owner. Reverts if the token is not currently on the list.
     * @param tokenAddress The address of the token to remove
     */
    function removeVestingToken(address tokenAddress) public onlyOwner {
        require(
            address(vestingTokens[tokenAddress].token) != address(0),
            "Vesting token on list"
        );

        delete vestingTokens[tokenAddress];
    }

    /* ========== Set/Get Approved Swap Tokens ========== */

    /**
     * @notice Adds a new token to the authorized swap tokens list
     * @dev Can only be called by the contract owner. Reverts if the token already exists on the list or if the address is invalid
     * @param tokenAddress The address of the new token to add
     * @param decimals The decimals of the new token
     */
    function addAuthorizedSwapToken(address tokenAddress, uint256 decimals)
        public
        onlyOwner
    {
        require(tokenAddress != address(0), "Invalid token address");
        require(
            address(authorizedSwapTokens[tokenAddress].token) == address(0),
            "Swap token on list"
        );

        authorizedSwapTokens[tokenAddress] = AuthorizedSwapTokens({
            token: IERC20(tokenAddress),
            decimals: decimals
        });
    }

    /**
     * @notice Removes a token from the authorized swap tokens list
     * @dev Can only be called by the contract owner. Reverts if the token is not currently on the list.
     * @param tokenAddress The address of the token to remove
     */
    function removeAuthorizedSwapToken(address tokenAddress) public onlyOwner {
        require(
            address(authorizedSwapTokens[tokenAddress].token) != address(0),
            "Swap token not on list"
        );

        delete authorizedSwapTokens[tokenAddress];
    }

    /* ========== Set Vesting Parameters ========== */

    /**
     * @notice Sets the release percentage for amount of vesting tokens that will immediately sent to users
     * @dev Allows the owner to set a threshold vesting token releases.
     * @param _releasePercentage The new percentage for the amount of vesting tokens immediately released to purchasers
     */
    function setReleasePercentage(uint256 _releasePercentage) public onlyOwner {
        releasePercentage = _releasePercentage;
    }

    /**
     * @notice Sets the threshold for the amount of vesting tokens to be purchased.
     * @dev Allows the owner to set a threshold for vesting token purchase. If a user's purchase amount exceeds this threshold, a specified percentage of purchased tokens will be instantly transferred to the user.
     * @param threshold The new threshold for the amount of vesting tokens to be purchased.
     */
    function setPurchaseAmountThreshold(uint256 threshold) public onlyOwner {
        purchaseAmountThreshold = threshold;
    }

    /* ========== Set Vesting Exchange Rate ========== */

    /**
     * @notice Sets the swap ratio for the vesting to swap token conversion
     * @dev Can only be executed by the owner of the contract
     * @param _ratio The ratio (multiply by 10^4 before sending to contract)
     */
    function setSwapRatio(uint256 _ratio) public onlyOwner {
        swapRatio = _ratio;
    }

    /* ========== Purchase and Vesting Functions ========== */

    /**
     * @notice Modifier to restrict certain functions to multisig only calls
     * @dev Reverts if the caller is not the treasury.
     */
    modifier multiSigOnly() {
        require(msg.sender == TREASURY, "Multisig not caller");
        _;
    }

    /**
     * @notice Adjust the amount from the scale of the source decimal to the destination decimal
     * @dev This function handles the case where the decimal numbers vary between two tokens.
     * @param amount The source amount to be adjusted
     * @param fromDecimals The decimal number of the source token
     * @param toDecimals The decimal number of the destination token
     * @return The amount adjusted to the destination decimal scale
     */
    function adjustDecimals(
        uint256 amount,
        uint256 fromDecimals,
        uint256 toDecimals
    ) public pure returns (uint256) {
        if (fromDecimals == toDecimals) {
            return amount;
        } else if (fromDecimals > toDecimals) {
            return amount / (10**(fromDecimals - toDecimals));
        } else {
            return amount * (10**(toDecimals - fromDecimals));
        }
    }

    /**
     * @notice Allows user to purchase tokens with DAI or USDC, which are then vested.
     * @dev Tokens being bought must be either DAI or USDC. Transfers funds from purchaser to Treasury. Only available when vesting is active.
     * If the purchase amount meets the threshold, a portion of tokens is immediately released.
     * The rest of the tokens are vested; if not enough tokens are available to vest the transaction will revert.
     * @param _vestingTokenPurchaseAmount The amount of vesting tokens to be purchased
     * @param _exchangeToken The token used for the purchase, either DAI or USDC
     * @param _vestingAsset The asset to be vested
     */
    function purchaseVestingToken(
        uint256 _vestingTokenPurchaseAmount,
        address _exchangeToken,
        address _vestingAsset,
        VestingParams memory _vestingParams
    ) public payable whenVestingActive {
        // Ensure cliff is shorter than vesting (vesting includes the cliff duration)

        require(
            _vestingParams.vestingWeeks > 0 &&
                _vestingParams.vestingWeeks >= _vestingParams.cliffWeeks,
            "Vesting: invalid vesting params set"
        );

        require(
            address(purchaseTokens[_exchangeToken].token) != address(0),
            "Exchange token must be a valid approved token"
        );

        uint256 scaledBuyPrice = _vestingTokenPurchaseAmount
            .mul(vestingTokens[_vestingAsset].price)
            .div(10**4);

        //Calculate required amount of buy token

        uint256 requiredBuyAmount = adjustDecimals(
            scaledBuyPrice,
            vestingTokens[_vestingAsset].numDecimals,
            purchaseTokens[_exchangeToken].numDecimals
        );

        emit processLog(
            "Required Sell Token Payment Amount Calculated",
            requiredBuyAmount
        );

        require(
            IERC20(_exchangeToken).balanceOf(msg.sender) >= requiredBuyAmount,
            "Not enough tokens in wallet to exchange for vesting token"
        );

        //Logic to determine if purchase amount meets threshold for immediate release of portion of vested token asset

        uint256 vestingAmount;
        uint256 sellTokenAmountCalc;

        //Calculate sell token amount (to compare to purchase amount threshold)
        sellTokenAmountCalc = requiredBuyAmount.div(
            purchaseTokens[_exchangeToken].decimals
        );

        emit processLog(
            "Scaled Down Amount of Sell Token Calculated",
            sellTokenAmountCalc
        );

        //Transfer funds from purchaser to Treasury

        IERC20(_exchangeToken).safeTransferFrom(
            msg.sender,
            TREASURY,
            requiredBuyAmount
        );

        // Complete vesting operations //

        if (sellTokenAmountCalc >= purchaseAmountThreshold) {
            uint256 amountToRelease = (
                _vestingTokenPurchaseAmount
                    .div(vestingTokens[_vestingAsset].decimals)
                    .mul(releasePercentage)
            ).div(100);

            emit processLog("Amount to Release Calculated", amountToRelease);

            // Withdraw amount from vesting contract and send to purchaser
            if (amountToRelease > 0) {
                _withdrawBonusTokens(
                    amountToRelease.mul(vestingTokens[_vestingAsset].decimals),
                    _vestingAsset,
                    msg.sender
                );
            }

            // Calculate the remaining amount to vest
            vestingAmount = _vestingTokenPurchaseAmount.sub(
                amountToRelease.mul(vestingTokens[_vestingAsset].decimals)
            );
            emit processLog("Vesting Amount Calculated", vestingAmount);

            // Vest the tokens for the user; if not enough tokens are available to vest the transaction will revert
            _vest(msg.sender, vestingAmount, _vestingParams);

            emit vestingTransactionComplete(msg.sender, vestingAmount);
        } else {
            vestingAmount = _vestingTokenPurchaseAmount;

            _vest(msg.sender, vestingAmount, _vestingParams);

            emit vestingTransactionComplete(msg.sender, vestingAmount);
        }
    }

    /**
     * @notice Sets up a token vesting schedule for the provided vestor
     * @dev Available only when vesting is active and only the owner can execute this function.
     *      If not enough tokens are available to vest, the transaction will be reverted.
     * @param vestor The address of the wallet to receive vesting tokens
     * @param amount The amount of tokens to be vested for the participant
     */
    function standardVesting(
        address vestor,
        uint256 amount,
        VestingParams memory _vestingParams
    ) public whenVestingActive onlyOwner {
        // Ensure cliff is shorter than vesting (vesting includes the cliff duration)
        require(
            _vestingParams.vestingWeeks > 0 &&
                _vestingParams.vestingWeeks >= _vestingParams.cliffWeeks,
            "Vesting: invalid vesting params set"
        );

        uint256 vestingAmount = amount;
        _vest(vestor, vestingAmount, _vestingParams);

        emit vestingTransactionComplete(msg.sender, vestingAmount);
    }

    /**
     * @notice Swaps a specified amount of tokens for a corresponding amount of vesting tokens, then vests those tokens to a specified address.
     * @dev Can only be called when swapping is active. Tokens to be swapped must be the authorized swap token.
     * Swapped tokens are sent to the Token Lock contract
     * If not enough tokens are available to vest, the transaction will revert.
     * @param swapTokenAmount The amount of swap tokens to be swapped and burned
     * @param tokenToSwap The token that is being swapped. Must be the authorized swap token.
     */
    function swapAndVest(
        uint256 swapTokenAmount,
        address tokenToSwap,
        VestingParams memory _vestingParams
    ) public whenSwappingActive {
        //Set vestor address to msg sender
        address vestor = msg.sender;

        // Ensure cliff is shorter than vesting (vesting includes the cliff duration)
        require(
            _vestingParams.vestingWeeks > 0 &&
                _vestingParams.vestingWeeks >= _vestingParams.cliffWeeks,
            "Vesting: invalid vesting params set"
        );

        // Check that swap token is authorized
        require(
            authorizedSwapTokens[tokenToSwap].token != IERC20(address(0)),
            "Token must be authorized swap token"
        );

        // Calculate amount to vest
        uint256 vestingAmount = swapTokenAmount.mul(swapRatio).div(10**4);
        emit processLog("Vesting Amount Calculated", vestingAmount);

        // Transfer tokens to TokenLock contract or Treasury
        authorizedSwapTokens[tokenToSwap].token.safeTransferFrom(
            msg.sender,
            address(this),
            swapTokenAmount
        );

        if (current_token_lock_status == tokenLockStatus.tokenLockActive) {
            // Transfer token to Token Lock contract (default behavior)
            _transferERC20(
                IERC20(tokenToSwap),
                address(tokenLock),
                swapTokenAmount
            );
        } else {
            // Transfer token to TREASURY
            _transferERC20(IERC20(tokenToSwap), TREASURY, swapTokenAmount);
        }

        emit processLog("Swap Token Transfered", swapTokenAmount);

        // Vest tokens on behalf of user
        _vest(vestor, vestingAmount, _vestingParams);

        emit vestingTransactionComplete(vestor, vestingAmount);
    }

    /**
     * @notice Sets up a vesting schedule for a user using the Vesting contract. Arguments are vesting parameters.
     * @param account The account that a vesting schedule is being set up for.
     * @param amount The amount of tokens being vested for the user.
     * @param params A struct containing the vesting parameters. The struct has
     *        the following parameters:
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
    function _vest(
        address account,
        uint256 amount,
        VestingParams memory params
    ) internal {
        vestingManager.vest(
            account,
            amount,
            params.asset,
            params.isFixed,
            params.cliffWeeks,
            params.vestingWeeks,
            params.startTime
        );
    }

    /**
     * @notice Allows claim of vested tokens; 
     * @dev Uses vestingManager to process the claim; 
     Vesting Executor claims on behalf of vestor and tokens are sent to vestor's account
     * @param scheduleId The ID of the vesting schedule
     * @param vestor The address of the vestor
     */
    function claimTokens(uint256 scheduleId, address vestor) external {
        vestingManager.claim(scheduleId, vestor);
    }

    /**
     * @notice Cancel an individual vesting schedule.
     * @dev If the indiviudal vesting schedule is cancellable, it transfers the outstanding tokens to the VestingExecutor. Can only be called by the DAO multisig.
     * @param account The account to cancel vesting for.
     * @param scheduleId The id of the vesting schedule being canceled.
     */
    function cancelVesting(address account, uint256 scheduleId)
        external
        multiSigOnly
    {
        vestingManager.cancelVesting(account, scheduleId);
    }

    /**
     * @notice Withdraws vesting tokens from the VestingManager contract.
     * @dev It only allows withdrawing tokens that are not locked in vesting. Can only be called by DAO multisig.
     * @param amount The amount to withdraw.
     * @param asset The token to withdraw.
     */
    function withdrawVestingTokens(uint256 amount, address asset)
        external
        multiSigOnly
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

    //End of contract
}
