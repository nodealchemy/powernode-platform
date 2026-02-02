# frozen_string_literal: true

# Service for querying and analyzing audit logs
#
# Provides audit log analysis including:
# - Stats and summaries
# - Security analysis
# - Compliance analysis
# - Timeline analysis
# - Risk analysis
# - Data formatting
#
# Usage:
#   service = AuditLogQueryService.new
#   stats = service.detailed_stats
#
class AuditLogQueryService
  SECURITY_ACTIONS = %w[login_failed unauthorized_access permission_denied password_change
                        account_locked suspicious_activity ip_blocked token_revoked].freeze
  FAILED_ACTIONS = %w[login_failed payment_failed operation_failed validation_failed].freeze
  HIGH_RISK_ACTIONS = %w[account_locked ip_blocked unauthorized_access suspicious_activity
                         data_breach_detected admin_override privilege_escalation].freeze
  MEDIUM_RISK_ACTIONS = %w[login_failed permission_denied password_change token_revoked
                           multiple_failed_attempts unusual_activity rate_limited].freeze
  LOW_RISK_ACTIONS = %w[password_reset settings_changed api_key_created webhook_created].freeze
  GDPR_ACTIONS = %w[data_export_requested data_deletion_requested consent_updated
                    privacy_settings_changed data_access_logged].freeze
  DATA_ACCESS_ACTIONS = %w[data_export data_access user_data_viewed account_data_accessed
                           report_generated bulk_export].freeze
  CONSENT_ACTIONS = %w[consent_given consent_withdrawn consent_updated
                       terms_accepted privacy_policy_accepted].freeze
  RETENTION_ACTIONS = %w[data_retention_applied data_archived data_purged
                         backup_created backup_restored].freeze
  ERROR_ACTIONS = %w[login_failed payment_failed system_error webhook_failed api_error].freeze
  ADMIN_ACTIONS = %w[admin_settings_update user_suspension account_suspension impersonation_start].freeze

  LEVEL_SUBQUERY = <<~SQL.freeze
    SELECT 'error' as level, unnest(array['login_failed', 'payment_failed', 'system_error']) as action
    UNION ALL
    SELECT 'warning' as level, unnest(array['payment_retry', 'account_suspension']) as action
    UNION ALL
    SELECT 'info' as level, unnest(array['user_login', 'user_logout', 'subscription_created']) as action
  SQL

  # =============================================================================
  # STATS
  # =============================================================================

  def basic_stats
    {
      total_logs: AuditLog.count,
      logs_today: AuditLog.where(created_at: Date.current.beginning_of_day..Date.current.end_of_day).count,
      logs_this_week: AuditLog.where(created_at: 1.week.ago..Time.current).count,
      by_action: AuditLog.group(:action).order("count_id DESC").limit(10).count(:id),
      by_source: AuditLog.group(:source).count,
      by_level: AuditLog.joins("LEFT JOIN (#{LEVEL_SUBQUERY}) AS levels ON levels.action = audit_logs.action")
                        .group("levels.level").count,
      failed_logins_today: AuditLog.where(action: "login_failed", created_at: Date.current.beginning_of_day..Date.current.end_of_day).count,
      suspicious_activity_count: detect_suspicious_activity_count
    }
  end

  def detailed_stats
    basic_stats.merge({
      top_users: AuditLog.joins(:user).group("users.email").order("count_id DESC").limit(5).count(:id),
      top_accounts: AuditLog.joins(:account).group("accounts.name").order("count_id DESC").limit(5).count(:id),
      hourly_distribution: AuditLog.where(created_at: 24.hours.ago..Time.current)
                                   .group("EXTRACT(hour FROM created_at)")
                                   .count,
      error_trend: AuditLog.where(action: ERROR_ACTIONS, created_at: 7.days.ago..Time.current)
                           .group_by_day(:created_at).count
    })
  end

  # =============================================================================
  # SECURITY SUMMARY
  # =============================================================================

  def security_summary(start_time:)
    logs = AuditLog.where("created_at >= ?", start_time)

    {
      totalEvents: logs.count,
      securityEvents: logs.where(action: SECURITY_ACTIONS).count,
      failedEvents: logs.where(action: FAILED_ACTIONS).count,
      highRiskEvents: logs.where(action: HIGH_RISK_ACTIONS).count,
      suspiciousEvents: logs.where(action: "suspicious_activity").count,
      uniqueUsers: logs.distinct.count(:user_id),
      uniqueIps: logs.where.not(ip_address: nil).distinct.count(:ip_address),
      bySeverity: logs.group(:severity).count,
      byRiskLevel: logs.group(:risk_level).count,
      hourlyDistribution: logs.group_by_hour(:created_at, range: start_time..Time.current).count
    }
  end

  # =============================================================================
  # COMPLIANCE SUMMARY
  # =============================================================================

  def compliance_summary(start_time:)
    logs = AuditLog.where("created_at >= ?", start_time)

    base_data = {
      totalEvents: logs.count,
      gdprEvents: logs.where(action: GDPR_ACTIONS).count,
      dataAccessEvents: logs.where(action: DATA_ACCESS_ACTIONS).count,
      consentEvents: logs.where(action: CONSENT_ACTIONS).count,
      retentionEvents: logs.where(action: RETENTION_ACTIONS).count,
      dataExportRequests: logs.where(action: "data_export_requested").count,
      dataDeletionRequests: logs.where(action: "data_deletion_requested").count,
      consentChanges: logs.where(action: CONSENT_ACTIONS).count,
      byComplianceType: {
        gdpr: logs.where(action: GDPR_ACTIONS).count,
        data_access: logs.where(action: DATA_ACCESS_ACTIONS).count,
        consent: logs.where(action: CONSENT_ACTIONS).count,
        retention: logs.where(action: RETENTION_ACTIONS).count
      },
      weeklyTrend: logs.where(action: GDPR_ACTIONS + DATA_ACCESS_ACTIONS)
                       .group_by_day(:created_at, range: start_time..Time.current)
                       .count,
      uniqueDataSubjects: logs.where(action: GDPR_ACTIONS).distinct.count(:user_id)
    }

    # Add pending requests if models exist
    begin
      base_data[:pendingRequests] = {
        exports: DataManagement::ExportRequest.where(status: "pending").count,
        deletions: DataManagement::DeletionRequest.where(status: "pending").count
      }
    rescue NameError
      base_data[:pendingRequests] = { exports: 0, deletions: 0 }
    end

    base_data
  end

  # =============================================================================
  # ACTIVITY TIMELINE
  # =============================================================================

  def activity_timeline(start_time:, granularity:)
    logs = AuditLog.where("created_at >= ?", start_time)

    timeline_data = timeline_by_granularity(logs, start_time, granularity)
    action_timeline = logs.group(:action).group_by_hour(:created_at, range: start_time..Time.current).count
    user_activity = logs.where.not(user_id: nil).group_by_hour(:created_at, range: start_time..Time.current).distinct.count(:user_id)

    peak_hour = timeline_data.max_by { |_, count| count }&.first
    lowest_hour = timeline_data.min_by { |_, count| count }&.first

    {
      timeline: timeline_data,
      actionTimeline: action_timeline,
      userActivity: user_activity,
      summary: {
        totalEvents: logs.count,
        averagePerHour: (logs.count.to_f / [ (Time.current - start_time) / 1.hour, 1 ].max).round(2),
        peakActivity: { time: peak_hour&.iso8601, count: timeline_data[peak_hour] || 0 },
        lowestActivity: { time: lowest_hour&.iso8601, count: timeline_data[lowest_hour] || 0 },
        uniqueUsers: logs.distinct.count(:user_id),
        uniqueActions: logs.distinct.count(:action)
      },
      topActions: logs.group(:action).order("count_id DESC").limit(10).count(:id),
      topUsers: logs.joins(:user).group("users.email").order("count_id DESC").limit(5).count(:id)
    }
  end

  # =============================================================================
  # RISK ANALYSIS
  # =============================================================================

  def risk_analysis(start_time:)
    logs = AuditLog.where("created_at >= ?", start_time)

    high_risk_count = logs.where(action: HIGH_RISK_ACTIONS).count
    medium_risk_count = logs.where(action: MEDIUM_RISK_ACTIONS).count
    low_risk_count = logs.where(action: LOW_RISK_ACTIONS).count

    suspicious_ips = logs.where(action: %w[login_failed unauthorized_access])
                         .group(:ip_address)
                         .having("count(*) > 5")
                         .count

    high_risk_users = logs.where(action: HIGH_RISK_ACTIONS + MEDIUM_RISK_ACTIONS)
                          .where.not(user_id: nil)
                          .group(:user_id)
                          .having("count(*) > 3")
                          .count

    off_hours_activity = logs.where("EXTRACT(hour FROM created_at) < 6 OR EXTRACT(hour FROM created_at) > 22").count

    unique_ips_per_user = logs.where.not(user_id: nil, ip_address: nil)
                              .group(:user_id)
                              .distinct
                              .count(:ip_address)
    multi_ip_users = unique_ips_per_user.count { |_, count| count > 5 }

    risk_score = calculate_overall_risk_score(
      high_risk_count: high_risk_count,
      medium_risk_count: medium_risk_count,
      suspicious_ips_count: suspicious_ips.count,
      off_hours_percentage: logs.count > 0 ? (off_hours_activity.to_f / logs.count * 100) : 0
    )

    {
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
      topThreats: logs.where(action: HIGH_RISK_ACTIONS)
                      .group(:action)
                      .order("count_id DESC")
                      .limit(5)
                      .count(:id),
      suspiciousIpDetails: suspicious_ips.first(10).to_h,
      riskTrend: logs.where(action: HIGH_RISK_ACTIONS + MEDIUM_RISK_ACTIONS)
                     .group_by_day(:created_at, range: start_time..Time.current)
                     .count,
      recommendations: generate_risk_recommendations(
        high_risk_count: high_risk_count,
        suspicious_ips_count: suspicious_ips.count,
        off_hours_activity: off_hours_activity
      )
    }
  end

  # =============================================================================
  # DATA FORMATTING
  # =============================================================================

  def format_log(log)
    {
      id: log.id,
      action: log.action,
      resource_type: log.resource_type,
      resource_id: log.resource_id,
      source: log.source || "system",
      ip_address: log.ip_address,
      user_agent: log.user_agent,
      user: log.user ? { id: log.user.id, email: log.user.email, full_name: log.user.full_name } : nil,
      account: log.account ? { id: log.account.id, name: log.account.name } : nil,
      old_values: log.old_values || {},
      new_values: log.new_values || {},
      metadata: log.metadata || {},
      status: determine_log_status(log),
      level: determine_log_level(log.action),
      message: format_log_message(log),
      changes_summary: log.changes_summary,
      created_at: log.created_at.iso8601
    }
  end

  def format_detailed_log(log)
    format_log(log).merge({
      user_agent_parsed: parse_user_agent(log.user_agent),
      related_logs: find_related_logs(log),
      risk_score: calculate_risk_score(log)
    })
  end

  # =============================================================================
  # EXPORT
  # =============================================================================

  def generate_export_data(logs, format)
    case format.downcase
    when "csv"
      generate_csv_export(logs)
    when "json"
      logs.map { |log| format_log(log) }.to_json
    else
      raise ArgumentError, "Unsupported export format: #{format}"
    end
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

  private

  def timeline_by_granularity(logs, start_time, granularity)
    case granularity
    when "minute"
      logs.group_by_minute(:created_at, range: start_time..Time.current).count
    when "day"
      logs.group_by_day(:created_at, range: start_time..Time.current).count
    else
      logs.group_by_hour(:created_at, range: start_time..Time.current).count
    end
  end

  def detect_suspicious_activity_count
    suspicious_count = 0

    suspicious_count += AuditLog.where(action: "login_failed", created_at: 24.hours.ago..Time.current)
                                .group(:ip_address)
                                .having("count(*) > 10")
                                .count
                                .size

    suspicious_count += AuditLog.where(action: ADMIN_ACTIONS, created_at: 24.hours.ago..Time.current)
                                .select { |log| log.created_at.hour < 6 || log.created_at.hour > 22 }
                                .count

    suspicious_count
  end

  def determine_log_status(log)
    case log.action
    when /failed|error|suspend|block|lock/i then "error"
    when /warning|timeout|retry/i then "warning"
    else "success"
    end
  end

  def determine_log_level(action)
    case action
    when /error|failed|suspend|lock|block/i then "error"
    when /warning|timeout|retry/i then "warning"
    when /create|update|delete|login|logout/i then "info"
    else "debug"
    end
  end

  def format_log_message(log)
    case log.action
    when "user_login" then "User #{log.user&.email} logged in from #{log.ip_address}"
    when "user_logout" then "User #{log.user&.email} logged out"
    when "user_registration" then "New user registered: #{log.user&.email}"
    when "subscription_created" then "New subscription created for #{log.account&.name}"
    when "payment_completed" then "Payment completed for #{log.account&.name}"
    when "payment_failed" then "Payment failed for #{log.account&.name}"
    when "login_failed" then "Failed login attempt for #{log.metadata&.dig('email')} from #{log.ip_address}"
    when "admin_settings_update" then "Admin settings updated by #{log.user&.email}"
    when "impersonation_start" then "#{log.user&.email} started impersonating user"
    when "impersonation_end" then "#{log.user&.email} ended impersonation session"
    else log.action.humanize
    end
  end

  def parse_user_agent(user_agent)
    return nil unless user_agent

    {
      raw: user_agent,
      browser: extract_browser(user_agent),
      platform: extract_platform(user_agent),
      device: extract_device(user_agent)
    }
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

  def find_related_logs(log)
    time_window = 1.hour
    related = AuditLog.where(created_at: (log.created_at - time_window)..(log.created_at + time_window))
                      .where.not(id: log.id)

    related = related.where(user: log.user) if log.user
    related = related.or(AuditLog.where(ip_address: log.ip_address)) if log.ip_address
    related = related.or(AuditLog.where(resource_type: log.resource_type, resource_id: log.resource_id)) if log.resource_type

    related.limit(10).map { |l| format_log(l) }
  end

  def calculate_risk_score(log)
    score = 0

    score += case log.action
    when /failed|error/i then 3
    when /login|logout/i then 1
    when /create|delete/i then 2
    when /admin|impersonation/i then 4
    else 1
    end

    hour = log.created_at.hour
    score += 2 if hour < 6 || hour > 22

    if log.ip_address
      recent_from_ip = AuditLog.where(ip_address: log.ip_address, created_at: log.created_at - 1.hour..log.created_at).count
      score += [ recent_from_ip / 5, 5 ].min
    end

    [ score, 10 ].min
  end

  def calculate_overall_risk_score(high_risk_count:, medium_risk_count:, suspicious_ips_count:, off_hours_percentage:)
    score = 0
    score += [ high_risk_count * 4, 40 ].min
    score += [ medium_risk_count * 1, 25 ].min
    score += [ suspicious_ips_count * 5, 20 ].min
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

  def generate_csv_export(logs)
    require "csv"

    CSV.generate(headers: true) do |csv|
      csv << [ "ID", "Action", "User Email", "Account", "Resource Type", "Resource ID",
              "Source", "IP Address", "Status", "Created At", "Metadata" ]

      logs.each do |log|
        csv << [
          log.id, log.action, log.user&.email, log.account&.name, log.resource_type,
          log.resource_id, log.source, log.ip_address, determine_log_status(log),
          log.created_at.iso8601, log.metadata.to_json
        ]
      end
    end
  end
end
