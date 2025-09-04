# frozen_string_literal: true

module Api
  module V1
    class ConfigController < ApplicationController
      skip_before_action :authenticate_request, only: [:index]
      
      # GET /api/v1/config
      # Returns configuration for frontend including correct API URLs
      def index
        render_success(build_config)
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
            registration_enabled: true,
            email_verification_required: true,
            multi_tenancy_enabled: multi_tenancy_enabled?
          },
          version: {
            api: '1.0.0',
            app: ENV.fetch('APP_VERSION', '0.0.1')
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
    end
  end
end