# frozen_string_literal: true

class Account < ApplicationRecord
  include Auditable

  # Associations
  has_many :users, dependent: :destroy
  has_one :subscription, dependent: :destroy
  has_many :invitations, dependent: :destroy
  has_many :account_delegations, class_name: "Account::Delegation", dependent: :destroy
  has_many :audit_logs, dependent: :destroy
  has_many :payment_methods, dependent: :destroy
  has_many :webhook_events, dependent: :destroy
  has_many :revenue_snapshots, dependent: :destroy
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

  # AI Credit System associations (Phase 2 - Credit System)
  has_one :ai_account_credits, class_name: "Ai::AccountCredit", dependent: :destroy
  has_many :ai_credit_transactions, class_name: "Ai::CreditTransaction", dependent: :destroy
  has_many :ai_credit_purchases, class_name: "Ai::CreditPurchase", dependent: :destroy
  has_many :ai_credit_transfers_sent, class_name: "Ai::CreditTransfer", foreign_key: :from_account_id, dependent: :destroy
  has_many :ai_credit_transfers_received, class_name: "Ai::CreditTransfer", foreign_key: :to_account_id, dependent: :destroy

  # AI Outcome Billing associations (Phase 2 - Outcome Billing)
  has_many :ai_outcome_definitions, class_name: "Ai::OutcomeDefinition", dependent: :destroy
  has_many :ai_sla_contracts, class_name: "Ai::SlaContract", dependent: :destroy
  has_many :ai_outcome_billing_records, class_name: "Ai::OutcomeBillingRecord", dependent: :destroy
  has_many :ai_sla_violations, class_name: "Ai::SlaViolation", dependent: :destroy

  # MCP Hosting associations (Phase 2 - MCP Hosting)
  has_many :mcp_hosted_servers, class_name: "Mcp::HostedServer", dependent: :destroy
  has_many :mcp_server_subscriptions, class_name: "Mcp::ServerSubscription", dependent: :destroy

  # AI RAG System associations (Phase 3 - Knowledge-Augmented Agents)
  has_many :ai_knowledge_bases, class_name: "Ai::KnowledgeBase", dependent: :destroy
  has_many :ai_rag_queries, class_name: "Ai::RagQuery", dependent: :destroy
  has_many :ai_data_connectors, class_name: "Ai::DataConnector", dependent: :destroy

  # AI Multi-Agent Team associations (Phase 3 - Team Orchestration)
  has_many :ai_team_roles, class_name: "Ai::TeamRole", dependent: :destroy
  has_many :ai_team_executions, class_name: "Ai::TeamExecution", dependent: :destroy
  has_many :ai_team_templates, class_name: "Ai::TeamTemplate", dependent: :destroy

  # AI Agent Marketplace associations (Phase 4 - Agent Marketplace)
  has_one :ai_publisher_account, class_name: "Ai::PublisherAccount", dependent: :destroy
  has_many :ai_agent_installations, class_name: "Ai::AgentInstallation", dependent: :destroy
  has_many :ai_agent_reviews, class_name: "Ai::AgentReview", dependent: :destroy
  has_many :ai_marketplace_transactions, class_name: "Ai::MarketplaceTransaction", dependent: :destroy

  # AI Governance Suite associations (Phase 4 - Governance & Compliance)
  has_many :ai_compliance_policies, class_name: "Ai::CompliancePolicy", dependent: :destroy
  has_many :ai_policy_violations, class_name: "Ai::PolicyViolation", dependent: :destroy
  has_many :ai_approval_chains, class_name: "Ai::ApprovalChain", dependent: :destroy
  has_many :ai_approval_requests, class_name: "Ai::ApprovalRequest", dependent: :destroy
  has_many :ai_data_classifications, class_name: "Ai::DataClassification", dependent: :destroy
  has_many :ai_data_detections, class_name: "Ai::DataDetection", dependent: :destroy
  has_many :ai_compliance_reports, class_name: "Ai::ComplianceReport", dependent: :destroy
  has_many :ai_compliance_audit_entries, class_name: "Ai::ComplianceAuditEntry", dependent: :destroy

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

  # Marketplace subscriptions (replaces deprecated ai_workflow_template_installations)
  has_many :marketplace_subscriptions, class_name: "Marketplace::Subscription", dependent: :destroy
  has_many :workflow_template_subscriptions, -> { for_workflow_templates }, class_name: "Marketplace::Subscription"

  # Analytics & Reporting associations
  has_many :report_requests, dependent: :destroy

  # MCP (Model Context Protocol) associations
  has_many :mcp_servers, dependent: :destroy

  # Git Provider associations
  has_many :git_provider_credentials, class_name: "Devops::GitProviderCredential", dependent: :destroy
  has_many :git_repositories, class_name: "Devops::GitRepository", dependent: :destroy
  has_many :git_webhook_events, class_name: "Devops::GitWebhookEvent", dependent: :destroy
  has_many :git_pipelines, class_name: "Devops::GitPipeline", dependent: :destroy
  has_many :git_pipeline_jobs, class_name: "Devops::GitPipelineJob", dependent: :destroy
  has_many :git_pipeline_approvals, class_name: "Devops::GitPipelineApproval", dependent: :destroy
  has_many :git_pipeline_schedules, class_name: "Devops::GitPipelineSchedule", dependent: :destroy
  has_many :git_runners, class_name: "Devops::GitRunner", dependent: :destroy

  # DevOps Pipeline Management associations
  has_many :devops_providers, class_name: "Devops::Provider", dependent: :destroy
  has_many :devops_pipelines, class_name: "Devops::Pipeline", dependent: :destroy
  has_many :devops_repositories, class_name: "Devops::Repository", dependent: :destroy
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

  # Reseller Program associations
  has_one :reseller, dependent: :destroy
  has_one :reseller_referral, class_name: "ResellerReferral", foreign_key: :referred_account_id, dependent: :destroy

  # Usage Tracking associations
  has_many :usage_events, dependent: :destroy
  has_many :usage_summaries, dependent: :destroy
  has_many :usage_quotas, dependent: :destroy

  # BaaS (Billing-as-a-Service) associations
  has_many :baas_tenants, class_name: "BaaS::Tenant", dependent: :destroy

  # Revenue Intelligence associations
  has_many :customer_health_scores, dependent: :destroy
  has_many :churn_predictions, dependent: :destroy
  has_many :revenue_forecasts, dependent: :destroy
  has_many :analytics_alerts, dependent: :destroy

  # Supply Chain Management associations
  has_many :supply_chain_sboms, class_name: "SupplyChain::Sbom", dependent: :destroy
  has_many :supply_chain_sbom_components, through: :supply_chain_sboms, source: :components
  has_many :supply_chain_sbom_vulnerabilities, through: :supply_chain_sboms, source: :vulnerabilities
  has_many :supply_chain_vulnerability_feeds, class_name: "SupplyChain::VulnerabilityFeed", dependent: :destroy
  has_many :supply_chain_remediation_plans, class_name: "SupplyChain::RemediationPlan", dependent: :destroy
  has_many :supply_chain_signing_keys, class_name: "SupplyChain::SigningKey", dependent: :destroy
  has_many :supply_chain_attestations, class_name: "SupplyChain::Attestation", dependent: :destroy
  has_many :supply_chain_container_images, class_name: "SupplyChain::ContainerImage", dependent: :destroy
  has_many :supply_chain_image_policies, class_name: "SupplyChain::ImagePolicy", dependent: :destroy
  has_many :supply_chain_vulnerability_scans, class_name: "SupplyChain::VulnerabilityScan", dependent: :destroy
  has_many :supply_chain_cve_monitors, class_name: "SupplyChain::CveMonitor", dependent: :destroy
  has_many :supply_chain_license_policies, class_name: "SupplyChain::LicensePolicy", dependent: :destroy
  has_many :supply_chain_license_violations, class_name: "SupplyChain::LicenseViolation", dependent: :destroy
  has_many :supply_chain_vendors, class_name: "SupplyChain::Vendor", dependent: :destroy
  has_many :supply_chain_risk_assessments, class_name: "SupplyChain::RiskAssessment", dependent: :destroy
  has_many :supply_chain_questionnaire_templates, class_name: "SupplyChain::QuestionnaireTemplate", dependent: :destroy
  has_many :supply_chain_vendor_monitoring_events, class_name: "SupplyChain::VendorMonitoringEvent", dependent: :destroy
  has_many :supply_chain_scan_templates, class_name: "SupplyChain::ScanTemplate", dependent: :destroy
  has_many :supply_chain_scan_instances, class_name: "SupplyChain::ScanInstance", dependent: :destroy
  has_many :supply_chain_scan_executions, class_name: "SupplyChain::ScanExecution", dependent: :destroy
  has_many :supply_chain_reports, class_name: "SupplyChain::Report", dependent: :destroy
  has_many :supply_chain_attributions, class_name: "SupplyChain::Attribution", dependent: :destroy
  has_many :supply_chain_license_detections, class_name: "SupplyChain::LicenseDetection", dependent: :destroy
  has_many :supply_chain_build_provenances, class_name: "SupplyChain::BuildProvenance", dependent: :destroy

  # Subscription-related associations
  has_many :invoices, through: :subscription
  has_many :payments

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
    subscription
  end

  def has_active_subscription?
    subscription&.active? || false
  end

  def subscription_status
    subscription&.status || "none"
  end

  def on_trial?
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
