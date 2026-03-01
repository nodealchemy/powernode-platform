#!/bin/bash
# frozen_string_literal: true

# Powernode Proxy Host Management Script
# Manages trusted hosts in admin settings for reverse proxy configuration
#
# Usage:
#   ./scripts/manage-proxy-hosts.sh add <host>
#   ./scripts/manage-proxy-hosts.sh remove <host>  
#   ./scripts/manage-proxy-hosts.sh list
#   ./scripts/manage-proxy-hosts.sh validate <host>
#   ./scripts/manage-proxy-hosts.sh status
#   ./scripts/manage-proxy-hosts.sh enable-proxy
#   ./scripts/manage-proxy-hosts.sh disable-proxy

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if we're in the correct directory
if [ ! -f "server/config/application.rb" ]; then
    echo -e "${RED}Error: This script must be run from the project root directory${NC}"
    exit 1
fi

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${CYAN}$1${NC}"
}

# Function to execute Rails runner command
run_rails_command() {
    local command="$1"
    cd server && bundle exec rails runner "$command" 2>/dev/null
}

# Function to update Vite's proxy config cache
update_vite_cache() {
    local project_root
    project_root=$(cd "$(dirname "$0")/.." && pwd)
    local cache_file="$project_root/frontend/.proxy-config-cache.json"

    print_info "Syncing Vite proxy cache..."

    # Get all trusted hosts from Rails
    local hosts_json
    hosts_json=$(run_rails_command "
        config = AdminSetting.reverse_proxy_url_config
        hosts = config[:trusted_hosts] || []
        # Strip ports for Vite allowedHosts (Vite handles ports separately)
        # But preserve IPv6 addresses like ::1
        hosts_without_ports = hosts.map do |h|
          # Only strip port if it's hostname:port format (not IPv6)
          if h.include?(':') && !h.start_with?(':') && h.match?(/:\\d+\$/)
            h.gsub(/:\\d+\$/, '')
          else
            h
          end
        end.uniq
        puts hosts_without_ports.to_json
    ")

    if [ -z "$hosts_json" ] || [ "$hosts_json" = "null" ]; then
        print_warning "Could not retrieve hosts for Vite cache"
        return 1
    fi

    # Generate the cache file with timestamp
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

    cat > "$cache_file" << EOF
{
  "allowedHosts": $hosts_json,
  "fetchedAt": "$timestamp",
  "source": "backend"
}
EOF

    print_success "Vite cache updated: $cache_file"

    # Check if frontend is running and notify user
    if pgrep -f "vite" > /dev/null 2>&1; then
        print_warning "Frontend is running - restart required for changes to take effect"
        print_info "Run: sudo systemctl restart powernode-frontend@default"
    fi
}

# Function to show usage
show_usage() {
    print_header "Powernode Proxy Host Management"
    echo ""
    echo "Usage: $0 <command> [arguments]"
    echo ""
    echo "Commands:"
    echo "  add <host>           Add a host to the trusted hosts list"
    echo "  remove <host>        Remove a host from the trusted hosts list"
    echo "  list                 List all trusted hosts"
    echo "  sync                 Sync Vite cache with backend trusted hosts"
    echo "  validate <host>      Validate a host pattern"
    echo "  status               Show proxy configuration status"
    echo "  enable-proxy         Enable reverse proxy URL configuration"
    echo "  disable-proxy        Disable reverse proxy URL configuration"
    echo "  generate-mcp         Generate .mcp.json from current proxy configuration"
    echo "  help                 Show this help message"
    echo ""
    echo "Host Patterns:"
    echo "  - Exact hosts:       example.com, api.company.com"
    echo "  - Wildcard hosts:    *.example.com, *.staging.company.com"
    echo "  - IP addresses:      192.168.1.100, 10.0.0.5"
    echo "  - With ports:        example.com:8080, *.dev.local:3000"
    echo ""
    echo "Examples:"
    echo "  $0 add example.com"
    echo "  $0 add \"*.staging.company.com\""
    echo "  $0 remove api.old.com"
    echo "  $0 validate \"*.example.com\""
    echo ""
}

# Function to add a host
add_host() {
    local host="$1"
    
    if [ -z "$host" ]; then
        print_error "Host parameter is required"
        echo "Usage: $0 add <host>"
        exit 1
    fi
    
    print_info "Adding host '$host' to trusted hosts list..."
    
    # Validate host first
    local validation_result
    validation_result=$(run_rails_command "
        result = AdminSetting.validate_proxy_host('$host')
        puts result.to_json
    ")
    
    if [ -z "$validation_result" ]; then
        print_error "Failed to validate host"
        exit 1
    fi
    
    # Check if validation passed
    local valid
    valid=$(echo "$validation_result" | ruby -rjson -e "puts JSON.parse(STDIN.read)['valid']")
    
    if [ "$valid" != "true" ]; then
        print_error "Host validation failed:"
        echo "$validation_result" | ruby -rjson -e "
            data = JSON.parse(STDIN.read)
            data['errors']&.each { |error| puts \"  - #{error}\" }
        "
        exit 1
    fi
    
    # Add the host
    local add_result
    add_result=$(run_rails_command "
        begin
          result = AdminSetting.add_trusted_host('$host')
          puts result ? 'success' : 'failed'
        rescue => e
          puts \"error: #{e.message}\"
        end
    ")
    
    case "$add_result" in
        "success")
            print_success "Host '$host' added successfully"
            update_vite_cache
            ;;
        "failed")
            print_error "Failed to add host '$host'"
            exit 1
            ;;
        error:*)
            print_error "Error adding host: ${add_result#error: }"
            exit 1
            ;;
        *)
            print_error "Unexpected result: $add_result"
            exit 1
            ;;
    esac
}

# Function to remove a host
remove_host() {
    local host="$1"
    
    if [ -z "$host" ]; then
        print_error "Host parameter is required"
        echo "Usage: $0 remove <host>"
        exit 1
    fi
    
    print_info "Removing host '$host' from trusted hosts list..."
    
    local remove_result
    remove_result=$(run_rails_command "
        begin
          result = AdminSetting.remove_trusted_host('$host')
          puts result ? 'success' : 'failed'
        rescue => e
          puts \"error: #{e.message}\"
        end
    ")
    
    case "$remove_result" in
        "success")
            print_success "Host '$host' removed successfully"
            update_vite_cache
            ;;
        "failed")
            print_error "Failed to remove host '$host'"
            exit 1
            ;;
        error:*)
            print_error "Error removing host: ${remove_result#error: }"
            exit 1
            ;;
        *)
            print_error "Unexpected result: $remove_result"
            exit 1
            ;;
    esac
}

# Function to list hosts
list_hosts() {
    print_info "Retrieving trusted hosts list..."
    
    local hosts_json
    hosts_json=$(run_rails_command "
        config = AdminSetting.reverse_proxy_url_config
        puts (config[:trusted_hosts] || []).to_json
    ")
    
    if [ -z "$hosts_json" ]; then
        print_error "Failed to retrieve hosts list"
        exit 1
    fi
    
    print_header "Trusted Hosts:"
    echo "$hosts_json" | ruby -rjson -e "
        hosts = JSON.parse(STDIN.read)
        if hosts.empty?
          puts '  (no hosts configured)'
        else
          hosts.each_with_index do |host, i|
            puts \"  #{i + 1}. #{host}\"
          end
        end
    "
    
    # Show total count
    local count
    count=$(echo "$hosts_json" | ruby -rjson -e "puts JSON.parse(STDIN.read).length")
    echo ""
    print_info "Total hosts: $count"
}

# Function to validate a host
validate_host() {
    local host="$1"
    
    if [ -z "$host" ]; then
        print_error "Host parameter is required"
        echo "Usage: $0 validate <host>"
        exit 1
    fi
    
    print_info "Validating host pattern '$host'..."
    
    local validation_result
    validation_result=$(run_rails_command "
        result = AdminSetting.validate_proxy_host('$host')
        puts result.to_json
    ")
    
    if [ -z "$validation_result" ]; then
        print_error "Failed to validate host"
        exit 1
    fi
    
    # Parse and display results
    echo "$validation_result" | ruby -rjson -e "
        data = JSON.parse(STDIN.read)
        
        puts \"\\033[0;36mValidation Results for '#{ENV['host']}':\\033[0m\"
        puts \"  Valid: #{data['valid'] ? '\\033[0;32mtrue\\033[0m' : '\\033[0;31mfalse\\033[0m'}\"
        puts \"  Trusted: #{data['trusted'] ? '\\033[0;32mtrue\\033[0m' : '\\033[0;33mfalse\\033[0m'}\"
        puts \"  Suspicious: #{data['suspicious'] ? '\\033[0;31mtrue\\033[0m' : '\\033[0;32mfalse\\033[0m'}\"
        
        if data['errors'] && !data['errors'].empty?
          puts \"\\n\\033[0;31mErrors:\\033[0m\"
          data['errors'].each { |error| puts \"  - #{error}\" }
        end
    " host="$host"
    
    # Exit with appropriate code
    local valid
    valid=$(echo "$validation_result" | ruby -rjson -e "puts JSON.parse(STDIN.read)['valid']")
    if [ "$valid" != "true" ]; then
        exit 1
    fi
}

# Function to show proxy status
show_status() {
    print_info "Retrieving proxy configuration status..."
    
    local status_json
    status_json=$(run_rails_command "
        config = AdminSetting.reverse_proxy_url_config
        trusted_hosts = config[:trusted_hosts] || []
        
        status = {
          enabled: config[:enabled] || false,
          trusted_hosts_count: trusted_hosts.length,
          security_enabled: config.dig(:security, :enabled) || false,
          strict_mode: config.dig(:security, :strict_mode) || false,
          default_protocol: config[:default_protocol] || 'https',
          default_host: config[:default_host],
          multi_tenancy_enabled: config.dig(:multi_tenancy, :enabled) || false
        }
        
        puts status.to_json
    ")
    
    if [ -z "$status_json" ]; then
        print_error "Failed to retrieve status"
        exit 1
    fi
    
    print_header "Reverse Proxy Configuration Status:"
    echo "$status_json" | ruby -rjson -e "
        status = JSON.parse(STDIN.read)
        
        enabled_color = status['enabled'] ? '\\033[0;32m' : '\\033[0;31m'
        security_color = status['security_enabled'] ? '\\033[0;32m' : '\\033[0;33m'
        strict_color = status['strict_mode'] ? '\\033[0;32m' : '\\033[0;33m'
        
        puts \"  Proxy URL Config: #{enabled_color}#{status['enabled'] ? 'ENABLED' : 'DISABLED'}\\033[0m\"
        puts \"  Trusted Hosts: \\033[0;36m#{status['trusted_hosts_count']}\\033[0m configured\"
        puts \"  Security: #{security_color}#{status['security_enabled'] ? 'ENABLED' : 'DISABLED'}\\033[0m\"
        puts \"  Strict Mode: #{strict_color}#{status['strict_mode'] ? 'ENABLED' : 'DISABLED'}\\033[0m\"
        puts \"  Default Protocol: \\033[0;36m#{status['default_protocol']}\\033[0m\"
        puts \"  Default Host: \\033[0;36m#{status['default_host'] || '(not set)'}\\033[0m\"
        puts \"  Multi-tenancy: #{status['multi_tenancy_enabled'] ? '\\033[0;32mENABLED\\033[0m' : '\\033[0;33mDISABLED\\033[0m'}\"
    "
}

# Function to enable proxy
enable_proxy() {
    print_info "Enabling reverse proxy URL configuration..."
    
    local result
    result=$(run_rails_command "
        begin
          AdminSetting.update_reverse_proxy_url_config(enabled: true)
          puts 'success'
        rescue => e
          puts \"error: #{e.message}\"
        end
    ")
    
    case "$result" in
        "success")
            print_success "Reverse proxy URL configuration enabled"
            ;;
        error:*)
            print_error "Error enabling proxy: ${result#error: }"
            exit 1
            ;;
        *)
            print_error "Unexpected result: $result"
            exit 1
            ;;
    esac
}

# Function to disable proxy
disable_proxy() {
    print_info "Disabling reverse proxy URL configuration..."
    
    local result
    result=$(run_rails_command "
        begin
          AdminSetting.update_reverse_proxy_url_config(enabled: false)
          puts 'success'
        rescue => e
          puts \"error: #{e.message}\"
        end
    ")
    
    case "$result" in
        "success")
            print_success "Reverse proxy URL configuration disabled"
            ;;
        error:*)
            print_error "Error disabling proxy: ${result#error: }"
            exit 1
            ;;
        *)
            print_error "Unexpected result: $result"
            exit 1
            ;;
    esac
}

# Probe a URL to verify it serves the Powernode backend API
# Returns 0 if the endpoint responds with a valid Powernode version payload
probe_backend() {
    local base_url="$1"
    local version_url="${base_url}/api/v1/version"

    local response
    response=$(curl -s --connect-timeout 5 --max-time 10 "$version_url" 2>/dev/null)

    # Check for Powernode version response: {"success":true,"data":{"version":"..."}}
    if echo "$response" | grep -q '"success":true' && echo "$response" | grep -q '"version"'; then
        return 0
    fi
    return 1
}

# Function to generate .mcp.json from proxy configuration
generate_mcp_config() {
    local project_root
    project_root=$(cd "$(dirname "$0")/.." && pwd)
    local mcp_file="$project_root/.mcp.json"

    print_info "Generating .mcp.json from proxy configuration..."

    # Write Ruby script to temp file to avoid shell escaping issues
    # Outputs candidate base URLs in priority order (one per line):
    #   1. default_host (if set)
    #   2. portless trusted hosts (proxy hostnames) via https
    #   3. port-suffixed trusted hosts (direct backend) via http
    local ruby_script
    ruby_script=$(mktemp /tmp/generate_mcp_XXXXXX.rb)
    cat > "$ruby_script" << 'RUBY'
config = AdminSetting.reverse_proxy_url_config
protocol = config[:default_protocol] || "https"
skip = %w[localhost 127.0.0.1 ::1]
candidates = []

# Priority 1: explicit default_host
if config[:default_host].present?
  candidates << "#{protocol}://#{config[:default_host]}"
end

# Build from trusted hosts
if config[:trusted_hosts].is_a?(Array)
  external = config[:trusted_hosts].reject { |h| skip.include?(h) || skip.include?(h.split(":").first) }
  proxy_hosts = external.reject { |h| h.match?(/:\d+\z/) }
  direct_hosts = external.select { |h| h.match?(/:\d+\z/) }

  # Priority 2: portless proxy hostnames via configured protocol
  proxy_hosts.each { |h| candidates << "#{protocol}://#{h}" }

  # Priority 3: port-suffixed hosts via http (direct backend access)
  direct_hosts.each { |h| candidates << "http://#{h}" }
end

if candidates.empty?
  $stderr.puts "No suitable hosts found in proxy configuration"
  exit 1
end

candidates.uniq.each { |c| puts c }
RUBY

    local candidate_urls
    candidate_urls=$(cd "$project_root/server" && bundle exec rails runner "$ruby_script" 2>/dev/null)
    rm -f "$ruby_script"

    if [ -z "$candidate_urls" ]; then
        print_error "Could not determine candidate URLs from proxy configuration"
        print_info "Ensure a non-localhost trusted host is configured or set a default_host:"
        print_info "  $0 add platform.example.com"
        exit 1
    fi

    # Probe each candidate to find a reachable Powernode backend
    local mcp_url=""
    while IFS= read -r base_url; do
        print_info "Probing $base_url ..."
        if probe_backend "$base_url"; then
            mcp_url="${base_url}/api/v1/mcp/message"
            break
        else
            print_warning "  Not a Powernode backend (no response or wrong service)"
        fi
    done <<< "$candidate_urls"

    if [ -z "$mcp_url" ]; then
        print_error "None of the candidate hosts serve the Powernode backend API"
        print_info "Candidates tried:"
        while IFS= read -r url; do
            print_info "  - $url"
        done <<< "$candidate_urls"
        print_info ""
        print_info "Ensure the backend is running and reachable from this machine."
        exit 1
    fi

    cat > "$mcp_file" << EOF
{
  "mcpServers": {
    "powernode": {
      "type": "http",
      "url": "$mcp_url"
    }
  }
}
EOF

    print_success "Generated $mcp_file"
    print_info "MCP URL: $mcp_url"
}

# Main script logic
case "${1:-}" in
    "add")
        add_host "$2"
        ;;
    "remove")
        remove_host "$2"
        ;;
    "list")
        list_hosts
        ;;
    "sync")
        update_vite_cache
        ;;
    "validate")
        validate_host "$2"
        ;;
    "status")
        show_status
        ;;
    "generate-mcp")
        generate_mcp_config
        ;;
    "enable-proxy")
        enable_proxy
        ;;
    "disable-proxy")
        disable_proxy
        ;;
    "help"|"--help"|"-h")
        show_usage
        ;;
    "")
        print_error "No command specified"
        echo ""
        show_usage
        exit 1
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        show_usage
        exit 1
        ;;
esac