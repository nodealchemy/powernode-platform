# frozen_string_literal: true

module CiCd
  # Repository configuration for CI/CD pipelines
  # Stores connection details and settings for Git repositories
  class Repository < ApplicationRecord
    # ============================================
    # Associations
    # ============================================
    belongs_to :account
    belongs_to :provider, class_name: 'CiCd::Provider', foreign_key: :ci_cd_provider_id

    has_many :pipeline_repositories, class_name: 'CiCd::PipelineRepository', foreign_key: :ci_cd_repository_id, dependent: :destroy
    has_many :pipelines, through: :pipeline_repositories

    # ============================================
    # Validations
    # ============================================
    validates :name, presence: true
    validates :full_name, presence: true, uniqueness: { scope: :account_id }
    validates :default_branch, presence: true

    # ============================================
    # Scopes
    # ============================================
    scope :active, -> { where(is_active: true) }
    scope :by_provider, ->(provider_id) { where(ci_cd_provider_id: provider_id) }
    scope :needs_sync, -> { where('last_synced_at IS NULL OR last_synced_at < ?', 1.hour.ago) }

    # ============================================
    # Instance Methods
    # ============================================

    def clone_url
      provider_type = provider.provider_type

      case provider_type
      when 'gitea', 'github', 'gitlab'
        "#{provider.base_url}/#{full_name}.git"
      else
        "#{provider.base_url}/#{full_name}"
      end
    end

    def ssh_clone_url
      provider_type = provider.provider_type
      host = URI.parse(provider.base_url).host

      case provider_type
      when 'github'
        "git@github.com:#{full_name}.git"
      when 'gitlab'
        "git@#{host}:#{full_name}.git"
      when 'gitea'
        "git@#{host}:#{full_name}.git"
      else
        clone_url
      end
    end

    def web_url
      "#{provider.base_url}/#{full_name}"
    end

    def owner
      full_name.split('/').first
    end

    def repo_name
      full_name.split('/').last
    end

    def sync_from_provider!
      client = CiCd::ProviderClient.new(provider)
      repo_data = client.get_repository(owner, repo_name)

      update!(
        name: repo_data[:name],
        default_branch: repo_data[:default_branch],
        external_id: repo_data[:id],
        settings: settings.merge(repo_data[:settings] || {}),
        last_synced_at: Time.current
      )
    rescue StandardError => e
      Rails.logger.error("Failed to sync repository #{full_name}: #{e.message}")
      raise
    end

    def protected_branch?(branch_name)
      protected_branches = settings.dig('protected_branches') || []
      protected_branches.any? { |pattern| File.fnmatch(pattern, branch_name) }
    end

    def requires_review_for_path?(file_path)
      review_paths = settings.dig('review_required_paths') || []
      review_paths.any? { |pattern| File.fnmatch(pattern, file_path, File::FNM_PATHNAME) }
    end

    def enqueue_sync
      CiCd::ProviderSyncJob.perform_async(id)
    end
  end
end
