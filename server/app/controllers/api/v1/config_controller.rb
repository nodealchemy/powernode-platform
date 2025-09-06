# frozen_string_literal: true

module Api
  module V1
    class ConfigController < ApplicationController
      skip_before_action :authenticate_request, only: [:index, :allowed_hosts]
      
      # GET /api/v1/config
      # Returns configuration for frontend including correct API URLs
      def index
        render_success(build_config)
      end
      
      # GET /api/v1/config/allowed_hosts
      # Public endpoint for Vite to fetch allowed hosts during build
      def allowed_hosts
        # Collect all allowed hosts from various admin settings
        hosts = []
        
        # Add from reverse proxy URL config (existing)
        config = AdminSetting.reverse_proxy_url_config
        hosts.concat(config[:trusted_hosts]) if config[:trusted_hosts].present?
        hosts << config[:default_host] if config[:default_host].present?
        
        # Add wildcard patterns for multi-tenancy
        if config[:multi_tenancy] && config[:multi_tenancy][:wildcard_patterns].present?
          hosts.concat(config[:multi_tenancy][:wildcard_patterns])
        end
        
        # Add from new admin settings we just configured
        trusted_hosts = AdminSetting.get('trusted_hosts', [])
        hosts.concat(trusted_hosts) if trusted_hosts.present?
        
        allowed_hosts = AdminSetting.get('allowed_hosts', [])  
        hosts.concat(allowed_hosts) if allowed_hosts.present?
        
        proxy_domains = AdminSetting.get('proxy_domains', [])
        hosts.concat(proxy_domains) if proxy_domains.present?
        
        # Always include localhost variants
        hosts.concat(['localhost', '127.0.0.1', '::1'])
        
        # Remove duplicates and sort
        hosts = hosts.uniq.compact.sort
        
        render_success({
          allowed_hosts: hosts,
          source: 'backend',
          fetched_at: Time.current.iso8601
        })
      rescue StandardError => e
        Rails.logger.error "Failed to fetch allowed hosts: #{e.message}"
        render_error('Failed to fetch configuration')
      end
      
      private
      
      def build_config
        {
          api: {
            base_url: generate_api_base_url,
            websocket_url: generate_websocket_url,
            detected_proxy: proxy_detected?
          },
          features: {
            registration_enabled: registration_enabled?,
            email_verification_required: email_verification_required?,
            multi_tenancy_enabled: multi_tenancy_enabled?
          },
          version: {
            api: 'v1',
            app: '0.0.2'
          }
        }
      end
      
      def generate_api_base_url
        if proxy_detected?
          # Use proxy headers to construct URL
          protocol = request.headers['X-Forwarded-Proto'] || request.protocol.chomp('://')
          host = request.headers['X-Forwarded-Host'] || request.host
          port = request.headers['X-Forwarded-Port'] || request.port
          
          # Don't include port if it's standard for the protocol
          include_port = !((protocol == 'https' && port.to_s == '443') || 
                          (protocol == 'http' && port.to_s == '80'))
          
          base = "#{protocol}://#{host}"
          base += ":#{port}" if include_port && port
          "#{base}/api/v1"
        else
          # Use direct URL
          "#{request.protocol}#{request.host_with_port}/api/v1"
        end
      end
      
      def generate_websocket_url
        if proxy_detected?
          # Use proxy headers to construct WebSocket URL
          protocol = request.headers['X-Forwarded-Proto'] || request.protocol.chomp('://')
          ws_protocol = protocol == 'https' ? 'wss' : 'ws'
          host = request.headers['X-Forwarded-Host'] || request.host
          port = request.headers['X-Forwarded-Port'] || request.port
          
          # Don't include port if it's standard for the protocol
          include_port = !((protocol == 'https' && port.to_s == '443') || 
                          (protocol == 'http' && port.to_s == '80'))
          
          base = "#{ws_protocol}://#{host}"
          base += ":#{port}" if include_port && port
          "#{base}/cable"
        else
          # Use direct WebSocket URL
          protocol = request.protocol.include?('https') ? 'wss' : 'ws'
          "#{protocol}://#{request.host_with_port}/cable"
        end
      end
      
      def proxy_detected?
        # Check if any proxy headers are present
        proxy_headers = %w[
          X-Forwarded-Host
          X-Forwarded-Proto
          X-Forwarded-For
          X-Real-IP
        ]
        
        proxy_headers.any? { |header| request.headers[header].present? }
      end
      
      def multi_tenancy_enabled?
        # Check if multi-tenancy is enabled in proxy settings
        return false unless defined?(AdminSetting)
        
        config = AdminSetting.reverse_proxy_url_config
        config.dig(:multi_tenancy, :enabled) == true
      rescue StandardError
        false
      end
      
      def registration_enabled?
        # Check if registration is enabled
        return true unless defined?(AdminSetting)
        
        setting = AdminSetting.find_by(key: 'registration_enabled')
        return true unless setting
        
        # Parse the value - handle string and boolean values
        value = setting.value
        
        # Convert to string for comparison if needed
        value_str = value.to_s.downcase.strip
        
        case value_str
        when 'false', '0', 'no', 'off', 'disabled'
          false
        when 'true', '1', 'yes', 'on', 'enabled'
          true
        else
          # Default to true if value is unclear
          true
        end
      rescue StandardError
        true
      end
      
      def email_verification_required?
        # Check if email verification is required
        return true unless defined?(AdminSetting)
        
        setting = AdminSetting.find_by(key: 'email_verification_required')
        return true unless setting
        
        # Parse the value - handle string and boolean values
        value = setting.value
        
        # Convert to string for comparison if needed
        value_str = value.to_s.downcase.strip
        
        case value_str
        when 'false', '0', 'no', 'off', 'disabled'
          false
        when 'true', '1', 'yes', 'on', 'enabled'
          true
        else
          # Default to true if value is unclear
          true
        end
      rescue StandardError
        true
      end
    end
  end
end