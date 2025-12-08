# frozen_string_literal: true

class AuditLoggingService
  include Singleton

  attr_accessor :context_storage

  def initialize
    @context_storage = {}
    @rate_limiter = {}
    @alert_thresholds = {
      failed_logins_per_hour: 10,
      admin_actions_off_hours: 5,
      high_risk_events_per_hour: 20,
      suspicious_activity_threshold: 15
    }
  end

  # Main logging entry point with context enrichment
  def log(action:, resource:, user: nil, account: nil, **options)
    # Extract context from current request/session
    enriched_options = enrich_context(options)

    # Add automatic account detection if not provided
    account ||= detect_account(user, resource)

    # Rate limiting check
    return if should_rate_limit?(action, user, enriched_options[:ip_address])
    
    # Create the audit log entry
    audit_log = AuditLog.log_action(
      action: action,
      resource: resource,
      user: user,
      account: account,
      **enriched_options
    )
    
    # Trigger real-time monitoring
    monitor_event(audit_log) if should_monitor?(audit_log)
    
    # Queue background analysis
    queue_analysis(audit_log) if requires_analysis?(audit_log)
    
    audit_log
  rescue => e
    Rails.logger.error "Audit logging failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    # Re-raise in test environment to surface audit logging errors
    raise if Rails.env.test?

    # Attempt to log the error itself
    log_system_error(e, action, resource, user, account)
    nil
  end

  # Specialized logging methods
  def log_authentication(action:, user: nil, request: nil, **options)
    context = extract_request_context(request) if request
    severity = action.include?('failed') ? 'high' : 'low'
    
    log(
      action: action,
      resource: user || create_dummy_user_resource(options[:email]),
      user: user,
      account: user&.account,
      severity: severity,
      **context,
      **options
    )
  end

  def log_data_access(action:, resource:, user:, data_classification: 'internal', **options)
    severity = case data_classification.to_s.downcase
               when 'public' then 'low'
               when 'internal' then 'medium'
               when 'confidential' then 'high'
               when 'restricted' then 'critical'
               else 'medium'
               end

    log(
      action: action,
      resource: resource,
      user: user,
      severity: severity,
      metadata: (options[:metadata] || {}).merge(
        data_classification: data_classification,
        access_type: options[:access_type] || 'read'
      ),
      **options
    )
  end

  def log_admin_action(action:, resource:, user:, **options)
    log(
      action: action,
      resource: resource,
      user: user,
      source: 'admin_panel',
      severity: 'high',
      metadata: (options[:metadata] || {}).merge(
        admin_action: true,
        requires_review: true
      ),
      **options
    )
  end

  def log_compliance_event(action:, resource:, user: nil, regulation:, **options)
    AuditLog.log_compliance_event(
      action: action,
      resource: resource,
      user: user,
      account: user&.account || detect_account(user, resource),
      regulation: regulation,
      compliance_type: options[:compliance_type],
      retention_period: options[:retention_period] || '7_years',
      **options
    )
  end

  def log_security_event(action:, resource:, user: nil, threat_level: 'medium', **options)
    AuditLog.log_security_event(
      action: action,
      resource: resource,
      user: user,
      account: user&.account || detect_account(user, resource),
      metadata: (options[:metadata] || {}).merge(
        threat_level: threat_level,
        security_event: true,
        requires_investigation: threat_level.in?(['high', 'critical'])
      ),
      **options
    )
  end

  def log_system_event(action:, severity: 'medium', **options)
    AuditLog.log_system_event(
      action: action,
      severity: severity,
      metadata: (options[:metadata] || {}).merge(
        system_event: true,
        automated: options[:automated] != false
      ),
      **options
    )
  end

  # Context management
  def with_context(context_hash)
    old_context = @context_storage[Thread.current.object_id] || {}
    @context_storage[Thread.current.object_id] = old_context.merge(context_hash)
    
    yield
  ensure
    @context_storage[Thread.current.object_id] = old_context
  end

  def current_context
    @context_storage[Thread.current.object_id] || {}
  end

  def set_request_context(request)
    return unless request

    context = extract_request_context(request)
    @context_storage[Thread.current.object_id] = context
  end

  def clear_context
    @context_storage.delete(Thread.current.object_id)
  end

  # Analytics and reporting
  def generate_security_report(time_range = 24.hours.ago..Time.current)
    AuditLog.security_summary(time_range).merge(
      recent_alerts: recent_security_alerts(time_range),
      risk_assessment: assess_current_risk_level,
      recommendations: generate_security_recommendations
    )
  end

  def generate_compliance_report(regulation = nil, time_range = 30.days.ago..Time.current)
    base_summary = AuditLog.compliance_summary(time_range)
    
    if regulation
      base_summary.merge(
        regulation_specific: compliance_events_for_regulation(regulation, time_range),
        compliance_score: calculate_compliance_score(regulation, time_range)
      )
    else
      base_summary
    end
  end

  def activity_summary(user: nil, account: nil, time_range: 7.days.ago..Time.current)
    scope = AuditLog.where(created_at: time_range)
    scope = scope.where(user: user) if user
    scope = scope.where(account: account) if account

    {
      total_activities: scope.count,
      by_action: scope.group(:action).count.sort_by(&:last).reverse.first(10),
      by_source: scope.group(:source).count,
      by_day: scope.by_day.count,
      suspicious_activities: scope.suspicious.count,
      recent_activities: scope.recent(20).includes(:user, :account).map(&:summary)
    }
  end

  # Real-time monitoring
  def setup_monitoring
    @monitoring_enabled = true
    
    # Start background thread for real-time analysis
    Thread.new do
      loop do
        perform_real_time_analysis
        sleep 30 # Check every 30 seconds
      end
    rescue => e
      Rails.logger.error "Audit monitoring thread error: #{e.message}"
      retry
    end if Rails.env.production?
  end

  private

  def enrich_context(options)
    base_context = current_context
    
    enriched = base_context.merge(options).merge(
      timestamp: Time.current.to_f,
      request_id: generate_request_id,
      correlation_id: options[:correlation_id] || base_context[:correlation_id] || SecureRandom.uuid
    )

    # Add geo-location if IP is available
    if enriched[:ip_address] && !enriched[:geo_location]
      enriched[:geo_location] = lookup_geo_location(enriched[:ip_address])
    end

    # Add device fingerprinting if user agent is available
    if enriched[:user_agent] && !enriched[:device_fingerprint]
      enriched[:device_fingerprint] = generate_device_fingerprint(enriched[:user_agent])
    end

    enriched
  end

  def extract_request_context(request)
    return {} unless request

    {
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      request_id: request.request_id,
      session_id: request.session.id,
      referer: request.referer,
      request_method: request.method,
      request_path: request.path,
      request_params: sanitize_params(request.params)
    }
  end

  def detect_account(user, resource)
    return user.account if user&.account
    return resource.account if resource.respond_to?(:account)
    return resource.user.account if resource.respond_to?(:user) && resource.user&.account
    
    # Fallback to system account
    Account.find_by(name: 'System') || Account.first
  end

  def should_rate_limit?(action, user, ip_address)
    # Disable rate limiting in test environment
    return false if Rails.env.test?

    # Implement rate limiting logic
    key = "audit_log:#{action}:#{user&.id || ip_address}"

    current_count = Rails.cache.read(key) || 0
    
    # Different limits for different actions
    limit = case action.to_s
            when /failed|error/ then 20  # Allow more failed action logs
            when /admin|delete/ then 5   # Stricter limits for admin actions
            else 50                      # General limit
            end

    if current_count >= limit
      Rails.logger.warn "Rate limiting audit log: #{action} for #{user&.email || ip_address}"
      return true
    end

    Rails.cache.write(key, current_count + 1, expires_in: 1.hour)
    false
  end

  def should_monitor?(audit_log)
    audit_log.is_suspicious? || 
    audit_log.is_security_related?
  end

  def requires_analysis?(audit_log)
    audit_log.is_suspicious? || 
    audit_log.action.in?(AuditLog.admin_actions)
  end

  def monitor_event(audit_log)
    # Broadcast to real-time monitoring systems
    ActionCable.server.broadcast("audit_monitoring", {
      type: 'security_event',
      data: {
        id: audit_log.id,
        action: audit_log.action,
        user: audit_log.user&.email,
        account: audit_log.account&.name,
        timestamp: audit_log.created_at,
        summary: audit_log.summary
      }
    })

    # Check for alert conditions
    check_alert_conditions(audit_log)
  end

  def queue_analysis(audit_log)
    # Queue background job for detailed analysis
    # Note: AuditLogAnalysisJob should be moved to worker service if needed
    # WorkerJobService.enqueue_audit_analysis(audit_log.id)
  end

  def check_alert_conditions(audit_log)
    current_hour = 1.hour.ago..Time.current

    case audit_log.action
    when /login_failed/
      failed_count = AuditLog.where(action: 'login_failed', created_at: current_hour).count
      send_alert('High failed login activity', "#{failed_count} failed logins in the last hour") if failed_count > @alert_thresholds[:failed_logins_per_hour]
      
    when *AuditLog.admin_actions
      if off_hours?
        admin_count = AuditLog.admin_events.where(created_at: current_hour).count
        send_alert('Off-hours admin activity', "#{admin_count} admin actions during off-hours") if admin_count > @alert_thresholds[:admin_actions_off_hours]
      end
      
    when *AuditLog.suspicious_actions
      suspicious_count = AuditLog.suspicious.where(created_at: current_hour).count
      send_alert('Suspicious activity spike', "#{suspicious_count} suspicious events in the last hour") if suspicious_count > @alert_thresholds[:suspicious_activity_threshold]
    end
  end

  def send_alert(title, message)
    Rails.logger.warn "SECURITY ALERT: #{title} - #{message}"
    
    # Send to security notification channels
    SecurityAlertService.send_alert(
      title: title,
      message: message,
      severity: 'high',
      timestamp: Time.current
    )
  end

  def perform_real_time_analysis
    return unless @monitoring_enabled

    # Analyze recent suspicious events since high_risk scope doesn't work without risk_level column
    recent_events = AuditLog.suspicious.where(created_at: 5.minutes.ago..Time.current)
    
    if recent_events.count > 10
      send_alert('Suspicious event spike', "#{recent_events.count} suspicious events in last 5 minutes")
    end

    # Check for anomalous patterns
    detect_anomalies
  end

  def detect_anomalies
    # Pattern detection logic
    current_hour_actions = AuditLog.where(created_at: 1.hour.ago..Time.current).group(:action).count
    typical_hour_actions = AuditLog.where(created_at: 7.days.ago..6.days.ago).group(:action).count

    current_hour_actions.each do |action, count|
      typical_count = typical_hour_actions[action] || 0
      
      if count > typical_count * 3 && count > 20  # 3x increase and significant volume
        send_alert('Anomalous activity pattern', "Action '#{action}' is #{count / typical_count.to_f}x higher than typical")
      end
    end
  end

  def recent_security_alerts(time_range)
    AuditLog.security_events
            .where(created_at: time_range)
            .recent(10)
            .map(&:summary)
  end

  def assess_current_risk_level
    recent_logs = AuditLog.where(created_at: 1.hour.ago..Time.current)
    
    risk_indicators = {
      failed_logins: recent_logs.where(action: 'login_failed').count,
      admin_actions: recent_logs.admin_events.count,
      suspicious_events: recent_logs.suspicious.count
    }

    total_risk_score = risk_indicators.values.sum
    
    case total_risk_score
    when 0..5 then 'low'
    when 6..15 then 'medium'
    when 16..30 then 'high'
    else 'critical'
    end
  end

  def generate_security_recommendations
    recommendations = []
    
    recent_failed_logins = AuditLog.where(action: 'login_failed', created_at: 24.hours.ago..Time.current).count
    
    if recent_failed_logins > 50
      recommendations << "Consider implementing additional rate limiting on login attempts"
    end
    
    if AuditLog.admin_events.where(created_at: 24.hours.ago..Time.current).count > 20
      recommendations << "Review recent admin actions for unauthorized access"
    end
    
    recommendations
  end

  def compliance_events_for_regulation(regulation, time_range)
    AuditLog.compliance_events
            .where(created_at: time_range)
            .where("metadata->>'regulation' = ?", regulation)
            .group(:action)
            .count
  end

  def calculate_compliance_score(regulation, time_range)
    # Simplified compliance scoring
    required_events = %w[security_scan data_export gdpr_request ccpa_request]
    completed_events = AuditLog.compliance_events
                             .where(created_at: time_range)
                             .where("metadata->>'regulation' = ?", regulation)
                             .where(action: required_events)
                             .group(:action)
                             .count

    (completed_events.keys.length.to_f / required_events.length * 100).round(1)
  end

  def off_hours?
    current_hour = Time.current.hour
    current_hour < 6 || current_hour > 22 || Time.current.weekend?
  end

  def lookup_geo_location(ip_address)
    # Simple geo-location lookup - in production, use a proper service
    return nil if ip_address.blank? || ip_address.in?(['127.0.0.1', '::1'])
    
    {
      ip: ip_address,
      city: 'Unknown',
      country: 'Unknown',
      provider: 'Unknown'
    }
  end

  def generate_device_fingerprint(user_agent)
    return nil if user_agent.blank?
    
    {
      user_agent: user_agent,
      device_type: extract_device_type(user_agent),
      browser: extract_browser(user_agent),
      platform: extract_platform(user_agent)
    }
  end

  def extract_device_type(user_agent)
    case user_agent
    when /Mobile|iPhone|Android/ then 'mobile'
    when /Tablet|iPad/ then 'tablet'
    else 'desktop'
    end
  end

  def extract_browser(user_agent)
    case user_agent
    when /Chrome/ then 'Chrome'
    when /Firefox/ then 'Firefox'
    when /Safari/ then 'Safari'
    when /Edge/ then 'Edge'
    else 'Unknown'
    end
  end

  def extract_platform(user_agent)
    case user_agent
    when /Windows/ then 'Windows'
    when /Macintosh|Mac OS/ then 'macOS'
    when /Linux/ then 'Linux'
    when /iPhone|iPad/ then 'iOS'
    when /Android/ then 'Android'
    else 'Unknown'
    end
  end

  def create_dummy_user_resource(email)
    OpenStruct.new(
      class: OpenStruct.new(name: 'User'),
      id: email || 'unknown_user'
    )
  end

  def sanitize_params(params)
    # Remove sensitive parameters
    params.except('password', 'password_confirmation', 'token', 'api_key', 'secret')
          .to_unsafe_h
          .deep_stringify_keys
  end

  def generate_request_id
    SecureRandom.hex(8)
  end

  def log_system_error(error, action, resource, user, account)
    begin
      AuditLog.create!(
        action: 'audit_logging_error',
        resource_type: 'AuditLog',
        resource_id: 'error',
        user: user,
        account: account || Account.first,
        source: 'system',
        metadata: {
          original_action: action,
          error_message: error.message,
          error_class: error.class.name,
          backtrace: error.backtrace&.first(5)
        }
      )
    rescue => e
      Rails.logger.error "Failed to log audit logging error: #{e.message}"
    end
  end
end