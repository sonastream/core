# Beta Technical Design


* [Feature List](#feature-list)
* [Overview](#overview)
* [Steps in Detail](#steps-in-detail)
  * [Modified 0xSplits contract](#modified-0xsplits-contract)
  * [Auction Bundle Payload Changes](#auction-bundle-payload-changes)

## Feature List

Below is the list of functionality to be added for the beta release:

- deploy modified [splits] wallet as part of the flow track onboarding flow
- configure modified split to deliver publisher payouts from NFT auction
- NFT settlement and artist reward claims push value to publishers/distributors
  represented as bridge addresses
- ~~allocate empty (`address(0)`) buckets to be configured later~~
- allow for the configuration and redirection of claim funds by any split holder

## Overview

1. Deploy the [splits] contracts
    - one containing the config for the Publishing payout post-auction
    - another containing the rewards configuration
2. New auction bundle payload that includes an optional `rewardsPayout` address
   executed in the [splits]
3. On settlement, push funds through to Publisher via the [splits] contract and optionally
    configure a separate `rewardsPayout` address on the NFT token.

## Steps in Detail

### Modified 0xSplits contract

We need a modified [splits] contract that is able to enact the above features

1. It needs to push funds to [bridge]-suppled addresses whenever another address
   interacts with the contract
2. It needs to allow any non-bridge address that is part of the split to push signed configs.
3. It needs to accept signed config changes from existing splits members and authenticate the signatures.

Currently. nothing really exists to handle our case of pushing funds through contracts
to some entities while allowing other actors to claim their funds, because pushing eth
and ERC20s to an address the protocol or tx sender doesn't own is not typically best practice.

### Auction Bundle Payload Changes

The current bundle is as follows:

```solidity
struct MetadataBundle {
  uint256 tokenId;
  address payable payout;
  string arweaveTxId;
}
```

Adding a separate address for the new rewards [splits] wallet and handling
the different potential configurations is a simple way to handle these
any potential config combination. It also recognizes that many songs
will probably utilize the same split config for NFT sales and rewards,
so it makes sense to reuse splits across songs. This also has the postive
side effect of batching funds for various groups from multiple tracks,
which allows for fewer transactions to claim funds.

```solidity
struct MetadataBundle {
  uint256 tokenId;
  address payable payout;
  address payable rewardsPayout;
  string arweaveTxId;
}
```

In the case that the rewardsPayout address is zero, the payout
address is submitted to the `SonaRewardToken.mintFromAuction` function.

This allows for flexibility around the cases of publish/distribution
arrangements, publish-only, and distribution-only.

| Agreement Type                      | `payout` address   | `rewardsPayout` address |
| ----------------------------------- | ------------------ | ----------------------- |
| same Publishing & Distribution      | splits address `A` | splits address `A`      |
| different Publishing & Distribution | splits address `A` | splits address `B`      |
| Distribution                        | `address(0)`       | splits address          |
| Publishing                          | splits address     | `address(0)`            |

[bridge]: https://bridge.xyz
[splits]: https://www.0xsplits.com
