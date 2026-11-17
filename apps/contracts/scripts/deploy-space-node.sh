#!/bin/bash

# Space Node Deployment Script
# This script builds and deploys the space node software

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

echo "🛰️  Deploying Space Node Software"
echo "📋 Chain ID: 724"
echo "🛰️  Space Node: Satellite Communication Software"

# Build the space node
echo "📦 Building Space Node binary..."
cargo build --release -p space-node

# Check if build was successful
if [ ! -f "target/release/lxon-space" ]; then
    echo "❌ Build failed - binary not found"
    exit 1
fi

echo "✅ Build successful"
echo "📦 Binary location: target/release/lxon-space"

# Configuration for space node
SPACE_NODE_CONFIG='{
  "constellation": {
    "satellites": [
      {
        "id": "lxon-sat-0",
        "altitude_km": 550.0,
        "inclination_deg": 53.0,
        "raan_deg": 0.0
      },
      {
        "id": "lxon-sat-1",
        "altitude_km": 550.0,
        "inclination_deg": 53.0,
        "raan_deg": 120.0
      },
      {
        "id": "lxon-sat-2",
        "altitude_km": 550.0,
        "inclination_deg": 53.0,
        "raan_deg": 240.0
      }
    ]
  },
  "ground_stations": [
    {
      "id": "gs-blr",
      "lat_deg": 12.97,
      "lon_deg": 77.59,
      "min_elevation_deg": 10.0
    },
    {
      "id": "gs-sg",
      "lat_deg": 1.35,
      "lon_deg": 103.82,
      "min_elevation_deg": 10.0
    }
  ],
  "l2_integration": {
    "sequencer_endpoint": "http://13.61.177.64:8547",
    "batch_submission_interval_ms": 1000
  }
}'

echo "🔧 Space Node Configuration:"
echo "$SPACE_NODE_CONFIG"

# Deployment steps
echo "🚀 Deployment steps:"
echo "   1. Upload binary to ground station servers"
echo "   2. Configure constellation and ground station data"
echo "   3. Set up L2 sequencer integration"
echo "   4. Start space node service"
echo "   5. Verify satellite communication"

# Create deployment directory structure
echo "📁 Creating deployment directory structure..."
mkdir -p deployments/space-node

# Save configuration
echo "$SPACE_NODE_CONFIG" > deployments/space-node/config.json

echo "✅ Space Node deployment preparation complete"
echo "📋 Next steps:"
echo "   1. Upload target/release/lxon-space to ground station servers"
echo "   2. Deploy configuration to /etc/lxon/space-node.json"
echo "   3. Create systemd service file"
echo "   4. Start the service"

echo "📄 Deployment assets:"
echo "   - Binary: target/release/lxon-space"
echo "   - Config: deployments/space-node/config.json"