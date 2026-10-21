# frozen_string_literal: true

class Account < ApplicationRecord
  include Auditable

  # An account's own audit rows belong to itself.
  def audit_account
    self
  end

  # Account teardown (see #run_account_teardown): runs BEFORE every built-in
  # dependent: callback, so the order of the has_many declarations (core or
  # extension decorators) cannot matter. `users` is declared WITHOUT a dependent
  # option on purpose and `audit_logs` is restrict_with_exception: both are
  # destroyed/deleted by the teardown itself, after every other dependent and in
  # that order (the audit rows last, once their key-operation copies are written).
  around_destroy :run_account_teardown, prepend: true
  before_destroy :refuse_teardown_if_guarded, prepend: true
  # Vault KV entries have no DB row, so they are purged only once the deletion
  # has committed (a Vault delete cannot be rolled back).
  after_destroy_commit :purge_secret_store_entries

  # Associations
  has_many :invitations, dependent: :destroy
  has_many :account_delegations, class_name: "Account::Delegation", dependent: :destroy
  # restrict: the teardown deletes the account's audit rows itself (after copying the key-operation
  # rows to platform scope), so a plain destroy path can never orphan or silently nullify them.
  has_many :audit_logs, dependent: :restrict_with_exception
  has_many :webhook_events, dependent: :destroy
  has_many :workers, dependent: :destroy
  has_many :api_keys, dependent: :destroy
  has_many :webhook_endpoints, dependent: :destroy
  has_many :pages, dependent: :destroy

  # AI-related associations
  has_many :ai_providers, class_name: "Ai::Provider", dependent: :destroy
  has_many :ai_provider_credentials, class_name: "Ai::ProviderCredential", dependent: :destroy
  has_many :ai_data_sources, class_name: "Ai::DataSource", dependent: :destroy
  has_many :ai_data_source_credentials, class_name: "Ai::DataSourceCredential", dependent: :destroy
  has_many :ai_agents, class_name: "Ai::Agent", dependent: :destroy
  has_many :ai_conversations, class_name: "Ai::Conversation", dependent: :destroy
  has_many :ai_messages, through: :ai_conversations, source: :messages
  has_many :ai_agent_executions, class_name: "Ai::AgentExecution", dependent: :destroy
  has_many :ai_agent_teams, class_name: "Ai::AgentTeam", dependent: :destroy

  # AI Model Router associations (Phase 1 - Intelligent Routing)
  has_many :ai_model_routing_rules, class_name: "Ai::ModelRoutingRule", dependent: :destroy
  has_many :ai_routing_decisions, class_name: "Ai::RoutingDecision", dependent: :destroy
  has_many :ai_cost_optimization_logs, class_name: "Ai::CostOptimizationLog", dependent: :destroy

  # AI ROI & Analytics associations (Phase 1 - ROI Tracking)
  has_many :ai_roi_metrics, class_name: "Ai::RoiMetric", dependent: :destroy
  has_many :ai_cost_attributions, class_name: "Ai::CostAttribution", dependent: :destroy
  has_many :ai_provider_metrics, class_name: "Ai::ProviderMetric", dependent: :destroy


  # AI RAG System associations (Phase 3 - Knowledge-Augmented Agents)
  has_many :ai_knowledge_bases, class_name: "Ai::KnowledgeBase", dependent: :destroy
  has_many :ai_rag_queries, class_name: "Ai::RagQuery", dependent: :destroy
  has_many :ai_data_connectors, class_name: "Ai::DataConnector", dependent: :destroy

  # AI Knowledge Graph associations (Phase 5 - Knowledge Graphs + Hybrid RAG)
  has_many :ai_knowledge_graph_nodes, class_name: "Ai::KnowledgeGraphNode", dependent: :destroy
  has_many :ai_knowledge_graph_edges, class_name: "Ai::KnowledgeGraphEdge", dependent: :destroy
  has_many :ai_hybrid_search_results, class_name: "Ai::HybridSearchResult", dependent: :destroy

  # AI Multi-Agent Team associations (Phase 3 - Team Orchestration)
  has_many :ai_team_roles, class_name: "Ai::TeamRole", dependent: :destroy
  has_many :ai_team_executions, class_name: "Ai::TeamExecution", dependent: :destroy
  has_many :ai_team_templates, class_name: "Ai::TeamTemplate", dependent: :destroy

  # AI Agent Marketplace associations (core: browse & install)
  has_many :ai_agent_installations, class_name: "Ai::AgentInstallation", dependent: :destroy
  has_many :ai_agent_reviews, class_name: "Ai::AgentReview", dependent: :destroy

  # AI DevOps Templates associations (Phase 4 - CI/CD Templates)
  has_many :ai_devops_templates, class_name: "Ai::DevopsTemplate", dependent: :destroy
  has_many :ai_devops_template_installations, class_name: "Ai::DevopsTemplateInstallation", dependent: :destroy
  has_many :ai_pipeline_executions, class_name: "Ai::PipelineExecution", dependent: :destroy
  has_many :ai_deployment_risks, class_name: "Ai::DeploymentRisk", dependent: :destroy
  has_many :ai_code_reviews, class_name: "Ai::CodeReview", dependent: :destroy

  # AI Sandbox Testing associations (Phase 4 - Sandbox & Testing)
  has_many :ai_sandboxes, class_name: "Ai::Sandbox", dependent: :destroy
  has_many :ai_test_scenarios, class_name: "Ai::TestScenario", dependent: :destroy
  has_many :ai_mock_responses, class_name: "Ai::MockResponse", dependent: :destroy
  has_many :ai_test_runs, class_name: "Ai::TestRun", dependent: :destroy
  has_many :ai_performance_benchmarks, class_name: "Ai::PerformanceBenchmark", dependent: :destroy
  has_many :ai_ab_tests, class_name: "Ai::AbTest", dependent: :destroy

  # AI A2A (Agent-to-Agent) Protocol associations
  has_many :ai_agent_cards, class_name: "Ai::AgentCard", dependent: :destroy
  has_many :ai_a2a_tasks, class_name: "Ai::A2aTask", dependent: :destroy

  # AI Ralph Loops - Iterative development execution
  has_many :ai_ralph_loops, class_name: "Ai::RalphLoop", dependent: :destroy
  has_many :ai_campaigns, class_name: "Ai::Campaign", dependent: :destroy
  has_many :ai_campaign_proposals, class_name: "Ai::CampaignProposal", dependent: :destroy
  has_many :ai_delivery_runs, class_name: "Ai::DeliveryRun", dependent: :destroy
  has_many :ai_improvement_recommendations, class_name: "Ai::ImprovementRecommendation", dependent: :destroy

  # AI Task Reviews & Trajectories
  has_many :ai_task_reviews, class_name: "Ai::TaskReview", dependent: :destroy
  has_many :ai_trajectories, class_name: "Ai::Trajectory", dependent: :destroy

  # AI Code Factory
  has_many :ai_code_factory_risk_contracts, class_name: "Ai::CodeFactory::RiskContract", dependent: :destroy
  has_many :ai_code_factory_review_states, class_name: "Ai::CodeFactory::ReviewState", dependent: :destroy
  has_many :ai_code_factory_harness_gaps, class_name: "Ai::CodeFactory::HarnessGap", dependent: :destroy

  # AI Missions
  has_many :ai_missions, class_name: "Ai::Mission", dependent: :destroy
  # APO app-4/app-6. Beside the missions on purpose: a project OWNS missions
  # (Ai::Project has_many :missions, dependent: :nullify), so the project
  # association must not be the thing that deletes them — the account cascade
  # is. Without this association every reader re-derived the account scope with
  # an explicit account-scoped `where` on the model, which is exactly the shape
  # a cross-tenant read slips through when someone forgets the scope.
  has_many :ai_projects, class_name: "Ai::Project", foreign_key: "account_id", dependent: :destroy
  has_many :environments, class_name: "Ai::Environment", foreign_key: "account_id", dependent: :destroy
  has_many :ai_mission_approvals, class_name: "Ai::MissionApproval", dependent: :destroy

  # AI Kill Switch
  has_many :ai_kill_switch_events, class_name: "Ai::KillSwitchEvent", dependent: :destroy

  # AI Autonomy
  has_many :ai_agent_goals, class_name: "Ai::AgentGoal", dependent: :destroy
  has_many :ai_agent_observations, class_name: "Ai::AgentObservation", dependent: :destroy
  has_many :ai_intervention_policies, class_name: "Ai::InterventionPolicy", dependent: :destroy
  has_many :ai_promotion_grants, class_name: "Ai::PromotionGrant", dependent: :delete_all
  has_many :ai_agent_proposals, class_name: "Ai::AgentProposal", dependent: :destroy
  has_many :ai_agent_escalations, class_name: "Ai::AgentEscalation", dependent: :destroy
  has_many :ai_agent_feedbacks, class_name: "Ai::AgentFeedback", dependent: :destroy
  has_many :ai_governance_reports, class_name: "Ai::GovernanceReport", dependent: :destroy
  has_many :ai_collusion_indicators, class_name: "Ai::CollusionIndicator", dependent: :destroy

  # AI Governance & Compliance Suite (core — approvals/compliance are platform-operation
  # capabilities, not billing; they must work in core mode without the business extension)
  has_many :ai_compliance_policies, class_name: "Ai::CompliancePolicy", dependent: :destroy
  has_many :ai_policy_violations, class_name: "Ai::PolicyViolation", dependent: :destroy
  has_many :ai_approval_chains, class_name: "Ai::ApprovalChain", dependent: :destroy
  has_many :ai_approval_requests, class_name: "Ai::ApprovalRequest", dependent: :destroy
  has_many :ai_deferred_operations, class_name: "Ai::DeferredOperation", dependent: :destroy
  has_many :ai_data_classifications, class_name: "Ai::DataClassification", dependent: :destroy
  has_many :ai_data_detections, class_name: "Ai::DataDetection", dependent: :destroy
  has_many :ai_compliance_reports, class_name: "Ai::ComplianceReport", dependent: :destroy
  has_many :ai_compliance_audit_entries, class_name: "Ai::ComplianceAuditEntry", dependent: :destroy

  # AI Self-Learning & Coordination (Phase 1-4 AGI)
  has_many :ai_experience_replays, class_name: "Ai::ExperienceReplay", dependent: :destroy
  has_many :ai_goal_plans, class_name: "Ai::GoalPlan", dependent: :destroy
  has_many :ai_stigmergic_signals, class_name: "Ai::StigmergicSignal", dependent: :destroy
  has_many :ai_pressure_fields, class_name: "Ai::PressureField", dependent: :destroy
  has_many :ai_team_restructure_events, class_name: "Ai::TeamRestructureEvent", dependent: :destroy

  # AI Skill Lifecycle associations
  has_many :ai_skill_proposals, class_name: "Ai::SkillProposal", dependent: :destroy
  has_many :ai_skill_conflicts, class_name: "Ai::SkillConflict", dependent: :destroy
  has_many :ai_skill_versions, class_name: "Ai::SkillVersion", dependent: :destroy
  has_many :ai_skill_usage_records, class_name: "Ai::SkillUsageRecord", dependent: :destroy

  # AI Agent Topology & Discovery
  has_many :ai_agent_connections, class_name: "Ai::AgentConnection", dependent: :destroy
  has_many :ai_discovery_results, class_name: "Ai::DiscoveryResult", dependent: :destroy
  has_many :ai_memory_pools, class_name: "Ai::MemoryPool", dependent: :destroy
  has_many :ai_code_review_comments, class_name: "Ai::CodeReviewComment", dependent: :destroy
  has_many :ai_guardrail_configs, class_name: "Ai::GuardrailConfig", dependent: :destroy

  # AI Worktree Sessions - Parallel execution with git worktrees
  has_many :ai_worktree_sessions, class_name: "Ai::WorktreeSession", dependent: :destroy

  # Analytics & Reporting associations
  has_many :report_requests, dependent: :destroy

  # MCP (Model Context Protocol) associations
  has_many :mcp_servers, dependent: :destroy
  has_many :mcp_sessions, dependent: :destroy

  # Git Provider associations
  has_many :git_providers, class_name: "Devops::GitProvider", dependent: :destroy
  has_many :git_provider_credentials, class_name: "Devops::GitProviderCredential", dependent: :destroy
  has_many :git_repositories, class_name: "Devops::GitRepository", dependent: :destroy
  has_many :git_webhook_events, class_name: "Devops::GitWebhookEvent", dependent: :destroy
  has_many :account_git_webhook_configs, class_name: "Devops::AccountGitWebhookConfig", dependent: :destroy
  has_many :git_pipelines, class_name: "Devops::GitPipeline", dependent: :destroy
  has_many :git_pipeline_jobs, class_name: "Devops::GitPipelineJob", dependent: :destroy
  has_many :git_pipeline_approvals, class_name: "Devops::GitPipelineApproval", dependent: :destroy
  has_many :git_pipeline_schedules, class_name: "Devops::GitPipelineSchedule", dependent: :destroy
  has_many :git_runners, class_name: "Devops::GitRunner", dependent: :destroy

  # DevOps Pipeline Management associations
  has_many :devops_providers, class_name: "Devops::Provider", dependent: :destroy
  has_many :devops_pipelines, class_name: "Devops::Pipeline", dependent: :destroy
  has_many :devops_repositories, -> { from_devops }, class_name: "Devops::GitRepository", dependent: :destroy
  has_many :devops_integration_templates, class_name: "Devops::IntegrationTemplate", dependent: :destroy
  has_many :devops_integration_instances, class_name: "Devops::IntegrationInstance", dependent: :destroy
  has_many :devops_integration_credentials, class_name: "Devops::IntegrationCredential", dependent: :destroy
  has_many :devops_ai_configs, class_name: "Devops::AiConfig", dependent: :destroy
  has_many :devops_pipeline_templates, class_name: "Devops::PipelineTemplate", dependent: :destroy

  # Shared infrastructure associations
  has_many :shared_prompt_templates, class_name: "Shared::PromptTemplate", dependent: :destroy

  # File Storage associations
  has_many :file_storages, class_name: "FileManagement::Storage", dependent: :destroy
  has_many :file_objects, class_name: "FileManagement::Object", dependent: :destroy
  has_many :file_tags, class_name: "FileManagement::Tag", dependent: :destroy

  # Usage metering associations (usage_events/summaries/quotas) are billing functionality —
  # added by the business extension's account decorator.

  # Marketing associations are in extensions/marketing/server/app/decorators/models/account_decorator.rb

  # Chat Gateway associations
  has_many :chat_channels, class_name: "Chat::Channel", dependent: :destroy
  has_many :chat_sessions, through: :chat_channels, source: :sessions
  has_many :chat_messages, through: :chat_sessions, source: :messages
  has_many :chat_blacklists, class_name: "Chat::Blacklist", dependent: :destroy

  # DevOps Container Orchestration associations
  has_many :devops_container_templates, class_name: "Devops::ContainerTemplate", dependent: :destroy
  has_many :devops_container_instances, class_name: "Devops::ContainerInstance", dependent: :destroy
  has_many :devops_secret_references, class_name: "Devops::SecretReference", dependent: :destroy
  has_one :devops_resource_quota, class_name: "Devops::ResourceQuota", dependent: :destroy

  # Docker Swarm Management associations
  has_many :devops_swarm_clusters, class_name: "Devops::SwarmCluster", dependent: :destroy
  has_many :devops_swarm_nodes, through: :devops_swarm_clusters, source: :swarm_nodes
  has_many :devops_swarm_services, through: :devops_swarm_clusters, source: :swarm_services
  has_many :devops_swarm_stacks, through: :devops_swarm_clusters, source: :swarm_stacks
  has_many :devops_swarm_deployments, through: :devops_swarm_clusters, source: :swarm_deployments
  has_many :devops_swarm_events, through: :devops_swarm_clusters, source: :swarm_events

  # Docker Host Management associations
  has_many :devops_docker_hosts, class_name: "Devops::DockerHost", dependent: :destroy
  has_many :devops_docker_containers, through: :devops_docker_hosts, source: :docker_containers
  has_many :devops_docker_images, through: :devops_docker_hosts, source: :docker_images
  has_many :devops_docker_events, through: :devops_docker_hosts, source: :docker_events
  has_many :devops_docker_activities, through: :devops_docker_hosts, source: :docker_activities

  # Phase 2 — Kubernetes clusters (managed, multi-NodeInstance topology
  # via Devops::KubernetesNode). Cascade destroy mirrors the Docker
  # host pattern; nodes auto-cascade via the FK constraint set on the
  # devops_kubernetes_nodes table.
  has_many :devops_kubernetes_clusters, class_name: "Devops::KubernetesCluster", dependent: :destroy
  has_many :devops_kubernetes_nodes, through: :devops_kubernetes_clusters, source: :kubernetes_nodes

  # Community and Federation associations
  has_many :community_agents, class_name: "CommunityAgent", foreign_key: :owner_account_id, dependent: :destroy
  has_many :federation_partners, class_name: "FederationPartner", dependent: :destroy
  has_many :ai_dag_executions, class_name: "Ai::DagExecution", dependent: :destroy

  # System extension associations (M1 Self-Serve Hardening).
  # Guarded by the `defined?(::System::...)` seam so core mode (system
  # extension absent) degrades gracefully: declaring the association in core
  # mode would register a `dependent: :destroy` callback that NameErrors the
  # moment an Account is destroyed. Full mode declares it normally; core mode
  # falls back to an empty collection that never raises on read.
  if defined?(::System::ProviderCredential)
    has_many :system_provider_credentials, class_name: "System::ProviderCredential", dependent: :destroy
  else
    def system_provider_credentials = []
  end

  # Account-owned rows that carry an account_id FK with no ON DELETE: removed by
  # the account teardown (see #run_account_teardown). delete_all is used only
  # for leaf log/event tables with no callbacks and no inbound FKs. Roles are
  # included because the DB cascades them but their role_permissions do not.
  has_many :roles, dependent: :destroy
  has_many :ai_file_locks, class_name: "Ai::FileLock", dependent: :destroy
  has_many :account_terminations, class_name: "Account::Termination", dependent: :destroy
  has_many :ai_agent_identities, class_name: "Ai::AgentIdentity", dependent: :destroy
  has_many :ai_agent_model_performances, class_name: "Ai::AgentModelPerformance", dependent: :destroy
  has_many :ai_agent_privilege_policies, class_name: "Ai::AgentPrivilegePolicy", dependent: :destroy
  has_many :ai_agent_templates, class_name: "Ai::AgentTemplate", dependent: :destroy
  has_many :ai_agui_events, class_name: "Ai::AguiEvent", dependent: :delete_all
  has_many :ai_agui_sessions, class_name: "Ai::AguiSession", dependent: :destroy
  has_many :ai_behavioral_fingerprints, class_name: "Ai::BehavioralFingerprint", dependent: :destroy
  has_many :ai_circuit_breakers, class_name: "Ai::CircuitBreaker", dependent: :destroy
  has_many :ai_compound_learnings, class_name: "Ai::CompoundLearning", dependent: :destroy
  has_many :ai_context_access_logs, class_name: "Ai::ContextAccessLog", dependent: :delete_all
  has_many :ai_delegation_policies, class_name: "Ai::DelegationPolicy", dependent: :destroy
  has_many :ai_encrypted_messages, class_name: "Ai::EncryptedMessage", dependent: :delete_all
  has_many :ai_evaluation_results, class_name: "Ai::EvaluationResult", dependent: :destroy
  has_many :ai_execution_events, class_name: "Ai::ExecutionEvent", dependent: :delete_all
  has_many :ai_execution_traces, class_name: "Ai::ExecutionTrace", dependent: :destroy
  has_many :ai_mcp_app_instances, class_name: "Ai::McpAppInstance", dependent: :destroy
  has_many :ai_mcp_apps, class_name: "Ai::McpApp", dependent: :destroy
  has_many :ai_persistent_contexts, class_name: "Ai::PersistentContext", dependent: :destroy
  has_many :ai_quarantine_records, class_name: "Ai::QuarantineRecord", dependent: :destroy
  has_many :ai_remediation_logs, class_name: "Ai::RemediationLog", dependent: :delete_all
  has_many :ai_role_profiles, class_name: "Ai::RoleProfile", dependent: :destroy
  has_many :ai_security_audit_trails, class_name: "Ai::SecurityAuditTrail", dependent: :delete_all
  has_many :ai_shared_knowledges, class_name: "Ai::SharedKnowledge", dependent: :destroy
  has_many :ai_skill_recipe_runs, class_name: "Ai::SkillRecipeRun", dependent: :destroy
  has_many :ai_skills, class_name: "Ai::Skill", dependent: :destroy
  has_many :ai_task_complexity_assessments, class_name: "Ai::TaskComplexityAssessment", dependent: :destroy
  has_many :data_deletion_requests, class_name: "DataManagement::DeletionRequest", dependent: :destroy
  has_many :data_export_requests, class_name: "DataManagement::ExportRequest", dependent: :destroy
  has_many :data_retention_policies, class_name: "DataManagement::RetentionPolicy", dependent: :destroy
  has_many :devops_port_allocations, class_name: "Devops::PortAllocation", dependent: :destroy
  has_many :knowledge_base_articles, class_name: "KnowledgeBase::Article", dependent: :destroy
  has_many :scheduled_reports, class_name: "ScheduledReport", dependent: :destroy
  has_many :security_secrets, class_name: "Security::Secret", dependent: :destroy
  has_many :terms_acceptances, class_name: "TermsAcceptance", dependent: :destroy
  has_many :user_consents, class_name: "UserConsent", dependent: :destroy

  # Destroyed by #run_account_teardown after every other dependent (many
  # account-owned rows hold RESTRICT / no-on_delete FKs to users). No
  # `dependent:` here: a declaration-order callback would run too early for
  # extension associations declared later.
  has_many :users

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :subdomain, format: { with: /\A[a-z0-9\-]+\z/, message: "can only contain lowercase letters, numbers, and hyphens" },
                       length: { minimum: 3, maximum: 30 },
                       uniqueness: { case_sensitive: false },
                       allow_blank: true
  validates :status, presence: true, inclusion: { in: %w[active suspended cancelled] }

  validate :settings_free_of_reserved_keys, if: :will_save_change_to_settings?

  # Note: settings is now a native JSON column, no explicit serialization needed

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :suspended, -> { where(status: "suspended") }
  scope :cancelled, -> { where(status: "cancelled") }

  # Callbacks
  before_validation :normalize_subdomain
  after_initialize :set_defaults
  # REMOVED (IMP-e85001682ade): after_create :broadcast_customer_created and
  # after_update :broadcast_customer_updated. They drove
  # #broadcast_customer_change, whose audience query selected
  # roles.name IN ("system.admin", "account.manager") — neither of which is a
  # Permissions::ROLES key, so the query returned no rows and the broadcast
  # reached nobody, ever. It was also a no-op in test by an explicit guard, so
  # nothing observed the emptiness.
  #
  # Deleted rather than repaired because there is nothing to repair FOR: the
  # audience was empty by construction in every environment, and no core
  # consumer of the customer_updates_<id> stream exists — no core spec, no core
  # frontend subscriber, no extension reference.
  #
  # A repair was technically available (core role keys owner/admin/super_admin
  # name no extension), so the core -> extension rule is NOT what forced this.
  # It is a supporting note: the working implementation of the idea lives in the
  # business extension (CustomerBroadcastAudience), which resolves its audience
  # by PERMISSION rather than by role name, shares no mechanism with this copy,
  # and is unaffected by its removal.
  # Environment campaign, increment 1: the default environments (dev, ci,
  # staging, ops, prod) exist BEFORE any extension bootstrap runs, because the
  # templates that bootstrap creates inherit the account's default one.
  # Declared first so it runs first.
  after_create_commit :ensure_default_environments

  # M1 Self-Serve: every new account gets per-account provider/regions/
  # instance-types/templates wired up so the activation funnel can spin
  # up Pro Cloud nodes without operator intervention. Failures are logged
  # but don't roll back account creation — surfaced via monitoring.
  after_create_commit :run_account_bootstrap

  # The Account#settings key holding the account-wide DEFAULT SDWAN network
  # for provisioning (IMP-94728a788498). When the chosen NodeTemplate says
  # nothing about a network, composed provisions fall back to this id so
  # fabric membership is the account's default posture rather than a
  # per-template opt-in. DB-driven config: operators set it through the
  # existing account-settings surface (SettingsUpdateService merges arbitrary
  # keys into `settings`); no seed, env var, or hardcoded value writes it.
  # A plain data key — the resolution semantics (opt-out sentinel, fail-loud
  # bucketing) live with the resolver, Ai::Provisioning::PlanComposerService.
  DEFAULT_SDWAN_NETWORK_SETTING = "default_sdwan_network_id"

  # --- Account teardown seam -------------------------------------------------
  # Account teardown marker. Row-level guards that protect a record during
  # normal operation (e.g. "cannot delete the only default credential") must
  # yield while the whole account is being destroyed; they ask
  # `Account.tearing_down?(account_id)`. Execution-state local, keyed by account
  # id, and cleared in an ensure so a failed destroy leaves the guards intact.
  def self.tearing_down?(account_id)
    account_id.present? && teardown_ids.include?(account_id)
  end

  # The operator performing a destroy!, recorded in the account.destroyed audit row.
  # A User, or an explicit String label (e.g. "rake:accounts:purge"). When unset the audit
  # row falls back to the OS process ("unattributed:process:<login>@<host>"), so it is never
  # anonymous but is plainly marked unattributed. Every destroy ENTRY POINT (controller, rake task,
  # job) must set `account.teardown_actor = current_user` (or an explicit label) before destroy!.
  attr_writer :teardown_actor

  # Associations holding keys / credentials whose ids the teardown audit records
  # (ids only, never material). An extension registers its own from a to_prepare block.
  def self.register_teardown_key_source(association)
    AccountTeardownAudit.key_sources[association.to_sym] = association.to_sym
  end

  def self.teardown_ids
    ActiveSupport::IsolatedExecutionState[:account_teardown_ids] ||= []
  end

  # Pre-flight refusals, run before the teardown has any side effect. An
  # extension registers one from a to_prepare block (the list is a class-level
  # ivar and a reload wipes it), like register_reserved_setting_key. The block
  # receives the account and returns nil/false/[] to allow, or a String / Array
  # of Strings (reasons) to refuse; a refusal makes `destroy` return false.
  # Registering under the same key again REPLACES the guard (a to_prepare block
  # re-runs on every reload without piling up duplicates).
  def self.teardown_guards
    @teardown_guards ||= {}
  end

  # `covers:` lists the [table, column] pairs the guard makes safe by refusing
  # while such rows exist; the FK coverage spec treats them as covered.
  def self.register_teardown_guard(key = nil, covers: [], &block)
    raise ArgumentError, "a teardown guard needs a block" unless block

    guard_key = key || block
    teardown_guards[guard_key] = block
    teardown_guard_covers[guard_key] = covers.map { |t, c| [ t.to_s, c.to_s ] }
  end

  def self.teardown_guard_covers
    @teardown_guard_covers ||= {}
  end

  # FK columns onto users from tables that ALSO hold shared rows (account_id
  # NULL) and that nothing on User deletes/nullifies by that column. Account-
  # owned rows are removed by the account's own dependents, but a SHARED row
  # (e.g. a platform-wide agent or repository) created by one of the account's
  # users would block deleting that user with a raw FK error. A nullable
  # attribution column is nullified; a NOT NULL one makes the teardown refuse,
  # telling the operator to reassign those rows first. Computed from
  # the schema once; a schema change needs a restart anyway.
  def self.shared_user_reference_edges
    @shared_user_reference_edges ||= begin
      conn = connection
      handled = User.reflect_on_all_associations
                    .select { |r| %i[destroy delete_all nullify restrict_with_error restrict_with_exception].include?(r.options[:dependent]) }
                    .filter_map { |r| (k = (r.klass rescue nil)) && [ k.table_name, r.foreign_key.to_s ] }
      conn.tables.flat_map { |t| conn.foreign_keys(t) }
          .select { |f| f.to_table == "users" && !%i[cascade nullify].include?(f.on_delete) }
          .select { |f| conn.columns(f.from_table).any? { |c| c.name == "account_id" && c.null } }
          .map { |f| [ f.from_table, f.column.to_s ] }
          .reject { |edge| handled.include?(edge) }
          .map { |table, column| [ table, column, conn.columns(table).find { |c| c.name == column }.null ] }
    end
  end

  # Shared rows' NULLABLE attribution columns are nullified by the teardown ...
  def self.shared_user_nullable_edges
    shared_user_reference_edges.select { |_t, _c, nullable| nullable }.map { |t, c, _| [ t, c ] }
  end

  # ... and a NOT NULL one cannot be, so the teardown refuses while such rows exist.
  def self.shared_user_required_edges
    shared_user_reference_edges.reject { |_t, _c, nullable| nullable }.map { |t, c, _| [ t, c ] }
  end

  def self.teardown_guard_coverage
    teardown_guard_covers.values.flatten(1)
  end

  # Keys of #settings that an owner (an extension included) has RESERVED against
  # account-level writes: key => reason. #settings is merged from a caller-supplied
  # hash by every account-settings writer (PUT /api/v1/settings, the accounts
  # controller), gated only on a tenant-level permission, so a key that means a
  # platform-operator decision (a grant read by a platform-wide reader) must not be
  # settable there. Core names no key; owners register theirs from a to_prepare
  # block (the registry is a class-level ivar and a reload wipes it).
  #
  # A reserved key can be REMOVED, and an unrelated edit to an account that
  # already holds one is not blocked: only adding it or changing its value is.
  # That is how a migration clears residue, and it does not make an old value
  # suddenly un-saveable.
  def self.reserved_setting_keys
    @reserved_setting_keys ||= {}
  end

  def self.register_reserved_setting_key(key, reason:)
    reserved_setting_keys[key.to_s] = reason.to_s
  end

  # Instance methods
  def active?
    status == "active"
  end

  # Raw configured value of DEFAULT_SDWAN_NETWORK_SETTING (string or symbol
  # key; jsonb round-trips strings, in-memory writers may use symbols), or
  # nil. Deliberately UNCLASSIFIED: whether a value is usable, an opt-out,
  # or a loud misconfiguration is the resolver's single-copy decision.
  def default_sdwan_network_setting
    s = settings
    return nil unless s.is_a?(Hash)

    s[DEFAULT_SDWAN_NETWORK_SETTING] || s[DEFAULT_SDWAN_NETWORK_SETTING.to_sym]
  end

  def suspended?
    status == "suspended"
  end

  def cancelled?
    status == "cancelled"
  end

  def ai_suspended?
    ai_suspended == true
  end

  def suspend_ai!(at: Time.current)
    update!(ai_suspended: true, ai_suspended_at: at)
  end

  def resume_ai!
    update!(ai_suspended: false, ai_suspended_at: nil)
  end

  def owner
    # Find the first user with the owner role in this account. ONE name format:
    # Role#name is the canonical key.
    users.joins(user_roles: :role)
         # "account.owner" was here too and matched nothing — Role#name holds
         # the canonical key, and no CATALOG role has ever carried that name
         # (IMP-e85001682ade). Said of the catalog deliberately: account-scoped
         # custom roles are created through the API and are unique only per
         # account_id, so a row literally named "account.owner" is creatable.
         # It was inert rather than harmful because "owner" sits beside it in
         # the union, which is precisely why it survived.
         .where(roles: { name: [ "owner" ] })
         .first
  end

  def managers
    users.joins(user_roles: :role).where(roles: { name: "manager" })
  end

  def current_subscription
    return nil unless respond_to?(:subscription)
    subscription
  end

  def has_active_subscription?
    return false unless respond_to?(:subscription)
    subscription&.active? || false
  end

  # M4 Enterprise Polish — single source of truth for "the currently
  # billing-active subscription" used by feature-gate readers like the
  # mission second-signature gate, CostCapGuard, audit export, and IP
  # allowlist. Returns nil when:
  #   * the account doesn't carry the `subscription` association at all
  #     (core mode without business loaded), or
  #   * the subscription exists but isn't in `active`/`trialing` state
  #     (past_due/cancelled/unpaid all gate features off).
  # Callers are expected to chain `.plan.features` / `.plan.limits` and
  # treat any nil link as "feature unavailable" (fail-closed for the
  # feature, fail-open for the existing flow).
  def active_subscription
    return nil unless respond_to?(:subscription)
    sub = subscription
    return nil if sub.nil?
    sub.active? ? sub : nil
  end

  def subscription_status
    return "none" unless respond_to?(:subscription)
    subscription&.status || "none"
  end

  def on_trial?
    return false unless respond_to?(:subscription)
    subscription&.on_trial? || false
  end

  def system_worker_token
    Worker.system_worker&.token
  end

  def has_system_worker?
    Worker.system_worker.present?
  end

  # M2 Self-Serve Hardening (BYOC): onboarding state lives in the
  # platform-managed `metadata` JSONB. The FirstRunWizard reads
  # `onboarding_completed?` to decide whether to redirect a freshly-
  # registered account into the BYOC flow; `mark_onboarding_complete!`
  # is invoked by Api::V1::OnboardingController#complete after the
  # operator either configures provider creds or skips.
  def onboarding_completed?
    return false unless metadata.is_a?(Hash)
    metadata["onboarding_completed_at"].present?
  end

  def onboarding_completed_at
    return nil unless metadata.is_a?(Hash)
    raw = metadata["onboarding_completed_at"]
    return nil if raw.blank?

    case raw
    when Time, DateTime, ActiveSupport::TimeWithZone then raw
    when String
      Time.iso8601(raw) rescue Time.parse(raw) rescue nil
    end
  end

  def mark_onboarding_complete!(at: Time.current, provider_credential_id: nil, provider_type: nil)
    base = (metadata.is_a?(Hash) ? metadata : {}).merge(
      "onboarding_completed_at" => at.iso8601
    )
    base["onboarding_provider_credential_id"] = provider_credential_id if provider_credential_id.present?
    base["onboarding_provider_type"] = provider_type if provider_type.present?
    self.metadata = base
    save!
  end

  # Setup-wizard state (superset of onboarding). Per-step completion is tracked
  # under metadata["setup"]["steps"][<key>]["completed_at"] so the registry-driven
  # wizard (Setup::StepRegistry) can resume by skipping completed steps. Only the
  # completion *stamp* is stored here — never the step's payload, which may carry
  # secrets (those go to their owning settings/Vault via the step's endpoint).
  def setup_state
    return {} unless metadata.is_a?(Hash)

    metadata["setup"].is_a?(Hash) ? metadata["setup"] : {}
  end

  def setup_step_completed?(key)
    setup_state.dig("steps", key.to_s, "completed_at").present?
  end

  def setup_step_completed_at(key)
    raw = setup_state.dig("steps", key.to_s, "completed_at")
    return nil if raw.blank?

    Time.iso8601(raw) rescue Time.parse(raw) rescue nil
  end

  def mark_setup_step!(key, at: Time.current)
    base  = metadata.is_a?(Hash) ? metadata.deep_dup : {}
    setup = base["setup"].is_a?(Hash) ? base["setup"] : {}
    steps = setup["steps"].is_a?(Hash) ? setup["steps"] : {}

    steps[key.to_s] = { "completed_at" => at.iso8601 }
    setup["steps"]  = steps
    base["setup"]   = setup
    self.metadata   = base
    save!
  end

  # Incremental per-extension configuration (Phase 4): an extension's setup steps
  # are tracked together under metadata["setup"]["extensions"][<slug>]["configured_at"],
  # so a newly-added/enabled extension surfaces a non-blocking "configure X" prompt
  # until stamped. Re-enabling a previously-configured extension keeps its stamp.
  def extension_configured?(slug)
    setup_state.dig("extensions", slug.to_s, "configured_at").present?
  end

  def extension_configured_at(slug)
    raw = setup_state.dig("extensions", slug.to_s, "configured_at")
    return nil if raw.blank?

    Time.iso8601(raw) rescue Time.parse(raw) rescue nil
  end

  def mark_extension_configured!(slug, at: Time.current)
    base  = metadata.is_a?(Hash) ? metadata.deep_dup : {}
    setup = base["setup"].is_a?(Hash) ? base["setup"] : {}
    exts  = setup["extensions"].is_a?(Hash) ? setup["extensions"] : {}

    exts[slug.to_s]   = { "configured_at" => at.iso8601 }
    setup["extensions"] = exts
    base["setup"]     = setup
    self.metadata     = base
    save!
  end

  private

  # Teardown, inside the destroy transaction and BEFORE any built-in dependent
  # callback (this is a prepended around_destroy; the code before `yield` is
  # the only place users can still be destroyed — after `yield` the account row
  # is already deleted). Order:
  #   0. (refuse_teardown_if_guarded, a before_destroy that runs first)
  #      pre-flight guards: registered ones + restrict_with_* associations —
  #      a refusal aborts before ANY side effect
  #   1. mark tearing down (yields the "only default credential" style guards)
  #   3. every reflected dependent: :destroy / :delete_all / :nullify
  #      association except users/audit_logs (core and extensions alike)
  #   4. destroy the users
  #   5. delete the audit rows last, so nothing written during teardown remains
  #   6. yield (the account row itself)
  def run_account_teardown
    self.class.teardown_ids << id
    begin
      audit = AccountTeardownAudit.new(self, actor: @teardown_actor)
      audit.snapshot!
      teardown_reflected_dependents
      users.destroy_all
      # Fail closed, inside this transaction: platform-scoped copies of the key-operation
      # audit rows and the account.destroyed record are written BEFORE the account's own
      # audit rows are deleted; if that raises, nothing is deleted.
      audit.record!
      # Not `audit_logs.delete_all`: on a has_many without a dependent option
      # that NULLIFIES account_id (NOT NULL) instead of deleting the rows.
      AuditLog.where(account_id: id).delete_all
      # A loaded audit_logs target would still look non-empty to the restrict check below.
      association(:audit_logs).reset
      yield
    ensure
      idx = self.class.teardown_ids.index(id)
      self.class.teardown_ids.delete_at(idx) if idx
    end
  end

  def purge_secret_store_entries
    count = Security::SecretStore.purge_account(account_id: id)
    Rails.logger.info("[Account.teardown] purged #{count} secret store entries for account #{id}") if count.positive?
  rescue StandardError => e
    # Visible, never values: the account id and the error class only. The deletion has
    # committed and cannot be undone, so the purge is recorded for the worker sweep to retry.
    Rails.logger.error("[Account.teardown] secret store purge FAILED for account #{id}: #{e.class}")
    record_purge_retry(e)
  end

  # The retry record is best-effort by necessity (this runs after commit and cannot raise into
  # the caller), but a failure to write it is logged loudly so it is never silent.
  def record_purge_retry(error)
    PlatformPurgeTask.enqueue!(kind: "secret_store_account", subject_id: id, error: error)
  rescue StandardError => e
    Rails.logger.error("[Account.teardown] purge retry record FAILED for account #{id}: #{e.class}; " \
                       "vault entries under the account path may be orphaned")
  end

  # Vault entries exist only in Vault and the purge runs after commit: refuse up front when
  # Vault is the active backend but is not healthy, rather than orphan them.
  def vault_unhealthy_refusal
    return unless Security::SecretStore.backend == :vault
    return if Security::VaultClient.instance.healthy?

    "Cannot delete account: Vault is the active secret backend but is not healthy, so its secrets could not be purged"
  rescue StandardError
    "Cannot delete account: Vault is the active secret backend but is not healthy, so its secrets could not be purged"
  end

  # Pre-flight (before_destroy, prepended so it halts before the teardown
  # marker and every side effect): a refusal makes `destroy` return false.
  def refuse_teardown_if_guarded
    reasons = teardown_refusals
    reasons.each { |reason| errors.add(:base, reason) }
    throw :abort if reasons.any?
  end

  def shared_row_refusals
    user_ids = users.pluck(:id)
    return [] if user_ids.empty?

    conn = self.class.connection
    self.class.shared_user_required_edges.filter_map do |table, column|
      tbl = Arel::Table.new(table)
      query = tbl.project(Arel.sql("1")).where(tbl[:account_id].eq(nil).and(tbl[column].in(user_ids))).take(1)
      next unless conn.select_value(query.to_sql).present?

      "Cannot delete account: shared #{table.humanize.downcase} (no owning account) still reference its users " \
        "via #{column}; reassign them first"
    end
  end

  def teardown_refusals
    reasons = self.class.reflect_on_all_associations
                  .select { |r| %i[restrict_with_error restrict_with_exception].include?(r.options[:dependent]) }
                  .reject { |r| r.name == :audit_logs } # deleted by the teardown itself
                  .select { |r| association(r.name).reader.then { |v| v.respond_to?(:exists?) ? v.exists? : v.present? } }
                  .map { |r| "Cannot delete account with existing #{r.name.to_s.humanize.downcase}" }
    reasons.concat(shared_row_refusals)
    reasons << vault_unhealthy_refusal
    self.class.teardown_guards.each_value { |guard| reasons.concat(Array(guard.call(self)).compact) }
    reasons.compact
  end

  # The ONLY User associations that restrict removing a single member and that
  # the account teardown deletes first (a spec fails if User gains another
  # restrict_with_* association that is not consciously listed here).
  TEARDOWN_USER_RESTRICTED_ASSOCIATIONS = %i[database_restores kb_attachments kb_comments kb_workflows].freeze

  # Runs every teardown step (core and extension) whatever its declaration
  # order. Steps are the reflected dependents plus the rows that restrict a
  # single user's removal (User `restrict_with_*` associations): removing ONE
  # member must refuse, but tearing the whole account down deletes them.
  # Tables reference each other (agents <- goals, ...), so a step that hits a
  # foreign key / refusing guard is rolled back to its savepoint and retried
  # after the others; passes repeat while any progress is made, and the first
  # error is raised when none is.
  def teardown_reflected_dependents
    steps = self.class.reflect_on_all_associations
                .select { |r| %i[destroy delete_all nullify].include?(r.options[:dependent]) }
                .reject { |r| %i[users audit_logs].include?(r.name) }
                .to_h { |r| [ r.name, -> { association(r.name).handle_dependency } ] }
    user_ids = users.pluck(:id)
    TEARDOWN_USER_RESTRICTED_ASSOCIATIONS.map { |name| User.reflect_on_association(name) }.each do |r|
      steps[:"user_#{r.name}"] = lambda do
        reparent_foreign_replies(user_ids) if r.klass == KnowledgeBase::Comment
        r.klass.where(r.foreign_key => user_ids).destroy_all
      end
    end
    self.class.shared_user_nullable_edges.each do |table, column|
      steps[:"shared_#{table}_#{column}"] = lambda do
        tbl = Arel::Table.new(table)
        self.class.connection.update(
          Arel::UpdateManager.new.table(tbl).set([ [ tbl[column], nil ] ])
                             .where(tbl[:account_id].eq(nil).and(tbl[column].in(user_ids))).to_sql
        )
      end
    end

    until steps.empty?
      failures = {}
      steps.each do |name, step|
        self.class.transaction(requires_new: true) { step.call }
      rescue ActiveRecord::InvalidForeignKey, ActiveRecord::RecordNotDestroyed => e
        association(name).reset if self.class.reflect_on_association(name)
        failures[name] = e
      end
      raise failures.values.first if failures.size == steps.size

      steps = steps.slice(*failures.keys)
    end
  end

  # Comments are destroyed with their replies (dependent: :destroy); a reply by
  # a user OUTSIDE this account on a shared article must survive, so detach it
  # to top level first (parent_id is nullable).
  def reparent_foreign_replies(user_ids)
    mine = KnowledgeBase::Comment.where(author_id: user_ids).select(:id)
    KnowledgeBase::Comment.where(parent_id: mine).where.not(author_id: user_ids).update_all(parent_id: nil)
  end

  # An account's own deletion audit row would reference the account whose row
  # is about to be deleted (audit_logs.account_id has no on_delete), so the
  # account's destroy is the one record that never audits itself.
  def log_record_deletion; end

  def settings_free_of_reserved_keys
    return if self.class.reserved_setting_keys.empty?

    now = settings.is_a?(Hash) ? settings.stringify_keys : {}
    before = settings_in_database.is_a?(Hash) ? settings_in_database.stringify_keys : {}
    self.class.reserved_setting_keys.each do |key, reason|
      next unless now.key?(key)
      next if before.key?(key) && before[key] == now[key]

      errors.add(:settings, "#{key} is reserved and cannot be set here: #{reason}")
    end
  end

  def normalize_subdomain
    self.subdomain = subdomain&.downcase&.strip
  end

  # M1 Self-Serve: bootstrap System extension state per-account. Wrapped
  # in rescue so a transient failure (e.g., system extension disabled)
  # doesn't roll back account creation — surface via monitoring instead.
  def ensure_default_environments
    Ai::Environment.ensure_defaults_for!(self)
  rescue StandardError => e
    Rails.logger.error(
      "[Account.after_create_commit] default environments failed for account #{id}: #{e.class}: #{e.message}"
    )
  end

  def run_account_bootstrap
    return unless defined?(::System::AccountBootstrapService)

    ::System::AccountBootstrapService.call(self)
  rescue StandardError => e
    Rails.logger.error(
      "[Account.after_create_commit] AccountBootstrapService failed for account #{id}: #{e.class}: #{e.message}"
    )
  end

  def set_defaults
    self.settings ||= {}
    # Read-write guard for the platform-managed metadata bag (M2 BYOC
    # onboarding flag, etc.). NOT NULL with default {} at the DB level,
    # but normalize new in-memory records too.
    self.metadata ||= {} if has_attribute?(:metadata)
  end

  %i[api_keys ai_provider_credentials ai_data_source_credentials git_provider_credentials
     devops_integration_credentials].each do |assoc|
    register_teardown_key_source(assoc)
  end
end
