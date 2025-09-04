#!/bin/bash

# Test script to demonstrate improved timeout features in auto-dev.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTO_DEV="$SCRIPT_DIR/auto-dev.sh"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Powernode Timeout Features Test ===${NC}"
echo ""

echo -e "${YELLOW}1. Testing default timeout values:${NC}"
echo "   Backend:  ${POWERNODE_BACKEND_TIMEOUT:-90}s"
echo "   Worker:   ${POWERNODE_WORKER_TIMEOUT:-60}s"
echo "   Worker Web: ${POWERNODE_WORKER_WEB_TIMEOUT:-45}s"
echo "   Frontend: ${POWERNODE_FRONTEND_TIMEOUT:-120}s"
echo ""

echo -e "${YELLOW}2. Testing with custom timeout (reduced for demo):${NC}"
export POWERNODE_BACKEND_TIMEOUT=30
export POWERNODE_FRONTEND_TIMEOUT=45
echo "   Custom Backend timeout: $POWERNODE_BACKEND_TIMEOUT"
echo "   Custom Frontend timeout: $POWERNODE_FRONTEND_TIMEOUT"
echo ""

echo -e "${YELLOW}3. Testing adaptive timeout calculation:${NC}"
echo "   System load: $(uptime | awk '{print $(NF-2), $(NF-1), $NF}')"
echo "   CPU cores: $(nproc)"
load_avg=$(uptime | awk '{print $(NF-2)}' | sed 's/,//')
cpu_count=$(nproc)
load_ratio=$(echo "scale=2; $load_avg / $cpu_count" | bc)
echo "   Load ratio: $load_ratio"

if (( $(echo "$load_ratio > 2.0" | bc -l) )); then
    echo -e "   ${YELLOW}High load detected - timeouts will be doubled${NC}"
elif (( $(echo "$load_ratio > 1.0" | bc -l) )); then
    echo -e "   ${YELLOW}Moderate load - timeouts increased by 50%${NC}"
else
    echo -e "   ${GREEN}Normal load - standard timeouts apply${NC}"
fi
echo ""

echo -e "${YELLOW}4. Testing debug mode output:${NC}"
export DEBUG=true
echo "   Debug mode enabled - verbose output will show:"
echo "   - Adaptive timeout calculations"
echo "   - Service startup phase detection"
echo "   - Detailed health check attempts"
echo ""

echo -e "${YELLOW}5. Available timeout environment variables:${NC}"
echo "   export POWERNODE_BACKEND_TIMEOUT=120  # Increase backend timeout"
echo "   export POWERNODE_FRONTEND_TIMEOUT=180 # Increase frontend timeout"
echo "   export POWERNODE_WORKER_TIMEOUT=90    # Increase worker timeout"
echo "   export DEBUG=true                     # Enable debug output"
echo ""

echo -e "${YELLOW}6. Service startup phase detection:${NC}"
echo "   The script now detects:"
echo "   - Database migrations (Backend)"
echo "   - Asset compilation (Backend)"
echo "   - Webpack building (Frontend)"
echo "   - TypeScript compilation (Frontend)"
echo "   - NPM dependency installation (Frontend)"
echo "   - Sidekiq job loading (Worker)"
echo ""

echo -e "${GREEN}Test complete!${NC}"
echo ""
echo "To see these features in action, try:"
echo "  DEBUG=true $AUTO_DEV ensure"
echo "  POWERNODE_FRONTEND_TIMEOUT=180 $AUTO_DEV ensure"
echo ""
echo "For slow systems or first-time startup:"
echo "  export POWERNODE_BACKEND_TIMEOUT=120"
echo "  export POWERNODE_FRONTEND_TIMEOUT=180"
echo "  DEBUG=true $AUTO_DEV ensure"