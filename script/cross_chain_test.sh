!#/bin/bash
set -exo pipefail

export SONA_DEPLOYMENT_SALT=snap_into_sonastreams
export MNEMONIC='test test test test test test test test test test test junk'
export ETHERSCAN_KEY=$(doppler secrets get ETHERSCAN_KEY --plain)
export SONA_TOKEN_URI_DOMAIN=testdomain.com
# 1. start the local OP stack
make --directory=./lib/optimism devnet-up
# 2. deploy contracts
#   a. deploy the L2 token contract
echo "waiting for chains to start up..."
sleep 20
forge script script/solidity/OpTokenTest.s.sol:OpTest --sig 'deployL2Token()' --rpc-url http://127.0.0.1:9545 --broadcast
#   b. deploy the L1 token contract
# 3. mint a L1 token.
# 4. Send it to the bridge
forge script script/solidity/OpTokenTest.s.sol:OpTest --sig 'deployL1Token()' --rpc-url http://127.0.0.1:8545 --broadcast --slow
# 5. check that the token has bridged
sleep 10
echo "Getting L2 Token Owner: "
cast call 0xe9f93e290eC3503D87742F1cf71577d04f062D36 'ownerOf(uint256)(address)' 1 --rpc-url http://127.0.0.1:9545
# 6. stop the local op stack
make --directory=./lib/optimism devnet-clean
