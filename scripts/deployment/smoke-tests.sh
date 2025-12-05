#!/bin/bash
# Smoke tests for Powernode Platform deployment
# Usage: ./smoke-tests.sh [app-url]

set -euo pipefail

APP_URL=${1:-http://localhost}
TIMEOUT=30
MAX_RETRIES=5

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Test HTTP endpoint
test_endpoint() {
    local url=$1
    local expected_status=${2:-200}
    local description=$3
    local retry_count=0
    
    log_info "Testing: $description"
    log_info "URL: $url"
    
    while [[ $retry_count -lt $MAX_RETRIES ]]; do
        local response=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TIMEOUT "$url" 2>/dev/null || echo "000")
        
        if [[ "$response" == "$expected_status" ]]; then
            log_success "✓ $description (HTTP $response)"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $MAX_RETRIES ]]; then
                log_warning "✗ $description failed (HTTP $response), retrying... ($retry_count/$MAX_RETRIES)"
                sleep 5
            else
                log_error "✗ $description failed (HTTP $response)"
                return 1
            fi
        fi
    done
}

# Test JSON API endpoint
test_json_endpoint() {
    local url=$1
    local expected_key=$2
    local description=$3
    local retry_count=0
    
    log_info "Testing: $description"
    log_info "URL: $url"
    
    while [[ $retry_count -lt $MAX_RETRIES ]]; do
        local response=$(curl -s --max-time $TIMEOUT -H "Accept: application/json" "$url" 2>/dev/null || echo "{}")
        local status=$(echo "$response" | jq -r ".$expected_key" 2>/dev/null || echo "null")
        
        if [[ "$status" != "null" && "$status" != "" ]]; then
            log_success "✓ $description (Response: $status)"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $MAX_RETRIES ]]; then
                log_warning "✗ $description failed, retrying... ($retry_count/$MAX_RETRIES)"
                sleep 5
            else
                log_error "✗ $description failed (No valid JSON response)"
                return 1
            fi
        fi
    done
}

# Test authenticated endpoint
test_auth_endpoint() {
    local url=$1
    local expected_status=${2:-401}
    local description=$3
    
    log_info "Testing: $description"
    log_info "URL: $url"
    
    local response=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TIMEOUT "$url" 2>/dev/null || echo "000")
    
    if [[ "$response" == "$expected_status" ]]; then
        log_success "✓ $description (HTTP $response - Authentication required)"
        return 0
    else
        log_error "✗ $description failed (HTTP $response)"
        return 1
    fi
}

# Test WebSocket connection
test_websocket() {
    local ws_url=$1
    local description=$2
    
    log_info "Testing: $description"
    log_info "URL: $ws_url"
    
    # Simple WebSocket test using curl if available, otherwise skip
    if command -v wscat >/dev/null 2>&1; then
        if timeout 10 wscat -c "$ws_url" --close >/dev/null 2>&1; then
            log_success "✓ $description"
            return 0
        else
            log_warning "✗ $description failed"
            return 1
        fi
    else
        log_warning "WebSocket test skipped (wscat not available)"
        return 0
    fi
}

# Run all smoke tests
main() {
    log_info "Starting smoke tests for: $APP_URL"
    local failed_tests=0
    
    # Frontend tests
    log_info "=== Frontend Tests ==="
    
    # Test main page
    if ! test_endpoint "$APP_URL" 200 "Frontend main page"; then
        failed_tests=$((failed_tests + 1))
    fi
    
    # Test health endpoint
    if ! test_endpoint "$APP_URL/health" 200 "Frontend health check"; then
        failed_tests=$((failed_tests + 1))
    fi
    
    # Test static assets (if available)
    if ! test_endpoint "$APP_URL/static/js/main.js" 200 "Static assets loading"; then
        log_warning "Static assets test failed (this may be normal)"
    fi
    
    # Backend API tests
    log_info "=== Backend API Tests ==="
    
    # Test API health endpoint
    if ! test_json_endpoint "$APP_URL/api/v1/health" "status" "Backend API health check"; then
        failed_tests=$((failed_tests + 1))
    fi
    
    # Test API version endpoint
    if ! test_json_endpoint "$APP_URL/api/v1/version" "version" "Backend API version"; then
        failed_tests=$((failed_tests + 1))
    fi
    
    # Test authentication endpoint (should require auth)
    if ! test_auth_endpoint "$APP_URL/api/v1/auth/me" 401 "Authentication protection"; then
        failed_tests=$((failed_tests + 1))
    fi
    
    # Test protected admin endpoint (should require auth)
    if ! test_auth_endpoint "$APP_URL/api/v1/admin/users" 401 "Admin endpoint protection"; then
        failed_tests=$((failed_tests + 1))
    fi
    
    # Database connectivity test (through API)
    if ! test_json_endpoint "$APP_URL/api/v1/health/database" "status" "Database connectivity"; then
        failed_tests=$((failed_tests + 1))
    fi
    
    # Redis connectivity test (through API)
    if ! test_json_endpoint "$APP_URL/api/v1/health/redis" "status" "Redis connectivity"; then
        failed_tests=$((failed_tests + 1))
    fi
    
    # Performance tests
    log_info "=== Performance Tests ==="
    
    # Test response time for main page
    local response_time=$(curl -o /dev/null -s -w "%{time_total}" --max-time $TIMEOUT "$APP_URL" 2>/dev/null || echo "999")
    if (( $(echo "$response_time < 5.0" | bc -l) )); then
        log_success "✓ Frontend response time: ${response_time}s"
    else
        log_warning "✗ Frontend response time slow: ${response_time}s"
    fi
    
    # Test API response time
    local api_response_time=$(curl -o /dev/null -s -w "%{time_total}" --max-time $TIMEOUT "$APP_URL/api/v1/health" 2>/dev/null || echo "999")
    if (( $(echo "$api_response_time < 3.0" | bc -l) )); then
        log_success "✓ API response time: ${api_response_time}s"
    else
        log_warning "✗ API response time slow: ${api_response_time}s"
    fi
    
    # Security tests
    log_info "=== Security Tests ==="
    
    # Test HTTPS redirect (if applicable)
    if [[ "$APP_URL" == https://* ]]; then
        local http_url="${APP_URL/https:/http:}"
        if test_endpoint "$http_url" 301 "HTTPS redirect"; then
            log_success "✓ HTTP to HTTPS redirect working"
        else
            log_warning "HTTPS redirect test failed"
        fi
    fi
    
    # Test security headers
    local security_headers=$(curl -s -I --max-time $TIMEOUT "$APP_URL" 2>/dev/null | grep -i "x-frame-options\|x-content-type-options\|x-xss-protection" | wc -l)
    if [[ $security_headers -gt 0 ]]; then
        log_success "✓ Security headers present ($security_headers found)"
    else
        log_warning "✗ Security headers missing"
        failed_tests=$((failed_tests + 1))
    fi
    
    # Summary
    log_info "=== Test Summary ==="
    if [[ $failed_tests -eq 0 ]]; then
        log_success "All smoke tests passed! 🎉"
        
        # Display deployment info
        log_info "Deployment Information:"
        log_info "  URL: $APP_URL"
        log_info "  Frontend Response Time: ${response_time}s"
        log_info "  API Response Time: ${api_response_time}s"
        log_info "  Security Headers: $security_headers found"
        
        return 0
    else
        log_error "$failed_tests smoke test(s) failed"
        return 1
    fi
}

# Check dependencies
check_dependencies() {
    local missing_deps=0
    
    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl is required for smoke tests"
        missing_deps=$((missing_deps + 1))
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq is required for JSON parsing"
        missing_deps=$((missing_deps + 1))
    fi
    
    if ! command -v bc >/dev/null 2>&1; then
        log_warning "bc is recommended for performance calculations"
    fi
    
    if [[ $missing_deps -gt 0 ]]; then
        log_error "Please install missing dependencies"
        exit 1
    fi
}

# Main execution
check_dependencies
main "$@"