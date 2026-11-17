#!/bin/bash

# DNS Propagation Monitor Script
# This script checks if DNS has propagated for lxon.in

echo "🔍 DNS Propagation Monitor for lxon.in"
echo "========================================"
echo ""

TARGET_IP="13.61.177.64"
DOMAINS=("lxon.in" "www.lxon.in")

check_dns() {
    local domain=$1
    echo "Checking $domain..."
    
    # Check local DNS
    local local_result=$(nslookup $domain 2>/dev/null | grep -A 1 "Name:" | tail -1 | awk '{print $2}')
    
    if [ "$local_result" = "$TARGET_IP" ]; then
        echo "✅ Local DNS: Resolved to $TARGET_IP"
    else
        echo "⏳ Local DNS: Not yet propagated (resolves to: $local_result)"
    fi
    
    # Check external DNS (if available)
    echo "🌐 Check online: https://dnschecker.org/#A/$domain"
    echo ""
}

for domain in "${DOMAINS[@]}"; do
    check_dns "$domain"
done

echo "========================================"
echo "Tips:"
echo "  - DNS propagation typically takes 2-4 hours"
echo "  - Maximum propagation time is 48 hours"
echo "  - Check dnschecker.org for real-time propagation status"
echo "  - Some ISPs update faster than others"
echo ""