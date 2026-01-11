# frozen_string_literal: true

class Api::V1::AuditLogsController < ApplicationController
  # Static SQL subquery for action-to-level mapping (no user input, safe from injection)
  LEVEL_SUBQUERY = <<~SQL.freeze
    SELECT 'error' as level, unnest(array['login_failed', 'payment_failed', 'system_error']) as action
    UNION ALL
    SELECT 'warning' as level, unnest(array['payment_retry', 'account_suspension']) as action
    UNION ALL
    SELECT 'info' as level, unnest(array['user_login', 'user_logout', 'subscription_created']) as action
  SQL
  skip_before_action :authenticate_request, only: [ :create ]
  before_action -> { require_permission("audit_logs.read") }, only: [ :index, :show, :stats, :security_summary, :compliance_summary, :activity_timeline, :risk_analysis ]
  before_action -> { require_permission("audit_logs.export") }, only: [ :export ]
  # NOTE: destroy and bulk_delete actions not yet implemented
  # before_action -> { require_permission("audit_logs.delete") }, only: [ :destroy, :bulk_delete ]
  before_action :authenticate_worker_or_admin, only: [ :create ]

  # GET /api/v1/audit_logs
  def index
    filters = audit_log_filters

    # Pagination using Kaminari
    page = params[:page] || 1
    per_page = [ params[:per_page]&.to_i || 50, 200 ].min # Default 50, max 200

    logs = AuditLog.includes(:user, :account)
                   .apply_filters(filters)
                   .order(created_at: :desc)
                   .page(page)
                   .per(per_page)

    render_success(
      data: logs.map { |log| audit_log_data(log) },
      meta: {
        current_page: logs.current_page,
        per_page: logs.limit_value,
        total_pages: logs.total_pages,
        total: logs.total_count,
        stats: audit_log_stats
      }
    )
  end

  # GET /api/v1/audit_logs/:id
  def show
    log = AuditLog.includes(:user, :account).find(params[:id])

    render_success(
      data: detailed_audit_log_data(log)
    )
  rescue ActiveRecord::RecordNotFound
    render_error("Audit log not found", status: :not_found)
  end

  # GET /api/v1/audit_logs/stats
  def stats
    render_success(
      data: detailed_audit_log_stats
    )
  end

  # GET /api/v1/audit_logs/security_summary
  def security_summary
    time_range = params[:time_range] || "24h"
    start_time = parse_time_range(time_range)

    logs = AuditLog.where("created_at >= ?", start_time)

    # Security-related actions
    security_actions = %w[login_failed unauthorized_access permission_denied password_change
                          account_locked suspicious_activity ip_blocked token_revoked]
    failed_actions = %w[login_failed payment_failed operation_failed validation_failed]
    high_risk_actions = %w[account_locked ip_blocked unauthorized_access suspicious_activity]

    render_success({
      totalEvents: logs.count,
      securityEvents: logs.where(action: security_actions).count,
      failedEvents: logs.where(action: failed_actions).count,
      highRiskEvents: logs.where(action: high_risk_actions).count,
      suspiciousEvents: logs.where(action: "suspicious_activity").count,
      uniqueUsers: logs.distinct.count(:user_id),
      uniqueIps: logs.where.not(ip_address: nil).distinct.count(:ip_address),
      bySeverity: logs.group(:severity).count,
      byRiskLevel: logs.group(:risk_level).count,
      hourlyDistribution: logs.group_by_hour(:created_at, range: start_time..Time.current).count
    })
  end

  # GET /api/v1/audit_logs/compliance_summary
  def compliance_summary
    time_range = params[:time_range] || "30d"
    start_time = parse_time_range(time_range)

    logs = AuditLog.where("created_at >= ?", start_time)

    # GDPR-related actions
    gdpr_actions = %w[data_export_requested data_deletion_requested consent_updated
                      privacy_settings_changed data_access_logged]

    # Data access patterns
    data_access_actions = %w[data_export data_access user_data_viewed account_data_accessed
                             report_generated bulk_export]

    # Consent management
    consent_actions = %w[consent_given consent_withdrawn consent_updated
                         terms_accepted privacy_policy_accepted]

    # Retention compliance
    retention_actions = %w[data_retention_applied data_archived data_purged
                           backup_created backup_restored]

    render_success({
      totalEvents: logs.count,
      gdprEvents: logs.where(action: gdpr_actions).count,
      dataAccessEvents: logs.where(action: data_access_actions).count,
      consentEvents: logs.where(action: consent_actions).count,
      retentionEvents: logs.where(action: retention_actions).count,
      dataExportRequests: logs.where(action: "data_export_requested").count,
      dataDeletionRequests: logs.where(action: "data_deletion_requested").count,
      consentChanges: logs.where(action: consent_actions).count,
      byComplianceType: {
        gdpr: logs.where(action: gdpr_actions).count,
        data_access: logs.where(action: data_access_actions).count,
        consent: logs.where(action: consent_actions).count,
        retention: logs.where(action: retention_actions).count
      },
      weeklyTrend: logs.where(action: gdpr_actions + data_access_actions)
                       .group_by_day(:created_at, range: start_time..Time.current)
                       .count,
      uniqueDataSubjects: logs.where(action: gdpr_actions).distinct.count(:user_id),
      pendingRequests: {
        exports: DataManagement::ExportRequest.where(status: "pending").count,
        deletions: DataManagement::DeletionRequest.where(status: "pending").count
      }
    })
  rescue NameError
    # Handle case where compliance models don't exist
    render_success({
      totalEvents: logs.count,
      gdprEvents: logs.where(action: gdpr_actions).count,
      dataAccessEvents: logs.where(action: data_access_actions).count,
      consentEvents: logs.where(action: consent_actions).count,
      retentionEvents: logs.where(action: retention_actions).count,
      pendingRequests: { exports: 0, deletions: 0 }
    })
  end

  # GET /api/v1/audit_logs/activity_timeline
  def activity_timeline
    time_range = params[:time_range] || "24h"
    start_time = parse_time_range(time_range)
    granularity = params[:granularity] || "hour"

    logs = AuditLog.where("created_at >= ?", start_time)

    # Group by time based on granularity
    timeline_data = case granularity
    when "minute"
      logs.group_by_minute(:created_at, range: start_time..Time.current).count
    when "hour"
      logs.group_by_hour(:created_at, range: start_time..Time.current).count
    when "day"
      logs.group_by_day(:created_at, range: start_time..Time.current).count
    else
      logs.group_by_hour(:created_at, range: start_time..Time.current).count
    end

    # Get action distribution over time
    action_timeline = logs.group(:action)
                          .group_by_hour(:created_at, range: start_time..Time.current)
                          .count

    # Get user activity over time
    user_activity = logs.where.not(user_id: nil)
                        .group_by_hour(:created_at, range: start_time..Time.current)
                        .distinct
                        .count(:user_id)

    # Peak activity detection
    peak_hour = timeline_data.max_by { |_, count| count }&.first
    lowest_hour = timeline_data.min_by { |_, count| count }&.first

    render_success({
      timeline: timeline_data,
      actionTimeline: action_timeline,
      userActivity: user_activity,
      summary: {
        totalEvents: logs.count,
        averagePerHour: (logs.count.to_f / [ (Time.current - start_time) / 1.hour, 1 ].max).round(2),
        peakActivity: {
          time: peak_hour&.iso8601,
          count: timeline_data[peak_hour] || 0
        },
        lowestActivity: {
          time: lowest_hour&.iso8601,
          count: timeline_data[lowest_hour] || 0
        },
        uniqueUsers: logs.distinct.count(:user_id),
        uniqueActions: logs.distinct.count(:action)
      },
      topActions: logs.group(:action).order("count_id DESC").limit(10).count(:id),
      topUsers: logs.joins(:user).group("users.email").order("count_id DESC").limit(5).count(:id)
    })
  end

  # GET /api/v1/audit_logs/risk_analysis
  def risk_analysis
    time_range = params[:time_range] || "7d"
    start_time = parse_time_range(time_range)

    logs = AuditLog.where("created_at >= ?", start_time)

    # Define risk categories
    high_risk_actions = %w[account_locked ip_blocked unauthorized_access suspicious_activity
                           data_breach_detected admin_override privilege_escalation]
    medium_risk_actions = %w[login_failed permission_denied password_change token_revoked
                             multiple_failed_attempts unusual_activity rate_limited]
    low_risk_actions = %w[password_reset settings_changed api_key_created webhook_created]

    # Calculate risk scores
    high_risk_count = logs.where(action: high_risk_actions).count
    medium_risk_count = logs.where(action: medium_risk_actions).count
    low_risk_count = logs.where(action: low_risk_actions).count

    # IP-based risk analysis
    suspicious_ips = logs.where(action: %w[login_failed unauthorized_access])
                         .group(:ip_address)
                         .having("count(*) > 5")
                         .count

    # User-based risk analysis
    high_risk_users = logs.where(action: high_risk_actions + medium_risk_actions)
                          .where.not(user_id: nil)
                          .group(:user_id)
                          .having("count(*) > 3")
                          .count

    # Time-based patterns (off-hours activity)
    off_hours_activity = logs.where("EXTRACT(hour FROM created_at) < 6 OR EXTRACT(hour FROM created_at) > 22").count

    # Geographic anomalies (if IP geolocation is available)
    unique_ips_per_user = logs.where.not(user_id: nil, ip_address: nil)
                              .group(:user_id)
                              .distinct
                              .count(:ip_address)
    multi_ip_users = unique_ips_per_user.select { |_, count| count > 5 }.keys.count

    # Calculate overall risk score (0-100)
    risk_score = calculate_overall_risk_score(
      high_risk_count: high_risk_count,
      medium_risk_count: medium_risk_count,
      suspicious_ips_count: suspicious_ips.count,
      off_hours_percentage: logs.count > 0 ? (off_hours_activity.to_f / logs.count * 100) : 0
    )

    render_success({
      overallRiskScore: risk_score,
      riskLevel: risk_level_from_score(risk_score),
      riskDistribution: {
        high: high_risk_count,
        medium: medium_risk_count,
        low: low_risk_count,
        info: logs.count - high_risk_count - medium_risk_count - low_risk_count
      },
      threatIndicators: {
        suspiciousIps: suspicious_ips.count,
        highRiskUsers: high_risk_users.count,
        offHoursActivity: off_hours_activity,
        multiIpUsers: multi_ip_users,
        failedLogins: logs.where(action: "login_failed").count,
        unauthorizedAccess: logs.where(action: "unauthorized_access").count
      },
      topThreats: logs.where(action: high_risk_actions)
                      .group(:action)
                      .order("count_id DESC")
                      .limit(5)
                      .count(:id),
      suspiciousIpDetails: suspicious_ips.first(10).to_h,
      riskTrend: logs.where(action: high_risk_actions + medium_risk_actions)
                     .group_by_day(:created_at, range: start_time..Time.current)
                     .count,
      recommendations: generate_risk_recommendations(
        high_risk_count: high_risk_count,
        suspicious_ips_count: suspicious_ips.count,
        off_hours_activity: off_hours_activity
      )
    })
  end

  # POST /api/v1/audit_logs/export
  def export
    filters = audit_log_filters
    format = params[:format] || "csv"

    # Enqueue background job for large exports
    if should_use_background_export?
      job_id = AuditLogExportJob.perform_later(
        current_user.id,
        filters,
        format
      ).job_id

      render_success(
        message: "Export job queued successfully",
        data: {
          job_id: job_id,
          estimated_completion: 5.minutes.from_now.iso8601
        },
        status: :accepted
      )
    else
      # For small exports, return data immediately
      logs = AuditLog.includes(:user, :account)
                     .apply_filters(filters)
                     .order(created_at: :desc)
                     .limit(1000)

      export_data = generate_export_data(logs, format)

      render_success(
        data: {
          format: format,
          content: export_data,
          filename: "audit_logs_#{Date.current.strftime('%Y%m%d')}.#{format}"
        }
      )
    end
  end

  # POST /api/v1/audit_logs
  def create
    begin
      # Extract parameters for audit log creation
      # Handle both flat and nested parameter formats
      audit_params = if params[:audit_log].present?
                       params[:audit_log].permit(:action, :resource_type, :resource_id, :source, :ip_address, :user_agent, details: {})
      else
                       params.permit(:action, :resource_type, :resource_id, :source, :ip_address, :user_agent, details: {})
      end

      # Validate required parameters
      unless audit_params[:action].present?
        return render_error("Action is required", status: :unprocessable_content)
      end

      # Set defaults for worker requests
      audit_params[:resource_type] ||= "WorkerJob"
      audit_params[:resource_id] ||= "worker_task"
      audit_params[:source] ||= "worker"
      audit_params[:ip_address] ||= request.remote_ip
      audit_params[:user_agent] ||= request.user_agent

      # Handle details/metadata (can be at top level or nested)
      metadata = audit_params[:details] || params[:details] || {}
      metadata[:created_via] = "worker_api"
      metadata[:request_timestamp] = Time.current.iso8601

      # Find account - use system account for worker requests
      account = if current_user&.account
                  current_user.account
      else
                  # For worker service requests, find a system account or use first account
                  Account.find_by(name: "System") || Account.first
      end

      unless account
        return render_error("No account found for audit log", status: :unprocessable_content)
      end

      # Create audit log
      audit_log = AuditLog.create!(
        action: audit_params[:action],
        resource_type: audit_params[:resource_type],
        resource_id: audit_params[:resource_id],
        user: current_user,
        account: account,
        source: audit_params[:source],
        ip_address: audit_params[:ip_address],
        user_agent: audit_params[:user_agent],
        metadata: metadata
      )

      render_success(
        message: "Audit log created successfully",
        data: {
          id: audit_log.id,
          action: audit_log.action,
          created_at: audit_log.created_at.iso8601
        },
        status: :created
      )

    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Audit log validation failed: #{e.record.errors.full_messages.join(', ')}"
      render_error(
        "Invalid audit log data",
        :unprocessable_content,
        details: e.record.errors.full_messages
      )
    rescue StandardError => e
      Rails.logger.error "Failed to create audit log: #{e.message}"
      render_error(
        "Failed to create audit log",
        :internal_server_error,
        details: e.message
      )
    end
  end

  # DELETE /api/v1/audit_logs/cleanup
  def cleanup
    cutoff_date = params[:cutoff_date]&.to_date || 1.year.ago.to_date

    return render_bad_request("Invalid cutoff date") if cutoff_date > Date.current

    deleted_count = AuditLog.where("created_at < ?", cutoff_date).delete_all

    # Log the cleanup action
    AuditLog.create!(
      user: current_user,
      account: current_user.account,
      action: "audit_logs_cleanup",
      resource_type: "AuditLog",
      resource_id: "bulk_cleanup",
      source: "admin_panel",
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: {
        cutoff_date: cutoff_date.iso8601,
        deleted_count: deleted_count
      }
    )

    render_success(
      message: "Successfully deleted #{deleted_count} audit log entries",
      data: {
        deleted_count: deleted_count,
        cutoff_date: cutoff_date.iso8601
      }
    )
  end

  private

  def require_admin_access
    unless current_user.has_permission?("account.manage") || current_user.has_permission?("admin.access")
      render_error("Access denied: Admin privileges required", status: :forbidden)
    end
  end

  def authenticate_worker_or_admin
    # Allow admin users or valid worker tokens
    return if current_user&.has_permission?("admin.access")

    # Check for worker token authentication
    auth_header = request.headers["Authorization"]
    return render_unauthorized("Missing authorization header") unless auth_header

    token = auth_header.sub(/^Bearer /, "")
    return render_unauthorized("Missing token") if token.blank?

    # Check if it's a worker token (swt_ prefix)
    if token.starts_with?("swt_")
      worker = Worker.find_by(token: token, status: "active")
      return if worker.present?
      render_unauthorized("Invalid worker token")
      return
    end

    # Otherwise try JWT decode for service tokens
    begin
      payload = JWT.decode(token, Rails.application.config.jwt_secret_key, true, algorithm: "HS256").first

      # Accept service tokens from worker
      if payload["service"] == "backend" && payload["type"] == "service"
        # Service token is valid, allow access
        return
      end

      render_unauthorized("Invalid service token")
    rescue JWT::DecodeError, JWT::ExpiredSignature => e
      Rails.logger.warn "Invalid service token for audit log creation: #{e.message}"
      render_unauthorized("Invalid or expired service token")
    end
  end

  def render_unauthorized(message)
    render_error(message, status: :unauthorized)
  end

  def audit_log_filters
    {
      action: params[:action_type],  # Use action_type to avoid Rails routing conflict
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
      source: log.source || "system",
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
      by_action: AuditLog.group(:action).order("count_id DESC").limit(10).count(:id),
      by_source: AuditLog.group(:source).count,
      by_level: AuditLog.joins("LEFT JOIN (#{level_subquery}) AS levels ON levels.action = audit_logs.action")
                        .group("levels.level").count,
      failed_logins_today: AuditLog.where(action: "login_failed", created_at: Date.current.beginning_of_day..Date.current.end_of_day).count,
      suspicious_activity_count: detect_suspicious_activity_count
    }
  end

  def detailed_audit_log_stats
    audit_log_stats.merge({
      top_users: AuditLog.joins(:user).group("users.email").order("count_id DESC").limit(5).count(:id),
      top_accounts: AuditLog.joins(:account).group("accounts.name").order("count_id DESC").limit(5).count(:id),
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
    when "csv"
      generate_csv_export(logs)
    when "json"
      logs.map { |log| audit_log_data(log) }.to_json
    else
      raise ArgumentError, "Unsupported export format: #{format}"
    end
  end

  def generate_csv_export(logs)
    require "csv"

    CSV.generate(headers: true) do |csv|
      csv << [ "ID", "Action", "User Email", "Account", "Resource Type", "Resource ID",
              "Source", "IP Address", "Status", "Created At", "Metadata" ]

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
      "error"
    when /warning|timeout|retry/i
      "warning"
    else
      "success"
    end
  end

  def determine_log_level(action)
    case action
    when /error|failed|suspend|lock|block/i
      "error"
    when /warning|timeout|retry/i
      "warning"
    when /create|update|delete|login|logout/i
      "info"
    else
      "debug"
    end
  end

  def format_log_message(log)
    case log.action
    when "user_login"
      "User #{log.user&.email} logged in from #{log.ip_address}"
    when "user_logout"
      "User #{log.user&.email} logged out"
    when "user_registration"
      "New user registered: #{log.user&.email}"
    when "subscription_created"
      "New subscription created for #{log.account&.name}"
    when "payment_completed"
      "Payment completed for #{log.account&.name}"
    when "payment_failed"
      "Payment failed for #{log.account&.name}"
    when "login_failed"
      "Failed login attempt for #{log.metadata&.dig('email')} from #{log.ip_address}"
    when "admin_settings_update"
      "Admin settings updated by #{log.user&.email}"
    when "impersonation_start"
      "#{log.user&.email} started impersonating user"
    when "impersonation_end"
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
      score += [ recent_from_ip / 5, 5 ].min
    end

    [ score, 10 ].min # Cap at 10
  end

  def detect_suspicious_activity_count
    suspicious_count = 0

    # Multiple failed logins from same IP
    suspicious_count += AuditLog.where(
      action: "login_failed",
      created_at: 24.hours.ago..Time.current
    ).group(:ip_address)
     .having("count(*) > 10")
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
    LEVEL_SUBQUERY
  end

  def error_actions
    [ "login_failed", "payment_failed", "system_error", "webhook_failed", "api_error" ]
  end

  def admin_actions
    [ "admin_settings_update", "user_suspension", "account_suspension", "impersonation_start" ]
  end

  def extract_browser(user_agent)
    case user_agent
    when /Chrome/i then "Chrome"
    when /Firefox/i then "Firefox"
    when /Safari/i then "Safari"
    when /Edge/i then "Edge"
    else "Unknown"
    end
  end

  def extract_platform(user_agent)
    case user_agent
    when /Windows/i then "Windows"
    when /Macintosh|Mac OS/i then "macOS"
    when /Linux/i then "Linux"
    when /iPhone|iPad/i then "iOS"
    when /Android/i then "Android"
    else "Unknown"
    end
  end

  def extract_device(user_agent)
    case user_agent
    when /Mobile|iPhone|Android/i then "Mobile"
    when /Tablet|iPad/i then "Tablet"
    else "Desktop"
    end
  end

  def render_bad_request(message)
    render_error(message, status: :bad_request)
  end

  def calculate_overall_risk_score(high_risk_count:, medium_risk_count:, suspicious_ips_count:, off_hours_percentage:)
    score = 0

    # High risk events contribution (0-40 points)
    score += [ high_risk_count * 4, 40 ].min

    # Medium risk events contribution (0-25 points)
    score += [ medium_risk_count * 1, 25 ].min

    # Suspicious IPs contribution (0-20 points)
    score += [ suspicious_ips_count * 5, 20 ].min

    # Off-hours activity contribution (0-15 points)
    score += [ off_hours_percentage * 0.5, 15 ].min

    [ score.round, 100 ].min
  end

  def risk_level_from_score(score)
    case score
    when 0..20 then "low"
    when 21..40 then "moderate"
    when 41..60 then "elevated"
    when 61..80 then "high"
    else "critical"
    end
  end

  def generate_risk_recommendations(high_risk_count:, suspicious_ips_count:, off_hours_activity:)
    recommendations = []

    if high_risk_count > 10
      recommendations << {
        priority: "high",
        category: "security",
        message: "High volume of security events detected. Review account access patterns and consider enabling additional authentication measures."
      }
    end

    if suspicious_ips_count > 3
      recommendations << {
        priority: "high",
        category: "network",
        message: "Multiple suspicious IP addresses detected. Consider implementing IP blocking or geo-restrictions."
      }
    end

    if off_hours_activity > 50
      recommendations << {
        priority: "medium",
        category: "monitoring",
        message: "Significant off-hours activity detected. Review access policies and consider implementing time-based access controls."
      }
    end

    if recommendations.empty?
      recommendations << {
        priority: "low",
        category: "general",
        message: "No immediate security concerns detected. Continue monitoring for anomalies."
      }
    end

    recommendations
  end

  def parse_time_range(time_range)
    case time_range
    when "1h" then 1.hour.ago
    when "6h" then 6.hours.ago
    when "24h" then 24.hours.ago
    when "7d" then 7.days.ago
    when "30d" then 30.days.ago
    when "90d" then 90.days.ago
    else 24.hours.ago
    end
  end

  def calculate_risk_distribution(logs)
    high_risk_actions = %w[account_locked ip_blocked unauthorized_access suspicious_activity]
    medium_risk_actions = %w[login_failed permission_denied password_change token_revoked]
    low_risk_actions = %w[user_login user_logout settings_changed profile_updated]

    {
      high: logs.where(action: high_risk_actions).count,
      medium: logs.where(action: medium_risk_actions).count,
      low: logs.where(action: low_risk_actions).count,
      info: logs.where.not(action: high_risk_actions + medium_risk_actions + low_risk_actions).count
    }
  end
end
