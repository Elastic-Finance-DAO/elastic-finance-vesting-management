// SPDX-License-Identifier: MIT

pragma solidity >=0.4.23 <0.9.0;

import "../interfaces/IVesting.sol";

contract VestingManager is Ownable {
    enum VestingStatus {
        VestingActive, // 0
        VestingInactive // 1
    }

    VestingStatus public currentVestingStatus = VestingStatus.VestingActive;

    event StatusChanged(VestingStatus status);
    event BeneficiaryAdded(address beneficiary);
    event BeneficiaryFunded(address beneficiary, uint256 amount);

    // This address can change the vesting status
    address public manager;

    // Vesting wallets mapped by beneficiary
    mapping(address => VestingWallet) public wallets;

    // Start timestamp and duration for new wallets
    uint64 public startTimestamp;
    uint64 public durationSeconds;

    constructor(uint64 _startTimestamp, uint64 _durationSeconds) {
        startTimestamp = _startTimestamp;
        durationSeconds = _durationSeconds;
    }

    // Ensure vesting is currently active
    modifier vestingActive() {
        require(
            currentVestingStatus == VestingStatus.VestingActive,
            "Vesting is not currently active."
        );
        _;
    }

    // Change the vesting status
    function setVestingStatus(VestingStatus _status) external onlyOwner {
        currentVestingStatus = _status;
        emit StatusChanged(_status);
    }

    // Add a beneficiary (create a vesting wallet)
    function addBeneficiary(address _beneficiary) external vestingActive {
        require(
            address(wallets[_beneficiary]) == address(0),
            "Beneficiary already added."
        );

        wallets[_beneficiary] = new VestingWallet(
            _beneficiary,
            startTimestamp,
            durationSeconds
        );
        emit BeneficiaryAdded(_beneficiary);
    }

    // Transfer tokens to a beneficiary's wallet
    function fundBeneficiary(
        address _token,
        address _beneficiary,
        uint256 _amount
    ) external vestingActive {
        require(
            address(wallets[_beneficiary]) != address(0),
            "Beneficiary does not exist."
        );

        IERC20(_token).transferFrom(
            msg.sender,
            address(wallets[_beneficiary]),
            _amount
        );
        emit BeneficiaryFunded(_beneficiary, _amount);
    }

    // Get the vesting end time of specific beneficiary
    function getVestingEnd(address _beneficiary) public view returns (uint256) {
        return wallets[_beneficiary].end();
    }
}
