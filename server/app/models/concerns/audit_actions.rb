# frozen_string_literal: true

# Centralized audit action definitions organized by domain.
# Domains introduced after the dot-notation convention use it throughout
# (e.g., ai.agents.create); domains that predate it (e.g., subscription_change)
# keep their original flat tokens by design — that is the established name for
# those events, not a compatibility shim. No action name may alias another:
# register_actions refuses a token shaped like the deprecated ai_<domain>.<verb>
# form (see LEGACY_ALIAS_PATTERN), and the same rule is pinned by
# spec/models/concerns/audit_actions_spec.rb against the core set itself.
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
    account_created
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
  # ACCOUNT DATA LIFECYCLE ACTIONS — server/app/controllers/api/v1/internal/
  # accounts_controller.rb, the account-scoped leg of the worker-driven
  # GDPR/CCPA deletion path (IMP-26a95cba1d43). Found while enumerating the
  # 225 further unregistered-literal occurrences left after
  # IMP-b95b8c5b6c40's devops/swarm/docker/worker fix — this is the cluster
  # that task named explicitly as the one that "matters most": every one of
  # these seven writers used a self-consistent "account.<verb>" prefix that
  # was never registered, so AuditLog's inclusion validation rejected every
  # row and log_internal_audit's rescue (internal_base_controller.rb, see
  # its swallowed-write fix below) dropped it silently everywhere except a
  # manual log read — the platform believed it was auditing irreversible
  # personal-data destruction and anonymization and was writing nothing.
  # Registered AS WRITTEN rather than renamed onto ACCOUNT_ACTIONS' unrelated
  # flat tokens (account_created, suspend_account, ...): same reasoning as
  # SWARM_ACTIONS/DOCKER_ACTIONS below — a self-consistent domain prefix
  # that was simply never registered, not a mis-spelling of an existing one.
  # =============================================================================
  # account.terminate (IMP-b33a3ecca331) — Api::V1::Internal::AccountsController
  # #terminate, the narrow member action that sets an account's status to
  # 'cancelled' at the end of Compliance::AccountTerminationJob's per-account
  # run. Same "account.<verb>" prefix as its siblings below; registered here
  # rather than in ACCOUNT_ACTIONS' flat tokens for the same reason as the
  # rest of this constant — it's the same controller, same self-consistent
  # prefix, not a rename of the unrelated admin-facing suspend_account/
  # activate_account pair (Admin::SettingsService, a different actor and a
  # reversible action).
  ACCOUNT_DATA_LIFECYCLE_ACTIONS = %w[
    account.terminate
    account.anonymize_audit_logs account.anonymize_payments
    account.delete_files account.delete_api_keys account.delete_webhooks
    account.delete_data_export_requests account.delete_data_deletion_requests
  ].freeze

  # =============================================================================
  # ACCOUNT TERMINATION ACTIONS — server/app/controllers/api/v1/internal/
  # account_terminations_controller.rb#update (IMP-b33a3ecca331 second
  # review, S-A). A distinct resource from Account itself (Account::
  # Termination), hence its own prefix rather than folding into
  # ACCOUNT_DATA_LIFECYCLE_ACTIONS above. Written on every allowed status
  # transition the status-transition guard admits (grace_period->processing,
  # processing->completed/grace_period), carrying from_status/to_status.
  # =============================================================================
  ACCOUNT_TERMINATION_ACTIONS = %w[
    account_termination.status_transition
  ].freeze

  # =============================================================================
  # USER DATA LIFECYCLE ACTIONS — server/app/controllers/api/v1/internal/
  # users_controller.rb, the user-scoped leg of the same GDPR/CCPA path
  # (IMP-26a95cba1d43). Same defect and same registration decision as
  # ACCOUNT_DATA_LIFECYCLE_ACTIONS above: a self-consistent "user.<verb>"
  # prefix, never registered.
  #
  # "user.delete" was removed (IMP-d845eb50e0b6): it was the literal for
  # UsersController#destroy, which had no route and nothing in the actual
  # GDPR erasure flow ever called it. The DESIGN INTENT is anonymize-in-place
  # — worker's DataDeletionJob and AccountTerminationJob call anonymize
  # endpoints instead of a hard delete, never hard-deleting the user row for
  # any deletion_type. (That anonymize path is itself currently defective in
  # production — internal users#anonymize writes a nonexistent `phone`
  # column and AccountTerminationJob's user-anonymize PATCH hits an unrouted
  # URL — tracked separately as improvement offer 01a0b57b-71ba, not fixed
  # here.) The dead destroy action and its dead literal are both gone;
  # hard-deleting a user is handled by the routed, permission-gated
  # Api::V1::UsersController#destroy (blocks self-deletion) and
  # Api::V1::Admin::UsersController#destroy (admin.user.delete; blocks
  # self-deletion AND removing the last account owner) — invariants this
  # internal action never had.
  # =============================================================================
  USER_DATA_LIFECYCLE_ACTIONS = %w[
    user.anonymize user.anonymize_audit_logs
    user.delete_consents user.delete_terms_acceptances
    user.delete_password_histories user.delete_roles
  ].freeze

  # =============================================================================
  # DATA DELETION REQUEST ACTIONS — server/app/controllers/api/v1/internal/
  # data_deletion_requests_controller.rb, the DeletionRequest state-machine
  # transitions (approve/reject/execute/complete) that drive the account/user
  # lifecycle writers above (IMP-26a95cba1d43). Same defect, same decision.
  # Distinct from the pre-existing flat COMPLIANCE_ACTIONS token
  # "data_deletion" (no dot, fired once by
  # DataManagement::DeletionRequest#log_deletion_requested on request
  # creation) — that token names a different event and is untouched here.
  # data_deletion.status_transition (IMP-b33a3ecca331 review, S3) —
  # Compliance::DataDeletionJob's own raw status-progress PATCHes (approved->
  # processing, processing->processing/completed/failed), guarded by
  # DataDeletionRequestsController::ALLOWED_WORKER_STATUS_TRANSITIONS. Distinct
  # from the four action_type-driven tokens below, which are the admin-facing
  # dispatch (approve/reject/execute/complete) — this one is the job reporting
  # its own progress on the SAME resource through a different code path.
  # =============================================================================
  DATA_DELETION_REQUEST_ACTIONS = %w[
    data_deletion.approve data_deletion.reject
    data_deletion.execute data_deletion.complete
    data_deletion.status_transition
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
    ai.providers.test_connection ai.providers.sync_models ai.providers.test_all
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
  # AI IMPROVEMENT ACTIONS
  # =============================================================================
  # The weekly discovery clock's per-account run record (D1). Registered here
  # because `AuditLog` validates `action` against this allowlist, and
  # `log_internal_audit` rescues its own failure — an unregistered action is
  # dropped silently, leaving a run history that reads as "never ran".
  AI_IMPROVEMENT_ACTIONS = %w[
    ai.improvement_discovery.run
  ].freeze

  # =============================================================================
  # AI AGENT TEAM ACTIONS — renamed from the underscore-namespace form
  # (ai_agent_team.<verb>) to the dot convention (IMP-85fb47438be6, operator
  # decision 2026-09-17): the old form matched LEGACY_ALIAS_PATTERN's shape
  # below even though it aliased nothing, which forced a carve-out. Renaming
  # removes the need for one — no core token matches the pattern now. Writers
  # (server/app/controllers/api/v1/ai/agent_teams_controller.rb,
  # agent_team_executions_controller.rb) and the historical-row migration
  # (db/migrate/20260917010000_reclassify_legacy_audit_actions.rb) were
  # updated in the same change; existing rows get a chained correction row
  # rather than being renamed in place, same as every other pair in that
  # migration.
  #
  # execution_cancel_requested/execution_pause_requested/
  # execution_resume_requested/execution_retried (IMP-352641d30a86): the four
  # control-signal literals agent_team_executions_controller.rb's
  # cancel/pause/resume/retry_execution actions already wrote in this
  # convention, but that renaming pass never registered them — they were
  # never an alias of execution_started/completed/failed above (those name
  # the worker's own lifecycle transitions, not an operator's control
  # request), so AuditLog's inclusion validation rejected every one of these
  # four rows. Found alongside a second, independent defect in the same four
  # call sites: each called an `audit_log` method that AuditLogging never
  # defines (it defines `log_audit_event`), which raised NoMethodError AFTER
  # the state mutation (control_signal update / job enqueue) had already
  # happened — fixed in the same change as this registration, so the
  # NoMethodError could not mask this validation gap once resolved.
  # =============================================================================
  AI_AGENT_TEAM_ACTIONS = %w[
    ai.agent_team.created ai.agent_team.updated ai.agent_team.deleted
    ai.agent_team.member_added ai.agent_team.member_removed
    ai.agent_team.execution_started ai.agent_team.execution_completed ai.agent_team.execution_failed
    ai.agent_team.execution_cancel_requested ai.agent_team.execution_pause_requested
    ai.agent_team.execution_resume_requested ai.agent_team.execution_retried
  ].freeze

  # =============================================================================
  # DEVOPS (CI/CD) ACTIONS
  #
  # IMP-b95b8c5b6c40 (2026-09-18): every writer under
  # server/app/controllers/api/v1/devops/{pipelines,pipeline_runs,providers,
  # repositories,schedules,prompt_templates,container_templates,containers,
  # container_quotas}_controller.rb used to call log_audit_event with a
  # "devops.<resource>.<verb>" literal — this array only ever registered the
  # "ci_cd.<resource>.<verb>" spelling, so EVERY one of those calls failed
  # AuditLog's inclusion validation and (log_audit_event rescues StandardError
  # and only re-raises in Rails.env.test?) was silently dropped everywhere
  # else, including production. Fixed by moving the writers to the already-
  # registered ci_cd.* spelling (verb-for-verb identical requests) rather than
  # adding a second "devops.*" spelling for the same events — one convention,
  # not two. container_templates/containers/container_quotas had NO registered
  # counterpart under either prefix (a second, distinct defect: never-
  # registered rather than mis-spelled); they join this array under the same
  # ci_cd.* convention as their siblings in the same controller family, and
  # their writers were renamed to match. See SWARM_ACTIONS/DOCKER_ACTIONS
  # below for the sibling defect in the swarm/docker sub-namespaces, which
  # keep their own already-self-consistent prefix instead.
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
    ci_cd.container_templates.list ci_cd.container_templates.read ci_cd.container_templates.create
    ci_cd.container_templates.update ci_cd.container_templates.delete ci_cd.container_templates.publish
    ci_cd.container_templates.unpublish ci_cd.container_templates.trigger_build ci_cd.container_templates.create_image_repo
    ci_cd.containers.list ci_cd.containers.read ci_cd.containers.execute ci_cd.containers.cancel
    ci_cd.container_quotas.update ci_cd.container_quotas.reset_usage ci_cd.container_quotas.update_overage
  ].freeze

  # =============================================================================
  # DOCKER SWARM ACTIONS — server/app/controllers/api/v1/devops/swarm/*.rb.
  # IMP-b95b8c5b6c40: these writers already used a self-consistent "swarm.*"
  # prefix (not "devops.swarm.*"), matching their own controller namespace —
  # they were simply never registered under ANY name, so every one of these
  # writes has always failed AuditLog's inclusion validation and been
  # silently dropped. Registered as-written rather than renamed: "swarm" is
  # its own resource domain (Docker Swarm orchestration), not a CI/CD
  # pipeline concept, so folding it under "ci_cd.*" would misname it.
  # swarm.clusters.sync (plural) is also the target the internal worker
  # callback in Api::V1::Internal::Devops::SwarmController#sync_results was
  # renamed to match (it previously wrote the singular "swarm.cluster.sync",
  # a second, independent naming drift on the same conceptual event).
  # =============================================================================
  SWARM_ACTIONS = %w[
    swarm.clusters.list swarm.clusters.read swarm.clusters.create swarm.clusters.update
    swarm.clusters.delete swarm.clusters.sync
    swarm.nodes.promote swarm.nodes.demote swarm.nodes.drain swarm.nodes.activate swarm.nodes.remove
    swarm.secrets.create swarm.secrets.delete
    swarm.configs.create swarm.configs.delete
    swarm.events.acknowledge
    swarm.stacks.create swarm.stacks.update swarm.stacks.delete swarm.stacks.deploy swarm.stacks.remove
    swarm.networks.create swarm.networks.delete
    swarm.services.import swarm.services.create swarm.services.update swarm.services.delete
    swarm.services.scale swarm.services.rollback
    swarm.volumes.create swarm.volumes.delete
  ].freeze

  # =============================================================================
  # DOCKER HOST ACTIONS — server/app/controllers/api/v1/devops/docker/*.rb.
  # IMP-b95b8c5b6c40: same defect as SWARM_ACTIONS above — a self-consistent
  # "docker.*" prefix, never registered. docker.hosts.sync (plural) is the
  # target the internal worker callback in
  # Api::V1::Internal::Devops::DockerController#sync_results was renamed to
  # match (it previously wrote the singular "docker.host.sync").
  # =============================================================================
  DOCKER_ACTIONS = %w[
    docker.images.import docker.images.pull docker.images.delete docker.images.tag
    docker.hosts.list docker.hosts.read docker.hosts.create docker.hosts.update
    docker.hosts.delete docker.hosts.sync
    docker.events.acknowledge
    docker.networks.create docker.networks.delete
    docker.containers.import docker.containers.create docker.containers.delete
    docker.containers.start docker.containers.stop docker.containers.restart
    docker.volumes.create docker.volumes.delete
  ].freeze

  # =============================================================================
  # WORKER ACTIONS — Workers::EnsureSystemWorker's mTLS dev-sentinel revocation
  # (app/services/workers/ensure_system_worker.rb). IMP-b95b8c5b6c40: found
  # while enumerating unregistered audit literals for the devops/ci_cd drift;
  # a distinct, unrelated writer with the same failure mode. Its own spec
  # (spec/services/workers/ensure_system_worker_spec.rb) stubs
  # Audit::LoggingService.instance.log entirely, so it never exercised the
  # real AuditLog validation and never caught this. Security-relevant (a
  # revoked mTLS identity), so — per the crypto-material-safety rule that key
  # operations must be audited — this write being silently dropped is itself
  # the gap that rule exists to prevent.
  # =============================================================================
  WORKER_ACTIONS = %w[
    worker.mtls_dev_sentinel_revoked
  ].freeze

  # =============================================================================
  # MCP SERVER ACTIONS
  # =============================================================================
  # mcp.tools.undeclared_action is governance telemetry (IMP-a0553dda1ec3): a
  # tool action requested with no Ai::Tools::BaseTool.declare_action
  # declaration. Since the fail-closed flip (APO-1e) such an action is REFUSED
  # and the row carries metadata outcome "refused"; rows without an outcome
  # predate the flip and record an action that ran ungoverned. Its payload is
  # shape-only — principal KIND, tool class, action name; never identity,
  # never credentials.
  # mcp.tools.canonical_principal_refused (HIER-P2I): Ai::Tools::BaseTool
  # refused a GLOBAL canonical agent (account_id NULL) as the acting
  # principal — a template never executes; the account's clone does. Carries
  # the canonical's slug and the tool/action, never the call's params.
  # mcp.tools.sensitive_access (IMP-4ef95e825a7a) is the only MCP audit action
  # of the three that records a SUCCESSFUL call rather than an anomaly, and the
  # only one whose write is load-bearing: the two above fail OPEN, while an
  # action declared `audit: true` fails CLOSED — the credential is not released
  # if the row cannot be written. One action name covers every audited verb
  # because `action` is allowlisted here; the verb itself is in
  # metadata->>'action_name', so the breakage set is
  #   AuditLog.by_action("mcp.tools.sensitive_access")
  #           .distinct.pluck(Arel.sql("metadata->>'action_name'"))
  # Payload is who/what/when — principal, tool, action, and the tool's own
  # resource context. NEVER the material that was handed out.
  MCP_ACTIONS = %w[
    mcp.servers.read mcp.servers.create mcp.servers.update mcp.servers.delete
    mcp.servers.connect mcp.servers.disconnect mcp.servers.health_check mcp.servers.discover_tools
    mcp.tools.read mcp.tools.execute mcp.tools.undeclared_action mcp.tools.canonical_principal_refused
    mcp.tools.sensitive_access
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
  # DEPLOY ACTIONS — Ai::Deploy::Orchestrator lifecycle (self-deploy + project deploy).
  # The privilege/irreversibility crossing is audited at every phase.
  # =============================================================================
  DEPLOY_ACTIONS = %w[
    deploy.initiated deploy.dry_run deploy.succeeded deploy.failed
    deploy.unhealthy deploy.rolled_back deploy.skipped deploy.blocked deploy.completed
  ].freeze

  # =============================================================================
  # PLATFORM ALERT CHANNEL ACTIONS (component status plane, E8) — every set,
  # replace and clear of an alert-channel credential, and every change to the
  # plain alert settings. The row names the KEY and the actor, never the value.
  # Deliberately named without "delete"/"admin": those substrings put an action
  # under the audit service's strictest rate limit, and a clear that is
  # rate-limited out of the audit trail is exactly the gap this exists to close.
  # =============================================================================
  PLATFORM_ALERT_CHANNEL_ACTIONS = %w[
    platform.alert_channels.secret_set
    platform.alert_channels.secret_replaced
    platform.alert_channels.secret_cleared
    platform.alert_channels.settings_updated
  ].freeze

  # =============================================================================
  # AUDIT SELF-CORRECTION ACTIONS — appended by data migrations that need to
  # annotate a sealed historical row without rewriting it. `action` is a hashed
  # field in the tamper-evident chain (Audit::LogIntegrityService#build_hash_data),
  # so a rename would invalidate that row's integrity_hash and force re-chaining
  # everything after it. Instead a migration appends one NEW chained row per
  # corrected row and leaves the original untouched. See
  # db/migrate/*_reclassify_legacy_audit_actions.rb (IMP-85fb47438be6).
  #
  # WHERE THE RECLASSIFICATION PAYLOAD LIVES, stated precisely: old_values and
  # new_values are NOT in build_hash_data's covered field list — a row's own
  # `action`, `resource_type`, `resource_id` etc. are covered, but old_values/
  # new_values are not, so anyone with UPDATE on audit_logs can rewrite them
  # and verify_entry/verify_chain stay green (F1, IMP-85fb47438be6 review,
  # 2026-09-17). The correction migration therefore puts the authoritative
  # {from, to} pair in `metadata` (which IS hashed) and keeps old_values/
  # new_values only as a non-authoritative, human-readable duplicate. Being a
  # NEW row does not by itself make its payload tamper-evident — only landing
  # it in a hashed column does.
  # =============================================================================
  AUDIT_CORRECTION_ACTIONS = %w[
    audit.action_reclassified
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
    ACCOUNT_DATA_LIFECYCLE_ACTIONS,
    ACCOUNT_TERMINATION_ACTIONS,
    USER_DATA_LIFECYCLE_ACTIONS,
    DATA_DELETION_REQUEST_ACTIONS,
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
    AI_IMPROVEMENT_ACTIONS,
    AI_AGENT_TEAM_ACTIONS,
    DEVOPS_ACTIONS,
    SWARM_ACTIONS,
    DOCKER_ACTIONS,
    WORKER_ACTIONS,
    DEPLOY_ACTIONS,
    MCP_ACTIONS,
    INVITATION_ACTIONS,
    SITE_SETTING_ACTIONS,
    REPORT_REQUEST_ACTIONS,
    PLATFORM_ALERT_CHANNEL_ACTIONS,
    AUDIT_CORRECTION_ACTIONS
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

  # Catches the deprecated LEGACY_ACTIONS shape (ai_agents.index, ai_messages.create,
  # ...): an underscore-joined "ai_" namespace immediately followed by a dotted
  # verb. Deliberately narrow — it does not match ordinary flat tokens like
  # "ai_execution_cost" (no dot) or ordinary dotted tokens like
  # "ai.agents.create" (no underscore before the dot). Enforced by
  # register_actions (below) so an extension can never register a token in
  # this shape; that guard is what cannot be bypassed, NOT the module as a
  # whole — extension_actions (below) returns the live mutable accumulator by
  # reference, so code with a direct reference to it could still write
  # around register_actions entirely. No core token may match this pattern
  # either (pinned by spec/models/concerns/audit_actions_spec.rb against
  # CORE_ALL_ACTIONS) — as of IMP-85fb47438be6's 2026-09-17 rename of
  # AI_AGENT_TEAM_ACTIONS to the dot convention, that holds with no carve-out.
  LEGACY_ALIAS_PATTERN = /\Aai_\w+\./.freeze

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
      tokens = Array(actions).map(&:to_s).uniq
      assert_no_legacy_alias_shape!(tokens, namespace: namespace)
      @extension_actions[namespace.to_s] = tokens.freeze
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

    # The token's underscore/dot "sibling" — the same string with every "."
    # swapped for "_" (dotted tokens) or every "_" swapped for "." (flat
    # tokens) — or nil if the token has no dot/underscore to swap, or the swap
    # is a no-op (F3, IMP-85fb47438be6 review, 2026-09-17: a token with
    # NEITHER character, e.g. "payment", must not compare to itself — without
    # this nil guard every such core token reads as its own sibling and
    # register_actions("some_ext", %w[payment]) raised on nothing). The single
    # definition both assert_no_legacy_alias_shape! (below) and
    # spec/models/concerns/audit_actions_spec.rb call, so the implementation
    # and the spec enforce one rule, not two independently-maintained copies.
    def dot_underscore_sibling(token)
      token = token.to_s
      sibling = token.include?(".") ? token.tr(".", "_") : token.tr("_", ".")
      return nil if sibling == token

      sibling
    end

    # Raises if any of `tokens` has the deprecated ai_<domain>.<verb> alias shape
    # (LEGACY_ACTIONS' shape, removed IMP-85fb47438be6), or reintroduces an
    # underscore/dot sibling of an action that is already valid (core or any
    # other extension) — the same alias problem the other direction. Shared by
    # the extension-registration seam (this method's only caller) and pinned
    # directly by spec/models/concerns/audit_actions_spec.rb against the core
    # set, so both enforce the identical rule and this is not a lint-only check.
    def assert_no_legacy_alias_shape!(tokens, namespace:)
      pattern_hits = tokens.select { |t| t.match?(LEGACY_ALIAS_PATTERN) }
      if pattern_hits.any?
        raise ArgumentError,
              "AuditActions.register_actions(#{namespace.inspect}): legacy-shaped " \
              "action token(s) #{pattern_hits.inspect} match /\\Aai_\\w+\\./ — " \
              "no aliases, dot notation only"
      end

      existing = all_actions
      sibling_hits = tokens.select { |t| (sibling = dot_underscore_sibling(t)) && existing.include?(sibling) }
      return if sibling_hits.empty?

      raise ArgumentError,
            "AuditActions.register_actions(#{namespace.inspect}): action token(s) " \
            "#{sibling_hits.inspect} collide with an existing underscore/dot sibling"
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
      when "swarm" then SWARM_ACTIONS
      when "docker" then DOCKER_ACTIONS
      when "worker" then WORKER_ACTIONS
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
        AI_IMPROVEMENT_ACTIONS,
        AI_AGENT_TEAM_ACTIONS
      ].flatten.uniq
    end
  end

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

    def actions_for_domain(domain)
      AuditActions.actions_for_domain(domain)
    end

    def ai_actions
      AuditActions.ai_actions
    end
  end
end
