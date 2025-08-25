# frozen_string_literal: true

class Api::V1::Admin::RateLimiting::RateLimitingController < ApplicationController
  include ApiResponse

  before_action :authenticate_request
  before_action -> { require_permission('admin.settings.security') }

  # GET /api/v1/admin/rate_limiting/statistics
  def statistics
    begin
      stats = RateLimitService.get_statistics
      
      render_success(stats)
    rescue => e
      Rails.logger.error "Failed to get rate limiting statistics: #{e.message}"
      render_error("Failed to retrieve rate limiting statistics", status: :internal_server_error)
    end
  end

  # GET /api/v1/admin/rate_limiting/violations
  def violations
    begin
      violations = get_recent_violations
      
      render_success({
        violations: violations,
        total_count: violations.count
      })
    rescue => e
      Rails.logger.error "Failed to get rate limiting violations: #{e.message}"
      render_error("Failed to retrieve rate limiting violations", status: :internal_server_error)
    end
  end

  # GET /api/v1/admin/rate_limiting/limits/:identifier
  def user_limits
    identifier = params[:identifier]
    
    if identifier.blank?
      return render_error("Identifier is required", status: :bad_request)
    end

    begin
      limits = RateLimitService.get_limit_info(identifier)
      
      render_success({
        identifier: identifier,
        limits: limits
      })
    rescue => e
      Rails.logger.error "Failed to get rate limits for #{identifier}: #{e.message}"
      render_error("Failed to retrieve rate limits", status: :internal_server_error)
    end
  end

  # DELETE /api/v1/admin/rate_limiting/limits/:identifier
  def clear_user_limits
    identifier = params[:identifier]
    
    if identifier.blank?
      return render_error("Identifier is required", status: :bad_request)
    end

    begin
      keys_cleared = RateLimitService.clear_limits_for(identifier)
      
      # Log the administrative action
      Rails.logger.info "Admin #{current_user.email} cleared rate limits for #{identifier} (#{keys_cleared} keys cleared)"
      
      render_success({
        message: "Rate limits cleared for #{identifier}",
        keys_cleared: keys_cleared,
        identifier: identifier
      })
    rescue ArgumentError => e
      render_error(e.message, status: :bad_request)
    rescue => e
      Rails.logger.error "Failed to clear rate limits for #{identifier}: #{e.message}"
      render_error("Failed to clear rate limits", status: :internal_server_error)
    end
  end

  # POST /api/v1/admin/rate_limiting/disable
  def disable_temporarily
    duration_minutes = params[:duration_minutes]&.to_i || 60
    
    if duration_minutes < 1 || duration_minutes > 480
      return render_error("Duration must be between 1 and 480 minutes", status: :bad_request)
    end

    begin
      RateLimitService.disable_temporarily(duration_minutes)
      
      # Log the administrative action
      Rails.logger.warn "Admin #{current_user.email} temporarily disabled rate limiting for #{duration_minutes} minutes"
      
      render_success({
        message: "Rate limiting disabled for #{duration_minutes} minutes",
        disabled_until: (Time.current + duration_minutes.minutes).iso8601,
        duration_minutes: duration_minutes
      })
    rescue => e
      Rails.logger.error "Failed to disable rate limiting: #{e.message}"
      render_error("Failed to disable rate limiting", status: :internal_server_error)
    end
  end

  # POST /api/v1/admin/rate_limiting/enable
  def enable
    begin
      RateLimitService.re_enable
      
      # Log the administrative action
      Rails.logger.info "Admin #{current_user.email} re-enabled rate limiting"
      
      render_success({
        message: "Rate limiting has been re-enabled",
        enabled_at: Time.current.iso8601
      })
    rescue => e
      Rails.logger.error "Failed to re-enable rate limiting: #{e.message}"
      render_error("Failed to re-enable rate limiting", status: :internal_server_error)
    end
  end

  # GET /api/v1/admin/rate_limiting/status
  def status
    begin
      temporarily_disabled = RateLimitService.temporarily_disabled?
      system_enabled = SystemSettingsService.rate_limiting_enabled?
      
      status_info = {
        system_enabled: system_enabled,
        temporarily_disabled: temporarily_disabled,
        effective_status: system_enabled && !temporarily_disabled ? 'enabled' : 'disabled',
        last_updated: Time.current.iso8601
      }
      
      if temporarily_disabled
        # Try to get the remaining time
        ttl = Rails.cache.redis.ttl('rate_limiting_temporarily_disabled')
        if ttl > 0
          status_info[:disabled_until] = (Time.current + ttl.seconds).iso8601
          status_info[:remaining_seconds] = ttl
        end
      end
      
      render_success(status_info)
    rescue => e
      Rails.logger.error "Failed to get rate limiting status: #{e.message}"
      render_error("Failed to retrieve rate limiting status", status: :internal_server_error)
    end
  end

  private

  def get_recent_violations
    violations = []
    
    # Get all rate limit keys and check for violations
    begin
      Rails.cache.redis.keys('rate_limit:*').each do |key|
        current_count = Rails.cache.read(key) || 0
        limit = extract_limit_from_key(key)
        
        if limit && current_count >= limit
          parts = key.split(':')
          next if parts.length < 4
          
          controller = parts[1]
          action = parts[2]
          identifier = parts[3]
          
          violations << {
            endpoint: "#{controller}/#{action}",
            identifier: identifier,
            count: current_count,
            limit: limit,
            timestamp: Time.current.iso8601 # We don't have exact timestamp, use current time
          }
        end
      end
    rescue => e
      Rails.logger.error "Error getting violations: #{e.message}"
    end
    
    # Sort by count descending (worst violations first)
    violations.sort_by { |v| -v[:count] }
  end

  def extract_limit_from_key(key)
    parts = key.split(':')
    return nil if parts.length < 4

    controller_name = parts[1]
    limit_type = determine_limit_type_for_controller(controller_name)
    SystemSettingsService.rate_limit_setting(limit_type)
  end

  def determine_limit_type_for_controller(controller_name)
    case controller_name
    when 'sessions'
      'login_attempts_per_hour'
    when 'registrations'
      'registration_attempts_per_hour'
    when 'passwords'
      'password_reset_attempts_per_hour'
    when 'email_verifications'
      'email_verification_attempts_per_hour'
    when 'webhooks'
      'webhook_requests_per_minute'
    when 'impersonation_sessions'
      'impersonation_attempts_per_hour'
    else
      'api_requests_per_minute'
    end
  end
end