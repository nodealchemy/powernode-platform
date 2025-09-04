# frozen_string_literal: true

module Api
  module V1
    module Admin
      class ProxySettingsController < ApplicationController
        before_action :require_admin_access
        
        # GET /api/v1/admin/proxy_settings/url_config
        def url_config
          config = AdminSetting.reverse_proxy_url_config
          render_success(config)
        rescue StandardError => e
          Rails.logger.error "Failed to fetch proxy URL config: #{e.message}"
          render_error('Failed to fetch proxy configuration')
        end
        
        # PUT /api/v1/admin/proxy_settings/url_config
        def update_url_config
          updated_config = AdminSetting.update_reverse_proxy_url_config(proxy_url_params)
          
          # Create audit log entry
          create_audit_log('proxy_settings.update', { 
            changes: proxy_url_params,
            updated_config: updated_config 
          })
          
          render_success(updated_config, meta: { message: 'Proxy URL configuration updated successfully' })
        rescue StandardError => e
          Rails.logger.error "Failed to update proxy URL config: #{e.message}"
          render_error('Failed to update proxy configuration', status: :bad_request)
        end
        
        # POST /api/v1/admin/proxy_settings/validate_host
        def validate_host
          host = params[:host]
          
          return render_validation_error(host: ['Host is required']) if host.blank?
          
          validation_result = AdminSetting.validate_proxy_host(host)
          
          render_success({
            host: host,
            validation: validation_result,
            timestamp: Time.current.iso8601
          })
        rescue StandardError => e
          Rails.logger.error "Failed to validate host: #{e.message}"
          render_error('Failed to validate host')
        end
        
        # POST /api/v1/admin/proxy_settings/test_headers
        def test_headers
          headers = params[:headers] || {}
          
          test_result = AdminSetting.test_proxy_headers(headers)
          
          render_success(test_result)
        rescue StandardError => e
          Rails.logger.error "Failed to test proxy headers: #{e.message}"
          render_error('Failed to test proxy headers')
        end
        
        # GET /api/v1/admin/proxy_settings/current_detection
        def current_detection
          # Extract current proxy context from request
          proxy_context = {
            forwarded_host: request.headers['X-Forwarded-Host'],
            forwarded_proto: request.headers['X-Forwarded-Proto'],
            forwarded_port: request.headers['X-Forwarded-Port'],
            forwarded_path: request.headers['X-Forwarded-Path'],
            forwarded_for: request.headers['X-Forwarded-For'],
            real_ip: request.headers['X-Real-IP'],
            original_host: request.host,
            original_protocol: request.protocol,
            remote_ip: request.remote_ip
          }.compact
          
          # Generate URLs based on current detection
          generated_urls = AdminSetting.generate_api_url(proxy_context) if proxy_context.any?
          
          render_success({
            proxy_detected: proxy_context.any?,
            proxy_context: proxy_context,
            generated_urls: generated_urls,
            request_headers: {
              'Host' => request.host,
              'X-Forwarded-Host' => request.headers['X-Forwarded-Host'],
              'X-Forwarded-Proto' => request.headers['X-Forwarded-Proto'],
              'X-Forwarded-Port' => request.headers['X-Forwarded-Port'],
              'X-Forwarded-Path' => request.headers['X-Forwarded-Path'],
              'X-Forwarded-For' => request.headers['X-Forwarded-For'],
              'X-Real-IP' => request.headers['X-Real-IP']
            }.compact,
            detection_timestamp: Time.current.iso8601
          })
        rescue StandardError => e
          Rails.logger.error "Failed to detect proxy: #{e.message}"
          render_error('Failed to detect proxy configuration')
        end
        
        # POST /api/v1/admin/proxy_settings/trusted_hosts
        def add_trusted_host
          pattern = params[:pattern]
          
          return render_validation_error(pattern: ['Pattern is required']) if pattern.blank?
          
          # Validate pattern format
          if pattern.include?('*')
            # Validate wildcard pattern
            unless pattern.match?(/^\*?\.?[a-z0-9\-\.]+$/i)
              return render_validation_error(pattern: ['Invalid wildcard pattern format'])
            end
          else
            # Validate standard hostname
            validation = AdminSetting.validate_proxy_host(pattern)
            unless validation[:valid]
              return render_validation_error(pattern: validation[:errors])
            end
          end
          
          AdminSetting.add_trusted_host(pattern)
          
          create_audit_log('proxy_settings.add_trusted_host', { pattern: pattern })
          
          render_success({ 
            pattern: pattern,
            trusted_hosts: AdminSetting.reverse_proxy_url_config[:trusted_hosts]
          }, meta: { message: 'Trusted host added successfully' })
        rescue StandardError => e
          Rails.logger.error "Failed to add trusted host: #{e.message}"
          render_error('Failed to add trusted host')
        end
        
        # DELETE /api/v1/admin/proxy_settings/trusted_hosts/:pattern
        def remove_trusted_host
          pattern = params[:pattern]
          
          return render_validation_error(pattern: ['Pattern is required']) if pattern.blank?
          
          AdminSetting.remove_trusted_host(pattern)
          
          create_audit_log('proxy_settings.remove_trusted_host', { pattern: pattern })
          
          render_success({ 
            pattern: pattern,
            trusted_hosts: AdminSetting.reverse_proxy_url_config[:trusted_hosts]
          }, meta: { message: 'Trusted host removed successfully' })
        rescue StandardError => e
          Rails.logger.error "Failed to remove trusted host: #{e.message}"
          render_error('Failed to remove trusted host')
        end
        
        # GET /api/v1/admin/proxy_settings/export
        def export
          config = AdminSetting.reverse_proxy_url_config
          
          render json: {
            success: true,
            data: {
              config: config,
              export_timestamp: Time.current.iso8601,
              export_format: 'json',
              version: '1.0'
            }
          }
        rescue StandardError => e
          Rails.logger.error "Failed to export proxy config: #{e.message}"
          render_error('Failed to export configuration')
        end
        
        # POST /api/v1/admin/proxy_settings/import
        def import
          config_data = params[:config]
          
          return render_validation_error(config: ['Configuration data is required']) if config_data.blank?
          
          # Validate configuration structure
          unless config_data.is_a?(Hash)
            return render_validation_error(config: ['Configuration must be a valid JSON object'])
          end
          
          # Import configuration
          updated_config = AdminSetting.update_reverse_proxy_url_config(config_data)
          
          create_audit_log('proxy_settings.import', {
            imported_config: config_data,
            updated_config: updated_config
          })
          
          render_success(updated_config, meta: { message: 'Configuration imported successfully' })
        rescue StandardError => e
          Rails.logger.error "Failed to import proxy config: #{e.message}"
          render_error('Failed to import configuration')
        end
        
        private
        
        def require_admin_access
          require_permission('admin.access')
        end
        
        def proxy_url_params
          # Handle both direct params and nested proxy_setting params
          config_params = params[:proxy_setting] || params
          
          config_params.permit(
            :enabled,
            :default_protocol,
            :default_host,
            :default_port,
            :base_path,
            trusted_hosts: [],
            security: [
              :enabled,
              :strict_mode,
              :validate_host_format,
              :block_suspicious_patterns
            ],
            multi_tenancy: [
              :enabled,
              wildcard_patterns: []
            ]
          ).to_h
        end
        
        def create_audit_log(action, metadata = {})
          return unless defined?(AuditLog)
          
          AuditLog.create(
            user: current_user,
            account: current_account,
            action: action,
            source: 'Api::V1::Admin::ProxySettingsController',
            ip_address: request.remote_ip,
            user_agent: request.user_agent,
            metadata: metadata
          )
        rescue StandardError => e
          Rails.logger.error "Failed to create audit log: #{e.message}"
        end
      end
    end
  end
end