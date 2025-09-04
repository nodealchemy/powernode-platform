#!/bin/bash

# Start Vite dev server for external reverse proxy
# This script configures Vite to work with an external nginx/Apache proxy

set -e

SCRIPT_DIR=$(dirname "$0")
FRONTEND_DIR=$(realpath "$SCRIPT_DIR/..")

echo "🌐 Starting Vite for External Reverse Proxy"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📍 External URLs:"
echo "   Frontend: https://dev-1.ipnode.org/"
echo "   Backend:  https://dev-1.ipnode.org/api/v1"
echo ""

# Set up environment for external proxy
cat > "$FRONTEND_DIR/.env.local" << 'EOF'
# External Reverse Proxy Configuration
VITE_APP_VERSION=0.0.2

# External proxy URLs
VITE_API_BASE_URL=https://dev-1.ipnode.org/api/v1
VITE_WS_BASE_URL=wss://dev-1.ipnode.org/cable

# Proxy settings
VITE_BEHIND_PROXY=true
VITE_PROXY_HOST=dev-1.ipnode.org
VITE_PROXY_PROTOCOL=https
VITE_AUTO_DETECT_BACKEND=false

# Server configuration
HOST=0.0.0.0
PORT=3001
EOF

echo "✓ Environment configured for external proxy"
echo ""

# Export critical environment variables
export VITE_BEHIND_PROXY=true
export VITE_PROXY_HOST=dev-1.ipnode.org
export VITE_PROXY_PROTOCOL=https
export NODE_ENV=development

echo "🚀 Starting Vite with external proxy configuration..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd "$FRONTEND_DIR"

# Use the external proxy specific config
npx vite --config vite.config.external-proxy.ts --host 0.0.0.0 --clearScreen false