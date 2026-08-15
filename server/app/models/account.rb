# frozen_string_literal: true

class Account < ApplicationRecord
  include Auditable

  # An account's own audit rows belong to itself.
  def audit_account
    self
  end

  # Associations
  has_many :users, dependent: :destroy
  has_many :invitations, dependent: :destroy
  has_many :account_delegations, class_name: "Account::Delegation", dependent: :destroy
  has_many :audit_logs, dependent: :destroy
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
  has_many :ai_mission_approvals, class_name: "Ai::MissionApproval", dependent: :destroy

  # AI Kill Switch
  has_many :ai_kill_switch_events, class_name: "Ai::KillSwitchEvent", dependent: :destroy

  # AI Autonomy
  has_many :ai_agent_goals, class_name: "Ai::AgentGoal", dependent: :destroy
  has_many :ai_agent_observations, class_name: "Ai::AgentObservation", dependent: :destroy
  has_many :ai_intervention_policies, class_name: "Ai::InterventionPolicy", dependent: :destroy
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
  has_many :ai_self_challenges, class_name: "Ai::SelfChallenge", dependent: :destroy
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

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :subdomain, format: { with: /\A[a-z0-9\-]+\z/, message: "can only contain lowercase letters, numbers, and hyphens" },
                       length: { minimum: 3, maximum: 30 },
                       uniqueness: { case_sensitive: false },
                       allow_blank: true
  validates :status, presence: true, inclusion: { in: %w[active suspended cancelled] }

  # Note: settings is now a native JSON column, no explicit serialization needed

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :suspended, -> { where(status: "suspended") }
  scope :cancelled, -> { where(status: "cancelled") }

  # Callbacks
  before_validation :normalize_subdomain
  after_initialize :set_defaults
  after_create :broadcast_customer_created
  after_update :broadcast_customer_updated, if: :saved_changes?
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
    # Find the first user with owner role in this account
    # Check for both possible role name formats
    users.joins(user_roles: :role)
         .where(roles: { name: [ "owner", "account.owner" ] })
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

  def normalize_subdomain
    self.subdomain = subdomain&.downcase&.strip
  end

  # M1 Self-Serve: bootstrap System extension state per-account. Wrapped
  # in rescue so a transient failure (e.g., system extension disabled)
  # doesn't roll back account creation — surface via monitoring instead.
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

  def broadcast_customer_created
    broadcast_customer_change("created")
  end

  def broadcast_customer_updated
    broadcast_customer_change("updated")
  end

  def broadcast_customer_change(event_type)
    # Skip broadcasting in test environment to avoid database query issues
    return if Rails.env.test?

    # Broadcast to all admin users
    data = {
      type: "customer_updated",
      event: event_type,
      customer_id: id,
      timestamp: Time.current.iso8601
    }

    # Find all admin accounts that should receive this update
    # Optimized: Only fetch IDs and broadcast directly without loading Account objects
    admin_account_ids = User.joins(:account, user_roles: :role)
                            .where(roles: { name: [ "system.admin", "account.manager" ] })
                            .distinct.pluck(:account_id)

    admin_account_ids.each do |admin_account_id|
      ActionCable.server.broadcast("customer_updates_#{admin_account_id}", data)
    end
  rescue StandardError => e
    Rails.logger.error "Failed to broadcast customer change: #{e.message}"
  end
end
