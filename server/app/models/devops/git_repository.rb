# frozen_string_literal: true

module Devops
  class GitRepository < ApplicationRecord
    # Table name (using git_ prefix, not devops_)
    self.table_name = "git_repositories"

    # Authentication
    # Belongs to account - access controlled through account ownership

    # Concerns
    include Auditable

    # Associations
    belongs_to :credential, class_name: "Devops::GitProviderCredential", foreign_key: "git_provider_credential_id", optional: true
    belongs_to :account
    belongs_to :provider, class_name: "Devops::Provider", foreign_key: "devops_provider_id", optional: true
    has_many :webhook_events, class_name: "Devops::GitWebhookEvent", foreign_key: "git_repository_id", dependent: :destroy
    has_many :pipelines, class_name: "Devops::GitPipeline", foreign_key: "git_repository_id", dependent: :destroy
    has_many :pipeline_schedules, class_name: "Devops::GitPipelineSchedule", foreign_key: "git_repository_id", dependent: :destroy
    has_many :runners, class_name: "Devops::GitRunner", foreign_key: "git_repository_id", dependent: :destroy

    # Devops pipeline associations
    has_many :devops_pipeline_repositories, class_name: "Devops::PipelineRepository", foreign_key: "git_repository_id", dependent: :destroy
    has_many :devops_pipelines, through: :devops_pipeline_repositories, source: :pipeline

    # Supply chain associations
    has_many :sboms, class_name: "SupplyChain::Sbom", foreign_key: "git_repository_id", dependent: :nullify

    # Delegations — provider_type resolves from devops provider or credential's git_provider
    delegate :provider_type, to: :resolved_provider, allow_nil: true

    # Constants
    BRANCH_FILTER_TYPES = %w[none exact wildcard regex].freeze

    # Validations
    validates :external_id, presence: true
    validates :name, presence: true, length: { maximum: 255 }
    validates :full_name, presence: true, length: { maximum: 500 }
    validates :owner, presence: true, length: { maximum: 255 }
    validates :full_name, uniqueness: { scope: :account_id, message: "repository already synced for this account" }
    validates :branch_filter_type, inclusion: { in: BRANCH_FILTER_TYPES }, allow_nil: true
    validates :branch_filter, presence: true, if: -> { branch_filter_type.present? && branch_filter_type != "none" }
    validates :origin, inclusion: { in: %w[git devops] }
    validates :credential, presence: true, if: -> { origin == "git" }
    validates :provider, presence: true, if: -> { origin == "devops" }

    # Scopes
    scope :with_webhook, -> { where(webhook_configured: true) }
    scope :with_webhooks, -> { with_webhook } # Alias for backwards compatibility
    scope :without_webhook, -> { where(webhook_configured: false) }
    scope :private_repos, -> { where(is_private: true) }
    scope :public_repos, -> { where(is_private: false) }
    scope :archived, -> { where(is_archived: true) }
    scope :active, -> { where(is_archived: false) }
    scope :forks, -> { where(is_fork: true) }
    scope :non_forks, -> { where(is_fork: false) }
    scope :recently_synced, -> { where("last_synced_at >= ?", 1.hour.ago) }
    scope :needs_sync, -> { where("last_synced_at IS NULL OR last_synced_at < ?", 1.hour.ago) }
    scope :by_owner, ->(owner) { where(owner: owner) }
    scope :by_language, ->(lang) { where("languages ? :lang", lang: lang) }
    scope :with_topic, ->(topic) { where("topics @> ?", [ topic ].to_json) }
    scope :from_devops, -> { where(origin: "devops") }
    scope :from_git, -> { where(origin: "git") }
    scope :by_provider, ->(provider_id) { where(devops_provider_id: provider_id) }

    # Callbacks
    before_create :generate_webhook_secret

    # Instance Methods

    def sync_needed?
      last_synced_at.nil? || last_synced_at < 1.hour.ago
    end

    alias needs_sync? sync_needed?

    def mark_synced!
      update!(last_synced_at: Time.current)
    end

    def configure_webhook!
      return { success: true, already_configured: true } if webhook_configured?

      client = Devops::Git::ApiClient.for(credential)
      result = client.create_webhook(self, webhook_secret)

      if result[:success]
        update!(
          webhook_configured: true,
          webhook_id: result[:webhook_id]
        )
      end

      result
    rescue StandardError => e
      { success: false, error: e.message }
    end

    def remove_webhook!
      return { success: true, not_configured: true } unless webhook_configured?

      client = Devops::Git::ApiClient.for(credential)
      result = client.delete_webhook(self)

      if result[:success]
        update!(
          webhook_configured: false,
          webhook_id: nil
        )
      end

      result
    rescue StandardError => e
      { success: false, error: e.message }
    end

    def primary_language
      return nil if languages.blank?

      languages.max_by { |_, v| v }&.first
    end

    def github?
      provider_type == "github"
    end

    def gitlab?
      provider_type == "gitlab"
    end

    def gitea?
      provider_type == "gitea"
    end

    # Devops-origin methods

    def protected_branch?(branch_name)
      protected_branches = metadata&.dig("protected_branches") || []
      protected_branches.any? { |pattern| File.fnmatch(pattern, branch_name) }
    end

    def requires_review_for_path?(file_path)
      review_paths = metadata&.dig("review_required_paths") || []
      review_paths.any? { |pattern| File.fnmatch(pattern, file_path, File::FNM_PATHNAME) }
    end

    def clone_url_for_devops
      return clone_url if clone_url.present?
      return unless provider

      "#{provider.base_url}/#{full_name}.git"
    end

    def web_url_for_devops
      return web_url if web_url.present?
      return unless provider

      "#{provider.base_url}/#{full_name}"
    end

    def resolved_provider
      provider || credential&.provider
    end

    def latest_pipeline
      pipelines.order(created_at: :desc).first
    end

    def pipeline_stats
      total = pipelines.count
      return {} if total.zero?

      {
        total: total,
        successful: pipelines.where(conclusion: "success").count,
        failed: pipelines.where(conclusion: "failure").count,
        cancelled: pipelines.where(conclusion: "cancelled").count,
        success_rate: (pipelines.where(conclusion: "success").count.to_f / total * 100).round(2)
      }
    end

    def recent_events(limit = 10)
      webhook_events.order(created_at: :desc).limit(limit)
    end

    # Branch Filtering Methods

    def branch_filter_enabled?
      branch_filter_type.present? && branch_filter_type != "none" && branch_filter.present?
    end

    def branch_matches_filter?(branch_name)
      return true unless branch_filter_enabled?
      return true if branch_name.blank?

      case branch_filter_type
      when "exact"
        branch_name == branch_filter
      when "wildcard"
        wildcard_match?(branch_name, branch_filter)
      when "regex"
        regex_match?(branch_name, branch_filter)
      else
        true
      end
    end

    def update_branch_filter!(filter_type:, filter_pattern: nil)
      update!(
        branch_filter_type: filter_type,
        branch_filter: filter_type == "none" ? nil : filter_pattern
      )
    end

    # Backwards compatibility aliases (must be public for controller access)
    def git_provider_credential
      credential
    end

    def git_provider
      resolved_provider
    end

    def git_webhook_events
      webhook_events
    end

    def git_pipelines
      pipelines
    end

    def git_pipeline_schedules
      pipeline_schedules
    end

    def git_runners
      runners
    end

    private

    def generate_webhook_secret
      self.webhook_secret ||= SecureRandom.hex(32)
    end

    def wildcard_match?(branch_name, pattern)
      # Convert wildcard pattern to regex: * becomes .*, ? becomes .
      regex_pattern = Regexp.escape(pattern)
                            .gsub('\*\*', ".*")  # ** matches any path including /
                            .gsub('\*', "[^/]*") # * matches anything except /
                            .gsub('\?', ".")     # ? matches single char
      Regexp.new("\\A#{regex_pattern}\\z").match?(branch_name)
    rescue RegexpError
      false
    end

    def regex_match?(branch_name, pattern)
      Regexp.new(pattern).match?(branch_name)
    rescue RegexpError
      false
    end
  end
end
