# frozen_string_literal: true

namespace :hosts do
  desc "List all allowed hosts (CORS origins + Vite allowed hosts)"
  task list: :environment do
    puts "\n=== CORS Allowed Origins ==="
    puts "Used by: CorsConfigurationService -> rack-cors"
    puts "Setting: cors_allowed_origins\n\n"

    cors_origins = AdminSetting.get('cors_allowed_origins', [])
    if cors_origins.is_a?(Array) && cors_origins.any?
      cors_origins.sort.each { |origin| puts "  - #{origin}" }
    else
      puts "  (none configured)"
    end

    puts "\n=== Vite Allowed Hosts ==="
    puts "Used by: /api/v1/config/allowed_hosts -> Vite dev server"
    puts "Setting: allowed_hosts\n\n"

    allowed_hosts = AdminSetting.get('allowed_hosts', [])
    if allowed_hosts.is_a?(Array) && allowed_hosts.any?
      allowed_hosts.sort.each { |host| puts "  - #{host}" }
    else
      puts "  (none configured)"
    end

    puts "\n=== Trusted Hosts (also used by Vite) ==="
    puts "Setting: trusted_hosts\n\n"

    trusted_hosts = AdminSetting.get('trusted_hosts', [])
    if trusted_hosts.is_a?(Array) && trusted_hosts.any?
      trusted_hosts.sort.each { |host| puts "  - #{host}" }
    else
      puts "  (none configured)"
    end

    puts "\n=== Proxy Domains (also used by Vite) ==="
    puts "Setting: proxy_domains\n\n"

    proxy_domains = AdminSetting.get('proxy_domains', [])
    if proxy_domains.is_a?(Array) && proxy_domains.any?
      proxy_domains.sort.each { |domain| puts "  - #{domain}" }
    else
      puts "  (none configured)"
    end

    puts ""
  end

  desc "Add host(s) to both CORS and Vite allowed lists. Usage: rails hosts:add[host1,host2]"
  task :add, [:hosts] => :environment do |_t, args|
    hosts_arg = args[:hosts]
    if hosts_arg.blank?
      puts "Error: No hosts specified"
      puts "Usage: rails hosts:add[host1,host2]"
      puts "Example: rails hosts:add[dev.example.com,staging.example.com]"
      exit 1
    end

    hosts = hosts_arg.split(',').map(&:strip).reject(&:blank?)
    if hosts.empty?
      puts "Error: No valid hosts provided"
      exit 1
    end

    puts "Adding hosts: #{hosts.join(', ')}\n\n"

    # Add to CORS allowed origins (need full URLs with protocol)
    cors_origins = AdminSetting.get('cors_allowed_origins', [])
    cors_origins = [] unless cors_origins.is_a?(Array)

    added_cors = []
    hosts.each do |host|
      https_origin = "https://#{host}"
      http_origin = "http://#{host}"

      unless cors_origins.include?(https_origin)
        cors_origins << https_origin
        added_cors << https_origin
      end

      unless cors_origins.include?(http_origin)
        cors_origins << http_origin
        added_cors << http_origin
      end
    end

    AdminSetting.set('cors_allowed_origins', cors_origins)
    puts "CORS origins added: #{added_cors.any? ? added_cors.join(', ') : '(already present)'}"

    # Add to allowed hosts (just hostnames)
    allowed_hosts = AdminSetting.get('allowed_hosts', [])
    allowed_hosts = [] unless allowed_hosts.is_a?(Array)

    added_hosts = []
    hosts.each do |host|
      unless allowed_hosts.include?(host)
        allowed_hosts << host
        added_hosts << host
      end
    end

    AdminSetting.set('allowed_hosts', allowed_hosts)
    puts "Vite allowed hosts added: #{added_hosts.any? ? added_hosts.join(', ') : '(already present)'}"

    puts "\nDone! Remember to:"
    puts "  1. Restart the Rails server for CORS changes to take effect"
    puts "  2. Run 'cd frontend && node scripts/fetch-proxy-config.js' to update Vite cache"
  end

  desc "Remove host from both CORS and Vite allowed lists. Usage: rails hosts:remove[host]"
  task :remove, [:host] => :environment do |_t, args|
    host = args[:host]&.strip
    if host.blank?
      puts "Error: No host specified"
      puts "Usage: rails hosts:remove[host]"
      puts "Example: rails hosts:remove[dev.example.com]"
      exit 1
    end

    puts "Removing host: #{host}\n\n"

    # Remove from CORS allowed origins
    cors_origins = AdminSetting.get('cors_allowed_origins', [])
    cors_origins = [] unless cors_origins.is_a?(Array)

    https_origin = "https://#{host}"
    http_origin = "http://#{host}"

    removed_cors = []
    if cors_origins.include?(https_origin)
      cors_origins.delete(https_origin)
      removed_cors << https_origin
    end
    if cors_origins.include?(http_origin)
      cors_origins.delete(http_origin)
      removed_cors << http_origin
    end

    AdminSetting.set('cors_allowed_origins', cors_origins)
    puts "CORS origins removed: #{removed_cors.any? ? removed_cors.join(', ') : '(not found)'}"

    # Remove from allowed hosts
    allowed_hosts = AdminSetting.get('allowed_hosts', [])
    allowed_hosts = [] unless allowed_hosts.is_a?(Array)

    if allowed_hosts.include?(host)
      allowed_hosts.delete(host)
      puts "Vite allowed hosts removed: #{host}"
    else
      puts "Vite allowed hosts removed: (not found)"
    end

    AdminSetting.set('allowed_hosts', allowed_hosts)

    puts "\nDone! Remember to:"
    puts "  1. Restart the Rails server for CORS changes to take effect"
    puts "  2. Run 'cd frontend && node scripts/fetch-proxy-config.js' to update Vite cache"
  end

  desc "Test CORS configuration for a specific origin. Usage: rails hosts:test_cors[origin]"
  task :test_cors, [:origin] => :environment do |_t, args|
    origin = args[:origin]&.strip
    if origin.blank?
      puts "Error: No origin specified"
      puts "Usage: rails hosts:test_cors[https://example.com]"
      exit 1
    end

    puts "Testing CORS for origin: #{origin}\n\n"

    allowed = CorsConfigurationService.origin_allowed?(origin)
    if allowed
      puts "✓ Origin '#{origin}' is ALLOWED"
    else
      puts "✗ Origin '#{origin}' is NOT allowed"
      puts "\nConfigured CORS origins:"
      CorsConfigurationService.allowed_origins.each { |o| puts "  - #{o}" }
    end
  end
end
