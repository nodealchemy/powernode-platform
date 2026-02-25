# frozen_string_literal: true

module Devops
  # Git provider configuration (Gitea, GitHub, GitLab, Jenkins)
  # Stores connection details and credentials for CI/CD integrations
  class Provider < ApplicationRecord
    self.table_name = "devops_providers"

    # ============================================
    # Associations
    # ============================================
    belongs_to :account
    belongs_to :created_by, class_name: "User", optional: true

    has_many :repositories, class_name: "Devops::Repository", foreign_key: :devops_provider_id, dependent: :destroy
    has_many :pipelines, class_name: "Devops::Pipeline", foreign_key: :devops_provider_id, dependent: :restrict_with_error

    # ============================================
    # Validations
    # ============================================
    validates :name, presence: true, uniqueness: { scope: :account_id }
    validates :provider_type, presence: true, inclusion: { in: %w[gitea github gitlab jenkins] }
    validates :base_url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
    validates :api_version, presence: true

    validate :only_one_default_per_account, if: :is_default?

    # ============================================
    # Scopes
    # ============================================
    scope :active, -> { where(is_active: true) }
    scope :default_provider, -> { where(is_default: true) }
    scope :by_type, ->(type) { where(provider_type: type) }
    scope :healthy, -> { where(health_status: "healthy") }

    # ============================================
    # Callbacks
    # ============================================
    before_save :ensure_single_default, if: :is_default_changed?

    # ============================================
    # Instance Methods
    # ============================================

    def api_endpoint
      case provider_type
      when "gitea"
        "#{base_url}/api/#{api_version}"
      when "github"
        base_url.include?("github.com") ? "https://api.github.com" : "#{base_url}/api/v3"
      when "gitlab"
        "#{base_url}/api/#{api_version}"
      when "jenkins"
        "#{base_url}/api/json"
      end
    end

    def credential
      return nil unless credential_key.present?

      Rails.application.credentials.dig(:devops, :providers, credential_key.to_sym)
    end

    def update_health_status!(status)
      update!(
        health_status: status,
        last_health_check_at: Time.current
      )
    end

    def healthy?
      health_status == "healthy"
    end

    def supports_capability?(capability)
      capabilities.include?(capability.to_s)
    end

    private

    def only_one_default_per_account
      existing_default = account.devops_providers.default_provider.where.not(id: id).exists?
      errors.add(:is_default, "can only have one default provider per account") if existing_default
    end

    def ensure_single_default
      return unless is_default?

      account.devops_providers.where.not(id: id).update_all(is_default: false)
    end
  end
end
