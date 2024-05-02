!#/bin/bash

# 1. start the local OP stack
make --directory=./lib/optimism devnet-up
# 2. deploy contracts
#   a. deploy the L2 token contract
forge script script/solidity/OpTokenTest.s.sol:OpTest --sig 'deployL2Token()' --rpc-url http://127.0.0.1:9545 --broadcast
#   b. deploy the L1 token contract
# 3. mint a L1 token.
# 4. Send it to the bridge
forge script script/solidity/OpTokenTest.s.sol:OpTest --sig 'deployL1Token()' --rpc-url http://127.0.0.1:8545 --broadcast --slow
# 5. check that the token has bridged
sleep 10
cast call 0xe9f93e290eC3503D87742F1cf71577d04f062D36 'ownerOf(uint256)(address)' 1 --rpc-url http://127.0.0.1:9545
# 6. stop the local op stack
make --directory=./lib/optimism devnet-down
