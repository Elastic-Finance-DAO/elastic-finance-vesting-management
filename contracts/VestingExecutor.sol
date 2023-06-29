// SPDX-License-Identifier: MIT

pragma solidity >=0.4.23 <0.9.0;

import "./Vesting.sol";

contract VestingExecutor is Ownable {
    // Deploy instance of the VestingManager contract
    VestingManager public vestingManager;

    /* ========== State Variables ========== */

    //Treasury account
    address payable immutable TREASURY =
        payable(0xa9f55E03FE7411501d06532111C92c58ebcA1D83);

    //WETH interface
    address public WETHAddress;
    IWETH private WETH;

    /* ========== Structs ========== */

    /**
     * @notice Vesting parameters structure.
     * @dev This structure holds all necessary parameters for vesting.
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

    /* ========== Enable ETH Deposits and wrap ETH to WETH ========== */

    //Receive ETH: Fallback
    fallback() external payable {}

    receive() external payable {}

    //Wrap WETH to ETH
    function _depositETHtoWETH(uint256 _amount) internal {
        WETH.deposit{value: _amount}();
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
        require(WETH.approve(to, type(uint256).max));
        token.transfer(to, amount);
    }

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

    /* ========== Purchase and Vesting Functions ========== */

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
     * @notice Sets up vesting schedules for multiple users using the Vesting contract.
     * @param accounts The accounts that the vesting schedules are being set up for.
     * @param amounts The amounts of tokens being vested for each user.
     */
    function _multiVest(address[] calldata accounts, uint256[] calldata amounts)
        internal
        whenVestingActive
    {
        vestingManager.multiVest(
            accounts,
            amounts,
            vestingParams.asset,
            vestingParams.isFixed,
            vestingParams.cliffWeeks,
            vestingParams.vestingWeeks,
            vestingParams.startTime
        );
    }
}
