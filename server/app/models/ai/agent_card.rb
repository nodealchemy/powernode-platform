# frozen_string_literal: true

module Ai
  class AgentCard < ApplicationRecord
    # ==================== Concerns ====================
    include Auditable

    # ==================== Constants ====================
    VISIBILITIES = %w[private internal public].freeze
    STATUSES = %w[active inactive deprecated].freeze
    PROTOCOL_VERSIONS = %w[0.1 0.2 0.3].freeze
    DEFAULT_PROTOCOL_VERSION = "0.3"

    # A2A Standard Skills
    STANDARD_SKILLS = %w[
      summarize translate analyze generate
      code_assist data_process workflow_execute
      search retrieve transform validate
    ].freeze

    # ==================== Associations ====================
    belongs_to :account
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id", optional: true

    has_many :a2a_tasks_as_from, class_name: "Ai::A2aTask", foreign_key: "from_agent_card_id", dependent: :nullify
    has_many :a2a_tasks_as_to, class_name: "Ai::A2aTask", foreign_key: "to_agent_card_id", dependent: :nullify

    # ==================== Validations ====================
    validates :name, presence: true, length: { maximum: 255 }
    validates :name, uniqueness: { scope: :account_id }
    validates :visibility, inclusion: { in: VISIBILITIES }
    validates :status, inclusion: { in: STATUSES }
    validates :protocol_version, inclusion: { in: PROTOCOL_VERSIONS }
    validates :card_version, format: { with: /\A\d+\.\d+\.\d+\z/, message: "must be in semantic version format (x.y.z)" }
    validates :endpoint_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }

    validate :validate_capabilities_schema
    validate :validate_authentication_schema

    # ==================== Scopes ====================
    scope :active, -> { where(status: "active") }
    scope :inactive, -> { where(status: "inactive") }
    scope :deprecated, -> { where(status: "deprecated") }
    scope :visible_to_account, ->(account_id) {
      where(account_id: account_id)
        .or(where(visibility: "public"))
        .or(where(visibility: "internal"))
    }
    scope :public_cards, -> { where(visibility: "public") }
    scope :internal_cards, -> { where(visibility: "internal") }
    scope :private_cards, -> { where(visibility: "private") }
    scope :with_capability, ->(skill) {
      where("capabilities->'skills' ? :skill", skill: skill)
    }
    scope :with_tag, ->(tag) {
      where("tags @> ?", [tag].to_json)
    }
    scope :published, -> { where.not(published_at: nil) }
    scope :by_protocol_version, ->(version) { where(protocol_version: version) }
    scope :for_discovery, ->(account_id) {
      active.visible_to_account(account_id)
    }

    # ==================== Callbacks ====================
    before_validation :set_defaults
    before_save :update_version_if_capabilities_changed
    after_save :sync_metrics_from_tasks
    after_create :broadcast_card_created
    after_update :broadcast_card_updated

    # ==================== Class Methods ====================

    # Find agents capable of handling a task description
    def self.find_agents_for_task(description, account_id:, limit: 10)
      # Simple keyword-based matching for now
      # Can be enhanced with embeddings/semantic search
      keywords = description.downcase.split(/\s+/)

      active.visible_to_account(account_id)
        .where("LOWER(name) SIMILAR TO :pattern OR LOWER(description) SIMILAR TO :pattern",
               pattern: "%(#{keywords.join('|')})%")
        .or(
          active.visible_to_account(account_id)
            .where("capabilities->'skills' ?| ARRAY[:skills]", skills: keywords)
        )
        .limit(limit)
    end

    # ==================== Instance Methods ====================

    # Generate A2A-compliant Agent Card JSON
    def to_a2a_json
      {
        name: name,
        description: description,
        url: endpoint_url,
        provider: {
          organization: provider_name || account.name,
          url: provider_url
        }.compact,
        version: card_version,
        documentationUrl: documentation_url,
        capabilities: a2a_capabilities,
        authentication: a2a_authentication,
        defaultInputModes: default_input_modes,
        defaultOutputModes: default_output_modes,
        skills: skills_list
      }.compact
    end

    # Simplified summary for listings
    def card_summary
      {
        id: id,
        name: name,
        description: description&.truncate(200),
        visibility: visibility,
        status: status,
        skills: skills_list,
        tags: tags,
        task_count: task_count,
        success_rate: success_rate,
        avg_response_time_ms: avg_response_time_ms,
        published_at: published_at
      }
    end

    # Full details
    def card_details
      card_summary.merge(
        agent_id: ai_agent_id,
        protocol_version: protocol_version,
        card_version: card_version,
        capabilities: capabilities,
        authentication: authentication,
        default_input_modes: default_input_modes,
        default_output_modes: default_output_modes,
        endpoint_url: endpoint_url,
        provider_name: provider_name,
        provider_url: provider_url,
        documentation_url: documentation_url,
        deprecated_at: deprecated_at,
        created_at: created_at,
        updated_at: updated_at
      )
    end

    # Skills extraction
    def skills_list
      capabilities.dig("skills") || []
    end

    # Add a skill
    def add_skill(skill_id, skill_config = {})
      self.capabilities = capabilities.deep_merge(
        "skills" => (skills_list + [skill_config.merge("id" => skill_id)]).uniq { |s| s["id"] || s }
      )
      save
    end

    # Remove a skill
    def remove_skill(skill_id)
      self.capabilities = capabilities.merge(
        "skills" => skills_list.reject { |s| (s.is_a?(Hash) ? s["id"] : s) == skill_id }
      )
      save
    end

    # Check if card has specific capability
    def has_skill?(skill_id)
      skills_list.any? { |s| (s.is_a?(Hash) ? s["id"] : s) == skill_id }
    end

    # Publish the card
    def publish!
      update!(published_at: Time.current, status: "active")
    end

    # Deprecate the card
    def deprecate!(reason: nil)
      update!(
        deprecated_at: Time.current,
        status: "deprecated",
        capabilities: capabilities.merge("deprecation_reason" => reason)
      )
    end

    # Calculate success rate
    def success_rate
      return nil if task_count.zero?

      (success_count.to_f / task_count * 100).round(2)
    end

    # Update metrics from tasks
    def refresh_metrics!
      tasks = a2a_tasks_as_to

      self.task_count = tasks.count
      self.success_count = tasks.where(status: "completed").count
      self.failure_count = tasks.where(status: "failed").count

      completed_tasks = tasks.where(status: "completed").where.not(duration_ms: nil)
      self.avg_response_time_ms = completed_tasks.average(:duration_ms)&.round(2)

      save!
    end

    # Check if card can handle input mode
    def supports_input_mode?(mode)
      default_input_modes.include?(mode) ||
        capabilities.dig("supportedInputModes")&.include?(mode)
    end

    # Check if card can produce output mode
    def supports_output_mode?(mode)
      default_output_modes.include?(mode) ||
        capabilities.dig("supportedOutputModes")&.include?(mode)
    end

    # Validate authentication for incoming request
    def validate_authentication(request_auth)
      return true if authentication.blank? || authentication["schemes"].blank?

      supported_schemes = authentication["schemes"] || []
      return false if supported_schemes.empty?

      # Check if request auth matches any supported scheme
      supported_schemes.any? do |scheme|
        case scheme
        when "bearer"
          request_auth[:type] == "bearer" && request_auth[:token].present?
        when "api_key"
          request_auth[:type] == "api_key" && request_auth[:key].present?
        when "oauth2"
          request_auth[:type] == "oauth2" && request_auth[:access_token].present?
        else
          false
        end
      end
    end

    private

    def set_defaults
      self.protocol_version ||= DEFAULT_PROTOCOL_VERSION
      self.card_version ||= "1.0.0"
      self.capabilities ||= {}
      self.authentication ||= {}
      self.default_input_modes ||= ["application/json"]
      self.default_output_modes ||= ["application/json"]
      self.tags ||= []
    end

    def update_version_if_capabilities_changed
      return unless capabilities_changed?

      version_parts = card_version.split(".").map(&:to_i)
      version_parts[2] += 1
      self.card_version = version_parts.join(".")
    end

    def validate_capabilities_schema
      return if capabilities.blank?

      # Validate skills array if present
      if capabilities["skills"].present? && !capabilities["skills"].is_a?(Array)
        errors.add(:capabilities, "skills must be an array")
      end

      # Validate streaming capability
      if capabilities["streaming"].present? && !capabilities["streaming"].in?([true, false])
        errors.add(:capabilities, "streaming must be a boolean")
      end
    end

    def validate_authentication_schema
      return if authentication.blank?

      # Validate schemes array if present
      if authentication["schemes"].present?
        unless authentication["schemes"].is_a?(Array)
          errors.add(:authentication, "schemes must be an array")
          return
        end

        valid_schemes = %w[bearer api_key oauth2 basic none]
        invalid = authentication["schemes"] - valid_schemes
        if invalid.any?
          errors.add(:authentication, "invalid schemes: #{invalid.join(', ')}")
        end
      end
    end

    def a2a_capabilities
      {
        streaming: capabilities["streaming"] || false,
        pushNotifications: capabilities["push_notifications"] || false,
        stateTransitionHistory: capabilities["state_transition_history"] || true
      }.merge(capabilities.except("skills", "streaming", "push_notifications", "state_transition_history"))
    end

    def a2a_authentication
      return nil if authentication.blank?

      {
        schemes: authentication["schemes"] || ["bearer"],
        credentials: authentication["credentials_url"]
      }.compact
    end

    def sync_metrics_from_tasks
      # Async metric sync
      # AiAgentCardMetricsSyncJob.perform_later(id)
    end

    def broadcast_card_created
      McpChannel.broadcast_to(
        "account_#{account_id}",
        {
          type: "agent_card_created",
          agent_card_id: id,
          name: name
        }
      )
    end

    def broadcast_card_updated
      McpChannel.broadcast_to(
        "account_#{account_id}",
        {
          type: "agent_card_updated",
          agent_card_id: id,
          name: name
        }
      )
    end
  end
end
