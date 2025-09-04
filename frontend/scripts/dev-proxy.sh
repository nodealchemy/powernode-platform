#!/bin/bash

# Development server startup for reverse proxy configuration
# This script ensures proper environment setup for proxy development

set -e

SCRIPT_DIR=$(dirname "$0")
FRONTEND_DIR=$(realpath "$SCRIPT_DIR/..")

echo "🚀 Starting Vite Development Server (Reverse Proxy Mode)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check for proxy configuration file
if [ -f "$FRONTEND_DIR/.env.proxy.local" ]; then
    echo "✓ Using .env.proxy.local configuration"
    cp "$FRONTEND_DIR/.env.proxy.local" "$FRONTEND_DIR/.env.local"
elif [ -f "$FRONTEND_DIR/.env.proxy" ]; then
    echo "✓ Using .env.proxy configuration"
    cp "$FRONTEND_DIR/.env.proxy" "$FRONTEND_DIR/.env.local"
else
    echo "⚠ No proxy configuration found, creating default..."
    cat > "$FRONTEND_DIR/.env.local" << 'EOF'
# Auto-generated proxy configuration
VITE_BEHIND_PROXY=true
VITE_PROXY_HOST=dev-1.ipnode.net
VITE_PROXY_PROTOCOL=https
VITE_API_BASE_URL=https://dev-1.ipnode.net/api/v1
VITE_WS_BASE_URL=wss://dev-1.ipnode.net/cable
EOF
fi

# Ensure proxy settings are exported
export VITE_BEHIND_PROXY=true
export BEHIND_PROXY=true

echo ""
echo "🔧 Configuration:"
echo "  Behind Proxy: YES"
echo "  Proxy Host: ${VITE_PROXY_HOST:-dev-1.ipnode.net}"
echo "  Proxy Protocol: ${VITE_PROXY_PROTOCOL:-https}"
echo ""
echo "📡 WebSocket HMR will connect through the reverse proxy"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Start Vite with explicit host binding
cd "$FRONTEND_DIR"
npm run dev -- --host 0.0.0.0 --clearScreen false