// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

import { IERC20Upgradeable as IERC20 } from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/// @title ISplitMain
/// @author 0xSplits <will@0xSplits.xyz>
interface ISplitMain {
	/// Structs
	struct SplitInput {
		address[] accounts;
		uint32[] percentAllocations;
	}

	/// FUNCTIONS

	function walletImplementation() external returns (address);

	function createSplit(
		address[] calldata accounts,
		uint32[] calldata percentAllocations
	) external returns (address);

	function updateSplit(
		address split,
		address[] calldata accounts,
		uint32[] calldata percentAllocations
	) external;

	function distributeETH(
		address split,
		address[] calldata accounts,
		uint32[] calldata percentAllocations
	) external;

	function updateAndDistributeETH(
		address split,
		address[] calldata accounts,
		uint32[] calldata percentAllocations
	) external;

	function distributeERC20(
		address split,
		IERC20 token,
		address[] calldata accounts,
		uint32[] calldata percentAllocations
	) external;

	function updateAndDistributeERC20(
		address split,
		IERC20 token,
		address[] calldata accounts,
		uint32[] calldata percentAllocations
	) external;

	function withdraw(
		address account,
		uint256 withdrawETH,
		IERC20[] calldata tokens
	) external;

	function createSplits(
		SplitInput[] calldata splits
	) external returns (address[] memory split);

	function transferControl(address split, address newController) external;

	function cancelControlTransfer(address split) external;

	function acceptControl(address split) external;

	/// EVENTS

	/// @notice emitted after each successful split creation
	/// @param split Address of the created split
	event CreateSplit(address indexed split);

	/// @notice emitted after each successful split update
	/// @param split Address of the updated split
	event UpdateSplit(address indexed split);

	/// @notice emitted after each initiated split control transfer
	/// @param split Address of the split control transfer was initiated for
	/// @param newPotentialController Address of the split's new potential controller
	event InitiateControlTransfer(
		address indexed split,
		address indexed newPotentialController
	);

	/// @notice emitted after each canceled split control transfer
	/// @param split Address of the split control transfer was canceled for
	event CancelControlTransfer(address indexed split);

	/// @notice emitted after each successful split control transfer
	/// @param split Address of the split control was transferred for
	/// @param previousController Address of the split's previous controller
	/// @param newController Address of the split's new controller
	event ControlTransfer(
		address indexed split,
		address indexed previousController,
		address indexed newController
	);

	/// @notice emitted after each successful ETH balance split
	/// @param split Address of the split that distributed its balance
	/// @param amount Amount of ETH distributed
	event DistributeETH(address indexed split, uint256 amount);

	/// @notice emitted after each successful ERC20 balance split
	/// @param split Address of the split that distributed its balance
	/// @param token Address of ERC20 distributed
	/// @param amount Amount of ERC20 distributed
	event DistributeERC20(
		address indexed split,
		IERC20 indexed token,
		uint256 amount
	);

	/// @notice emitted after each successful withdrawal
	/// @param account Address that funds were withdrawn to
	/// @param ethAmount Amount of ETH withdrawn
	/// @param tokens Addresses of ERC20s withdrawn
	/// @param tokenAmounts Amounts of corresponding ERC20s withdrawn
	event Withdrawal(
		address indexed account,
		uint256 ethAmount,
		IERC20[] tokens,
		uint256[] tokenAmounts
	);
}
