// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.15;

import "forge-std/Script.sol";
import { ERC1967Proxy } from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20Upgradeable as IERC20 } from "openzeppelin-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { Deployer } from "./Deploy_libraries.s.sol";

import { SonaRewardToken } from "../../contracts/SonaRewardToken.sol";
import { SonaRewardTokenL1, IERC721Bridge } from "../../contracts/SonaRewardTokenL1.sol";
import { SonaRewardTokenL2 } from "../../contracts/SonaRewardTokenL2.sol";
import { ERC20Mock } from "../../contracts/test/mock/ERC20Mock.sol";

contract OpTest is Script, Deployer {
	address[] internal _OWNER;
	address internal _REDISTRIBUTION;
	address internal _TREASURY;
	address internal _AUTHORIZER;
	string internal _URI_DOMAIN;

	function setUp() external {
		string memory mnemonic = vm.envString("MNEMONIC");
		if (block.chainid == 1) {
			_OWNER = vm.envAddress("SONA_OWNER_ADDRESS", ",");
			_REDISTRIBUTION = vm.envAddress("SONA_REDISTRIBUTION_ADDRESS");
			_TREASURY = vm.envAddress("SONA_TREASURY_ADDRESS");
			_AUTHORIZER = vm.envAddress("SONA_AUTHORIZER_ADDRESS");
			_URI_DOMAIN = vm.envString("SONA_TOKEN_URI_DOMAIN");
		} else {
			address[] memory testOwner = new address[](1);
			testOwner[0] = vm.addr(vm.deriveKey(mnemonic, 1));
			_OWNER = vm.envOr("SONA_OWNER_ADDRESS", ",", testOwner);
			_AUTHORIZER = vm.envOr(
				"SONA_AUTHORIZER_ADDRESS",
				vm.addr(vm.deriveKey(mnemonic, 2))
			);
			_REDISTRIBUTION = vm.envOr(
				"SONA_REDISTRIBUTION_ADDRESS",
				vm.addr(vm.deriveKey(mnemonic, 3))
			);
			_TREASURY = vm.envOr(
				"SONA_TREASURY_ADDRESS",
				vm.addr(vm.deriveKey(mnemonic, 3))
			);
			_URI_DOMAIN = vm.envString("SONA_TOKEN_URI_DOMAIN");
		}
	}

	function run() external view override {
		bytes memory code = type(SonaRewardToken).creationCode;
		bytes memory l1Code = type(SonaRewardTokenL1).creationCode;
		bytes memory l2Code = type(SonaRewardTokenL2).creationCode;

		address addr = getCreate2Address(code, "");
		address l1Addr = getCreate2Address(l1Code, "");
		address l2Addr = getCreate2Address(l2Code, "");
		console.log(addr);
		console.log(l1Addr);
		console.log(l2Addr);
	}

	function deployL2Token() external {
		address rewardToken = deployToken();
		string memory mnemonic = vm.envString("MNEMONIC");

		SonaRewardToken tokenProxy = SonaRewardToken(rewardToken);

		uint256 key = vm.deriveKey(mnemonic, 0);
		console.log("L2 Token deployer: ", vm.addr(key));
		vm.startBroadcast(key);

		// Deploy Reward Token
		SonaRewardTokenL2 tokenBase = new SonaRewardTokenL2(
			900,
			0x4200000000000000000000000000000000000014
		);
		vm.stopBroadcast();
		console.log("new base: ", address(tokenBase));

		bytes memory reinitL2 = abi.encodeWithSelector(
			SonaRewardTokenL2.setRemoteTokenAddress.selector,
			address(tokenProxy)
		);
		vm.startBroadcast(key);
		tokenProxy.upgradeToAndCall(address(tokenBase), reinitL2);
		/*
		SonaRewardTokenL2(rewardToken).grantRole(
			MINTER_ROLE,
			0x4200000000000000000000000000000000000014
		);
		*/
	}

	function deployL1Token() external {
		address rewardToken = deployToken();
		string memory mnemonic = vm.envString("MNEMONIC");

		SonaRewardToken tokenProxy = SonaRewardToken(rewardToken);

		uint256 key = vm.deriveKey(mnemonic, 1);
		console.log("L1 Token deployer: ", vm.addr(key));
		vm.startBroadcast(key);

		// Deploy Reward Token
		SonaRewardTokenL1 tokenBase = new SonaRewardTokenL1();
		vm.stopBroadcast();
		console.log("new base: ", address(tokenBase));

		key = vm.deriveKey(mnemonic, 0);
		vm.startBroadcast(key);
		tokenProxy.upgradeTo(address(tokenBase));

		// TODO: Grant permissions to creator to mint
		SonaRewardTokenL1(rewardToken).grantRole(MINTER_ROLE, vm.addr(key));
		// TODO: Mint and send token
		SonaRewardTokenL1(rewardToken).mint(
			vm.addr(key),
			1,
			"",
			payable(address(0))
		);
		vm.stopBroadcast();
		uint256[] memory tokenIds = new uint256[](1);
		tokenIds[0] = 1;
		vm.startBroadcast(key);
		SonaRewardTokenL1(rewardToken).migratetoL2(
			tokenIds,
			IERC721Bridge(0x3Aa5ebB10DC797CAC828524e59A333d0A371443c)
		);
	}

	function attemptBridge() external {
		address rewardToken = 0x78B2C28fD89B6B7E86b071908FB3Ecb569C66Bf4;
		string memory mnemonic = vm.envString("MNEMONIC");
		uint256 key = vm.deriveKey(mnemonic, 0);
		console.log("L2 Token deployer: ", vm.addr(key));

		vm.startBroadcast(key);
		SonaRewardTokenL1(rewardToken).mint(
			vm.addr(key),
			2,
			"",
			payable(address(0))
		);
		vm.stopBroadcast();

		uint256[] memory tokenIds = new uint256[](1);
		tokenIds[0] = 2;

		vm.startBroadcast(key);
		SonaRewardTokenL1(rewardToken).migratetoL2(
			tokenIds,
			IERC721Bridge(0x3Aa5ebB10DC797CAC828524e59A333d0A371443c)
		);
	}

	function deployToken() internal returns (address rewardToken) {
		string memory mnemonic = vm.envString("MNEMONIC");

		bytes memory initCode = type(SonaRewardToken).creationCode;
		address tokenBase = getCreate2Address(initCode, "");
		console.log("token base: ", tokenBase);
		deploy2(initCode, "", vm.deriveKey(mnemonic, 0));

		address _TEMP_SONA_OWNER = vm.addr(vm.deriveKey(mnemonic, 0));
		bytes memory rewardTokenInitializerArgs = abi.encodeWithSelector(
			SonaRewardToken.initialize.selector,
			"Sona Rewards Token",
			"SONA",
			_TEMP_SONA_OWNER,
			_TREASURY,
			_URI_DOMAIN
		);

		initCode = type(ERC1967Proxy).creationCode;
		rewardToken = getCreate2Address(
			initCode,
			abi.encode(tokenBase, rewardTokenInitializerArgs)
		);

		deploy2(
			initCode,
			abi.encode(tokenBase, rewardTokenInitializerArgs),
			vm.deriveKey(mnemonic, 0)
		);
		if (rewardToken.code.length == 0) {
			revert("reward token Deployment failed");
		}
		console.log("proxy address: ", rewardToken);
	}
}
