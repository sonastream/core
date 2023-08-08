// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

import { ISplitMain } from "./interfaces/ISplitMain.sol";
import { IERC20Upgradeable as IERC20 } from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

///ERRORS

/// @notice Unauthorized sender
error Unauthorized();

///
///@title SplitWallet
///@author 0xSplits <will@0xSplits.xyz>
///@notice The implementation logic for `SplitProxy`.
///@dev `SplitProxy` handles `receive()` itself to avoid the gas cost with `DELEGATECALL`.
contract SplitWallet {
	using SafeTransferLib for address;

	///EVENTS

	/// @notice emitted after each successful ETH transfer to proxy
	/// @param split Address of the split that received ETH
	/// @param amount Amount of ETH received
	event ReceiveETH(address indexed split, uint256 amount);

	///STORAGE

	///STORAGE - CONSTANTS & IMMUTABLES

	/// @notice address of SplitMain for split distributions & EOA/SC withdrawals
	ISplitMain public immutable splitMain;

	///MODIFIERS

	/// @notice Reverts if the sender isn't SplitMain
	modifier onlySplitMain() {
		if (msg.sender != address(splitMain)) revert Unauthorized();
		_;
	}

	///CONSTRUCTOR

	constructor() {
		splitMain = ISplitMain(msg.sender);
	}

	///FUNCTIONS - PUBLIC & EXTERNAL

	/// @notice Sends amount `amount` of ETH in proxy to SplitMain
	/// @dev payable reduces gas cost; no vulnerability to accidentally lock
	/// ETH introduced since fn call is restricted to SplitMain
	/// @param amount Amount to send
	function sendETHToMain(uint256 amount) external payable onlySplitMain {
		address(splitMain).safeTransferETH(amount);
	}

	/// @notice Sends amount `amount` of ERC20 `token` in proxy to SplitMain
	/// @dev payable reduces gas cost; no vulnerability to accidentally lock
	/// ETH introduced since fn call is restricted to SplitMain
	/// @param token Token to send
	/// @param amount Amount to send
	function sendERC20ToMain(
		IERC20 token,
		uint256 amount
	) external payable onlySplitMain {
		address(token).safeTransfer(address(splitMain), amount);
	}
}