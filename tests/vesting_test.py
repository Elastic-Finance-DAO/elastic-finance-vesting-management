""" 
Vesting Manager and Executor Test Suite
~~~~~~~~~~~~~~~~~~~~~~~~-~~~~

Unit tests for vesting manager and executor contracts. 
Blockchain state resets after each test.
In addition to assertions, transaction information is printed (calls, logs).
Utilizes brownie and pytest. 

"""

import pytest
import json
import brownie
from brownie import accounts, Contract, network
from brownie import VestingExecutor, VestingManager
from web3 import Web3
from brownie.test import given, strategy
import time
import math

####################################################################################
##### ----- Fixtures   ----- #####
####################################################################################


@pytest.fixture(scope="module")
def main():
    vesting_executor = VestingExecutor.deploy({"from": accounts[1]})
    yield vesting_executor


@pytest.fixture(scope="module")
def vesting_manager(main):
    vesting_executor = main
    vesting_manager_address = main.vestingManager()
    return vesting_manager_address


@pytest.fixture(scope="function")
def standard_vesting_parameters():
    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    asset_address = eefi_contract.address
    is_fixed = False
    cliff_weeks = 52  # 1 year
    vesting_weeks = 55  # Vesting occurs over 3 weeks post-cliff
    start_time = current_time = time.time()  # Current time in UNIX

    vesting_params_list = [
        asset_address,
        is_fixed,
        cliff_weeks,
        vesting_weeks,
        start_time,
    ]

    return vesting_params_list


@pytest.fixture(scope="module")
def valid_vesting_parameters(main):
    vesting_executor = main

    purchase_cliff_weeks = 52  # 1 year
    purchase_vesting_weeks = 55  # Vesting occurs over 3 weeks post-cliff
    swap_cliff_weeks = 52
    swap_vesting_weeks = 55

    vesting_executor = main

    vesting_executor.setValidVestingParams(
        purchase_cliff_weeks,
        purchase_vesting_weeks,
        swap_cliff_weeks,
        swap_vesting_weeks,
        {"from": accounts[1]},
    )
    

@pytest.fixture(scope="module")
def set_vesting_token(main):
    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    vesting_token_price = 12.25 * 10**4

    eefi_token_address = eefi_contract.address

    eefi_token_decimals = 10**18

    eefi_token_decimal_number = 18

    set_vesting_token = vesting_executor.addVestingToken(
        eefi_token_address,
        eefi_token_decimals,
        vesting_token_price,
        eefi_token_decimal_number,
    )

    return set_vesting_token


@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass


####################################################################################
##### ----- Tests   ----- #####
####################################################################################

##### ----- Asset Deposits and Balances  ----- #####


# Contract does not accept ETH deposits
def test_transfer_eth_into_vesting_manager_contract(vesting_manager, capsys):
    # Contract does not accept ETH, so it should fail

    vesting_manager_address = vesting_manager

    with brownie.reverts():
        transfer_ETH_into_contract = accounts[0].transfer(
            vesting_manager_address, "1 ether"
        )

    with capsys.disabled():
        print("Contract does not accept ETH, so it should fail")


#Ensure valid vesting parameters are set 
def test_valid_vesting_parameters_setting(main, capsys):
    
    vesting_executor = main

    purchase_cliff_weeks = 52  # 1 year
    purchase_vesting_weeks = 55  # Vesting occurs over 3 weeks post-cliff
    swap_cliff_weeks = 52
    swap_vesting_weeks = 55

    vesting_executor = main

    vesting_executor.setValidVestingParams(
        purchase_cliff_weeks,
        purchase_vesting_weeks,
        swap_cliff_weeks,
        swap_vesting_weeks,
        {"from": accounts[1]},
    )
    
    with capsys.disabled():
        print(vesting_executor.validVestingParams())
    

# # Ensure Vesting Manger contract is deployed properly can can accept vesting asset
def test_check_balance_of_vesting_manager_eefi(vesting_manager, main, capsys):
    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    vesting_manager_address = vesting_manager

    eefi_approval = 500000 * 10**18

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    transfer_amount = 5000 * 10**18

    assert (
        contract_eefi_balance == transfer_amount
    ), "tokens not successfully transfered"

    with capsys.disabled():
        print("Balance should be 5000 EEFI")
        print(contract_eefi_balance)
        
# # Ensure token lock contract is deployed properly
def test_address_of_token_lock_contract(vesting_manager, main, capsys):
    vesting_executor = main

    token_lock_address = vesting_executor.tokenLock()

    assert (
        token_lock_address != main
    ), "token lock contract not deployed"

    with capsys.disabled():
        print("Token lock address should be different from executor")


# ##### ----- Contract Status: Vesting, Staking  ----- #####


# # Vesting status is pausable
def test_reset_vesting_status(main, capsys):
    ## Test Setup ##

    vesting_executor = main

    ## Test Actions ##

    testing_status = 1  # Inactive

    vesting_executor.setVestingStatus(
        testing_status, {"from": accounts[1]}
    )  # Set status

    vesting_status = vesting_executor.getCurrentVestingStatus()  # Check status

    assert vesting_status == 1, "vestings status not updated"

    with capsys.disabled():
        print("Vesting status should be 1 (inactive)")
        print(vesting_status)


# ##### ----- Thresholds, Ratios and Asset Pricing ----- #####


# # Purchase amount threshold to trigger immediate release of portion of vesting tokens
def test_set_purchase_amount_threshold(main, capsys):
    ## Test Setup ##

    vesting_executor = main

    ## Test Actions ##

    purchase_amount_threshold = 5000

    vesting_executor.setPurchaseAmountThreshold(
        purchase_amount_threshold, {"from": accounts[1]}
    )  # Set threshold

    purchase_amount_threshold_contract = (
        vesting_executor.purchaseAmountThreshold()
    )  # Check threshold

    assert purchase_amount_threshold == purchase_amount_threshold_contract

    with capsys.disabled():
        print("Purchase amount threshold should be 3500")
        print(purchase_amount_threshold_contract)


# # Percentage of vesting tokens to be released
def test_setting_release_percentage(main, capsys):
    ## Test Setup ##

    vesting_executor = main
    ## Test Actions ##

    release_percentage = 2

    vesting_executor.setReleasePercentage(
        release_percentage, {"from": accounts[1]}
    )  # Set percentage

    release_percentage_threshold_contract = (
        vesting_executor.releasePercentage()
    )  # Check percentage

    assert (
        release_percentage == release_percentage_threshold_contract
    ), "release percentage not set"

    with capsys.disabled():
        print("Release percentage should be 2")
        print(release_percentage_threshold_contract)


# ##### ----- Vesting Asset Withdrawal  ----- #####


# # Withdraw unlocked, vested assets from contract (multisig only)
def test_vesting_token_withdrawal(vesting_manager, main, capsys):
    # # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    withdraw_amount = 200 * 10**18

    ## Test Actions ##

    withdrawal_tx = vesting_executor.withdrawVestingTokens(
        withdraw_amount, eefi_contract.address, {"from": eefi_whale}
    )

    eefi_balance_of_wallet = eefi_contract.balanceOf(accounts[1])

    assert withdraw_amount == eefi_balance_of_wallet, "Withdrawal amount mismatch"

    with capsys.disabled():
        print("Wallet EEFI balance should be 200")
        print("Wallet balance:", eefi_balance_of_wallet / 10**18)


# ##### ----- Access Control ----- #####


# # Non-multisig address can't withdraw unlocked vested assets
def test_vesting_token_withdrawal_no_multisig(vesting_manager, main, capsys):
    # # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    withdraw_amount = 200 * 10**18

    ## Test Actions ##

    with brownie.reverts():
        withdrawal_tx = vesting_executor.withdrawVestingTokens(
            withdraw_amount, eefi_contract.address, {"from": accounts[1]}
        )

    with capsys.disabled():
        print("Tx should fail because sender not from multisig")


# # Non-multisig address can't cancel individual vesting schedule
def test_vesting_cancellation_not_multisig(vesting_manager, main, capsys, chain):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    asset_address = eefi_contract.address
    is_fixed = False
    cliff_weeks = 52  # 1 year
    vesting_weeks = 55  # Vesting occurs over 3 weeks post-cliff
    start_time = time.time()  # Current time in UNIX

    vesting_params_list = [
        asset_address,
        is_fixed,
        cliff_weeks,
        vesting_weeks,
        start_time,
    ]

    # Vest Tokens ##

    vestor_address = accounts[0].address

    eefi_vesting_amount = 1000 * 10**18

    standard_vesting_transaction = vesting_executor.standardVesting(
        vestor_address,
        eefi_vesting_amount,
        vesting_params_list,
        {"from": accounts[1]},
    )

    ## Move Chain Forward ##

    unix_seconds_in_a_day = 86399
    days = 95
    unix_time_elapsed = int(unix_seconds_in_a_day * days)

    unix_time_at_end_of_vesting = int(start_time + unix_time_elapsed)

    chain.mine(1, unix_time_at_end_of_vesting)

    ## Test Actions ##

    account_vesting_schedule = vesting_executor.retrieveScheduleInfo(vestor_address)

    account_vesting_number = account_vesting_schedule[0][0]

    with brownie.reverts():
        cancel_vesting_for_user = (
            vesting_executor.cancelVesting(
                vestor_address, account_vesting_number, {"from": accounts[1]}
            ),
            "If failed, multisig modifier did not work",
        )

    with capsys.disabled():
        print("If failed, multisig modifier did not work")


# #### ----- Vesting Asset Purchases, Swaps and Standard Vesting  ----- #####


# Purchase vesting asset with USDC, release portion of vesting asset allocation to purchaser
def test_purchase_vesting_token_usdc(
    set_vesting_token, standard_vesting_parameters, vesting_manager, main, capsys
):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    usdc_contract = Contract("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48")

    usdc_token_address = usdc_contract.address

    usdc_whale = accounts.at("0x7B299ff0Bf1531C095bBE63bCF79af31eEA418Da", force=True)

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Set Threshold and Release Percentage #

    purchase_amount_threshold = 3000

    vesting_executor.setPurchaseAmountThreshold(
        purchase_amount_threshold, {"from": accounts[1]}
    )  # Set threshold

    release_percentage = 2

    vesting_executor.setReleasePercentage(
        release_percentage, {"from": accounts[1]}
    )  # Set release percentage

    # Vesting Token Pricing #

    vesting_token_price = 12

    usdc_approval = 500000 * 10**6

    desired_eefi_amount = 426.258897

    purchase_amount = (desired_eefi_amount * vesting_token_price) * 10**6

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    vesting_params_list = standard_vesting_parameters

    # Set Vesting Token

    eefi_token_address = eefi_contract.address

    eefi_token_decimals = 10**18

    eefi_token_decimal_number = 18

    set_vesting_token = set_vesting_token

    ## Test Actions ##

    usdc_approval_tx = usdc_contract.approve(
        vesting_executor_address, usdc_approval, {"from": usdc_whale}
    )

    purchase_tx = vesting_executor.purchaseVestingToken(
        desired_eefi_amount * eefi_token_decimals,
        usdc_token_address,
        eefi_contract.address,
        vesting_params_list,
        {"from": usdc_whale},
    )
    release_percentage_decimal = 0.02

    bonus_amount = int(desired_eefi_amount * release_percentage_decimal)

    eefi_vested = (desired_eefi_amount - bonus_amount) * 10**18

    vested_amount_contract = purchase_tx.events[-1]["vestedAssetAmount"]

    assert (
        vested_amount_contract == eefi_vested
    ), "Vested amount and expected vested amount don't match"

    with capsys.disabled():
        print(purchase_tx.events[-1])
        print(purchase_tx.info())
        # print(vested_amount_contract)
        print("USDC whale balance", usdc_contract.balanceOf(usdc_whale))
        print(("Purchase Amount", purchase_amount))


# Purchase asset with DAI, vest, release portion of vesting asset allocation to purchaser
def test_purchase_vesting_token_dai(
    set_vesting_token, standard_vesting_parameters, vesting_manager, main, capsys
):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    dai_contract = Contract("0x6B175474E89094C44Da98b954EedeAC495271d0F")

    dai_token_address = dai_contract.address

    dai_whale = accounts.at("0x748dE14197922c4Ae258c7939C7739f3ff1db573", force=True)

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Set Threshold and Release Percentage #

    purchase_amount_threshold = 3000

    vesting_executor.setPurchaseAmountThreshold(
        purchase_amount_threshold, {"from": accounts[1]}
    )  # Set threshold

    release_percentage = 2

    vesting_executor.setReleasePercentage(
        release_percentage, {"from": accounts[1]}
    )  # Set release percentage

    # Vesting Token Pricing #

    dai_approval = 500000 * 10**18

    desired_eefi_amount = 300

    vesting_token_price = 12

    purchase_amount = (desired_eefi_amount * vesting_token_price) * 10**18

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    vesting_params_list = standard_vesting_parameters

    # Set Vesting Token

    set_vesting_token = set_vesting_token

    ## Test Actions ##

    dai_approval_tx = dai_contract.approve(
        vesting_executor_address, dai_approval, {"from": dai_whale}
    )

    purchase_tx = vesting_executor.purchaseVestingToken(
        desired_eefi_amount * 10**18,
        dai_token_address,
        eefi_contract.address,
        vesting_params_list,
        {"from": dai_whale},
    )

    release_percentage_decimal = 0.02

    bonus_amount = int(desired_eefi_amount * release_percentage_decimal)

    eefi_vested = (desired_eefi_amount - bonus_amount) * 10**18

    vested_amount_contract = purchase_tx.events[-1]["vestedAssetAmount"]

    assert (
        vested_amount_contract == eefi_vested
    ), "Vested amount and expected vested amount don't match"

    with capsys.disabled():
        print(vested_amount_contract)
        print("DAI whale balance", dai_contract.balanceOf(dai_whale))
        print(("Purchase Amount", purchase_amount))


# Vest assets for address (owner-only), used to vest team assets
def test_standard_vesting(
    set_vesting_token, standard_vesting_parameters, vesting_manager, main, capsys
):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    vesting_params_list = standard_vesting_parameters

    ## Test Actions ##

    vestor_address = accounts[0].address

    eefi_vesting_amount = 1000 * 10**18

    standard_vesting_transaction = vesting_executor.standardVesting(
        vestor_address,
        eefi_vesting_amount,
        vesting_params_list,
        {"from": accounts[1]},
    )

    assert (
        standard_vesting_transaction.events[0]["asset"] == eefi_contract.address
    ), "Vesting token was not successfully vested"

    contract_vested_amount = int(standard_vesting_transaction.events[0]["amount"])

    assert contract_vested_amount == eefi_vesting_amount, "Vested token amount mismatch"

    with capsys.disabled():
        print(standard_vesting_transaction.info())
        print(standard_vesting_transaction.events)


# Swap asset for vested asset (includes setting swap ratio), used to swap old asset for new asset and vest
# Asset is deposited into the Token Lock contract
def test_swap_and_vest(
    set_vesting_token, standard_vesting_parameters, vesting_manager, main, capsys, chain
):
    ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 1500 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    vesting_params_list = standard_vesting_parameters

    ## Test Actions ##

    # Swap Status

    swap_status = 0  # Active

    vesting_executor.setSwappingStatus(swap_status)  # Set status

    swapping_status = vesting_executor.getCurrentSwappingStatus()  # Check status

    assert swap_status == swapping_status, "Swapping status not set to active"

    # Swap Ratio

    swap_ratio = 0.25

    swap_ratio_scaled = 0.25 * 10**4

    vesting_executor.setSwapRatio(swap_ratio_scaled, {"from": accounts[1]})

    contract_swap_ratio = vesting_executor.swapRatio()

    assert contract_swap_ratio == swap_ratio_scaled, "Swap ratio not set properly"

    # Add Authorized Swap Token

    swap_token_address = eefi_contract.address

    swap_token_decimals = 10**18

    set_swap_token = vesting_executor.addAuthorizedSwapToken(
        swap_token_address, swap_token_decimals, {"from": accounts[1]}
    )

    swap_token_details = vesting_executor.authorizedSwapTokens(swap_token_address)

    assert (
        swap_token_details[0] == swap_token_address
    ), "Swap token address not set properly"
    assert (
        swap_token_details[1] == swap_token_decimals
    ), "Swap token decimals not set properly"

    # Add Vesting Token

    set_vesting_token = set_vesting_token

    # Swap Transaction

    swap_token_amount = 252.36585

    swap_token_decimals = 10**18

    token_to_swap = eefi_contract.address

    eefi_approval = 5000 * 10**18

    vesting_token_decimals = 10**18

    eefi_approval_tx = eefi_contract.approve(
        vesting_executor_address, eefi_approval, {"from": eefi_whale}
    )

    swap_and_vest_transaction = vesting_executor.swapAndVest(
        swap_token_amount * swap_token_decimals,
        token_to_swap,
        vesting_params_list,
        {"from": eefi_whale},
    )

    expected_vested_token_amount = swap_token_amount * swap_ratio
    contract_vested_token_amount = (
        int(swap_and_vest_transaction.events[-2]["amount"]) / vesting_token_decimals
    )

    assert math.isclose(
        expected_vested_token_amount, contract_vested_token_amount, rel_tol=0.005
    ), f"The amount vested ({contract_vested_token_amount}) and the expected amount ({expected_vested_token_amount}) are not as close as expected."

    with capsys.disabled():
        print(swap_and_vest_transaction.info())


# Swap asset for vested asset (includes setting swap ratio), used to swap old asset for new asset and vest
# Token lock is set to inactive and asset is deposited into the Treasury contract
def test_swap_and_vest_treasury(
    set_vesting_token, standard_vesting_parameters, vesting_manager, main, capsys, chain
):
    ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 1500 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    vesting_params_list = standard_vesting_parameters

    ## Test Actions ##

    # Swap Status

    swap_status = 0  # Active

    vesting_executor.setSwappingStatus(swap_status)  # Set status

    swapping_status = vesting_executor.getCurrentSwappingStatus()  # Check status

    assert swap_status == swapping_status, "Swapping status not set to active"

    # Token Lock Status

    token_lock_status = 1  # Inactive

    vesting_executor.setTokenLockStatus(token_lock_status)  # Set status

    token_lock_status_contract = (
        vesting_executor.getCurrentTokenLockStatus()
    )  # Check status

    assert (
        token_lock_status == token_lock_status_contract
    ), "Token locking not set to inactive"

    # Swap Ratio

    swap_ratio = 0.25

    swap_ratio_scaled = 0.25 * 10**4

    vesting_executor.setSwapRatio(swap_ratio_scaled, {"from": accounts[1]})

    contract_swap_ratio = vesting_executor.swapRatio()

    assert contract_swap_ratio == swap_ratio_scaled, "Swap ratio not set properly"

    # Add Authorized Swap Token

    swap_token_address = eefi_contract.address

    swap_token_decimals = 10**18

    set_swap_token = vesting_executor.addAuthorizedSwapToken(
        swap_token_address, swap_token_decimals, {"from": accounts[1]}
    )

    swap_token_details = vesting_executor.authorizedSwapTokens(swap_token_address)

    assert (
        swap_token_details[0] == swap_token_address
    ), "Swap token address not set properly"
    assert (
        swap_token_details[1] == swap_token_decimals
    ), "Swap token decimals not set properly"

    # Add Vesting Token

    set_vesting_token = set_vesting_token

    # Swap Transaction

    swap_token_amount = 632.89652

    swap_token_decimals = 10**18

    token_to_swap = eefi_contract.address

    eefi_approval = 5000 * 10**18

    vesting_token_decimals = 10**18

    eefi_approval_tx = eefi_contract.approve(
        vesting_executor_address, eefi_approval, {"from": eefi_whale}
    )

    swap_and_vest_transaction = vesting_executor.swapAndVest(
        swap_token_amount * swap_token_decimals,
        token_to_swap,
        vesting_params_list,
        {"from": eefi_whale},
    )

    treasury_address = "0xf950a86013bAA227009771181a885E369e158da3"

    assert (
        swap_and_vest_transaction.events[3]["to"] == treasury_address
    ), "Token not transferred to Treasury address"

    expected_vested_token_amount = swap_token_amount * swap_ratio
    contract_vested_token_amount = (
        int(swap_and_vest_transaction.events[-2]["amount"]) / vesting_token_decimals
    )

    assert math.isclose(
        expected_vested_token_amount, contract_vested_token_amount, rel_tol=0.005
    ), f"The amount vested ({contract_vested_token_amount}) and the expected amount ({expected_vested_token_amount}) are not as close as expected."

    with capsys.disabled():
        print(swap_and_vest_transaction.info())


# Purchase is less than purchase price threshold (no bonus provided)
def test_purchase_vesting_token_purchase_price_lower_than_threshold(
    set_vesting_token, standard_vesting_parameters, vesting_manager, main, capsys
):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    dai_contract = Contract("0x6B175474E89094C44Da98b954EedeAC495271d0F")

    dai_token_address = dai_contract.address

    dai_whale = accounts.at("0x748dE14197922c4Ae258c7939C7739f3ff1db573", force=True)

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Set Threshold and Release Percentage #

    purchase_amount_threshold = 3000

    vesting_executor.setPurchaseAmountThreshold(
        purchase_amount_threshold, {"from": accounts[1]}
    )  # Set threshold

    release_percentage = 2

    vesting_executor.setReleasePercentage(
        release_percentage, {"from": accounts[1]}
    )  # Set release percentage

    # Vesting Token Pricing #

    vesting_token_price = 12

    dai_approval = 500000 * 10**18

    desired_eefi_amount = 25.786

    purchase_amount = (desired_eefi_amount * vesting_token_price) * 10**18

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    vesting_params_list = standard_vesting_parameters

    # Set Vesting Token

    eefi_token_address = eefi_contract.address

    eefi_token_decimals = 10**18

    set_vesting_token = set_vesting_token

    ## Test Actions ##

    dai_approval_tx = dai_contract.approve(
        vesting_executor_address, dai_approval, {"from": dai_whale}
    )

    purchase_tx = vesting_executor.purchaseVestingToken(
        desired_eefi_amount * eefi_token_decimals,
        dai_token_address,
        eefi_contract.address,
        vesting_params_list,
        {"from": dai_whale},
    )

    scaled_desired_eefi_amount = desired_eefi_amount * 10**18

    assert (
        float(purchase_tx.events[-1]["vestedAssetAmount"]) == scaled_desired_eefi_amount
    ), "Purchase amount not expected amount"

    with capsys.disabled():
        print(purchase_tx.info())
        print("DAI whale balance", dai_contract.balanceOf(dai_whale))
        print(("Purchase Amount", purchase_amount))


##### ----- Vested Asset Claiming / Schedule Cancellation ----- #####


# Claim standard vested asset after 1 year (note that contract claims on behalf of user, but token is sent to schedule holder)
def test_vesting_claim_standard_vest(vesting_manager, main, capsys, chain):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    asset_address = eefi_contract.address
    is_fixed = False
    cliff_weeks = 52  # 1 year
    vesting_weeks = 55  # Vesting occurs over 3 weeks post-cliff
    start_time = time.time()  # Current time in UNIX

    vesting_params_list = [
        asset_address,
        is_fixed,
        cliff_weeks,
        vesting_weeks,
        start_time,
    ]

    # Vest Tokens #

    vestor_address = accounts[0].address

    eefi_vesting_amount = 1000 * 10**18

    standard_vesting_transaction = vesting_executor.standardVesting(
        vestor_address,
        eefi_vesting_amount,
        vesting_params_list,
        {"from": accounts[1]},
    )

    # Move Chain Forward ##

    unix_seconds_in_a_day = 86399
    days = 375
    unix_time_elapsed = int(unix_seconds_in_a_day * days)

    unix_time_at_end_of_vesting = int(start_time + unix_time_elapsed)

    chain.mine(1, unix_time_at_end_of_vesting)
    ## Test Actions ##

    account_vesting_schedule = vesting_executor.retrieveScheduleInfo(vestor_address)

    account_vesting_number = account_vesting_schedule[0][0]

    # Test is of partial claim, as vesting period has not concluded
    account_claim_transaction = vesting_executor.claimTokens(
        account_vesting_number, vestor_address
    )

    assert (
        account_claim_transaction.events[1]["claimer"] == vestor_address
    ), "Vesting claim did not succeed"

    with capsys.disabled():
        print(standard_vesting_transaction.info())
        print(account_vesting_schedule)
        print(account_claim_transaction.info())
        print(vestor_address)


# #Claim purchased asset after 1 year
def test_vesting_claim_purchase(
    set_vesting_token, vesting_manager, main, capsys, chain
):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    dai_contract = Contract("0x6B175474E89094C44Da98b954EedeAC495271d0F")

    dai_token_address = dai_contract.address

    dai_whale = accounts.at("0x748dE14197922c4Ae258c7939C7739f3ff1db573", force=True)

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Set Threshold and Release Percentage #

    purchase_amount_threshold = 3000

    vesting_executor.setPurchaseAmountThreshold(
        purchase_amount_threshold, {"from": accounts[1]}
    )  # Set threshold

    release_percentage = 2

    vesting_executor.setReleasePercentage(
        release_percentage, {"from": accounts[1]}
    )  # Set release percentage

    # Vesting Token Pricing #

    vesting_token_price = 12

    dai_approval = 500000 * 10**18

    desired_eefi_amount = 300

    purchase_amount = (desired_eefi_amount * vesting_token_price) * 10**18

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set Vesting Token

    eefi_token_address = eefi_contract.address

    eefi_token_decimals = 10**18

    set_vesting_token = set_vesting_token

    # Set up Vesting Parameters #

    asset_address = eefi_contract.address
    is_fixed = False  # Vesting can be cancelled
    cliff_weeks = 52  # 1 year
    vesting_weeks = 55  # Vesting occurs over 3 weeks post-cliff
    start_time = current_time = time.time()  # Current time in UNIX

    vesting_params_list = [
        asset_address,
        is_fixed,
        cliff_weeks,
        vesting_weeks,
        start_time,
    ]

    ## Buy Vesting Tokens ##

    dai_approval_tx = dai_contract.approve(
        vesting_executor_address, dai_approval, {"from": dai_whale}
    )

    purchase_tx = vesting_executor.purchaseVestingToken(
        desired_eefi_amount * eefi_token_decimals,
        dai_token_address,
        eefi_contract.address,
        vesting_params_list,
        {"from": dai_whale},
    )

    # Move Chain Forward ##

    unix_seconds_in_a_day = 86399
    days = 375
    unix_time_elapsed = int(unix_seconds_in_a_day * days)

    unix_time_at_end_of_vesting = int(start_time + unix_time_elapsed)

    chain.mine(1, unix_time_at_end_of_vesting)

    ## Test Actions ##

    dai_whale_address = dai_whale.address

    account_vesting_schedule = vesting_executor.retrieveScheduleInfo(dai_whale_address)

    account_vesting_number = account_vesting_schedule[0][0]

    # Test is of partial claim, as vesting period has not concluded
    account_claim_transaction = vesting_executor.claimTokens(
        account_vesting_number, dai_whale_address
    )

    assert (
        account_claim_transaction.events[1]["claimer"] == dai_whale_address
    ), "Vesting claim did not succeed"

    with capsys.disabled():
        print(purchase_tx.info())
        print(account_vesting_schedule)
        print(account_claim_transaction.info())
        print(dai_whale_address)


# Cancel individual vesting schedule after 3 months (multisig only)
def test_vesting_cancellation(vesting_manager, main, capsys, chain):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    asset_address = eefi_contract.address
    is_fixed = False
    cliff_weeks = 52  # 1 year
    vesting_weeks = 55  # Vesting occurs over 3 weeks post-cliff
    start_time = time.time()  # Current time in UNIX

    vesting_params_list = [
        asset_address,
        is_fixed,
        cliff_weeks,
        vesting_weeks,
        start_time,
    ]

    # Vest Tokens ##

    vestor_address = accounts[0].address

    eefi_vesting_amount = 1000 * 10**18

    standard_vesting_transaction = vesting_executor.standardVesting(
        vestor_address,
        eefi_vesting_amount,
        vesting_params_list,
        {"from": accounts[1]},
    )

    ## Move Chain Forward ##

    unix_seconds_in_a_day = 86399
    days = 95
    unix_time_elapsed = int(unix_seconds_in_a_day * days)

    unix_time_at_end_of_vesting = int(start_time + unix_time_elapsed)

    chain.mine(1, unix_time_at_end_of_vesting)

    ## Test Actions ##

    account_vesting_schedule = vesting_executor.retrieveScheduleInfo(vestor_address)

    account_vesting_number = account_vesting_schedule[0][0]

    cancel_vesting_for_user = vesting_executor.cancelVesting(
        vestor_address, account_vesting_number, {"from": eefi_whale}
    )

    assert (
        cancel_vesting_for_user.events[0]["value"] == eefi_vesting_amount
    ), "Vesting was not cancelled"

    with capsys.disabled():
        print(cancel_vesting_for_user.info())


##### ----- Views  ----- #####


# View global locked token amount
def test_view_locked_token_amount(
    set_vesting_token, standard_vesting_parameters, vesting_manager, main, capsys
):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    vesting_params_list = standard_vesting_parameters

    # Vest Tokens #

    vestor_address = accounts[0].address

    eefi_vesting_amount = 1000 * 10**18

    standard_vesting_transaction = vesting_executor.standardVesting(
        vestor_address,
        eefi_vesting_amount,
        vesting_params_list,
        {"from": accounts[1]},
    )

    ## Test Actions ##

    # View Locked Amount #

    locked_tokens = vesting_executor.viewLockedAmount(eefi_contract.address)

    assert (
        locked_tokens == eefi_vesting_amount
    ), "Mismatch between tokens vested and locked."

    with capsys.disabled():
        print("Locked and vested tokens should match.")


# View indiviudal vesting schedule
def test_view_individual_vesting_schedule(
    standard_vesting_parameters, vesting_manager, main, capsys, chain
):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    vesting_params_list = standard_vesting_parameters

    # Vest Tokens ##

    vestor_address = accounts[0].address

    eefi_vesting_amount = 1000 * 10**18

    standard_vesting_transaction = vesting_executor.standardVesting(
        vestor_address,
        eefi_vesting_amount,
        vesting_params_list,
        {"from": accounts[1]},
    )

    ## Test Actions ##

    account_vesting_schedule = vesting_executor.retrieveScheduleInfo(vestor_address)

    account_vesting_number = account_vesting_schedule[0][0]

    assert account_vesting_number == 0, "View not working properly"

    with capsys.disabled():
        print(
            "Vesting schedule number should be 0, as it is the first vesting schedule created"
        )
        print(account_vesting_schedule)


##### ----- Requirements ----- #####


# #Can't vest more tokens than in the contract (locked + unlocked quantities)
def test_standard_vesting_token_runs_out(
    standard_vesting_parameters, vesting_manager, main, capsys
):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    vesting_params_list = standard_vesting_parameters

    ## Test Actions ##

    # Vest 1
    vestor_address = accounts[0].address

    eefi_vesting_amount = 2500 * 10**18

    standard_vesting_transaction = vesting_executor.standardVesting(
        vestor_address,
        eefi_vesting_amount,
        vesting_params_list,
        {"from": accounts[1]},
    )

    # Vest 2 (more than what is left in contract - locked)
    vestor_address = accounts[0].address

    eefi_vesting_amount = 2501 * 10**18

    with brownie.reverts("Vesting: Not enough unlocked supply available to to vest"):
        standard_vesting_transaction = vesting_executor.standardVesting(
            vestor_address,
            eefi_vesting_amount,
            vesting_params_list,
            {"from": accounts[1]},
        )

    with capsys.disabled():
        print(standard_vesting_transaction.info())
        print(
            "Transaction should fail because total vested amount requests exceed contract balance (locked and unlocked tokens)"
        )


# Can't purchase vesting asset with non-approved token
def test_purchase_vesting_token_non_approved_token(
    set_vesting_token, standard_vesting_parameters, vesting_manager, main, capsys
):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    lusd_contract = Contract("0x5f98805A4E8be255a32880FDeC7F6728C6568bA0")

    lusd_token_address = lusd_contract.address

    lusd_whale = accounts.at("0x833642ED556a8a41D5fd5729D9fED774A039f13c", force=True)

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Set Threshold and Release Percentage #

    purchase_amount_threshold = 3000

    vesting_executor.setPurchaseAmountThreshold(
        purchase_amount_threshold, {"from": accounts[1]}
    )  # Set threshold

    release_percentage = 2

    vesting_executor.setReleasePercentage(
        release_percentage, {"from": accounts[1]}
    )  # Set release percentage

    lusd_approval = 500000 * 10**18

    desired_eefi_amount = 300

    vesting_token_price = 12

    purchase_amount = (desired_eefi_amount * vesting_token_price) * 10**18

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    vesting_params_list = standard_vesting_parameters

    # Set Vesting Token

    eefi_token_address = eefi_contract.address

    eefi_token_decimals = 10**18

    set_vesting_token = set_vesting_token

    ## Test Actions ##

    lusd_approval_tx = lusd_contract.approve(
        vesting_executor_address, lusd_approval, {"from": lusd_whale}
    )

    with brownie.reverts("Exchange token must be a valid approved token"):
        purchase_tx = vesting_executor.purchaseVestingToken(
            desired_eefi_amount * eefi_token_decimals,
            lusd_token_address,
            eefi_contract.address,
            vesting_params_list,
            {"from": lusd_whale},
        )

    with capsys.disabled():
        print("Purchase should fail because LUSD not in approved tokens list")


# Can't vest when standard vesting is paused.
def test_vesting_when_paused(
    standard_vesting_parameters, vesting_manager, main, capsys
):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    vesting_params_list = standard_vesting_parameters

    # Pause Vesting

    testing_status = 1  # Inactive

    vesting_executor.setStandardVestingStatus(
        testing_status, {"from": accounts[1]}
    )  # Set status

    ## Test Actions ##

    vestor_address = accounts[0].address

    eefi_vesting_amount = 2500 * 10**18

    with brownie.reverts("Standard vesting not active"):
        standard_vesting_transaction = vesting_executor.standardVesting(
            vestor_address,
            eefi_vesting_amount,
            vesting_params_list,
            {"from": accounts[1]},
        )

    with capsys.disabled():
        print("Transaction should fail because vesting is paused")


# Can't purchase and vest when vesting is paused
def test_purchase_vesting_paused(
    set_vesting_token, standard_vesting_parameters, vesting_manager, main, capsys
):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    dai_contract = Contract("0x6B175474E89094C44Da98b954EedeAC495271d0F")

    dai_token_address = dai_contract.address

    dai_whale = accounts.at("0x748dE14197922c4Ae258c7939C7739f3ff1db573", force=True)

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Set Threshold and Release Percentage #

    purchase_amount_threshold = 3000

    vesting_executor.setPurchaseAmountThreshold(
        purchase_amount_threshold, {"from": accounts[1]}
    )  # Set threshold

    release_percentage = 2

    vesting_executor.setReleasePercentage(
        release_percentage, {"from": accounts[1]}
    )  # Set release percentage

    # Vesting Token Pricing #

    dai_approval = 500000 * 10**18

    desired_eefi_amount = 300

    vesting_token_price = 12

    purchase_amount = (desired_eefi_amount * vesting_token_price) * 10**18

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    vesting_params_list = standard_vesting_parameters

    # Set Vesting Token

    set_vesting_token = set_vesting_token

    # Pause Vesting

    testing_status = 1  # Inactive

    vesting_executor.setVestingStatus(
        testing_status, {"from": accounts[1]}
    )  # Set status

    ## Test Actions ##

    dai_approval_tx = dai_contract.approve(
        vesting_executor_address, dai_approval, {"from": dai_whale}
    )

    with brownie.reverts("Vesting not active"):
        purchase_tx = vesting_executor.purchaseVestingToken(
            desired_eefi_amount * 10**18,
            dai_token_address,
            eefi_contract.address,
            vesting_params_list,
            {"from": dai_whale},
        )

    with capsys.disabled():
        print(("Vesting should fail because it is inactive."))


# Can't swap when swapping is paused.
def test_swap_and_vest_when_paused(vesting_manager, main, capsys, chain):
    ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    asset_address = eefi_contract.address
    is_fixed = False
    cliff_weeks = 52  # 1 year
    vesting_weeks = 55  # Vesting occurs over 3 weeks post-cliff
    start_time = time.time()  # Current time in UNIX

    vesting_params_list = [
        asset_address,
        is_fixed,
        cliff_weeks,
        vesting_weeks,
        start_time,
    ]

    ## Test Actions ##

    # Swap Ratio

    swap_ratio = 0.25

    swap_ratio_scaled = 0.25 * 10**4

    vesting_executor.setSwapRatio(swap_ratio_scaled, {"from": accounts[1]})

    contract_swap_ratio = vesting_executor.swapRatio()

    # Add Authorized Swap Token

    swap_token_address = eefi_contract.address

    swap_token_decimals = 10**18

    set_swap_token = vesting_executor.addAuthorizedSwapToken(
        swap_token_address, swap_token_decimals, {"from": accounts[1]}
    )

    swap_token_details = vesting_executor.authorizedSwapTokens(swap_token_address)

    # Swap Transaction

    swap_token_amount = 100 * 10**18

    swap_token_decimals = 10**18

    swap_token_amount_scaled = swap_token_amount * swap_token_decimals

    token_to_swap = eefi_contract.address

    eefi_approval = 200 * 10**18

    eefi_approval_tx = eefi_contract.approve(
        vesting_executor_address, eefi_approval, {"from": eefi_whale}
    )

    with brownie.reverts("Swapping not active"):
        swap_and_vest_transaction = vesting_executor.swapAndVest(
            swap_token_amount_scaled,
            token_to_swap,
            vesting_params_list,
            {"from": eefi_whale},
        )

    with capsys.disabled():
        print("Swap transaction should fail because swapping is not active.")


# #Can't swap with unapproved swapping asset
def test_swap_and_vest_with_non_approved_asset(
    standard_vesting_parameters, vesting_manager, main, capsys, chain
):
    ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    vesting_params_list = standard_vesting_parameters

    # Swap Status

    swap_status = 0  # Active

    vesting_executor.setSwappingStatus(swap_status, {"from": accounts[1]})  # Set status

    # Swap Ratio

    swap_ratio = 0.25

    swap_ratio_scaled = 0.25 * 10**4

    vesting_executor.setSwapRatio(swap_ratio_scaled, {"from": accounts[1]})

    contract_swap_ratio = vesting_executor.swapRatio()

    # Swap Transaction

    swap_token_amount = 100

    swap_token_decimals = 10**18

    swap_token_amount_scaled = swap_token_amount * swap_token_decimals

    token_to_swap = eefi_contract.address

    eefi_approval = 200 * 10**18

    eefi_approval_tx = eefi_contract.approve(
        vesting_executor_address, eefi_approval, {"from": eefi_whale}
    )

    ## Test Actions ##

    with brownie.reverts("Token must be authorized swap token"):
        swap_and_vest_transaction = vesting_executor.swapAndVest(
            swap_token_amount_scaled,
            token_to_swap,
            vesting_params_list,
            {"from": eefi_whale},
        )

    with capsys.disabled():
        print("Swap transaction should fail because swap token is not authorized.")


# Can't vest with incorrect vesting parameters
def test_standard_vesting_incorrect_parameters(vesting_manager, main, capsys):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Invalid Vesting Parameters (Standard Vesting) #

    asset_address = eefi_contract.address
    is_fixed = False
    cliff_weeks = 52  # 1 year
    vesting_weeks = 50  # Vesting is less than cliff
    start_time = time.time()  # Current time in UNIX

    vesting_params_list = [
        asset_address,
        is_fixed,
        cliff_weeks,
        vesting_weeks,
        start_time,
    ]

    ## Test Actions ##

    vestor_address = accounts[0].address

    eefi_vesting_amount = 2500 * 10**18

    with brownie.reverts("Vesting: invalid vesting params set"):
        standard_vesting_transaction = vesting_executor.standardVesting(
            vestor_address,
            eefi_vesting_amount,
            vesting_params_list,
            {"from": accounts[1]},
        )

    with capsys.disabled():
        print("Transaction should fail because vesting parameters are not correct.")
        

# #Can't swap with invalid vesting parameters (start time)
def test_swap_and_vest_with_wrong_start_time(
    valid_vesting_parameters, vesting_manager, main, capsys, chain
):
    ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")
    
    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Invalid Vesting Parameters (Wrong Start Time) #

    asset_address = eefi_contract.address
    is_fixed = False
    cliff_weeks = 52  # 1 year
    vesting_weeks = 50  # Vesting is less than cliff
    start_time = time.time() - 30*60  # Current time in UNIX 30 minutes ago

    vesting_params_list = [
        asset_address,
        is_fixed,
        cliff_weeks,
        vesting_weeks,
        start_time,
    ]

    # Swap Status

    swap_status = 0  # Active

    vesting_executor.setSwappingStatus(swap_status, {"from": accounts[1]})  # Set status

    # Swap Ratio

    swap_ratio = 0.25

    swap_ratio_scaled = 0.25 * 10**4

    vesting_executor.setSwapRatio(swap_ratio_scaled, {"from": accounts[1]})

    contract_swap_ratio = vesting_executor.swapRatio()
    
    # Add Authorized Swap Token

    swap_token_address = eefi_contract.address

    swap_token_decimals = 10**18

    set_swap_token = vesting_executor.addAuthorizedSwapToken(
        swap_token_address, swap_token_decimals, {"from": accounts[1]}
    )

    # Swap Transaction

    swap_token_amount = 100

    swap_token_decimals = 10**18

    swap_token_amount_scaled = swap_token_amount * swap_token_decimals

    token_to_swap = eefi_contract.address

    eefi_approval = 200 * 10**18

    eefi_approval_tx = eefi_contract.approve(
        vesting_executor_address, eefi_approval, {"from": eefi_whale}
    )

    ## Test Actions ##

    with brownie.reverts("Vesting: not valid parameters"):
        swap_and_vest_transaction = vesting_executor.swapAndVest(
            swap_token_amount_scaled,
            token_to_swap,
            vesting_params_list,
            {"from": eefi_whale},
        )

    with capsys.disabled():
        print("Swap transaction should fail because start time is not valid.")
        
        
 #Can't swap with invalid vesting parameters (cliff and vesting)
def test_swap_and_vest_with_wrong_cliff_and_vesting(
    valid_vesting_parameters, vesting_manager, main, capsys, chain
):
    ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")
    
    dai_contract = Contract("0x6B175474E89094C44Da98b954EedeAC495271d0F")

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Invalid Vesting Parameters (Wrong Cliff and vesting period) #

    asset_address = eefi_contract.address
    is_fixed = False
    cliff_weeks = 2  # 1 year
    vesting_weeks = 10  
    start_time = time.time() #Current time in UNIX

    vesting_params_list = [
        asset_address,
        is_fixed,
        cliff_weeks,
        vesting_weeks,
        start_time,
    ]

    # Swap Status

    swap_status = 0  # Active

    vesting_executor.setSwappingStatus(swap_status, {"from": accounts[1]})  # Set status
    
    # Add Authorized Swap Token

    swap_token_address = eefi_contract.address

    swap_token_decimals = 10**18

    set_swap_token = vesting_executor.addAuthorizedSwapToken(
        swap_token_address, swap_token_decimals, {"from": accounts[1]}
    )

    # Swap Ratio

    swap_ratio = 0.25

    swap_ratio_scaled = 0.25 * 10**4

    vesting_executor.setSwapRatio(swap_ratio_scaled, {"from": accounts[1]})

    contract_swap_ratio = vesting_executor.swapRatio()

    # Swap Transaction

    swap_token_amount = 100

    swap_token_decimals = 10**18

    swap_token_amount_scaled = swap_token_amount * swap_token_decimals

    token_to_swap = eefi_contract.address

    eefi_approval = 200 * 10**18

    eefi_approval_tx = eefi_contract.approve(
        vesting_executor_address, eefi_approval, {"from": eefi_whale}
    )

    ## Test Actions ##

    with brownie.reverts("Vesting: not valid parameters"):
        swap_and_vest_transaction = vesting_executor.swapAndVest(
            swap_token_amount_scaled,
            token_to_swap,
            vesting_params_list,
            {"from": eefi_whale},
        )

    with capsys.disabled():
        print("Swap transaction should fail because cliff and vesting are not valid.")
        
        
# Can't purchase if start time is incorrect
def test_purchase_vesting_start_time_incorrect(
    set_vesting_token, valid_vesting_parameters, vesting_manager, main, capsys
):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    dai_contract = Contract("0x6B175474E89094C44Da98b954EedeAC495271d0F")

    dai_token_address = dai_contract.address

    dai_whale = accounts.at("0x748dE14197922c4Ae258c7939C7739f3ff1db573", force=True)

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Set Threshold and Release Percentage #

    purchase_amount_threshold = 3000

    vesting_executor.setPurchaseAmountThreshold(
        purchase_amount_threshold, {"from": accounts[1]}
    )  # Set threshold

    release_percentage = 2

    vesting_executor.setReleasePercentage(
        release_percentage, {"from": accounts[1]}
    )  # Set release percentage

    # Vesting Token Pricing #

    dai_approval = 500000 * 10**18

    desired_eefi_amount = 300

    vesting_token_price = 12

    purchase_amount = (desired_eefi_amount * vesting_token_price) * 10**18

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

     # Set up Invalid Vesting Parameters (Wrong Start Time) #

    asset_address = eefi_contract.address
    is_fixed = False
    cliff_weeks = 52  # 1 year
    vesting_weeks = 50  # Vesting is less than cliff
    start_time = time.time() - 30*60  # Current time in UNIX 30 minutes ago

    vesting_params_list = [
        asset_address,
        is_fixed,
        cliff_weeks,
        vesting_weeks,
        start_time,
    ]

    # Set Vesting Token

    set_vesting_token = set_vesting_token

    ## Test Actions ##

    dai_approval_tx = dai_contract.approve(
        vesting_executor_address, dai_approval, {"from": dai_whale}
    )

    with brownie.reverts("Vesting: invalid vesting params set"):
        purchase_tx = vesting_executor.purchaseVestingToken(
            desired_eefi_amount * 10**18,
            dai_token_address,
            eefi_contract.address,
            vesting_params_list,
            {"from": dai_whale},
        )

    with capsys.disabled():
        print(("Vesting should fail because start time is incorrect."))
        

# Can't purchase if cliff and vesting are incorrect
def test_purchase_vesting_cliff_vesting_incorrect(
    set_vesting_token, valid_vesting_parameters, vesting_manager, main, capsys
):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    dai_contract = Contract("0x6B175474E89094C44Da98b954EedeAC495271d0F")

    dai_token_address = dai_contract.address

    dai_whale = accounts.at("0x748dE14197922c4Ae258c7939C7739f3ff1db573", force=True)

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Set Threshold and Release Percentage #

    purchase_amount_threshold = 3000

    vesting_executor.setPurchaseAmountThreshold(
        purchase_amount_threshold, {"from": accounts[1]}
    )  # Set threshold

    release_percentage = 2

    vesting_executor.setReleasePercentage(
        release_percentage, {"from": accounts[1]}
    )  # Set release percentage

    # Vesting Token Pricing #

    dai_approval = 500000 * 10**18

    desired_eefi_amount = 300

    vesting_token_price = 12

    purchase_amount = (desired_eefi_amount * vesting_token_price) * 10**18

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

     # Set up Invalid Vesting Parameters (Wrong Start Time) #

    asset_address = eefi_contract.address
    is_fixed = False
    cliff_weeks = 18  # 1 year
    vesting_weeks = 20  # Vesting is less than cliff
    start_time = time.time()  # Current time in UNIX 30 minutes ago

    vesting_params_list = [
        asset_address,
        is_fixed,
        cliff_weeks,
        vesting_weeks,
        start_time,
    ]

    # Set Vesting Token

    set_vesting_token = set_vesting_token

    ## Test Actions ##

    dai_approval_tx = dai_contract.approve(
        vesting_executor_address, dai_approval, {"from": dai_whale}
    )

    with brownie.reverts("Vesting: invalid vesting params set"):
        purchase_tx = vesting_executor.purchaseVestingToken(
            desired_eefi_amount * 10**18,
            dai_token_address,
            eefi_contract.address,
            vesting_params_list,
            {"from": dai_whale},
        )

    with capsys.disabled():
        print(("Vesting should fail because cliff and vesting are incorrect."))


# Can't claim asset during cliff period
def test_vesting_claim_standard_before_cliff_end(vesting_manager, main, capsys, chain):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    asset_address = eefi_contract.address
    is_fixed = False
    cliff_weeks = 52  # 1 year
    vesting_weeks = 55  # Vesting occurs over 3 weeks post-cliff
    start_time = time.time()  # Current time in UNIX

    vesting_params_list = [
        asset_address,
        is_fixed,
        cliff_weeks,
        vesting_weeks,
        start_time,
    ]

    # Vest Tokens #

    vestor_address = accounts[0].address

    eefi_vesting_amount = 1000 * 10**18

    standard_vesting_transaction = vesting_executor.standardVesting(
        vestor_address,
        eefi_vesting_amount,
        vesting_params_list,
        {"from": accounts[1]},
    )

    # Move Chain Forward (Less than 1 year) ##

    unix_seconds_in_a_day = 86399
    days = 275
    unix_time_elapsed = int(unix_seconds_in_a_day * days)

    unix_time_at_end_of_vesting = int(start_time + unix_time_elapsed)

    chain.mine(1, unix_time_at_end_of_vesting)

    ## Test Actions ##

    account_vesting_schedule = vesting_executor.retrieveScheduleInfo(vestor_address)

    account_vesting_number = account_vesting_schedule[0][0]

    # Attempt to claim before cliff end

    with brownie.reverts("Vesting: cliff not reached"):
        account_claim_transaction = vesting_executor.claimTokens(
            account_vesting_number, vestor_address
        )

    with capsys.disabled():
        print("Vesting claim should fail because cliff period has not ended")


# Can't withdraw locked tokens
def test_vesting_cant_withdraw_locked_tokens(vesting_manager, main, capsys, chain):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 2000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    asset_address = eefi_contract.address
    is_fixed = False
    cliff_weeks = 52  # 1 year
    vesting_weeks = 55  # Vesting occurs over 3 weeks post-cliff
    start_time = time.time()  # Current time in UNIX

    vesting_params_list = [
        asset_address,
        is_fixed,
        cliff_weeks,
        vesting_weeks,
        start_time,
    ]

    # Vest Tokens #

    vestor_address = accounts[0].address

    eefi_vesting_amount = 2000 * 10**18  # Lock all tokens

    standard_vesting_transaction = vesting_executor.standardVesting(
        vestor_address,
        eefi_vesting_amount,
        vesting_params_list,
        {"from": accounts[1]},
    )

    # Move Chain Forward (Less than 1 year) ##

    unix_seconds_in_a_day = 86399
    days = 275
    unix_time_elapsed = int(unix_seconds_in_a_day * days)

    unix_time_at_end_of_vesting = int(start_time + unix_time_elapsed)

    chain.mine(1, unix_time_at_end_of_vesting)

    ## Test Actions ##

    withdraw_amount = 2000 * 10**18  # Attempt to withdraw locked tokens

    with brownie.reverts("Vesting: Can't withdraw"):
        withdrawal_tx = vesting_executor.withdrawVestingTokens(
            withdraw_amount, eefi_contract.address, {"from": eefi_whale}
        )

    with capsys.disabled():
        print("Withdrawal transaction should fail because all tokens are locked.")


# Can't cancel fixed vesting schedule
def test_vesting_cancellation_fixed_decline(vesting_manager, main, capsys, chain):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    asset_address = eefi_contract.address
    is_fixed = True  # Vesting schedule can't be changed
    cliff_weeks = 52  # 1 year
    vesting_weeks = 55  # Vesting occurs over 3 weeks post-cliff
    start_time = time.time()  # Current time in UNIX

    vesting_params_list = [
        asset_address,
        is_fixed,
        cliff_weeks,
        vesting_weeks,
        start_time,
    ]

    # Vest Tokens ##

    vestor_address = accounts[0].address

    eefi_vesting_amount = 1000 * 10**18

    standard_vesting_transaction = vesting_executor.standardVesting(
        vestor_address,
        eefi_vesting_amount,
        vesting_params_list,
        {"from": accounts[1]},
    )

    ## Move Chain Forward ##

    unix_seconds_in_a_day = 86399
    days = 95
    unix_time_elapsed = int(unix_seconds_in_a_day * days)

    unix_time_at_end_of_vesting = int(start_time + unix_time_elapsed)

    chain.mine(1, unix_time_at_end_of_vesting)

    ## Test Actions ##

    account_vesting_schedule = vesting_executor.retrieveScheduleInfo(vestor_address)

    account_vesting_number = account_vesting_schedule[0][0]

    with brownie.reverts("Vesting: Account is fixed"):
        cancel_vesting_for_user = vesting_executor.cancelVesting(
            vestor_address, account_vesting_number, {"from": eefi_whale}
        )

    with capsys.disabled():
        print("Transaction should fail because vesting schedule is fixed.")


# Account can't claim another's vesting tokens
def test_vesting_claim_standard_non_vesting_account(
    vesting_manager, main, capsys, chain
):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    asset_address = eefi_contract.address
    is_fixed = False
    cliff_weeks = 52  # 1 year
    vesting_weeks = 55  # Vesting occurs over 3 weeks post-cliff
    start_time = time.time()  # Current time in UNIX

    vesting_params_list = [
        asset_address,
        is_fixed,
        cliff_weeks,
        vesting_weeks,
        start_time,
    ]

    # Vest Tokens #

    vestor_address = accounts[0].address

    eefi_vesting_amount = 1000 * 10**18

    standard_vesting_transaction = vesting_executor.standardVesting(
        vestor_address,
        eefi_vesting_amount,
        vesting_params_list,
        {"from": accounts[1]},
    )

    # Move Chain Forward (1 year) ##

    unix_seconds_in_a_day = 86399
    days = 370
    unix_time_elapsed = int(unix_seconds_in_a_day * days)

    unix_time_at_end_of_vesting = int(start_time + unix_time_elapsed)

    chain.mine(1, unix_time_at_end_of_vesting)

    ## Test Actions ##

    account_vesting_schedule = vesting_executor.retrieveScheduleInfo(vestor_address)

    account_vesting_number = account_vesting_schedule[0][0]

    # Attempt to claim another's Schedule

    non_vesting_address = "0x4D663Bc146DBE8337D5fECd99d6f5cAB7B316A26"

    with brownie.reverts("Vesting: Token not claimable"):
        account_claim_transaction = vesting_executor.claimTokens(
            account_vesting_number, non_vesting_address
        )

    with capsys.disabled():
        print(
            "Vesting claim should fail because account does not have a vesting schedule"
        )


##### ----- Edge Cases ----- #####


# Purchase fractions of vesting asset
def test_purchase_vesting_token_dai_fraction(
    set_vesting_token, standard_vesting_parameters, vesting_manager, main, capsys
):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    dai_contract = Contract("0x6B175474E89094C44Da98b954EedeAC495271d0F")

    dai_token_address = dai_contract.address

    dai_whale = accounts.at("0x748dE14197922c4Ae258c7939C7739f3ff1db573", force=True)

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Set Threshold and Release Percentage #

    purchase_amount_threshold = 3000

    vesting_executor.setPurchaseAmountThreshold(
        purchase_amount_threshold, {"from": accounts[1]}
    )  # Set threshold

    release_percentage = 2

    vesting_executor.setReleasePercentage(
        release_percentage, {"from": accounts[1]}
    )  # Set release percentage

    # Vesting Token Pricing #

    vesting_token_price = 12

    dai_approval = 500000 * 10**18

    desired_eefi_amount = 330.50

    purchase_amount = (desired_eefi_amount * vesting_token_price) * 10**18

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    vesting_params_list = standard_vesting_parameters

    # Set Vesting Token

    set_vesting_token = set_vesting_token

    ## Test Actions ##

    dai_approval_tx = dai_contract.approve(
        vesting_executor_address, dai_approval, {"from": dai_whale}
    )

    purchase_tx = vesting_executor.purchaseVestingToken(
        desired_eefi_amount * 10**18,
        dai_token_address,
        eefi_contract.address,
        vesting_params_list,
        {"from": dai_whale},
    )

    release_percentage_decimal = 0.02

    bonus_amount = int(desired_eefi_amount * release_percentage_decimal)

    eefi_vested = (desired_eefi_amount - bonus_amount) * 10**18

    vested_amount_contract = purchase_tx.events[-1]["vestedAssetAmount"]

    assert (
        vested_amount_contract == eefi_vested
    ), "Vested amount and expected vested amount don't match"

    with capsys.disabled():
        print(purchase_tx.info())
        print("DAI whale balance", dai_contract.balanceOf(dai_whale))
        print(("Purchase Amount", purchase_amount))


# Purchase price is fraction; amount desired is fraction;
def test_purchase_vesting_token_dai_price_fraction(
    set_vesting_token, standard_vesting_parameters, vesting_manager, main, capsys
):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    dai_contract = Contract("0x6B175474E89094C44Da98b954EedeAC495271d0F")

    dai_token_address = dai_contract.address

    dai_whale = accounts.at("0x748dE14197922c4Ae258c7939C7739f3ff1db573", force=True)

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Set Threshold and Release Percentage #

    purchase_amount_threshold = 3000

    vesting_executor.setPurchaseAmountThreshold(
        purchase_amount_threshold, {"from": accounts[1]}
    )  # Set threshold

    release_percentage = 2

    vesting_executor.setReleasePercentage(
        release_percentage, {"from": accounts[1]}
    )  # Set release percentage

    # Vesting Token Pricing #

    vesting_token_price = (
        12.25 * 10**4
    )  # Note that adjustment was made in set_vesting_token_fixture for this test; The number is added to check calculations.

    dai_approval = 500000 * 10**18

    desired_eefi_amount = 400.7689878

    purchase_amount = desired_eefi_amount * vesting_token_price

    purchase_amount_non_scaled = (desired_eefi_amount * vesting_token_price) / 10**4

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    vesting_params_list = standard_vesting_parameters

    # Set Vesting Token

    set_vesting_token = set_vesting_token

    ## Test Actions ##

    dai_approval_tx = dai_contract.approve(
        vesting_executor_address, dai_approval, {"from": dai_whale}
    )

    purchase_tx = vesting_executor.purchaseVestingToken(
        desired_eefi_amount * 10**18,
        dai_token_address,
        eefi_contract.address,
        vesting_params_list,
        {"from": dai_whale},
    )
    release_percentage_decimal = 0.02

    bonus_amount = int(desired_eefi_amount * release_percentage_decimal)

    eefi_vested = (desired_eefi_amount - bonus_amount) * 10**18

    payment_amount_contract = float(purchase_tx.events[0]["number"]) / 10**18

    assert math.isclose(
        payment_amount_contract, purchase_amount_non_scaled, rel_tol=1e-9
    ), f"The payment amount in the contract ({payment_amount_contract}) and the purchase amount ({purchase_amount}) are not as close as expected."

    with capsys.disabled():
        print(purchase_tx.info())
        print("DAI whale balance", dai_contract.balanceOf(dai_whale))
        print("Purchase Amount", purchase_amount_non_scaled)


# Test to ensure vesting still happens if small amounts of token are unlocked
def test_standard_vesting_minor_difference(
    standard_vesting_parameters, vesting_manager, main, capsys
):
    # ## Test Setup ##

    # Contracts #

    vesting_executor = main

    eefi_contract = Contract("0x92915c346287DdFbcEc8f86c8EB52280eD05b3A3")

    vesting_executor_address = vesting_executor.address

    vesting_manager_address = vesting_manager

    # Transfer EEFI #

    eefi_whale = accounts.at("0xf950a86013bAA227009771181a885E369e158da3", force=True)

    transfer_amount = 5000 * 10**18

    eefi_contract.transfer(
        vesting_manager_address, transfer_amount, {"from": eefi_whale}
    )

    contract_eefi_balance = eefi_contract.balanceOf(vesting_manager_address)

    # Set up Vesting Parameters #

    vesting_params_list = standard_vesting_parameters

    ## Test Actions ##

    # Vest 1
    vestor_address = accounts[0].address

    eefi_vesting_amount = 2500 * 10**18

    standard_vesting_transaction = vesting_executor.standardVesting(
        vestor_address,
        eefi_vesting_amount,
        vesting_params_list,
        {"from": accounts[1]},
    )

    # Vest 2 (small amount less than what's in the contract + locked)
    vestor_address = accounts[0].address

    eefi_vesting_amount = 2499.998 * 10**18

    standard_vesting_transaction_1 = vesting_executor.standardVesting(
        vestor_address,
        eefi_vesting_amount,
        vesting_params_list,
        {"from": accounts[1]},
    )

    assert standard_vesting_transaction.status == 1, "Transaction did not succeed"
    assert (
        standard_vesting_transaction_1.status == 1
    ), "Second transaction did not succeed"

    with capsys.disabled():
        print(standard_vesting_transaction.info())
        print(standard_vesting_transaction_1.info())
        print(
            "Transaction should succeed because total vested amount requests leave dust in the contract"
        )
