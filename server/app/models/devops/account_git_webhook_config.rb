# frozen_string_literal: true

module Devops
  class AccountGitWebhookConfig < ApplicationRecord
    # Table name
    self.table_name = "account_git_webhook_configs"

    # Concerns
    include Auditable

    # Constants
    STATUSES = %w[active inactive].freeze
    BRANCH_FILTER_TYPES = %w[none exact wildcard regex].freeze
    CONTENT_TYPES = %w[application/json application/x-www-form-urlencoded].freeze
    RETRY_BACKOFFS = %w[linear exponential].freeze

    # Available event types for account-level git webhooks
    EVENT_TYPES = Devops::GitWebhookEvent::EVENT_TYPES.freeze

    # Associations
    belongs_to :account
    belongs_to :created_by, class_name: "User", optional: true

    # Validations
    validates :name, presence: true, length: { maximum: 255 }
    validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :branch_filter_type, inclusion: { in: BRANCH_FILTER_TYPES }, allow_nil: true
    validates :branch_filter, presence: true, if: -> { branch_filter_type.present? && branch_filter_type != "none" }
    validates :content_type, presence: true, inclusion: { in: CONTENT_TYPES }
    validates :timeout_seconds, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 300 }
    validates :retry_limit, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }
    validates :retry_backoff, presence: true, inclusion: { in: RETRY_BACKOFFS }
    validates :description, length: { maximum: 500 }, allow_blank: true
    validate :validate_custom_headers_limit

    # Scopes
    scope :active, -> { where(status: "active", is_active: true) }
    scope :inactive, -> { where.not(status: "active").or(where(is_active: false)) }
    scope :for_event_type, ->(event_type) { where("event_types @> ?", [ event_type ].to_json) }

    # Callbacks
    before_validation :set_defaults
    before_create :generate_secrets

    # Instance Methods

    def active?
      status == "active" && is_active?
    end

    def inactive?
      !active?
    end

    def can_receive_event?(event_type)
      active? && (event_types.blank? || event_types.include?(event_type) || event_types.include?("*"))
    end

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

    def success_rate
      total = success_count + failure_count
      return 100.0 if total.zero?

      (success_count.to_f / total * 100).round(2)
    end

    def failure_rate
      100.0 - success_rate
    end

    def total_deliveries
      success_count + failure_count
    end

    def health_status
      return "unknown" if total_deliveries.zero?
      return "excellent" if success_rate >= 95.0
      return "good" if success_rate >= 85.0
      return "warning" if success_rate >= 70.0

      "critical"
    end

    def increment_success_count!
      increment!(:success_count)
      update_column(:last_delivery_at, Time.current)
    end

    def increment_failure_count!
      increment!(:failure_count)
      update_column(:last_delivery_at, Time.current)
    end

    def regenerate_secret!
      self.secret_key = generate_secret_value
      save!
    end

    def regenerate_signature_secret!
      self.signature_secret = "whsig_#{SecureRandom.base64(32).tr('+/', '-_')}"
      save!
    end

    def masked_secret
      return nil unless secret_key.present?

      "#{secret_key[0..7]}#{'*' * 24}#{secret_key[-8..]}"
    end

    def generate_signature(payload)
      return nil unless signature_secret.present?

      timestamp = Time.current.to_i
      payload_string = "#{timestamp}.#{payload}"
      signature = OpenSSL::HMAC.hexdigest("SHA256", signature_secret, payload_string)

      "t=#{timestamp},v1=#{signature}"
    end

    def next_retry_delay(attempt_number)
      base_delay = 5 # seconds

      delay = case retry_backoff
      when "linear"
                base_delay * attempt_number
      when "exponential"
                base_delay * (2**(attempt_number - 1))
      else
                base_delay
      end

      delay.clamp(1, 300) # Max 5 minutes
    end

    private

    def set_defaults
      self.status ||= "active"
      self.is_active = true if is_active.nil?
      self.timeout_seconds ||= 30
      self.retry_limit ||= 3
      self.retry_backoff ||= "exponential"
      self.content_type ||= "application/json"
      self.event_types ||= []
      self.custom_headers ||= {}
      self.branch_filter_type ||= "none"
    end

    def generate_secrets
      self.secret_key ||= generate_secret_value
      self.signature_secret ||= "whsig_#{SecureRandom.base64(32).tr('+/', '-_')}"
    end

    def generate_secret_value
      "whsec_#{SecureRandom.base64(32).tr('+/', '-_')}"
    end

    def validate_custom_headers_limit
      return if custom_headers.blank?

      if custom_headers.is_a?(Hash) && custom_headers.keys.length > 20
        errors.add(:custom_headers, "cannot exceed 20 headers")
      end
    end

    def wildcard_match?(branch_name, pattern)
      regex_pattern = Regexp.escape(pattern)
                            .gsub('\*\*', ".*")
                            .gsub('\*', "[^/]*")
                            .gsub('\?', ".")
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
