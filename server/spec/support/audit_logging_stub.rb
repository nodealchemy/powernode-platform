# frozen_string_literal: true

# Simple stub for AuditLoggingService in test environment
class AuditLoggingService
  def self.instance
    @instance ||= new
  end

  def log(action:, resource: nil, user: nil, account: nil, **options)
    Rails.logger.info "AUDIT LOG: #{action} by #{user&.email || 'unknown'} on #{resource&.class&.name || 'unknown'}"
    true
  end

  def log_authentication(action:, user: nil, request: nil, account: nil, **options)
    Rails.logger.info "AUTH AUDIT: #{action} for #{user&.email || 'unknown'}"
    true
  end

  def log_admin_action(action:, resource: nil, user: nil, account: nil, **options)
    Rails.logger.info "ADMIN AUDIT: #{action} by #{user&.email || 'unknown'}"
    true
  end

  def log_security_event(action:, resource: nil, user: nil, account: nil, threat_level: 'medium', **options)
    Rails.logger.info "SECURITY AUDIT: #{action} (#{threat_level}) by #{user&.email || 'unknown'}"
    true
  end

  def log_data_access(action:, resource: nil, user: nil, account: nil, data_classification: 'internal', **options)
    Rails.logger.info "DATA ACCESS: #{action} (#{data_classification}) by #{user&.email || 'unknown'}"
    true
  end

  def log_compliance_event(action:, resource: nil, user: nil, account: nil, regulation:, **options)
    Rails.logger.info "COMPLIANCE: #{action} (#{regulation}) by #{user&.email || 'unknown'}"
    true
  end
end if Rails.env.test?