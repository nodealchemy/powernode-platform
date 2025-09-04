#!/bin/bash

# Reverse Proxy Configuration Checker
# This script validates the reverse proxy setup and tests connectivity

set -e

SCRIPT_DIR=$(dirname "$0")
PROJECT_ROOT=$(realpath "$SCRIPT_DIR/..")
FRONTEND_DIR="$PROJECT_ROOT/frontend"
SERVER_DIR="$PROJECT_ROOT/server"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "🔍 Reverse Proxy Configuration Checker"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check environment configuration
check_env_config() {
    echo "📋 Checking Environment Configuration..."
    echo ""
    
    if [ -f "$FRONTEND_DIR/.env.local" ]; then
        echo -e "${GREEN}✓${NC} Frontend .env.local exists"
        
        # Check key variables
        if grep -q "VITE_BEHIND_PROXY=true" "$FRONTEND_DIR/.env.local"; then
            echo -e "${GREEN}✓${NC} Reverse proxy mode enabled"
        else
            echo -e "${YELLOW}⚠${NC} Reverse proxy mode not enabled"
        fi
        
        PROXY_HOST=$(grep "VITE_PROXY_HOST=" "$FRONTEND_DIR/.env.local" | cut -d'=' -f2)
        if [ -n "$PROXY_HOST" ]; then
            echo -e "${GREEN}✓${NC} Proxy host configured: $PROXY_HOST"
        else
            echo -e "${RED}✗${NC} Proxy host not configured"
        fi
        
        PROXY_PROTOCOL=$(grep "VITE_PROXY_PROTOCOL=" "$FRONTEND_DIR/.env.local" | cut -d'=' -f2)
        if [ -n "$PROXY_PROTOCOL" ]; then
            echo -e "${GREEN}✓${NC} Proxy protocol configured: $PROXY_PROTOCOL"
        else
            echo -e "${RED}✗${NC} Proxy protocol not configured"
        fi
    else
        echo -e "${RED}✗${NC} Frontend .env.local not found"
        echo "  Run: ./scripts/setup-reverse-proxy.sh to create it"
    fi
    echo ""
}

# Check Vite configuration
check_vite_config() {
    echo "📋 Checking Vite Configuration..."
    echo ""
    
    if [ -f "$FRONTEND_DIR/vite.config.ts" ]; then
        echo -e "${GREEN}✓${NC} Main vite.config.ts exists"
        
        # Check for proxy detection code
        if grep -q "VITE_BEHIND_PROXY" "$FRONTEND_DIR/vite.config.ts"; then
            echo -e "${GREEN}✓${NC} Proxy detection code present"
        else
            echo -e "${YELLOW}⚠${NC} Proxy detection code not found"
        fi
        
        # Check for HMR configuration
        if grep -q "hmr:" "$FRONTEND_DIR/vite.config.ts"; then
            echo -e "${GREEN}✓${NC} HMR configuration present"
        else
            echo -e "${YELLOW}⚠${NC} HMR configuration not found"
        fi
    else
        echo -e "${RED}✗${NC} vite.config.ts not found"
    fi
    
    if [ -f "$FRONTEND_DIR/vite.config.external-proxy.ts" ]; then
        echo -e "${GREEN}✓${NC} External proxy config exists"
    else
        echo -e "${YELLOW}⚠${NC} External proxy config not found"
        echo "  This is optional but recommended for external proxies"
    fi
    echo ""
}

# Check nginx configuration
check_nginx_config() {
    echo "📋 Checking Nginx Configuration..."
    echo ""
    
    if [ -f "$PROJECT_ROOT/nginx-proxy.conf" ]; then
        echo -e "${GREEN}✓${NC} nginx-proxy.conf exists"
        
        # Check for key proxy directives
        if grep -q "proxy_set_header X-Forwarded-Proto" "$PROJECT_ROOT/nginx-proxy.conf"; then
            echo -e "${GREEN}✓${NC} X-Forwarded headers configured"
        else
            echo -e "${RED}✗${NC} X-Forwarded headers not configured"
        fi
        
        if grep -q "location /@vite/" "$PROJECT_ROOT/nginx-proxy.conf"; then
            echo -e "${GREEN}✓${NC} Vite HMR location configured"
        else
            echo -e "${YELLOW}⚠${NC} Vite HMR location not configured"
        fi
        
        if grep -q "location /api/" "$PROJECT_ROOT/nginx-proxy.conf"; then
            echo -e "${GREEN}✓${NC} API proxy location configured"
        else
            echo -e "${RED}✗${NC} API proxy location not configured"
        fi
    else
        echo -e "${YELLOW}⚠${NC} nginx-proxy.conf not found"
        echo "  Run: ./scripts/setup-reverse-proxy.sh to create it"
    fi
    
    # Check if nginx is installed
    if command -v nginx &> /dev/null; then
        echo -e "${GREEN}✓${NC} Nginx is installed"
        
        # Check if config is linked (only if running as non-root)
        if [ "$EUID" -eq 0 ] || sudo -n true 2>/dev/null; then
            if [ -f "/etc/nginx/sites-enabled/powernode" ]; then
                echo -e "${GREEN}✓${NC} Powernode nginx config is enabled"
            else
                echo -e "${YELLOW}⚠${NC} Powernode nginx config not enabled"
                echo "  Run: sudo ln -s $PROJECT_ROOT/nginx-proxy.conf /etc/nginx/sites-enabled/powernode"
            fi
        fi
    else
        echo -e "${YELLOW}⚠${NC} Nginx not installed"
    fi
    echo ""
}

# Check service connectivity
check_services() {
    echo "📋 Checking Service Connectivity..."
    echo ""
    
    # Check backend
    if curl -s -f http://localhost:3000/health > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Backend is running on port 3000"
    else
        echo -e "${YELLOW}⚠${NC} Backend not responding on port 3000"
    fi
    
    # Check frontend
    if curl -s -f http://localhost:3001 > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Frontend is running on port 3001"
    else
        echo -e "${YELLOW}⚠${NC} Frontend not responding on port 3001"
    fi
    
    # Check if proxy host is configured and accessible
    if [ -f "$FRONTEND_DIR/.env.local" ]; then
        PROXY_HOST=$(grep "VITE_PROXY_HOST=" "$FRONTEND_DIR/.env.local" | cut -d'=' -f2)
        PROXY_PROTOCOL=$(grep "VITE_PROXY_PROTOCOL=" "$FRONTEND_DIR/.env.local" | cut -d'=' -f2)
        
        if [ -n "$PROXY_HOST" ] && [ -n "$PROXY_PROTOCOL" ]; then
            echo ""
            echo "Testing proxy endpoint: $PROXY_PROTOCOL://$PROXY_HOST"
            
            # Test DNS resolution
            if host "$PROXY_HOST" > /dev/null 2>&1; then
                echo -e "${GREEN}✓${NC} DNS resolution successful for $PROXY_HOST"
            else
                echo -e "${YELLOW}⚠${NC} Cannot resolve $PROXY_HOST"
            fi
            
            # Test HTTPS connectivity (if applicable)
            if [ "$PROXY_PROTOCOL" = "https" ]; then
                if curl -s -f -k "$PROXY_PROTOCOL://$PROXY_HOST" > /dev/null 2>&1; then
                    echo -e "${GREEN}✓${NC} HTTPS endpoint is accessible"
                else
                    echo -e "${YELLOW}⚠${NC} Cannot reach $PROXY_PROTOCOL://$PROXY_HOST"
                    echo "  This might be normal if nginx is not yet configured"
                fi
            fi
        fi
    fi
    echo ""
}

# Check allowed hosts configuration
check_allowed_hosts() {
    echo "📋 Checking Allowed Hosts Configuration..."
    echo ""
    
    # Check Vite allowed hosts
    if [ -f "$FRONTEND_DIR/vite.config.ts" ]; then
        echo "Vite allowed hosts:"
        grep -A 5 "allowedHosts:" "$FRONTEND_DIR/vite.config.ts" | grep -E "'\." | sed 's/.*'\''\(.*\)'\''.*/  • \1/' || echo "  (dynamic configuration)"
    fi
    
    # Check backend proxy settings
    if [ -f "$SERVER_DIR/config/proxy_settings.yml" ]; then
        echo ""
        echo "Backend trusted hosts:"
        grep -A 10 "trusted_hosts:" "$SERVER_DIR/config/proxy_settings.yml" | grep "    -" | sed 's/.*- /  • /'
    else
        echo -e "${YELLOW}⚠${NC} Backend proxy_settings.yml not found"
    fi
    echo ""
}

# Display summary
display_summary() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Configuration Check Summary"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    if [ -f "$FRONTEND_DIR/.env.local" ]; then
        PROXY_HOST=$(grep "VITE_PROXY_HOST=" "$FRONTEND_DIR/.env.local" | cut -d'=' -f2)
        PROXY_PROTOCOL=$(grep "VITE_PROXY_PROTOCOL=" "$FRONTEND_DIR/.env.local" | cut -d'=' -f2)
        
        echo "Current Configuration:"
        echo "  Proxy URL: ${PROXY_PROTOCOL}://${PROXY_HOST}"
        echo "  Frontend:  http://localhost:3001"
        echo "  Backend:   http://localhost:3000"
        echo ""
    fi
    
    echo "Quick Start Commands:"
    echo "  Setup:     ./scripts/setup-reverse-proxy.sh"
    echo "  Start:     ./start-with-proxy.sh"
    echo "  Dev Mode:  cd frontend && ./scripts/dev-external-proxy.sh"
    echo ""
    echo "For more information, see:"
    echo "  • frontend/docs/REVERSE_PROXY_SETUP.md"
    echo "  • frontend/EXTERNAL_PROXY_QUICKSTART.md"
}

# Main execution
main() {
    check_env_config
    check_vite_config
    check_nginx_config
    check_services
    check_allowed_hosts
    display_summary
}

# Handle command line arguments
case "$1" in
    --help|-h)
        echo "Usage: $0 [--quick]"
        echo ""
        echo "Options:"
        echo "  --quick    Quick check (skip service connectivity tests)"
        echo "  --help     Show this help message"
        exit 0
        ;;
    --quick)
        check_env_config
        check_vite_config
        check_nginx_config
        check_allowed_hosts
        display_summary
        ;;
    *)
        main
        ;;
esac