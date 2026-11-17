#!/bin/bash
# Server deployment script for LXON mainnet
# Run on EC2 instance: i-0407f01e54ddb910d
# SSH: ubuntu@16.171.20.249 (EC2 Instance Connect)

export DEPLOYER_PRIVATE_KEY="0xf32ed14ef603f2fe92ef11bb597edbfcd67c3f8c1b85da1b03b8a03a98b0946"
export RPC_URL="http://16.171.20.249:8546"
export CHAIN_ID=724

# Contract addresses (already deployed)
export LXON="0xAbB6281e51e81c513c7F50D3B1c378CF6a30890c"
export WLXON="0x4F90ddD66C2616DC8870F7f7B94b3e0247068ad4"
export FACTORY="0x2f795957675eD1A178FBdC030cD394276536bA78"
export OLD_ROUTER="0xef4ce5C29dD14fE2A342F0BC38D5A1cEBD500e6C"
export OLD_PAIR="0xa306fc2e6ab334d72d6ce1e6954965fd916a9954"

# New contracts (just deployed)
export NEW_PAIR="0xFe314aa897a9a9BCe20724F196b7085CBC407B12"
export NEW_ROUTER="0x5AD1Db2178659C4d8289b48B9e48CeFD3EC50e23"
export PSM="0xdf2D4dE919013e6f908319EcE59C9CaFbD05a49a"
export AUTOMATOR="0xDa55F55201Ccd32F107D33e6b25c698083CBF37e"

echo "=== LXON Mainnet Peg Layer Deployed ==="
echo "Pair: $NEW_PAIR"
echo "Router: $NEW_ROUTER"
echo "PSM: $PSM"
echo "Automator: $AUTOMATOR"

# 1. Fund automator with WLXON
echo "1. Funding automator..."
cast send $WLXON "deposit()" --rpc-url $RPC_URL --value 5000000000000000000000 --private-key $DEPLOYER_PRIVATE_KEY
cast send $WLXON "transfer(address,uint256)" $AUTOMATOR 5000000000000000000000 --rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY

# 2. Call automator.fund() 
echo "2. Calling automator.fund()..."
cast send $AUTOMATOR "fund()" --rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY

# 3. Test PSM deposit + mint
echo "3. Testing PSM..."
cast send $PSM "deposit(uint256)" 1000000000000000000 --rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY
cast send $PSM "mint(uint256)" 1000000000000000000 --rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY

echo "=== Deployment Complete ==="
