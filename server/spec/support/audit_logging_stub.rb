# frozen_string_literal: true

# Stub for AuditLoggingService in test environment
# This stub actually creates AuditLog records so tests can verify audit behavior
class AuditLoggingService
  include Singleton

  def log(action:, resource: nil, user: nil, account: nil, **options)
    Rails.logger.info "AUDIT LOG: #{action} by #{user&.email || 'unknown'} on #{resource&.class&.name || 'unknown'}"

    # Actually create the audit log record for tests that need to verify audit behavior
    AuditLog.log_action(
      action: action.to_s,
      resource: resource,
      user: user,
      account: account || user&.account || (resource.respond_to?(:account) ? resource.account : nil) || Account.first,
      ip_address: options[:ip_address],
      user_agent: options[:user_agent],
      source: options[:source] || 'api',
      metadata: options[:metadata] || {}
    )
  rescue => e
    Rails.logger.error "Test audit logging failed: #{e.message}"
    nil
  end

  def log_authentication(action:, user: nil, request: nil, account: nil, **options)
    Rails.logger.info "AUTH AUDIT: #{action} for #{user&.email || 'unknown'}"
    log(action: action, resource: user, user: user, account: account || user&.account, **options)
  end

  def log_admin_action(action:, resource: nil, user: nil, account: nil, **options)
    Rails.logger.info "ADMIN AUDIT: #{action} by #{user&.email || 'unknown'}"
    log(action: action, resource: resource, user: user, account: account, source: 'admin_panel', **options)
  end

  def log_security_event(action:, resource: nil, user: nil, account: nil, threat_level: 'medium', **options)
    Rails.logger.info "SECURITY AUDIT: #{action} (#{threat_level}) by #{user&.email || 'unknown'}"
    log(action: action, resource: resource, user: user, account: account, metadata: { threat_level: threat_level }, **options)
  end

  def log_data_access(action:, resource: nil, user: nil, account: nil, data_classification: 'internal', **options)
    Rails.logger.info "DATA ACCESS: #{action} (#{data_classification}) by #{user&.email || 'unknown'}"
    log(action: action, resource: resource, user: user, account: account, metadata: { data_classification: data_classification }, **options)
  end

  def log_compliance_event(action:, resource: nil, user: nil, account: nil, regulation:, **options)
    Rails.logger.info "COMPLIANCE: #{action} (#{regulation}) by #{user&.email || 'unknown'}"
    log(action: action, resource: resource, user: user, account: account, metadata: { regulation: regulation }, **options)
  end
end if Rails.env.test?
