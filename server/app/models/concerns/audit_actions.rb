# frozen_string_literal: true

# Centralized audit action definitions organized by domain.
# All actions use dot notation for consistency (e.g., ai.agents.create) except
# for legacy flat tokens (e.g., subscription_created) kept for compatibility.
#
# Extension seam (mirrors Permissions.register_catalog / register_roles):
# core declares its own actions/sources in the frozen CORE_* constants; an
# extension registers ITS actions via AuditActions.register_actions(namespace, [...])
# (and sources via register_sources) from its engine initializer. The runtime
# allowlists are the dynamic unions AuditActions.all_actions / all_sources —
# core ∪ everything registered by the currently-loaded extensions. A disabled
# extension never runs its initializer, so it is naturally excluded. Nothing in
# core (this file or any consumer) names an extension.
module AuditActions
  extend ActiveSupport::Concern

  # =============================================================================
  # CORE SYSTEM ACTIONS
  # =============================================================================
  CORE_ACTIONS = %w[
    create update delete created updated deleted
    login logout payment subscription_change role_change
  ].freeze

  # =============================================================================
  # USER MANAGEMENT ACTIONS
  # =============================================================================
  USER_ACTIONS = %w[
    user_created user_updated user_deleted
    user_login user_logout user_registration login_failed password_reset
    login_2fa_required
    account_locked account_unlocked account_switch password_changed email_verified
    two_factor_enabled two_factor_disabled backup_codes_generated
  ].freeze

  # =============================================================================
  # ACCOUNT MANAGEMENT ACTIONS (core-retained subset)
  # impersonation_started / impersonation_ended are extension-owned (business).
  # =============================================================================
  ACCOUNT_ACTIONS = %w[
    suspend_account activate_account admin_settings_update
  ].freeze

  # =============================================================================
  # WEBHOOK ACTIONS (core-retained — inbound/outbound webhook lifecycle)
  # Regrouped out of the former PAYMENT_ACTIONS; the payment/invoice events
  # that lived alongside them are extension-owned (business).
  # =============================================================================
  WEBHOOK_ACTIONS = %w[
    webhook_received webhook_failed webhook_retry
    webhook_created webhook_updated webhook_deleted
    webhook_test webhook_test_failed webhook_status_changed
    webhook_delivery_retry webhook_health_test
  ].freeze

  # =============================================================================
  # API & INTEGRATION ACTIONS
  # =============================================================================
  API_ACTIONS = %w[
    api_key_created api_key_updated api_key_deleted api_key_regenerated
    api_key_revoked api_key_status_changed api_access_denied
    api_request api_request_failed
    integration_connected integration_disconnected
  ].freeze

  # =============================================================================
  # OAUTH APPLICATION ACTIONS
  # =============================================================================
  OAUTH_ACTIONS = %w[
    oauth_application_created oauth_application_updated oauth_application_deleted
    oauth_application_secret_regenerated oauth_application_suspended
    oauth_application_activated oauth_application_revoked oauth_tokens_bulk_revoked
  ].freeze

  # =============================================================================
  # SYSTEM ACTIONS
  # =============================================================================
  SYSTEM_ACTIONS = %w[
    data_export data_import security_scan compliance_check
    system_maintenance system_backup system_restore
    audit_log_cleanup audit_log_export
    audit_logging_error error_occurred
    database_restore_created database_restore_status_changed
    scheduled_task_created scheduled_task_updated scheduled_task_deleted
    task_execution_created task_execution_status_changed
    job_enqueue notification_send billing_operation webhook_process
    analytics_request report_generation health_check email_configuration
  ].freeze

  # =============================================================================
  # SECURITY ACTIONS
  # =============================================================================
  SECURITY_ACTIONS = %w[
    security_alert fraud_detection suspicious_activity
    csrf_token_generated jwt_secret_regenerated
  ].freeze

  # =============================================================================
  # COMPLIANCE ACTIONS
  # =============================================================================
  COMPLIANCE_ACTIONS = %w[
    gdpr_request ccpa_request data_deletion data_anonymization
  ].freeze

  # =============================================================================
  # EMAIL & NOTIFICATION ACTIONS
  # =============================================================================
  NOTIFICATION_ACTIONS = %w[
    test_email_sent test_email_failed email_sent email_failed
    email_settings_refreshed notification_sent notification_failed
  ].freeze

  # =============================================================================
  # AI AGENT ACTIONS (Standardized dot notation)
  # =============================================================================
  AI_AGENT_ACTIONS = %w[
    ai.agents.read ai.agents.create ai.agents.update ai.agents.delete
    ai.agents.execute ai.agents.clone ai.agents.pause ai.agents.resume
    ai.agents.archive ai.agents.test ai.agents.validate ai.agents.stats ai.agents.analytics
    ai.agents.execution.cancel ai.agents.execution.delete ai.agents.execution.retry
  ].freeze

  # =============================================================================
  # AI CONVERSATION ACTIONS
  # =============================================================================
  AI_CONVERSATION_ACTIONS = %w[
    ai.conversations.create ai.conversations.update ai.conversations.delete ai.conversations.archive
    ai.conversations.complete ai.conversations.duplicate ai.conversations.export ai.conversations.pause
    ai.conversations.resume ai.conversations.unarchive ai.conversations.message.send
    ai_conversation_channel_subscribed ai_conversation_channel_unsubscribed
    ai_conversation_message_sent ai_conversation_message_failed
  ].freeze

  # =============================================================================
  # AI MESSAGE ACTIONS
  # =============================================================================
  AI_MESSAGE_ACTIONS = %w[
    ai.messages.create ai.messages.update ai.messages.delete ai.messages.edit_content
    ai.messages.rate ai.messages.regenerate
  ].freeze

  # =============================================================================
  # AI ANALYTICS ACTIONS
  # =============================================================================
  AI_ANALYTICS_ACTIONS = %w[
    ai_execution_cost ai_daily_cost_summary
    ai.analytics.usage_recorded ai.analytics.update ai.analytics.report_generated
    ai.analytics.cost_analysis ai.analytics.dashboard ai.analytics.export ai.analytics.insights
    ai.analytics.report.cancel ai.analytics.report.create ai.analytics.report.download
  ].freeze

  # =============================================================================
  # AI PROVIDER ACTIONS
  # =============================================================================
  AI_PROVIDER_ACTIONS = %w[
    ai_provider_credential_created ai_provider_credential_updated ai_provider_credential_deleted
    ai_provider_credential_tested ai_provider_credential_made_default ai_provider_credential_decrypted
    ai_provider_credential_encryption_rotated
    ai.providers.list ai.providers.view ai.providers.create ai.providers.update ai.providers.delete
    ai.providers.read ai.providers.test ai.providers.sync ai.providers.configure
    ai.providers.test_connection ai.providers.sync_models ai.providers.setup_defaults ai.providers.test_all
    ai.providers.credential.create ai.providers.credential.update ai.providers.credential.delete
    ai.providers.credential.test ai.providers.credential.make_default ai.providers.credential.rotate
    ai.credentials.read ai.credentials.create ai.credentials.update ai.credentials.delete ai.credentials.test
  ].freeze

  # =============================================================================
  # AI DATA SOURCE ACTIONS — includes the OAuth 2.0 connect-flow key operations
  # (oauth.authorize / oauth.callback) and credential lifecycle; these MUST stay
  # registered per the crypto-material-safety rule (all key ops audited).
  # =============================================================================
  AI_DATA_SOURCE_ACTIONS = %w[
    ai.data_sources.create ai.data_sources.update ai.data_sources.delete
    ai.data_sources.test_connection ai.data_sources.introspect
    ai.data_sources.credential.create ai.data_sources.credential.update
    ai.data_sources.credential.delete ai.data_sources.credential.test
    ai.data_sources.credential.make_default
    ai.data_sources.oauth.authorize ai.data_sources.oauth.callback
    ai.data_sources.endpoint.create ai.data_sources.endpoint.update ai.data_sources.endpoint.delete
    ai.data_sources.subscription.create ai.data_sources.subscription.delete
  ].freeze

  # =============================================================================
  # AI PROMPT TEMPLATE ACTIONS
  # =============================================================================
  AI_PROMPT_TEMPLATE_ACTIONS = %w[
    ai.prompt_templates.list ai.prompt_templates.read ai.prompt_templates.create
    ai.prompt_templates.update ai.prompt_templates.delete ai.prompt_templates.preview
    ai.prompt_templates.duplicate
  ].freeze

  # =============================================================================
  # AI MONITORING ACTIONS
  # =============================================================================
  AI_MONITORING_ACTIONS = %w[
    ai.monitoring.alerts_check ai.monitoring.alerts_view ai.monitoring.circuit_breaker.close
    ai.monitoring.circuit_breaker.open ai.monitoring.circuit_breaker.reset ai.monitoring.circuit_breakers.category_reset
    ai.monitoring.circuit_breakers.reset_all ai.monitoring.dashboard ai.monitoring.health_check
    ai.monitoring.start ai.monitoring.stop
  ].freeze

  # =============================================================================
  # AI ROI ACTIONS
  # =============================================================================
  AI_ROI_ACTIONS = %w[
    ai.roi.dashboard ai.roi.calculate ai.roi.aggregate
  ].freeze

  # =============================================================================
  # AI AGENT TEAM ACTIONS
  # =============================================================================
  AI_AGENT_TEAM_ACTIONS = %w[
    ai_agent_team.created ai_agent_team.updated ai_agent_team.deleted
    ai_agent_team.member_added ai_agent_team.member_removed
    ai_agent_team.execution_started ai_agent_team.execution_completed ai_agent_team.execution_failed
  ].freeze

  # =============================================================================
  # DEVOPS (CI/CD) ACTIONS
  # =============================================================================
  DEVOPS_ACTIONS = %w[
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
  ].freeze

  # =============================================================================
  # MCP SERVER ACTIONS
  # =============================================================================
  MCP_ACTIONS = %w[
    mcp.servers.read mcp.servers.create mcp.servers.update mcp.servers.delete
    mcp.servers.connect mcp.servers.disconnect mcp.servers.health_check mcp.servers.discover_tools mcp.servers.workflow_builder_read
    mcp.tools.read mcp.tools.execute
    mcp.executions.read mcp.executions.cancel
    mcp.oauth.authorize_initiated mcp.oauth.callback_success mcp.oauth.disconnect mcp.oauth.status_read mcp.oauth.token_refreshed
  ].freeze

  # =============================================================================
  # INVITATION ACTIONS
  # =============================================================================
  INVITATION_ACTIONS = %w[
    invitation.created invitation.updated invitation.deleted
    invitation.resent invitation.cancelled invitation.accepted
  ].freeze

  # =============================================================================
  # SITE SETTING ACTIONS
  # =============================================================================
  SITE_SETTING_ACTIONS = %w[
    create_site_setting update_site_setting delete_site_setting bulk_update_site_settings
  ].freeze

  # =============================================================================
  # REPORT REQUEST ACTIONS — fired by ReportRequest#log_status_change, plus the
  # retention sweep (Api::V1::Internal::ReportsController#cleanup_old, driven by
  # the worker's Reports::CleanupOldReportsJob), which destroys rows and their
  # stored artifacts and so records one entry per row removed.
  # =============================================================================
  REPORT_REQUEST_ACTIONS = %w[
    report_request_pending
    report_request_processing
    report_request_completed
    report_request_failed
    report_request_cancelled
    report_request_cleanup_deleted
  ].freeze

  # =============================================================================
  # LEGACY ACTIONS (deprecated, kept for backward compatibility)
  # These will be migrated to their standardized equivalents
  # =============================================================================
  LEGACY_ACTIONS = %w[
    ai_agents.index ai_agents.create ai_agents.update ai_agents.destroy
    ai_agents.execute ai_agents.clone ai_agents.pause ai_agents.resume
    ai_agents.archive ai_agents.stats ai_agents.analytics
    ai_conversations.update ai_conversations.create ai_conversations.destroy
    ai_messages.update ai_messages.create ai_messages.destroy ai_messages.edit_content
    ai_analytics.usage_recorded ai_analytics.update
  ].freeze

  # =============================================================================
  # DEPLOY ACTIONS — Ai::Deploy::Orchestrator lifecycle (self-deploy + project deploy).
  # The privilege/irreversibility crossing is audited at every phase.
  # =============================================================================
  DEPLOY_ACTIONS = %w[
    deploy.initiated deploy.dry_run deploy.succeeded deploy.failed
    deploy.unhealthy deploy.rolled_back deploy.skipped deploy.blocked deploy.completed
  ].freeze

  # =============================================================================
  # CORE ALL ACTIONS — frozen union of the core-only groups above.
  # Extension-contributed actions are NOT here; they join at runtime via
  # the dynamic AuditActions.all_actions union. (Was the combined ALL_ACTIONS.)
  # =============================================================================
  CORE_ALL_ACTIONS = [
    CORE_ACTIONS,
    USER_ACTIONS,
    ACCOUNT_ACTIONS,
    WEBHOOK_ACTIONS,
    API_ACTIONS,
    OAUTH_ACTIONS,
    SYSTEM_ACTIONS,
    SECURITY_ACTIONS,
    COMPLIANCE_ACTIONS,
    NOTIFICATION_ACTIONS,
    AI_AGENT_ACTIONS,
    AI_CONVERSATION_ACTIONS,
    AI_MESSAGE_ACTIONS,
    AI_ANALYTICS_ACTIONS,
    AI_PROVIDER_ACTIONS,
    AI_DATA_SOURCE_ACTIONS,
    AI_PROMPT_TEMPLATE_ACTIONS,
    AI_MONITORING_ACTIONS,
    AI_ROI_ACTIONS,
    AI_AGENT_TEAM_ACTIONS,
    DEVOPS_ACTIONS,
    DEPLOY_ACTIONS,
    MCP_ACTIONS,
    INVITATION_ACTIONS,
    SITE_SETTING_ACTIONS,
    REPORT_REQUEST_ACTIONS,
    LEGACY_ACTIONS
  ].flatten.uniq.freeze

  # =============================================================================
  # CORE SOURCES — the audit-log `source` allowlist (relocated here from
  # AuditLog so it can carry an extension seam symmetric with actions). No
  # extension sources exist today; all current sources are core. all_sources
  # is the dynamic core ∪ registered union (see below).
  # =============================================================================
  CORE_SOURCES = %w[
    web api system webhook admin_panel mobile_app integration automation
    scheduler worker security_system compliance_system
  ].freeze

  # =============================================================================
  # EXTENSION SEAM — mutable accumulators populated by extension engines via
  # register_actions / register_sources. Keyed registration is idempotent.
  # =============================================================================
  # namespace (String) => frozen Array of action tokens contributed by that ext.
  @extension_actions = {}
  # Flat Array of source tokens contributed by extensions.
  @extension_sources = []

  class << self
    # Extension sink for audit ACTIONS — the audit twin of
    # Permissions.register_catalog. `namespace` is purely for attribution /
    # grouping (e.g. "business", "supply_chain", "system"); it is NOT enforced
    # as a name prefix, because audit action names are legacy-flat
    # (e.g. "subscription_created") as well as dotted. Idempotent: re-registering
    # the same namespace replaces that namespace's set (so reloader cycles and
    # double-loads converge instead of accumulating).
    #
    # Usage (extensions/<x>/server/lib/<engine>/engine.rb, after_initialize):
    #   AuditActions.register_actions("business", %w[subscription_created ...])
    def register_actions(namespace, actions)
      @extension_actions[namespace.to_s] = Array(actions).map(&:to_s).uniq.freeze
      nil
    end

    # Extension sink for audit SOURCES — symmetric with register_actions but
    # flat (sources have no namespace grouping). Idempotent union.
    def register_sources(sources)
      @extension_sources = (@extension_sources + Array(sources).map(&:to_s)).uniq
      nil
    end

    # Read-side accessors (parallel to Permissions.extension_* accessors).
    def extension_actions = @extension_actions
    def extension_sources = @extension_sources

    # The full runtime action allowlist: core ∪ every loaded extension's
    # registered actions. Computed dynamically at call time so actions
    # registered during boot (engine after_initialize) are honored, and a
    # disabled extension (whose initializer never runs) is naturally excluded.
    # Consumers (validation, valid_action?) use this, never CORE_ALL_ACTIONS.
    def all_actions
      (CORE_ALL_ACTIONS + @extension_actions.values.flatten).uniq
    end

    # The full runtime source allowlist: core ∪ registered. Same dynamics.
    def all_sources
      (CORE_SOURCES + @extension_sources).uniq
    end

    def valid_action?(action)
      all_actions.include?(action.to_s)
    end

    def valid_source?(source)
      all_sources.include?(source.to_s)
    end

    def standardize_action(action)
      MIGRATION_MAPPINGS[action.to_s] || action.to_s
    end

    def actions_for_domain(domain)
      case domain.to_s
      when "core" then CORE_ACTIONS
      when "user" then USER_ACTIONS
      when "account" then ACCOUNT_ACTIONS
      when "webhook" then WEBHOOK_ACTIONS
      when "api" then API_ACTIONS
      when "system" then SYSTEM_ACTIONS
      when "security" then SECURITY_ACTIONS
      when "compliance" then COMPLIANCE_ACTIONS
      when "notification" then NOTIFICATION_ACTIONS
      when "ai_agent" then AI_AGENT_ACTIONS
      when "ai_conversation" then AI_CONVERSATION_ACTIONS
      when "ai_message" then AI_MESSAGE_ACTIONS
      when "ai_analytics" then AI_ANALYTICS_ACTIONS
      when "ai_provider" then AI_PROVIDER_ACTIONS
      when "ai_prompt_template" then AI_PROMPT_TEMPLATE_ACTIONS
      when "ai_monitoring" then AI_MONITORING_ACTIONS
      when "ai_agent_team" then AI_AGENT_TEAM_ACTIONS
      when "devops" then DEVOPS_ACTIONS
      when "mcp" then MCP_ACTIONS
      when "invitation" then INVITATION_ACTIONS
      when "site_setting" then SITE_SETTING_ACTIONS
      else []
      end
    end

    def ai_actions
      [
        AI_AGENT_ACTIONS,
        AI_CONVERSATION_ACTIONS,
        AI_MESSAGE_ACTIONS,
        AI_ANALYTICS_ACTIONS,
        AI_PROVIDER_ACTIONS,
        AI_PROMPT_TEMPLATE_ACTIONS,
        AI_MONITORING_ACTIONS,
        AI_ROI_ACTIONS,
        AI_AGENT_TEAM_ACTIONS
      ].flatten.uniq
    end
  end

  # =============================================================================
  # MIGRATION MAPPINGS
  # Maps legacy action names to their standardized equivalents
  # =============================================================================
  MIGRATION_MAPPINGS = {
    # AI Agents legacy -> standardized
    "ai_agents.index" => "ai.agents.read",
    "ai_agents.create" => "ai.agents.create",
    "ai_agents.update" => "ai.agents.update",
    "ai_agents.destroy" => "ai.agents.delete",
    "ai_agents.execute" => "ai.agents.execute",
    "ai_agents.clone" => "ai.agents.clone",
    "ai_agents.pause" => "ai.agents.pause",
    "ai_agents.resume" => "ai.agents.resume",
    "ai_agents.archive" => "ai.agents.archive",
    "ai_agents.stats" => "ai.agents.stats",
    "ai_agents.analytics" => "ai.agents.analytics",

    # AI Conversations legacy -> standardized
    "ai_conversations.create" => "ai.conversations.create",
    "ai_conversations.update" => "ai.conversations.update",
    "ai_conversations.destroy" => "ai.conversations.delete",

    # AI Messages legacy -> standardized
    "ai_messages.create" => "ai.messages.create",
    "ai_messages.update" => "ai.messages.update",
    "ai_messages.destroy" => "ai.messages.delete",
    "ai_messages.edit_content" => "ai.messages.edit_content",

    # AI Analytics legacy -> standardized
    "ai_analytics.usage_recorded" => "ai.analytics.usage_recorded",
    "ai_analytics.update" => "ai.analytics.update"
  }.freeze

  # =============================================================================
  # HELPER METHODS (instance/class via ActiveSupport::Concern) — delegate to the
  # module-level class methods so includers (AuditLog) keep the same surface.
  # =============================================================================
  class_methods do
    def valid_action?(action)
      AuditActions.valid_action?(action)
    end

    def valid_source?(source)
      AuditActions.valid_source?(source)
    end

    def standardize_action(action)
      AuditActions.standardize_action(action)
    end

    def actions_for_domain(domain)
      AuditActions.actions_for_domain(domain)
    end

    def ai_actions
      AuditActions.ai_actions
    end
  end
end
