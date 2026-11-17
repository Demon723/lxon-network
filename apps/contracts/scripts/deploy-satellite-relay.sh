#!/bin/bash

# Satellite Relay Deployment Script
# This script builds and deploys the satellite relay infrastructure

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

echo "📡 Deploying Satellite Relay Infrastructure"
echo "📋 Chain ID: 724"
echo "🛰️  Satellite Integration: DTN Protocol"

# Build the satellite relay
echo "📦 Building Satellite Relay binary..."
cargo build --release -p space-relay

# Check if build was successful
if [ ! -f "target/release/space-relay" ]; then
    echo "❌ Build failed - binary not found"
    exit 1
fi

echo "✅ Build successful"
echo "📦 Binary location: target/release/space-relay"

# Configuration for satellite relay
RELAY_CONFIG='{
  "dtn_config": {
    "node_id": "lxon-gateway",
    "max_bundle_size": 1048576,
    "max_lifetime": 86400
  },
  "orbit_config": {
    "tle_source": "celestrak",
    "update_interval": 3600
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
  ]
}'

echo "🔧 Satellite Relay Configuration:"
echo "$RELAY_CONFIG"

# Deployment steps
echo "🚀 Deployment steps:"
echo "   1. Upload binary to satellite gateway servers"
echo "   2. Install DTN protocol daemon"
echo "   3. Configure orbit and ground station data"
echo "   4. Start satellite relay service"
echo "   5. Verify satellite communication"

# Create deployment directory structure
echo "📁 Creating deployment directory structure..."
mkdir -p deployments/satellite-relay

# Save configuration
echo "$RELAY_CONFIG" > deployments/satellite-relay/config.json

echo "✅ Satellite Relay deployment preparation complete"
echo "📋 Next steps:"
echo "   1. Upload target/release/space-relay to gateway servers"
echo "   2. Deploy configuration to /etc/lxon/satellite-relay.json"
echo "   3. Create systemd service file"
echo "   4. Start the service"

echo "📄 Deployment assets:"
echo "   - Binary: target/release/space-relay"
echo "   - Config: deployments/satellite-relay/config.json"