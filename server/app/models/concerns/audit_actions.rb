# frozen_string_literal: true

# Centralized audit action definitions organized by domain
# All actions use dot notation for consistency (e.g., ai.agents.create)
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
  # PLAN MANAGEMENT ACTIONS
  # =============================================================================
  PLAN_ACTIONS = %w[
    create_plan update_plan delete_plan toggle_plan_status
    plan_upgraded plan_downgraded billing_updated
  ].freeze

  # =============================================================================
  # ACCOUNT MANAGEMENT ACTIONS
  # =============================================================================
  ACCOUNT_ACTIONS = %w[
    suspend_account activate_account admin_settings_update
    impersonation_started impersonation_ended
  ].freeze

  # =============================================================================
  # SUBSCRIPTION ACTIONS
  # =============================================================================
  SUBSCRIPTION_ACTIONS = %w[
    subscription_created subscription_updated subscription_cancelled subscription_paused
  ].freeze

  # =============================================================================
  # PAYMENT ACTIONS
  # =============================================================================
  PAYMENT_ACTIONS = %w[
    payment_completed payment_failed payment_refunded payment_disputed
    invoice_generated invoice_sent invoice_paid invoice_overdue
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
    csrf_token_generated
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
  # AI WORKFLOW ACTIONS
  # =============================================================================
  AI_WORKFLOW_ACTIONS = %w[
    ai.workflows.list ai.workflows.view ai.workflows.create ai.workflows.update ai.workflows.delete
    ai.workflows.read ai.workflows.execute ai.workflows.pause ai.workflows.resume ai.workflows.duplicate
    ai.workflows.export ai.workflows.validate ai.workflows.clone ai.workflows.import
    ai.workflows.convert_to_template ai.workflows.convert_to_workflow ai.workflows.create_from_template
    ai.executions.read ai.executions.create ai.executions.update ai.executions.cancel ai.executions.retry
    ai.workflow_runs.read ai.workflow_runs.create ai.workflow_runs.update ai.workflow_runs.cancel
    ai.workflow_runs.retry ai.workflow_runs.pause ai.workflow_runs.resume
    ai.workflows.run.cancel ai.workflows.run.delete ai.workflows.run.download ai.workflows.run.pause
    ai.workflows.run.resume ai.workflows.run.retry ai.workflows.runs.bulk_delete
    ai.workflow_validations.auto_fix ai.workflow_validations.create
    ai.workflow_validations.read ai.workflow_validations.auto_fix_single ai.workflow_validations.preview_fixes
    ai.validation_statistics.read ai.validation_statistics.health_distribution ai.validation_statistics.common_issues
    ai.workflow_git_triggers.create ai.workflow_git_triggers.update ai.workflow_git_triggers.delete
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
  # AI MARKETPLACE ACTIONS
  # =============================================================================
  AI_MARKETPLACE_ACTIONS = %w[
    ai.marketplace.installation_deleted ai.marketplace.template_created ai.marketplace.template_created_from_workflow
    ai.marketplace.template_deleted ai.marketplace.template_installed ai.marketplace.template_published
    ai.marketplace.template_rated ai.marketplace.template_updated ai.marketplace.workflow_published
    marketplace_listing_resubmitted
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
  # APP MANAGEMENT ACTIONS
  # =============================================================================
  APP_ACTIONS = %w[
    app_created app_deleted app_updated app_published app_unpublished app_submitted_for_review
    app_feature_created app_feature_updated app_feature_deleted app_feature_duplicated
    app_feature_enabled_by_default app_feature_disabled_by_default
    app_plan_created app_plan_updated app_plan_deleted app_plan_activated app_plan_deactivated app_plans_reordered
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
  # SUPPLY CHAIN ACTIONS
  # =============================================================================
  SUPPLY_CHAIN_ACTIONS = %w[
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
  # ALL ACTIONS COMBINED
  # =============================================================================
  ALL_ACTIONS = [
    CORE_ACTIONS,
    USER_ACTIONS,
    PLAN_ACTIONS,
    ACCOUNT_ACTIONS,
    SUBSCRIPTION_ACTIONS,
    PAYMENT_ACTIONS,
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
    AI_WORKFLOW_ACTIONS,
    AI_PROMPT_TEMPLATE_ACTIONS,
    AI_MARKETPLACE_ACTIONS,
    AI_MONITORING_ACTIONS,
    AI_ROI_ACTIONS,
    AI_AGENT_TEAM_ACTIONS,
    APP_ACTIONS,
    DEVOPS_ACTIONS,
    MCP_ACTIONS,
    INVITATION_ACTIONS,
    SITE_SETTING_ACTIONS,
    SUPPLY_CHAIN_ACTIONS,
    LEGACY_ACTIONS
  ].flatten.uniq.freeze

  # =============================================================================
  # MIGRATION MAPPINGS
  # Maps legacy action names to their standardized equivalents
  # =============================================================================
  MIGRATION_MAPPINGS = {
    # AI Agents legacy -> standardized
    'ai_agents.index' => 'ai.agents.read',
    'ai_agents.create' => 'ai.agents.create',
    'ai_agents.update' => 'ai.agents.update',
    'ai_agents.destroy' => 'ai.agents.delete',
    'ai_agents.execute' => 'ai.agents.execute',
    'ai_agents.clone' => 'ai.agents.clone',
    'ai_agents.pause' => 'ai.agents.pause',
    'ai_agents.resume' => 'ai.agents.resume',
    'ai_agents.archive' => 'ai.agents.archive',
    'ai_agents.stats' => 'ai.agents.stats',
    'ai_agents.analytics' => 'ai.agents.analytics',

    # AI Conversations legacy -> standardized
    'ai_conversations.create' => 'ai.conversations.create',
    'ai_conversations.update' => 'ai.conversations.update',
    'ai_conversations.destroy' => 'ai.conversations.delete',

    # AI Messages legacy -> standardized
    'ai_messages.create' => 'ai.messages.create',
    'ai_messages.update' => 'ai.messages.update',
    'ai_messages.destroy' => 'ai.messages.delete',
    'ai_messages.edit_content' => 'ai.messages.edit_content',

    # AI Analytics legacy -> standardized
    'ai_analytics.usage_recorded' => 'ai.analytics.usage_recorded',
    'ai_analytics.update' => 'ai.analytics.update'
  }.freeze

  # =============================================================================
  # HELPER METHODS
  # =============================================================================
  class_methods do
    def valid_action?(action)
      ALL_ACTIONS.include?(action.to_s)
    end

    def standardize_action(action)
      MIGRATION_MAPPINGS[action.to_s] || action.to_s
    end

    def actions_for_domain(domain)
      case domain.to_s
      when 'core' then CORE_ACTIONS
      when 'user' then USER_ACTIONS
      when 'plan' then PLAN_ACTIONS
      when 'account' then ACCOUNT_ACTIONS
      when 'subscription' then SUBSCRIPTION_ACTIONS
      when 'payment' then PAYMENT_ACTIONS
      when 'api' then API_ACTIONS
      when 'system' then SYSTEM_ACTIONS
      when 'security' then SECURITY_ACTIONS
      when 'compliance' then COMPLIANCE_ACTIONS
      when 'notification' then NOTIFICATION_ACTIONS
      when 'ai_agent' then AI_AGENT_ACTIONS
      when 'ai_conversation' then AI_CONVERSATION_ACTIONS
      when 'ai_message' then AI_MESSAGE_ACTIONS
      when 'ai_analytics' then AI_ANALYTICS_ACTIONS
      when 'ai_provider' then AI_PROVIDER_ACTIONS
      when 'ai_workflow' then AI_WORKFLOW_ACTIONS
      when 'ai_prompt_template' then AI_PROMPT_TEMPLATE_ACTIONS
      when 'ai_marketplace' then AI_MARKETPLACE_ACTIONS
      when 'ai_monitoring' then AI_MONITORING_ACTIONS
      when 'ai_agent_team' then AI_AGENT_TEAM_ACTIONS
      when 'app' then APP_ACTIONS
      when 'devops' then DEVOPS_ACTIONS
      when 'mcp' then MCP_ACTIONS
      when 'invitation' then INVITATION_ACTIONS
      when 'site_setting' then SITE_SETTING_ACTIONS
      when 'supply_chain' then SUPPLY_CHAIN_ACTIONS
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
        AI_WORKFLOW_ACTIONS,
        AI_PROMPT_TEMPLATE_ACTIONS,
        AI_MARKETPLACE_ACTIONS,
        AI_MONITORING_ACTIONS,
        AI_ROI_ACTIONS,
        AI_AGENT_TEAM_ACTIONS
      ].flatten.uniq
    end
  end
end
