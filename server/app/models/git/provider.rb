# frozen_string_literal: true

module Git
  class Provider < ApplicationRecord
    # Authentication
    # Provider definitions are global - access controlled by account through credentials

    # Concerns
    include Auditable

    # Associations
    has_many :credentials, class_name: "Git::ProviderCredential", foreign_key: "git_provider_id", dependent: :destroy
    has_many :webhook_events, class_name: "Git::WebhookEvent", foreign_key: "git_provider_id", dependent: :destroy

    # Validations
    validates :name, presence: true, length: { maximum: 100 }
    validates :slug, presence: true, uniqueness: true, length: { maximum: 50 },
                     format: { with: /\A[a-z0-9\-_]+\z/, message: "must contain only lowercase letters, numbers, hyphens, and underscores" }
    validates :provider_type, presence: true,
                              inclusion: { in: %w[github gitlab gitea], message: "must be github, gitlab, or gitea" }
    validates :api_base_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }
    validates :web_base_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }
    validates :capabilities, presence: true

    # Scopes
    scope :active, -> { where(is_active: true) }
    scope :inactive, -> { where(is_active: false) }
    scope :by_type, ->(type) { where(provider_type: type) }
    scope :with_oauth, -> { where(supports_oauth: true) }
    scope :with_pat, -> { where(supports_pat: true) }
    scope :with_webhooks, -> { where(supports_webhooks: true) }
    scope :with_ci_cd, -> { where(supports_ci_cd: true) }
    scope :ordered_by_priority, -> { order(:priority_order, :name) }

    # Callbacks
    before_validation :generate_slug, if: -> { name.present? && slug.blank? }
    before_validation :normalize_urls

    # Instance Methods

    def supports_capability?(capability)
      capabilities.include?(capability.to_s)
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

    def self_hosted?
      !github? || api_base_url.present?
    end

    def default_api_base_url
      case provider_type
      when "github"
        "https://api.github.com"
      when "gitlab"
        "https://gitlab.com/api/v4"
      else
        nil # Gitea must be configured
      end
    end

    def effective_api_base_url
      api_base_url.presence || default_api_base_url
    end

    def default_web_base_url
      case provider_type
      when "github"
        "https://github.com"
      when "gitlab"
        "https://gitlab.com"
      else
        nil
      end
    end

    def effective_web_base_url
      web_base_url.presence || default_web_base_url
    end

    def available_events
      base_events = %w[push pull_request issues issue_comment]
      ci_events = supports_ci_cd? ? %w[workflow_run deployment] : []
      base_events + ci_events
    end

    def credentials_for_account(account)
      credentials.where(account: account, is_active: true)
    end

    def default_credential_for_account(account)
      credentials_for_account(account).find_by(is_default: true)
    end

    private

    def generate_slug
      self.slug = name.downcase.gsub(/[^a-z0-9\s]/, "").gsub(/\s+/, "-")
    end

    def normalize_urls
      self.api_base_url = api_base_url.chomp("/") if api_base_url.present?
      self.web_base_url = web_base_url.chomp("/") if web_base_url.present?
    end
  end
end
