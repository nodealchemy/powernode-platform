# frozen_string_literal: true

class AuditLog < ApplicationRecord
  # Associations
  belongs_to :user, optional: true
  belongs_to :account

  # Enhanced validations with comprehensive action types
  validates :action, presence: true, inclusion: {
    in: %w[
      create update delete created updated deleted login logout payment subscription_change role_change
      user_created user_updated user_deleted
      create_plan update_plan delete_plan toggle_plan_status
      suspend_account activate_account admin_settings_update
      impersonation_started impersonation_ended
      user_login user_logout user_registration login_failed password_reset
      subscription_created subscription_updated subscription_cancelled subscription_paused
      payment_completed payment_failed payment_refunded payment_disputed
      invoice_generated invoice_sent invoice_paid invoice_overdue
      webhook_received webhook_failed webhook_retry
      api_key_created api_key_revoked api_access_denied
      data_export data_import security_scan compliance_check
      system_maintenance system_backup system_restore
      account_locked account_unlocked account_switch password_changed email_verified
      two_factor_enabled two_factor_disabled backup_codes_generated
      plan_upgraded plan_downgraded billing_updated
      integration_connected integration_disconnected
      notification_sent notification_failed
      audit_log_cleanup audit_log_export
      security_alert fraud_detection suspicious_activity
      gdpr_request ccpa_request data_deletion data_anonymization
      test_email_sent test_email_failed email_sent email_failed
      email_settings_refreshed notification_sent notification_failed
      api_request api_request_failed
      ai_execution_cost ai_daily_cost_summary ai_analytics.usage_recorded ai_analytics.update
      ai_conversations.update ai_conversations.create ai_conversations.destroy
      ai_messages.update ai_messages.create ai_messages.destroy
      ai_agents.index ai_agents.create ai_agents.update ai_agents.destroy
      ai_agents.execute ai_agents.clone ai_agents.pause ai_agents.resume
      ai_agents.archive ai_agents.stats ai_agents.analytics
      ai.agents.read ai.agents.create ai.agents.update ai.agents.delete
      ai.agents.execute ai.agents.clone ai.agents.pause ai.agents.resume
      ai.agents.archive ai.agents.test ai.agents.validate
      audit_logging_error
      ai_conversation_channel_subscribed ai_conversation_channel_unsubscribed
      ai_conversation_message_sent ai_conversation_message_failed
      ai_messages.create ai_messages.update ai_messages.destroy ai_messages.edit_content
      ai_analytics.usage_recorded ai_analytics.report_generated
      ai_provider_credential_created ai_provider_credential_updated ai_provider_credential_deleted
      ai_provider_credential_tested ai_provider_credential_made_default ai_provider_credential_decrypted
      ai_provider_credential_encryption_rotated
      ai.providers.list ai.providers.view ai.providers.create ai.providers.update ai.providers.delete
      ai.providers.test_connection ai.providers.sync_models ai.providers.credential.create
      ai.providers.credential.update ai.providers.credential.delete ai.providers.credential.test
      ai.providers.read ai.providers.test ai.providers.sync ai.providers.configure
      ai.credentials.read ai.credentials.create ai.credentials.update ai.credentials.delete ai.credentials.test
      ai.workflows.list ai.workflows.view ai.workflows.create ai.workflows.update ai.workflows.delete
      ai.workflows.execute ai.workflows.pause ai.workflows.resume ai.workflows.duplicate
      ai.workflows.read ai.workflows.export ai.workflows.validate ai.workflows.clone
      ai.executions.read ai.executions.create ai.executions.update ai.executions.cancel ai.executions.retry
      ai.workflow_runs.read ai.workflow_runs.create ai.workflow_runs.update ai.workflow_runs.cancel
      ai.workflow_runs.retry ai.workflow_runs.pause ai.workflow_runs.resume
      ai.agents.execution.cancel ai.agents.execution.delete ai.agents.execution.retry
      ai.providers.sync_models ai.providers.credential.make_default ai.providers.credential.rotate
      ai.analytics.cost_analysis ai.analytics.dashboard ai.analytics.export ai.analytics.insights
      ai.analytics.report.cancel ai.analytics.report.create ai.analytics.report.download
      ai.marketplace.installation_deleted ai.marketplace.template_created ai.marketplace.template_created_from_workflow
      ai.marketplace.template_deleted ai.marketplace.template_installed ai.marketplace.template_published
      ai.marketplace.template_rated ai.marketplace.template_updated ai.marketplace.workflow_published
      ai.monitoring.alerts_check ai.monitoring.alerts_view ai.monitoring.circuit_breaker.close
      ai.monitoring.circuit_breaker.open ai.monitoring.circuit_breaker.reset ai.monitoring.circuit_breakers.category_reset
      ai.monitoring.circuit_breakers.reset_all ai.monitoring.dashboard ai.monitoring.health_check
      ai.monitoring.start ai.monitoring.stop
      ai.workflow_git_triggers.create ai.workflow_git_triggers.update ai.workflow_git_triggers.delete
      ai.conversations.create ai.conversations.update ai.conversations.delete ai.conversations.archive
      ai.conversations.complete ai.conversations.duplicate ai.conversations.export ai.conversations.pause
      ai.conversations.resume ai.conversations.unarchive ai.conversations.message.send
      ai.messages.rate ai.messages.regenerate
      ai.validation_statistics.read ai.validation_statistics.health_distribution ai.validation_statistics.common_issues
      ai.workflows.convert_to_template ai.workflows.convert_to_workflow ai.workflows.create_from_template ai.workflows.import
      ai.workflows.run.cancel ai.workflows.run.delete ai.workflows.run.download ai.workflows.run.pause
      ai.workflows.run.resume ai.workflows.run.retry ai.workflows.runs.bulk_delete
      ai.workflow_validations.auto_fix ai.workflow_validations.create
      ai.workflow_validations.read ai.workflow_validations.auto_fix_single ai.workflow_validations.preview_fixes
      ai.providers.setup_defaults ai.providers.test_all
      app_created app_deleted app_updated app_published app_unpublished app_submitted_for_review
      app_feature_created app_feature_updated app_feature_deleted app_feature_duplicated
      app_feature_enabled_by_default app_feature_disabled_by_default
      app_plan_created app_plan_updated app_plan_deleted app_plan_activated app_plan_deactivated app_plans_reordered
      ci_cd.pipelines.list ci_cd.pipelines.read ci_cd.pipelines.create ci_cd.pipelines.update ci_cd.pipelines.delete
      ci_cd.pipelines.trigger ci_cd.pipelines.duplicate ci_cd.pipelines.export_yaml
      ci_cd.pipeline_runs.list ci_cd.pipeline_runs.read ci_cd.pipeline_runs.cancel ci_cd.pipeline_runs.retry ci_cd.pipeline_runs.logs
      ci_cd.providers.list ci_cd.providers.read ci_cd.providers.create ci_cd.providers.update ci_cd.providers.delete
      ci_cd.providers.test_connection ci_cd.providers.sync_repositories
      ci_cd.repositories.list ci_cd.repositories.read ci_cd.repositories.create ci_cd.repositories.update ci_cd.repositories.delete
      ci_cd.repositories.sync ci_cd.repositories.attach_pipeline ci_cd.repositories.detach_pipeline
      ci_cd.schedules.list ci_cd.schedules.read ci_cd.schedules.create ci_cd.schedules.update ci_cd.schedules.delete ci_cd.schedules.toggle
      ci_cd.prompt_templates.list ci_cd.prompt_templates.read ci_cd.prompt_templates.create ci_cd.prompt_templates.update
      ci_cd.prompt_templates.delete ci_cd.prompt_templates.duplicate ci_cd.prompt_templates.preview
      mcp.servers.read mcp.servers.create mcp.servers.update mcp.servers.delete
      mcp.servers.connect mcp.servers.disconnect mcp.servers.health_check mcp.servers.discover_tools mcp.servers.workflow_builder_read
      mcp.tools.read mcp.tools.execute
      mcp.executions.read mcp.executions.cancel
      mcp.oauth.authorize_initiated mcp.oauth.callback_success mcp.oauth.disconnect mcp.oauth.status_read mcp.oauth.token_refreshed
      marketplace_listing_resubmitted
      ai_agent_team.created ai_agent_team.updated ai_agent_team.deleted
      ai_agent_team.member_added ai_agent_team.member_removed
      ai_agent_team.execution_started ai_agent_team.execution_completed ai_agent_team.execution_failed
      invitation.created invitation.updated invitation.deleted
      invitation.resent invitation.cancelled invitation.accepted
      job_enqueue notification_send billing_operation webhook_process
      analytics_request report_generation health_check email_configuration
      error_occurred
      supply_chain.attestations.create supply_chain.attestations.delete supply_chain.attestations.read
      supply_chain.attestations.record_to_rekor supply_chain.attestations.sign supply_chain.attestations.update
      supply_chain.attestations.verify
      supply_chain.container_images.create supply_chain.container_images.delete supply_chain.container_images.evaluate_policies
      supply_chain.container_images.quarantine supply_chain.container_images.read supply_chain.container_images.scan
      supply_chain.container_images.update supply_chain.container_images.verify
      supply_chain.reports.create supply_chain.reports.delete supply_chain.reports.download
      supply_chain.reports.generate_attribution supply_chain.reports.generate_compliance supply_chain.reports.generate_sbom
      supply_chain.reports.generate_vendor_risk supply_chain.reports.generate_vulnerability supply_chain.reports.read
      supply_chain.reports.regenerate supply_chain.reports.update
      supply_chain.sboms.calculate_risk supply_chain.sboms.correlate_vulnerabilities supply_chain.sboms.create
      supply_chain.sboms.delete supply_chain.sboms.export supply_chain.sboms.read supply_chain.sboms.update
      supply_chain.vendors.assess supply_chain.vendors.create supply_chain.vendors.delete
      supply_chain.vendors.read supply_chain.vendors.reassess supply_chain.vendors.update
    ]
  }
  validates :resource_type, presence: true
  validates :resource_id, presence: true
  validates :source, presence: true, inclusion: {
    in: %w[web api system webhook admin_panel mobile_app integration automation scheduler worker security_system compliance_system]
  }
  validates :severity, inclusion: { in: %w[low medium high critical] }, allow_nil: false
  validates :risk_level, inclusion: { in: %w[low medium high critical] }, allow_nil: false

  # Note: old_values, new_values, and metadata are JSON columns in PostgreSQL
  # They have native JSON serialization, no need for explicit serialize calls

  # Enhanced scopes
  scope :for_resource, ->(type, id) { where(resource_type: type, resource_id: id) }
  scope :by_user, ->(user) { where(user: user) }
  scope :by_account, ->(account) { where(account: account) }
  scope :by_action, ->(action) { where(action: action) }
  scope :by_source, ->(source) { where(source: source) }
  scope :by_severity, ->(severity) { where(severity: severity) }
  scope :by_risk_level, ->(risk_level) { where(risk_level: risk_level) }
  scope :recent, -> { order(created_at: :desc) }
  scope :in_date_range, ->(start_date, end_date) { where(created_at: start_date..end_date) }

  # Security-focused scopes
  scope :security_events, -> { where(action: security_actions) }
  scope :failed_events, -> { where(action: failed_actions) }
  scope :admin_events, -> { where(action: admin_actions) }
  scope :high_risk, -> { where(risk_level: [ "high", "critical" ]) }
  scope :suspicious, -> { where(action: suspicious_actions) }
  scope :compliance_events, -> { where(action: compliance_actions) }

  # Time-based scopes
  scope :today, -> { where(created_at: Date.current.beginning_of_day..Date.current.end_of_day) }
  scope :this_week, -> { where(created_at: 1.week.ago.beginning_of_week..Time.current) }
  scope :this_month, -> { where(created_at: 1.month.ago.beginning_of_month..Time.current) }
  scope :last_hour, -> { where(created_at: 1.hour.ago..Time.current) }

  # Analytics scopes
  scope :by_hour, -> { group("DATE_TRUNC('hour', created_at)") }
  scope :by_day, -> { group("DATE_TRUNC('day', created_at)") }
  scope :by_week, -> { group("DATE_TRUNC('week', created_at)") }
  scope :by_month, -> { group("DATE_TRUNC('month', created_at)") }

  # Performance scopes
  scope :recent_activity, ->(limit = 100) { recent.limit(limit) }
  scope :batch_process, ->(batch_size = 1000) { limit(batch_size) }

  # Advanced filtering scopes for admin interface
  scope :apply_filters, ->(filters) {
    scope = all
    scope = scope.where(action: filters[:action]) if filters[:action].present?
    scope = scope.joins(:user).where(users: { email: filters[:user_email] }) if filters[:user_email].present?
    scope = scope.joins(:account).where(accounts: { name: filters[:account_name] }) if filters[:account_name].present?
    scope = scope.where(resource_type: filters[:resource_type]) if filters[:resource_type].present?
    scope = scope.where(source: filters[:source]) if filters[:source].present?
    scope = scope.where(ip_address: filters[:ip_address]) if filters[:ip_address].present?
    scope = scope.where(created_at: filters[:date_from].beginning_of_day..) if filters[:date_from].present?
    scope = scope.where(created_at: ..filters[:date_to].end_of_day) if filters[:date_to].present?
    scope
  }

  # Callbacks
  after_initialize :set_defaults
  before_create :apply_integrity_hash

  # Apply cryptographic integrity hash for immutable audit chain
  def apply_integrity_hash
    Audit::LogIntegrityService.apply_integrity(self)
  rescue StandardError => e
    Rails.logger.error "Failed to apply integrity hash to audit log: #{e.message}"
    # Don't block audit log creation if integrity service fails
  end

  # Class methods for action categorization
  def self.security_actions
    %w[
      login_failed password_reset account_locked account_unlocked
      two_factor_enabled two_factor_disabled backup_codes_generated
      api_access_denied security_alert fraud_detection suspicious_activity
      password_changed email_verified
    ]
  end

  def self.failed_actions
    %w[
      login_failed payment_failed webhook_failed notification_failed
      api_access_denied subscription_failed integration_failed
    ]
  end

  def self.admin_actions
    %w[
      admin_settings_update impersonation_started impersonation_ended
      suspend_account activate_account account_locked account_unlocked
      audit_log_cleanup system_maintenance system_backup system_restore
      security_scan compliance_check
    ]
  end

  def self.suspicious_actions
    %w[
      login_failed api_access_denied fraud_detection suspicious_activity
      multiple_login_attempts unusual_activity_pattern
      security_alert account_locked
    ]
  end

  def self.compliance_actions
    %w[
      gdpr_request ccpa_request data_deletion data_anonymization
      data_export data_import compliance_check audit_log_export
      security_scan privacy_settings_update
    ]
  end

  def self.log_action(action:, resource:, user: nil, account:, old_values: nil, new_values: nil, **options)
    # Calculate risk level and severity automatically
    risk_level = calculate_risk_level(action, options)
    severity = calculate_severity(action, options)

    create!(
      action: action,
      resource_type: resource.class.name,
      resource_id: resource.id,
      user: user,
      account: account,
      old_values: old_values,
      new_values: new_values,
      ip_address: options[:ip_address],
      user_agent: options[:user_agent],
      source: options[:source] || "web",
      severity: options[:severity] || severity,
      risk_level: options[:risk_level] || risk_level,
      metadata: (options[:metadata] || {}).merge(
        request_id: options[:request_id],
        session_id: options[:session_id],
        correlation_id: options[:correlation_id],
        geo_location: options[:geo_location],
        device_fingerprint: options[:device_fingerprint]
      ).compact
    )
  end

  # Enhanced logging methods
  def self.log_security_event(action:, resource:, user: nil, account:, **options)
    log_action(
      action: action,
      resource: resource,
      user: user,
      account: account,
      severity: "high",
      risk_level: "high",
      **options.merge(source: options[:source] || "security_system")
    )
  end

  def self.log_compliance_event(action:, resource:, user: nil, account:, **options)
    log_action(
      action: action,
      resource: resource,
      user: user,
      account: account,
      severity: "medium",
      risk_level: "medium",
      **options.merge(
        source: options[:source] || "compliance_system",
        metadata: (options[:metadata] || {}).merge(
          compliance_type: options[:compliance_type],
          regulation: options[:regulation],
          retention_period: options[:retention_period]
        )
      )
    )
  end

  def self.log_system_event(action:, **options)
    # For system events, create a dummy resource
    dummy_resource = OpenStruct.new(class: OpenStruct.new(name: "System"), id: "system")

    log_action(
      action: action,
      resource: dummy_resource,
      user: nil,
      account: Account.find_by(name: "System") || Account.first, # Fallback account
      source: "system",
      **options
    )
  end

  # Risk and severity calculation
  def self.calculate_risk_level(action, options = {})
    return options[:risk_level] if options[:risk_level].present?

    case action.to_s
    when *suspicious_actions
      "critical"
    when *failed_actions
      "high"
    when *security_actions
      "high"
    when *admin_actions
      "medium"
    when *compliance_actions
      "medium"
    else
      "low"
    end
  end

  def self.calculate_severity(action, options = {})
    return options[:severity] if options[:severity].present?

    case action.to_s
    when /failed|error|suspicious|fraud|security_alert/
      "critical"
    when /warning|retry|timeout/
      "medium"
    when /admin|compliance|backup|maintenance/
      "medium"
    else
      "low"
    end
  end

  def self.log_login(user, **options)
    log_action(
      action: "login",
      resource: user,
      user: user,
      account: user.account,
      **options
    )
  end

  def self.log_logout(user, **options)
    log_action(
      action: "logout",
      resource: user,
      user: user,
      account: user.account,
      **options
    )
  end

  def self.log_payment(payment, **options)
    log_action(
      action: "payment",
      resource: payment,
      account: payment.account,
      new_values: {
        amount_cents: payment.amount_cents,
        status: payment.status,
        payment_method: payment.payment_method
      },
      **options
    )
  end

  def self.log_subscription_change(subscription, old_status, new_status, user: nil, **options)
    log_action(
      action: "subscription_change",
      resource: subscription,
      user: user,
      account: subscription.account,
      old_values: { status: old_status },
      new_values: { status: new_status },
      **options
    )
  end

  # Instance methods
  def resource
    return nil unless resource_type && resource_id
    resource_type.constantize.find_by(id: resource_id)
  rescue NameError, ActiveRecord::RecordNotFound
    nil
  end

  def actor
    user || "System"
  end

  def summary
    case action
    when "login"
      "#{actor} logged in"
    when "logout"
      "#{actor} logged out"
    when "create"
      "#{actor} created #{resource_type}"
    when "update"
      "#{actor} updated #{resource_type}"
    when "delete"
      "#{actor} deleted #{resource_type}"
    when "payment"
      amount = new_values&.dig("amount_cents")
      "Payment of $#{amount / 100.0 if amount} #{new_values&.dig('status')}"
    when "subscription_change"
      old_status = old_values&.dig("status")
      new_status = new_values&.dig("status")
      "Subscription changed from #{old_status} to #{new_status}"
    when "role_change"
      "#{actor} changed roles for #{resource_type}"
    else
      "#{actor} performed #{action} on #{resource_type}"
    end
  end

  def changes_summary
    return nil unless old_values.present? && new_values.present?

    changes = []
    new_values.each do |key, new_value|
      old_value = old_values[key]
      if old_value != new_value
        changes << "#{key}: #{old_value} → #{new_value}"
      end
    end

    changes.join(", ")
  end

  def severity_color
    # Note: severity column doesn't exist in database schema
    # Return default color for now
    "text-gray-600 bg-gray-50"
    # case severity
    # when 'critical' then 'text-red-600 bg-red-50'
    # when 'high' then 'text-red-500 bg-red-50'
    # when 'medium' then 'text-yellow-600 bg-yellow-50'
    # when 'low' then 'text-green-600 bg-green-50'
    # else 'text-gray-600 bg-gray-50'
    # end
  end

  def risk_level_color
    # Note: risk_level column doesn't exist in database schema
    # Return default color for now
    "text-gray-600 bg-gray-50"
    # case risk_level
    # when 'critical' then 'text-purple-600 bg-purple-50'
    # when 'high' then 'text-red-600 bg-red-50'
    # when 'medium' then 'text-yellow-600 bg-yellow-50'
    # when 'low' then 'text-green-600 bg-green-50'
    # else 'text-gray-600 bg-gray-50'
    # end
  end

  def formatted_metadata
    return {} unless metadata.present?

    formatted = {}
    metadata.each do |key, value|
      case key
      when "geo_location"
        formatted["Location"] = "#{value['city']}, #{value['country']}" if value.is_a?(Hash)
      when "device_fingerprint"
        formatted["Device"] = value["device_type"] if value.is_a?(Hash)
      when "request_id"
        formatted["Request ID"] = value.to_s.truncate(12)
      when "correlation_id"
        formatted["Correlation ID"] = value.to_s.truncate(12)
      else
        formatted[key.humanize] = value.to_s.truncate(50)
      end
    end

    formatted
  end

  def is_suspicious?
    # Note: risk_level and severity columns don't exist in database schema
    # Base detection on action only for now
    self.class.suspicious_actions.include?(action)
    # self.class.suspicious_actions.include?(action) ||
    # risk_level.in?(['high', 'critical']) ||
    # severity == 'critical'
  end

  def is_security_related?
    self.class.security_actions.include?(action) ||
    source == "security_system"
  end

  def is_compliance_related?
    self.class.compliance_actions.include?(action) ||
    source == "compliance_system"
  end

  # Analytics class methods
  def self.security_summary(time_range = 24.hours.ago..Time.current)
    logs = where(created_at: time_range)

    {
      total_events: logs.count,
      security_events: logs.security_events.count,
      failed_events: logs.failed_events.count,
      # high_risk_events: logs.high_risk.count,  # high_risk scope disabled (missing risk_level column)
      suspicious_events: logs.suspicious.count,
      unique_users: logs.joins(:user).distinct.count("users.id"),
      unique_ips: logs.where.not(ip_address: nil).distinct.count(:ip_address),
      # by_severity: logs.group(:severity).count,  # severity column doesn't exist
      # by_risk_level: logs.group(:risk_level).count,  # risk_level column doesn't exist
      hourly_distribution: logs.by_hour.count
    }
  end

  def self.compliance_summary(time_range = 30.days.ago..Time.current)
    logs = where(created_at: time_range)

    {
      total_compliance_events: logs.compliance_events.count,
      gdpr_requests: logs.where(action: "gdpr_request").count,
      ccpa_requests: logs.where(action: "ccpa_request").count,
      data_deletions: logs.where(action: "data_deletion").count,
      data_exports: logs.where(action: "data_export").count,
      security_scans: logs.where(action: "security_scan").count,
      by_regulation: logs.compliance_events.group("metadata->>'regulation'").count,
      monthly_trend: logs.compliance_events.by_month.count
    }
  end

  def self.activity_timeline(limit = 50)
    recent(limit).includes(:user, :account).map do |log|
      {
        id: log.id,
        timestamp: log.created_at,
        action: log.action,
        user: log.user&.email || "System",
        account: log.account&.name,
        resource: "#{log.resource_type}##{log.resource_id}",
        # severity: log.severity,  # severity column doesn't exist
        # risk_level: log.risk_level,  # risk_level column doesn't exist
        ip_address: log.ip_address,
        message: log.summary
      }
    end
  end

  def self.risk_analysis(time_range = 7.days.ago..Time.current)
    logs = where(created_at: time_range)

    # Note: risk_level column doesn't exist, disable advanced risk analysis
    {
      # risk_scores = logs.map do |log|
      #   calculate_dynamic_risk_score(log)
      # end
      #
      # average_risk_score: risk_scores.sum.to_f / risk_scores.length,
      # high_risk_percentage: (logs.high_risk.count.to_f / logs.count * 100).round(2),
      # top_risk_actions: logs.group(:action).average('CASE
      #   WHEN risk_level = \'critical\' THEN 4
      #   WHEN risk_level = \'high\' THEN 3
      #   WHEN risk_level = \'medium\' THEN 2
      #   ELSE 1 END').sort_by(&:last).reverse.first(10),
      # risk_trend: logs.by_day.group(:risk_level).count
      total_events: logs.count,
      suspicious_events: logs.suspicious.count,
      security_events: logs.security_events.count,
      failed_events: logs.failed_events.count
    }
  end

  private

  def self.calculate_dynamic_risk_score(log)
    # Note: risk_level and severity columns don't exist in database schema
    # Return simplified risk score based on action and source
    score = 1.0

    # Base score by action type
    if suspicious_actions.include?(log.action)
      score = 4.0
    elsif failed_actions.include?(log.action)
      score = 3.0
    elsif security_actions.include?(log.action)
      score = 2.5
    elsif admin_actions.include?(log.action)
      score = 2.0
    end

    # Time-based factors
    hour = log.created_at.hour
    score *= 1.5 if hour < 6 || hour > 22 # Off-hours
    score *= 1.3 if log.created_at.saturday? || log.created_at.sunday? # Weekends

    # Source factors
    score *= case log.source
    when "api" then 1.2
    when "system" then 0.8
    when "webhook" then 1.1
    else 1.0
    end

    score.round(2)
  end

  private

  def set_defaults
    self.old_values ||= {}
    self.new_values ||= {}
    self.metadata ||= {}
  end
end
