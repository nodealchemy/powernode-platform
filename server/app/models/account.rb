# frozen_string_literal: true

class Account < ApplicationRecord
  include Auditable

  # Associations
  has_many :users, dependent: :destroy
  has_one :subscription, dependent: :destroy
  has_many :invitations, dependent: :destroy
  has_many :account_delegations, dependent: :destroy
  has_many :audit_logs, dependent: :destroy
  has_many :payment_methods, dependent: :destroy
  has_many :webhook_events, dependent: :destroy
  has_many :revenue_snapshots, dependent: :destroy
  has_many :workers, dependent: :destroy
  has_many :apps, dependent: :destroy
  has_many :app_subscriptions, dependent: :destroy
  has_many :api_keys, dependent: :destroy
  has_many :webhook_endpoints, dependent: :destroy

  # AI-related associations
  has_many :ai_providers, class_name: "Ai::Provider", dependent: :destroy
  has_many :ai_provider_credentials, class_name: "Ai::ProviderCredential", dependent: :destroy
  has_many :ai_agents, class_name: "Ai::Agent", dependent: :destroy
  has_many :ai_conversations, class_name: "Ai::Conversation", dependent: :destroy
  has_many :ai_messages, class_name: "Ai::Message", dependent: :destroy
  has_many :ai_agent_executions, class_name: "Ai::AgentExecution", dependent: :destroy
  has_many :ai_agent_teams, class_name: "Ai::AgentTeam", dependent: :destroy

  # AI Workflow associations
  has_many :ai_workflows, class_name: "Ai::Workflow", dependent: :destroy
  has_many :ai_workflow_runs, class_name: "Ai::WorkflowRun", dependent: :destroy
  has_many :ai_workflow_template_installations, class_name: "Ai::WorkflowTemplateInstallation", dependent: :destroy

  # Analytics & Reporting associations
  has_many :report_requests, dependent: :destroy

  # MCP (Model Context Protocol) associations
  has_many :mcp_servers, dependent: :destroy

  # Git Provider associations
  has_many :git_provider_credentials, class_name: "Git::ProviderCredential", dependent: :destroy
  has_many :git_repositories, class_name: "Git::Repository", dependent: :destroy
  has_many :git_webhook_events, class_name: "Git::WebhookEvent", dependent: :destroy
  has_many :git_pipelines, class_name: "Git::Pipeline", dependent: :destroy
  has_many :git_pipeline_jobs, class_name: "Git::PipelineJob", dependent: :destroy
  has_many :git_pipeline_approvals, class_name: "Git::PipelineApproval", dependent: :destroy
  has_many :git_pipeline_schedules, class_name: "Git::PipelineSchedule", dependent: :destroy
  has_many :git_runners, class_name: "Git::Runner", dependent: :destroy

  # CI/CD Pipeline Management associations
  has_many :ci_cd_providers, class_name: "CiCd::Provider", dependent: :destroy
  has_many :ci_cd_pipelines, class_name: "CiCd::Pipeline", dependent: :destroy
  has_many :ci_cd_repositories, class_name: "CiCd::Repository", dependent: :destroy

  # Shared infrastructure associations
  has_many :shared_prompt_templates, class_name: "Shared::PromptTemplate", dependent: :destroy

  # File Storage associations
  has_many :file_storages, class_name: "FileManagement::Storage", dependent: :destroy
  has_many :file_objects, class_name: "FileManagement::Object", dependent: :destroy
  has_many :file_tags, class_name: "FileManagement::Tag", dependent: :destroy

  # Subscription-related associations
  has_many :invoices, through: :subscription
  has_many :payments, through: :invoices

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
    admin_account_ids = User.joins(:account, user_roles: :role)
                            .where(roles: { name: [ "system.admin", "account.manager" ] })
                            .distinct.pluck(:account_id)
    admin_accounts = Account.where(id: admin_account_ids)

    admin_accounts.each do |admin_account|
      ActionCable.server.broadcast("customer_updates_#{admin_account.id}", data)
    end
  rescue => e
    Rails.logger.error "Failed to broadcast customer change: #{e.message}"
  end
end
