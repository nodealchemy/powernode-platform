# frozen_string_literal: true

class Account < ApplicationRecord
  include Auditable

  # Associations
  has_many :users, dependent: :destroy
  has_many :invitations, dependent: :destroy
  has_many :account_delegations, class_name: "Account::Delegation", dependent: :destroy
  has_many :audit_logs, dependent: :destroy
  has_many :webhook_events, dependent: :destroy
  has_many :workers, dependent: :destroy
  has_many :api_keys, dependent: :destroy
  has_many :webhook_endpoints, dependent: :destroy

  # AI-related associations
  has_many :ai_providers, class_name: "Ai::Provider", dependent: :destroy
  has_many :ai_provider_credentials, class_name: "Ai::ProviderCredential", dependent: :destroy
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

  # AI Workflow associations
  has_many :ai_workflows, class_name: "Ai::Workflow", dependent: :destroy
  has_many :ai_workflow_runs, class_name: "Ai::WorkflowRun", dependent: :destroy

  # AI A2A (Agent-to-Agent) Protocol associations
  has_many :ai_agent_cards, class_name: "Ai::AgentCard", dependent: :destroy
  has_many :ai_a2a_tasks, class_name: "Ai::A2aTask", dependent: :destroy

  # AI Ralph Loops - Iterative development execution
  has_many :ai_ralph_loops, class_name: "Ai::RalphLoop", dependent: :destroy

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

  # Usage Tracking associations
  has_many :usage_events, dependent: :destroy
  has_many :usage_summaries, dependent: :destroy
  has_many :usage_quotas, dependent: :destroy

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

  # Community and Federation associations
  has_many :community_agents, class_name: "CommunityAgent", foreign_key: :owner_account_id, dependent: :destroy
  has_many :federation_partners, class_name: "FederationPartner", dependent: :destroy
  has_many :ai_dag_executions, class_name: "Ai::DagExecution", dependent: :destroy

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

  # Instance methods
  def active?
    status == "active"
  end

  def suspended?
    status == "suspended"
  end

  def cancelled?
    status == "cancelled"
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

  private

  def normalize_subdomain
    self.subdomain = subdomain&.downcase&.strip
  end

  def set_defaults
    self.settings ||= {}
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
