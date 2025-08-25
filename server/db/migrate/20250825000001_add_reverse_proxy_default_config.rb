# frozen_string_literal: true

class AddReverseProxyDefaultConfig < ActiveRecord::Migration[8.0]
  def up
    # Add default reverse proxy configuration
    default_config = {
      enabled: false,
      current_environment: Rails.env,
      environments: {
        development: {
          frontend: {
            host: "localhost",
            port: 3001,
            protocol: "http",
            base_url: "http://localhost:3001",
            health_check_path: "/health"
          },
          backend: {
            host: "localhost", 
            port: 3000,
            protocol: "http",
            base_url: "http://localhost:3000",
            health_check_path: "/api/v1/health"
          },
          worker: {
            host: "localhost",
            port: 4567,
            protocol: "http", 
            base_url: "http://localhost:4567",
            health_check_path: "/health"
          }
        },
        production: {
          frontend: {
            host: "app.powernode.io",
            port: 443,
            protocol: "https",
            base_url: "https://app.powernode.io",
            health_check_path: "/health"
          },
          backend: {
            host: "api.powernode.io",
            port: 443, 
            protocol: "https",
            base_url: "https://api.powernode.io",
            health_check_path: "/api/v1/health"
          },
          worker: {
            host: "worker.powernode.io",
            port: 443,
            protocol: "https",
            base_url: "https://worker.powernode.io", 
            health_check_path: "/health"
          }
        }
      },
      url_mappings: [
        {
          id: "frontend_root",
          name: "Frontend Routes",
          pattern: "/",
          target_service: "frontend",
          priority: 1,
          methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
          enabled: true,
          description: "Forward root requests to frontend service"
        },
        {
          id: "api_routes", 
          name: "API Routes",
          pattern: "/api/v1/*",
          target_service: "backend",
          priority: 10,
          methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
          enabled: true,
          description: "Forward API requests to backend service"
        },
        {
          id: "worker_routes",
          name: "Worker Routes", 
          pattern: "/worker/*",
          target_service: "worker",
          priority: 5,
          methods: ["GET", "POST"],
          enabled: false,
          description: "Forward worker requests to worker service"
        }
      ],
      load_balancing: {
        enabled: false,
        algorithm: "round_robin", # round_robin, least_connections, ip_hash
        health_check_interval: 30,
        failover_enabled: true
      },
      ssl_config: {
        enabled: false,
        enforce_https: false,
        certificate_path: "/etc/ssl/certs/powernode.crt",
        private_key_path: "/etc/ssl/private/powernode.key",
        protocols: ["TLSv1.2", "TLSv1.3"],
        ciphers: "ECDHE+AESGCM:ECDHE+AES256:!aNULL:!MD5:!DSS",
        hsts_enabled: true,
        hsts_max_age: 31536000
      },
      cors_config: {
        enabled: true,
        allowed_origins: ["*"],
        allowed_methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allowed_headers: ["Content-Type", "Authorization", "X-Requested-With"],
        exposed_headers: ["X-Total-Count", "X-Request-ID"],
        credentials: true,
        max_age: 86400
      },
      headers: {
        security_headers: {
          enabled: true,
          x_frame_options: "SAMEORIGIN",
          x_content_type_options: "nosniff", 
          x_xss_protection: "1; mode=block",
          referrer_policy: "strict-origin-when-cross-origin"
        },
        custom_headers: {
          request: [],
          response: [
            {
              name: "X-Powered-By",
              value: "Powernode Platform",
              enabled: true
            }
          ]
        }
      },
      rate_limiting: {
        enabled: false,
        default_limit: 1000,
        window_size: 3600,
        burst_limit: 100
      },
      compression: {
        enabled: true,
        types: ["text/html", "text/css", "text/javascript", "application/json"],
        level: 6
      }
    }
    
    AdminSetting.find_or_create_by(key: 'reverse_proxy_config') do |setting|
      setting.value = default_config
    end

    # Service discovery configuration
    service_discovery_config = {
      enabled: true,
      methods: ["dns", "port_scan"],
      dns_config: {
        enabled: true,
        timeout: 5,
        retries: 3
      },
      consul_config: {
        enabled: false,
        host: "localhost",
        port: 8500,
        token: nil,
        datacenter: "dc1"
      },
      port_scan_config: {
        enabled: true,
        port_ranges: {
          frontend: [3000, 3010],
          backend: [3000, 3010], 
          worker: [4560, 4570]
        },
        timeout: 2
      },
      kubernetes_config: {
        enabled: false,
        namespace: "default",
        label_selector: "app=powernode"
      }
    }
    
    AdminSetting.find_or_create_by(key: 'service_discovery_config') do |setting|
      setting.value = service_discovery_config
    end

    # Proxy-specific templates
    proxy_templates = {
      nginx: {
        enabled: true,
        config_path: "/etc/nginx/sites-available/powernode",
        reload_command: "sudo nginx -s reload",
        test_command: "sudo nginx -t"
      },
      apache: {
        enabled: false,
        config_path: "/etc/apache2/sites-available/powernode.conf",
        reload_command: "sudo systemctl reload apache2",
        test_command: "sudo apache2ctl configtest"
      },
      traefik: {
        enabled: false,
        config_path: "/etc/traefik/dynamic/powernode.yml",
        reload_command: "docker kill -s HUP traefik",
        test_command: nil
      }
    }
    
    AdminSetting.find_or_create_by(key: 'proxy_templates') do |setting|
      setting.value = proxy_templates
    end
  end

  def down
    AdminSetting.where(key: ['reverse_proxy_config', 'service_discovery_config', 'proxy_templates']).destroy_all
  end
end