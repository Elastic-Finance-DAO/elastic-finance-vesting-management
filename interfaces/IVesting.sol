// SPDX-License-Identifier: MIT

pragma solidity >=0.4.23 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/finance/VestingWallet.sol";


// WETH Interface //
interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint wad) external; 
}

