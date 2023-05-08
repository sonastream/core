import { createTestClient, createWalletClient, http, numberToHex, bytesToHex, hexToBytes, createPublicClient, getContract, hexToBigInt, concat } from "viem"
import { HDAccount, mnemonicToAccount } from "viem/accounts"
import { foundry } from "viem/chains"
import SonaReserveAuction from "../out-via-ir/SonaReserveAuction.sol/SonaReserveAuction.json"
import { sonaReserveAuctionABI } from "../abi/generated"

const testClient = createTestClient({
	chain: foundry,
	mode: "anvil",
	transport: http(),
})

const walletClient = createWalletClient({
	account: mnemonicToAccount("test test test test test test test test test test test junk"),
	chain: foundry,
	transport: http(),
})

const publicClient = createPublicClient({
	chain: foundry,
	transport: http(),
})

const domain = {
	name: "SonaReserveAuction",
	version: "1",
	chainId: 31337,
	verifyingContract: "0x59Fb3367bC8Ab75A898435F60757cC1Cf1875CD7",
} as const

const types = {
	MetadataBundle: [
		{ name: "arweaveTxId", type: "string" },
		{ name: "tokenId", type: "uint256" },
	],
}

const artistBundle = {
	arweaveTxId: "Hello World!",
	tokenId: concat(["0x5D2d2Ea1B0C7e2f086cC731A496A38Be1F19FD3f", numberToHex(68, { size: 12 })]),
} as const

const collectorBundle = {
	arweaveTxId: "Hello World",
	tokenId: concat(["0x5D2d2Ea1B0C7e2f086cC731A496A38Be1F19FD3f", numberToHex(69, { size: 12 })]),
} as const

async function main() {
	await testClient.setLoggingEnabled(true)
	console.log(domain)
	console.log(types)
	console.log(artistBundle)
	console.log(collectorBundle)
	let sig = await signMessage(artistBundle)
	console.log("artistBundle signature: ", split(sig))
	sig = await signMessage(collectorBundle)
	console.log("collectorBundle signature: ", split(sig))
	/*
  await testClient.setCode({
    address: domain.verifyingContract,
    bytecode: SonaReserveAuction.bytecode.object as `0x${string}`,
  })

  const auction = getContract({
    address: domain.verifyingContract,
    abi: sonaReserveAuctionABI,
    walletClient,
    publicClient,
  })

  auction.read.verify([{ arweaveTxId: message.arweaveTxId, tokenId: hexToBigInt(message.tokenId) }, v, r, s])
  */
}

main()

async function signMessage(msg: { [key: string]: unknown }): Promise<`0x${string}`> {
	return walletClient.signTypedData({
		domain,
		types,
		primaryType: "MetadataBundle",
		message: msg,
	})
}

function split(signature: `0x${string}`): [number, `0x${string}`, `0x${string}`] {
	const raw = hexToBytes(signature)
	switch (raw.length) {
		case 65:
			return [
				raw[64], // v
				bytesToHex(raw.slice(0, 32)) as `0x${string}`, // r
				bytesToHex(raw.slice(32, 64)) as `0x${string}`, // s
			]
		default:
			throw new Error("Invalid signature length, cannot split")
	}
}
