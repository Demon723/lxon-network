#!/usr/bin/env python3
import json
import sys

# Read deployment artifact
with open('out/LXONNativeTokenSimple.sol/LXONNativeToken.json', 'r') as f:
    artifact = json.load(f)

bytecode = artifact['bytecode']['object']
abi = artifact['abi']

# Extract constructor
constructor_abi = [item for item in abi if item['type'] == 'constructor'][0]

print("Bytecode length:", len(bytecode))
print("ABI functions:", [item['name'] for item in abi if item['type'] == 'function'])

# Save for deployment
deployment_data = {
    'bytecode': bytecode,
    'abi': abi,
    'constructor': constructor_abi
}

with open('deployment_data.json', 'w') as f:
    json.dump(deployment_data, f, indent=2)

print("\nDeployment data saved to deployment_data.json")
print("Contract address: 0x547f9311075986D26142c92d2AEf20d3386aC66f (validator)")
