#!/bin/bash
# =============================================================================
# Deploy LXON Token List to IPFS
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

# Check if IPFS is installed
if ! command -v ipfs &> /dev/null; then
    warn "IPFS CLI not found. Installing..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install ipfs
    else
        wget https://dist.ipfs.io/go-ipfs/v0.20.0/go-ipfs_v0.20.0_linux-amd64.tar.gz
        tar -xvzf go-ipfs_v0.20.0_linux-amd64.tar.gz
        sudo mv go-ipfs /usr/local/bin/ipfs
    fi
fi

# Initialize IPFS if not already initialized
if [ ! -d "$HOME/.ipfs" ]; then
    log "Initializing IPFS..."
    ipfs init
fi

# Start IPFS daemon
log "Starting IPFS daemon..."
ipfs daemon > /dev/null 2>&1 &
IPFS_PID=$!
sleep 5

# Upload token list to IPFS
log "Uploading token list to IPFS..."
TOKENLIST_HASH=$(ipfs add lxon.tokenlist.json | awk '{print $2}')
log "Token list uploaded: https://ipfs.io/ipfs/$TOKENLIST_HASH"

# Upload logos (create placeholder logos first)
log "Creating placeholder logos..."
mkdir -p logos
cat > logos/lxon.png << 'EOF'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==
EOF

cat > logos/wlxon.png << 'EOF'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==
EOF

cat > logos/weth.png << 'EOF'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==
EOF

cat > logos/eurc.png << 'EOF'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==
EOF

log "Uploading logos to IPFS..."
LXON_LOGO=$(ipfs add logos/lxon.png | awk '{print $2}')
WLXON_LOGO=$(ipfs add logos/wlxon.png | awk '{print $2}')
WETH_LOGO=$(ipfs add logos/weth.png | awk '{print $2}')
EURC_LOGO=$(ipfs add logos/eurc.png | awk '{print $2}')

log "Logo hashes:"
log "  LXON: https://ipfs.io/ipfs/$LXON_LOGO"
log "  WLXON: https://ipfs.io/ipfs/$WLXON_LOGO"
log "  WETH: https://ipfs.io/ipfs/$WETH_LOGO"
log "  EURC: https://ipfs.io/ipfs/$EURC_LOGO"

# Update token list with actual IPFS hashes
log "Updating token list with IPFS logo hashes..."
sed -i.bak "s|ipfs://QmTcHk5YzQ5nKQeFz5YzQ5nKQeFz5YzQ5nKQeFz5YzQ5/lxon.png|ipfs://$LXON_LOGO|g" lxon.tokenlist.json
sed -i.bak "s|ipfs://QmTcHk5YzQ5nKQeFz5YzQ5nKQeFz5YzQ5nKQeFz5YzQ5/wlxon.png|ipfs://$WLXON_LOGO|g" lxon.tokenlist.json
sed -i.bak "s|ipfs://QmTcHk5YzQ5nKQeFz5YzQ5nKQeFz5YzQ5nKQeFz5YzQ5/weth.png|ipfs://$WETH_LOGO|g" lxon.tokenlist.json
sed -i.bak "s|ipfs://QmTcHk5YzQ5nKQeFz5YzQ5nKQeFz5YzQ5nKQeFz5YzQ5/eurc.png|ipfs://$EURC_LOGO|g" lxon.tokenlist.json

# Re-upload updated token list
log "Re-uploading updated token list..."
FINAL_HASH=$(ipfs add lxon.tokenlist.json | awk '{print $2}')

# Kill IPFS daemon
kill $IPFS_PID

log "Deployment complete!"
log "=========================================="
log "Token List URL: https://ipfs.io/ipfs/$FINAL_HASH"
log "=========================================="
log ""
log "Next steps:"
log "1. Test the token list: https://tokenlists.org/?url=https://ipfs.io/ipfs/$FINAL_HASH"
log "2. Add to Uniswap Interface:"
log "   - Go to https://app.uniswap.org/#/swap"
log "   - Click on the token selector"
log "   - Click on the list icon"
log "   - Select 'Custom Lists'"
log "   - Paste: https://ipfs.io/ipfs/$FINAL_HASH"
log "   - Click 'Add List'"
log ""
log "Alternative: Use GitHub Pages"
log "1. Fork this repository"
log "2. Upload token list to GitHub"
log "3. Enable GitHub Pages"
log "4. Use the GitHub Pages URL instead of IPFS"
