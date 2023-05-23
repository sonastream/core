// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.16;

//  ___  _____  _  _    __      ___  ____  ____  ____    __    __  __
// / __)(  _  )( \( )  /__\    / __)(_  _)(  _ \( ___)  /__\  (  \/  )
// \__ \ )(_)(  )  (  /(__)\   \__ \  )(   )   / )__)  /(__)\  )    (
// (___/(_____)(_)\_)(__)(__)  (___/ (__) (_)\_)(____)(__)(__)(_/\/\_)

import { SonaAdmin } from "./access/SonaAdmin.sol";
import { UUPSUpgradeable } from "openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { MerkleProofLib } from "solady/utils/MerkleProofLib.sol";
import { SonaRewardToken } from "./SonaRewardToken.sol";
import { IERC20Upgradeable as IERC20 } from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IRewardGateway } from "./interfaces/IRewardGateway.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { Initializable } from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import { ZeroCheck } from "./utils/ZeroCheck.sol";

/// @title The interface for Track Collectors and Artists to claim Rewards
contract SonaRewards is Initializable, SonaAdmin {
	using MerkleProofLib for bytes32[];
	using ZeroCheck for address;
	using ZeroCheck for address payable;
	/*//////////////////////////////////////////////////////////////
		STRUCTS
	//////////////////////////////////////////////////////////////*/

	struct RewardRoot {
		bytes32 hash;
		uint64 start;
		uint64 end;
	}

	/*//////////////////////////////////////////////////////////////
		MAPPINGS
	//////////////////////////////////////////////////////////////*/

	/// @notice A pseudo-array to hold each publish merkle root
	/// @dev This is a cleaner storage pattern for upgradable contracts compared to an actual array
	mapping(uint256 => RewardRoot) public rewardRoots;

	/// @notice the unix epoch timestamp representing the end of last period rewards were claimed for a given tokenId
	/// @dev this value can only monotonically increase, in order to prevent double claims
	mapping(uint256 => uint64) public dateTimeLastClaimed;

	/*//////////////////////////////////////////////////////////////
		STATE
	//////////////////////////////////////////////////////////////*/

	/// @notice The id of the last RewardRoot published
	uint256 public lastRootId;

	address private _rewardVault;
	SonaRewardToken private _sonaRewardToken;
	IERC20 private _paymentToken;
	IWETH private _wETHToken;
	string private _claimLookupUrl;

	/*//////////////////////////////////////////////////////////////
		EVENTS
	//////////////////////////////////////////////////////////////*/
	event IntegrationsUpdated(
		address sonaRewardToken,
		address paymentToken,
		address wETHToken,
		address rewardVault,
		string claimLookupUrl
	);

	event RewardRootCreated(
		uint256 indexed rootId,
		bytes32 indexed hash,
		uint64 start,
		uint64 end
	);
	event RewardRootInvalidated(uint256 indexed rootId);

	event RewardsClaimed(
		uint256 indexed tokenId,
		address indexed claimant,
		uint256 indexed rootId,
		uint256 amount
	);
	/*//////////////////////////////////////////////////////////////
		ERRORS
	//////////////////////////////////////////////////////////////*/

	error RootNonexistent(uint256 rootId);
	error ClaimantNotHolder(address claimant, uint256 tokenId);
	error ClaimLengthMismatch();
	error InvalidProof();
	error InvalidClaimAttempt();
	error StartNotBeforeEnd(uint64 start, uint64 end);
	error RewardTransferFailed();
	error InvalidTokenInputs(address paymentToken, address wETHToken);
	error OffchainLookup(
		address sender,
		string[] urls,
		bytes callData,
		bytes4 callbackFunction,
		bytes extraData
	);

	/*//////////////////////////////////////////////////////////////
		CONSTRUCTOR
	//////////////////////////////////////////////////////////////*/

	/// @dev a proxiable base contract should not be initializable
	constructor() {
		_disableInitializers();
	}

	/// @notice the constructor-like function used for proxy contracts
	/// @dev Pass in either a non-zero paymentToken_ or wETHToken_ param. One and only one should be non-zero
	/// @param _eoaAdmin The administrator of proxy upgrades and RewardRoots
	/// @param sonaRewardToken_ The address of the SonaRewardToken NFT smart contract
	/// @param paymentToken_ The address of the reward token Collectors and Artists earn
	/// @param wETHToken_ The address of the wETH token if Collectors and Artists earn ETH
	/// @param rewardVault_ The holder of the reward token that has granted this contract enough of an allowance to operate
	/// @param claimLookupUrl_ The templated url returned via `OffchainLookup`. Must be EIP-3668 compliant
	function initialize(
		address _eoaAdmin,
		SonaRewardToken sonaRewardToken_,
		IERC20 paymentToken_,
		IWETH wETHToken_,
		address rewardVault_,
		string calldata claimLookupUrl_
	) public initializer {
		_setupRole(_ADMIN_ROLE, _eoaAdmin);
		_setRoleAdmin(_ADMIN_ROLE, _ADMIN_ROLE);

		_updateIntegrations(
			sonaRewardToken_,
			paymentToken_,
			wETHToken_,
			rewardVault_,
			claimLookupUrl_
		);
	}

	/*//////////////////////////////////////////////////////////////
		External Functions
	//////////////////////////////////////////////////////////////*/

	// receive function

	/// @dev only accept ETH from our registered `_wETHToken`
	receive() external payable {
		if (msg.sender != address(_wETHToken)) {
			revert();
		}
	}

	// Mint Roots

	/// @notice publish a merkle tree root and allow Reward claims
	/// @dev the subsequent start time should be equal to the last published end time for given period
	/// @param _root The hash of the merkle root to submit proofs against.
	/// @param _start The epoch start time (in seconds) for the reward period
	/// @param _end The epoch end time (in seconds) for the reward period
	function addRoot(
		bytes32 _root,
		uint64 _start,
		uint64 _end
	) public onlySonaAdmin {
		if (!(_start < _end)) revert StartNotBeforeEnd(_start, _end);
		unchecked {
			++lastRootId;
		}
		rewardRoots[lastRootId] = RewardRoot(_root, _start, _end);
		emit RewardRootCreated(lastRootId, _root, _start, _end);
	}

	/// @notice prevent claims against a published root
	/// @param _rootId The index number representing the root to be invalidated
	function invalidateRoot(uint256 _rootId) public onlySonaAdmin {
		if (_rootId > lastRootId) revert RootNonexistent(_rootId);
		rewardRoots[_rootId].hash = bytes32(type(uint256).max);
		emit RewardRootInvalidated(_rootId);
	}

	// Claim Funds

	/// @notice get the api endpoint and request payload to get merkle claim info
	/// @dev this should always revert and allows for a fast preflight response
	/// @param _tokenId The SonaRewardToken token ID
	/// @param _start The beginning of the time period to collect rewards for
	/// @param _end The end of the time period to collect rewards for
	function claimLookup(
		uint256 _tokenId,
		uint64 _start,
		uint64 _end
	) public view {
		string[] memory urls = new string[](1);
		urls[0] = _claimLookupUrl;
		revert OffchainLookup(
			address(this),
			urls,
			abi.encodeWithSelector(
				IRewardGateway.getRewardsforPeriod.selector,
				_tokenId,
				_start,
				_end
			),
			this.claimRewards.selector,
			""
		);
	}

	/// @notice collect tokens by presenting valid proofs and owning token number `_tokenId`
	/// @param _tokenId The SonaRewardToken for which rewards are being claimed
	/// @param _rootIds the index numbers of the roots to prove against
	/// @param _proofs the proofs for each respective root
	/// @param _amounts the amounts to be claimed from each respective root
	function claimRewards(
		uint256 _tokenId,
		uint256[] calldata _rootIds,
		bytes32[][] calldata _proofs,
		uint256[] calldata _amounts
	) public {
		if (_sonaRewardToken.ownerOf(_tokenId) != msg.sender)
			revert ClaimantNotHolder(msg.sender, _tokenId);
		if (_rootIds.length != _proofs.length || _rootIds.length != _amounts.length)
			revert ClaimLengthMismatch();

		uint256 transferAmount;
		uint256 _rootIdsArrayLength = _rootIds.length;
		for (uint256 i = 0; i < _rootIdsArrayLength; i++) {
			_claimRewardsOne(_tokenId, _rootIds[i], _proofs[i], _amounts[i]);
			transferAmount += _amounts[i];
		}
		address payoutAddress = _getPayoutAddress(_tokenId, msg.sender);
		if (address(_paymentToken).isNotZero()) {
			if (
				!_paymentToken.transferFrom(_rewardVault, payoutAddress, transferAmount)
			) revert RewardTransferFailed();
		} else {
			if (!_wETHToken.transferFrom(_rewardVault, address(this), transferAmount))
				revert RewardTransferFailed();
			_wETHToken.withdraw(transferAmount);
			payable(payoutAddress).transfer(transferAmount);
		}
	}

	/// @notice the contract owner can update state variables
	/// @param sonaRewardToken_ The address of the SonaRewardToken NFT smart contract
	/// @param paymentToken_ The address of the reward token Collectors and Artists earn
	/// @param wETHToken_ The address of the wETH token if Collectors and Artists earn ETH
	/// @param rewardVault_ The holder of the reward token that has granted this contract enough of an allowance to operate
	/// @param claimLookupUrl_ The templated url returned via `OffchainLookup`. Must be EIP-3668 compliant
	function updateIntegrations(
		SonaRewardToken sonaRewardToken_,
		IERC20 paymentToken_,
		IWETH wETHToken_,
		address rewardVault_,
		string calldata claimLookupUrl_
	) public onlySonaAdmin {
		_updateIntegrations(
			sonaRewardToken_,
			paymentToken_,
			wETHToken_,
			rewardVault_,
			claimLookupUrl_
		);
	}

	/*//////////////////////////////////////////////////////////////
		Internal Functions
	//////////////////////////////////////////////////////////////*/
	function _claimRewardsOne(
		uint256 _tokenId,
		uint256 _rootId,
		bytes32[] calldata _proof,
		uint256 _amount
	) internal {
		RewardRoot storage root = rewardRoots[_rootId];
		if (root.start < dateTimeLastClaimed[_tokenId])
			revert InvalidClaimAttempt();
		bytes32 leaf = keccak256(
			bytes.concat(
				keccak256(abi.encode(_tokenId, _amount, root.start, root.end))
			)
		);
		if (_proof.verify(root.hash, leaf)) {
			dateTimeLastClaimed[_tokenId] = root.end; // prevent reentrancy by updating this before transfer
			emit RewardsClaimed(_tokenId, msg.sender, _rootId, _amount);
			return;
		}
		revert InvalidProof();
	}

	function _updateIntegrations(
		SonaRewardToken sonaRewardToken_,
		IERC20 paymentToken_,
		IWETH wETHToken_,
		address rewardVault_,
		string calldata claimLookupUrl_
	) internal {
		if (
			(address(paymentToken_).isNotZero() && address(wETHToken_).isNotZero()) ||
			address(paymentToken_) == address(wETHToken_)
		) {
			revert InvalidTokenInputs(address(paymentToken_), address(wETHToken_));
		}
		_sonaRewardToken = sonaRewardToken_;
		_paymentToken = paymentToken_;
		_wETHToken = wETHToken_;
		_rewardVault = rewardVault_;
		_claimLookupUrl = claimLookupUrl_;
		emit IntegrationsUpdated(
			address(sonaRewardToken_),
			address(paymentToken_),
			address(wETHToken_),
			rewardVault_,
			claimLookupUrl_
		);
	}

	function _getPayoutAddress(
		uint256 _tokenId,
		address _holder
	) internal view returns (address payable payoutAddress) {
		address payable splits = _sonaRewardToken.getRewardTokenSplitsAddr(
			_tokenId
		);
		return splits.isNotZero() ? splits : payable(_holder);
	}
}
