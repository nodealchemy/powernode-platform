# frozen_string_literal: true

class Api::V1::AuditLogsController < ApplicationController
  before_action :require_admin_access

  # GET /api/v1/audit_logs
  def index
    filters = audit_log_filters
    logs = AuditLog.includes(:user, :account)
                   .apply_filters(filters)
                   .order(created_at: :desc)
                   .page(params[:page] || 1)
                   .per(params[:per_page] || 50)

    render json: {
      success: true,
      data: {
        logs: logs.map { |log| audit_log_data(log) },
        pagination: {
          current_page: logs.current_page,
          per_page: logs.limit_value,
          total_pages: logs.total_pages,
          total_count: logs.total_count
        },
        stats: audit_log_stats
      }
    }, status: :ok
  end

  # GET /api/v1/audit_logs/:id
  def show
    log = AuditLog.includes(:user, :account).find(params[:id])
    
    render json: {
      success: true,
      data: detailed_audit_log_data(log)
    }, status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error: 'Audit log not found'
    }, status: :not_found
  end

  # GET /api/v1/audit_logs/stats
  def stats
    render json: {
      success: true,
      data: detailed_audit_log_stats
    }, status: :ok
  end

  # POST /api/v1/audit_logs/export
  def export
    filters = audit_log_filters
    format = params[:format] || 'csv'
    
    # Enqueue background job for large exports
    if should_use_background_export?
      job_id = AuditLogExportJob.perform_later(
        current_user.id,
        filters,
        format
      ).job_id
      
      render json: {
        success: true,
        message: 'Export job queued successfully',
        data: {
          job_id: job_id,
          estimated_completion: 5.minutes.from_now.iso8601
        }
      }, status: :accepted
    else
      # For small exports, return data immediately
      logs = AuditLog.includes(:user, :account)
                     .apply_filters(filters)
                     .order(created_at: :desc)
                     .limit(1000)
      
      export_data = generate_export_data(logs, format)
      
      render json: {
        success: true,
        data: {
          format: format,
          content: export_data,
          filename: "audit_logs_#{Date.current.strftime('%Y%m%d')}.#{format}"
        }
      }, status: :ok
    end
  end

  # DELETE /api/v1/audit_logs/cleanup
  def cleanup
    cutoff_date = params[:cutoff_date]&.to_date || 1.year.ago.to_date
    
    return render_bad_request('Invalid cutoff date') if cutoff_date > Date.current
    
    deleted_count = AuditLog.where('created_at < ?', cutoff_date).delete_all
    
    # Log the cleanup action
    AuditLog.create!(
      user: current_user,
      account: current_user.account,
      action: 'audit_logs_cleanup',
      resource_type: 'AuditLog',
      resource_id: 'bulk_cleanup',
      source: 'admin_panel',
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: {
        cutoff_date: cutoff_date.iso8601,
        deleted_count: deleted_count
      }
    )
    
    render json: {
      success: true,
      message: "Successfully deleted #{deleted_count} audit log entries",
      data: {
        deleted_count: deleted_count,
        cutoff_date: cutoff_date.iso8601
      }
    }, status: :ok
  end

  private

  def require_admin_access
    unless current_user.owner? || current_user.admin?
      render json: {
        success: false,
        error: "Access denied: Admin privileges required"
      }, status: :forbidden
    end
  end

  def audit_log_filters
    {
      action: params[:action],
      user_email: params[:user_email],
      account_name: params[:account_name],
      resource_type: params[:resource_type],
      source: params[:source],
      ip_address: params[:ip_address],
      date_from: params[:date_from]&.to_date,
      date_to: params[:date_to]&.to_date,
      status: params[:status]
    }.compact
  end

  def audit_log_data(log)
    {
      id: log.id,
      action: log.action,
      resource_type: log.resource_type,
      resource_id: log.resource_id,
      source: log.source || 'system',
      ip_address: log.ip_address,
      user_agent: log.user_agent,
      user: log.user ? {
        id: log.user.id,
        email: log.user.email,
        full_name: log.user.full_name
      } : nil,
      account: log.account ? {
        id: log.account.id,
        name: log.account.name
      } : nil,
      metadata: log.metadata || {},
      status: determine_log_status(log),
      level: determine_log_level(log.action),
      message: format_log_message(log),
      created_at: log.created_at.iso8601
    }
  end

  def detailed_audit_log_data(log)
    audit_log_data(log).merge({
      user_agent_parsed: parse_user_agent(log.user_agent),
      related_logs: find_related_logs(log),
      risk_score: calculate_risk_score(log)
    })
  end

  def audit_log_stats
    {
      total_logs: AuditLog.count,
      logs_today: AuditLog.where(created_at: Date.current.beginning_of_day..Date.current.end_of_day).count,
      logs_this_week: AuditLog.where(created_at: 1.week.ago..Time.current).count,
      by_action: AuditLog.group(:action).order('count_id DESC').limit(10).count(:id),
      by_source: AuditLog.group(:source).count,
      by_level: AuditLog.joins("LEFT JOIN (#{level_subquery}) AS levels ON levels.action = audit_logs.action")
                        .group('levels.level').count,
      failed_logins_today: AuditLog.where(action: 'login_failed', created_at: Date.current.beginning_of_day..Date.current.end_of_day).count,
      suspicious_activity_count: detect_suspicious_activity_count
    }
  end

  def detailed_audit_log_stats
    audit_log_stats.merge({
      top_users: AuditLog.joins(:user).group('users.email').order('count_id DESC').limit(5).count(:id),
      top_accounts: AuditLog.joins(:account).group('accounts.name').order('count_id DESC').limit(5).count(:id),
      hourly_distribution: AuditLog.where(created_at: 24.hours.ago..Time.current)
                                   .group("EXTRACT(hour FROM created_at)")
                                   .count,
      error_trend: AuditLog.where(action: error_actions, created_at: 7.days.ago..Time.current)
                           .group_by_day(:created_at).count
    })
  end

  def should_use_background_export?
    estimated_count = AuditLog.apply_filters(audit_log_filters).count
    estimated_count > 5000
  end

  def generate_export_data(logs, format)
    case format.downcase
    when 'csv'
      generate_csv_export(logs)
    when 'json'
      logs.map { |log| audit_log_data(log) }.to_json
    else
      raise ArgumentError, "Unsupported export format: #{format}"
    end
  end

  def generate_csv_export(logs)
    require 'csv'
    
    CSV.generate(headers: true) do |csv|
      csv << ['ID', 'Action', 'User Email', 'Account', 'Resource Type', 'Resource ID', 
              'Source', 'IP Address', 'Status', 'Created At', 'Metadata']
      
      logs.each do |log|
        csv << [
          log.id,
          log.action,
          log.user&.email,
          log.account&.name,
          log.resource_type,
          log.resource_id,
          log.source,
          log.ip_address,
          determine_log_status(log),
          log.created_at.iso8601,
          log.metadata.to_json
        ]
      end
    end
  end

  def determine_log_status(log)
    case log.action
    when /failed|error|suspend|block|lock/i
      'error'
    when /warning|timeout|retry/i
      'warning'
    else
      'success'
    end
  end

  def determine_log_level(action)
    case action
    when /error|failed|suspend|lock|block/i
      'error'
    when /warning|timeout|retry/i
      'warning'
    when /create|update|delete|login|logout/i
      'info'
    else
      'debug'
    end
  end

  def format_log_message(log)
    case log.action
    when 'user_login'
      "User #{log.user&.email} logged in from #{log.ip_address}"
    when 'user_logout'
      "User #{log.user&.email} logged out"
    when 'user_registration'
      "New user registered: #{log.user&.email}"
    when 'subscription_created'
      "New subscription created for #{log.account&.name}"
    when 'payment_completed'
      "Payment completed for #{log.account&.name}"
    when 'payment_failed'
      "Payment failed for #{log.account&.name}"
    when 'login_failed'
      "Failed login attempt for #{log.metadata&.dig('email')} from #{log.ip_address}"
    when 'admin_settings_update'
      "Admin settings updated by #{log.user&.email}"
    when 'impersonation_start'
      "#{log.user&.email} started impersonating user"
    when 'impersonation_end'
      "#{log.user&.email} ended impersonation session"
    else
      log.action.humanize
    end
  end

  def parse_user_agent(user_agent)
    # Simple user agent parsing - in production, use a proper library like browser gem
    return nil unless user_agent

    {
      raw: user_agent,
      browser: extract_browser(user_agent),
      platform: extract_platform(user_agent),
      device: extract_device(user_agent)
    }
  end

  def find_related_logs(log)
    # Find related logs within 1 hour time window
    time_window = 1.hour
    related = AuditLog.where(
      created_at: (log.created_at - time_window)..(log.created_at + time_window)
    ).where.not(id: log.id)
    
    # Filter by same user, IP, or resource if available
    related = related.where(user: log.user) if log.user
    related = related.or(AuditLog.where(ip_address: log.ip_address)) if log.ip_address
    related = related.or(AuditLog.where(resource_type: log.resource_type, resource_id: log.resource_id)) if log.resource_type
    
    related.limit(10).map { |l| audit_log_data(l) }
  end

  def calculate_risk_score(log)
    score = 0
    
    # Base risk by action type
    score += case log.action
             when /failed|error/i then 3
             when /login|logout/i then 1
             when /create|delete/i then 2
             when /admin|impersonation/i then 4
             else 1
             end
    
    # Risk by time (higher risk during off-hours)
    hour = log.created_at.hour
    score += 2 if hour < 6 || hour > 22
    
    # Risk by frequency (multiple actions from same IP/user)
    if log.ip_address
      recent_from_ip = AuditLog.where(
        ip_address: log.ip_address, 
        created_at: log.created_at - 1.hour..log.created_at
      ).count
      score += [recent_from_ip / 5, 5].min
    end
    
    [score, 10].min # Cap at 10
  end

  def detect_suspicious_activity_count
    suspicious_count = 0
    
    # Multiple failed logins from same IP
    suspicious_count += AuditLog.where(
      action: 'login_failed',
      created_at: 24.hours.ago..Time.current
    ).group(:ip_address)
     .having('count(*) > 10')
     .count
     .size
    
    # Admin actions outside business hours
    suspicious_count += AuditLog.where(
      action: admin_actions,
      created_at: 24.hours.ago..Time.current
    ).select { |log| log.created_at.hour < 6 || log.created_at.hour > 22 }
     .count
    
    suspicious_count
  end

  def level_subquery
    "SELECT 'error' as level, unnest(array['login_failed', 'payment_failed', 'system_error']) as action
     UNION ALL
     SELECT 'warning' as level, unnest(array['payment_retry', 'account_suspension']) as action
     UNION ALL  
     SELECT 'info' as level, unnest(array['user_login', 'user_logout', 'subscription_created']) as action"
  end

  def error_actions
    ['login_failed', 'payment_failed', 'system_error', 'webhook_failed', 'api_error']
  end

  def admin_actions
    ['admin_settings_update', 'user_suspension', 'account_suspension', 'impersonation_start']
  end

  def extract_browser(user_agent)
    case user_agent
    when /Chrome/i then 'Chrome'
    when /Firefox/i then 'Firefox'  
    when /Safari/i then 'Safari'
    when /Edge/i then 'Edge'
    else 'Unknown'
    end
  end

  def extract_platform(user_agent)
    case user_agent
    when /Windows/i then 'Windows'
    when /Macintosh|Mac OS/i then 'macOS'
    when /Linux/i then 'Linux'
    when /iPhone|iPad/i then 'iOS'
    when /Android/i then 'Android'
    else 'Unknown'
    end
  end

  def extract_device(user_agent)
    case user_agent
    when /Mobile|iPhone|Android/i then 'Mobile'
    when /Tablet|iPad/i then 'Tablet'
    else 'Desktop'
    end
  end

  def render_bad_request(message)
    render json: {
      success: false,
      error: message
    }, status: :bad_request
  end
end