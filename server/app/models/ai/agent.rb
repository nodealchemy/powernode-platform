# frozen_string_literal: true

# AI Agent Model - MCP-only implementation for tool registration and execution
# Completely replaces legacy event-based communication with MCP protocol
module Ai
  class Agent < ApplicationRecord
    self.table_name = "ai_agents"

    # Core concerns
    include Auditable
    include Searchable

    # Extracted concerns
    include Ai::Agent::StatusChecks
    include Ai::Agent::McpTool
    include Ai::Agent::McpRegistration
    include Ai::Agent::McpSchemas
    include Ai::Agent::Execution
    include Ai::Agent::Statistics
    include Ai::Agent::Operations

    # Associations
    belongs_to :account
    belongs_to :creator, class_name: "User"
    belongs_to :provider, class_name: "Ai::Provider", foreign_key: "ai_provider_id"
    has_many :executions, class_name: "Ai::AgentExecution", foreign_key: "ai_agent_id", dependent: :destroy
    has_many :conversations, class_name: "Ai::Conversation", foreign_key: "ai_agent_id", dependent: :destroy
    has_many :messages, class_name: "Ai::Message", foreign_key: "ai_agent_id", dependent: :destroy

    # Validations
    validates :name, presence: true, length: { maximum: 255 }, uniqueness: { scope: :account_id }
    validates :description, length: { maximum: 1000 }
    validates :slug, presence: true, uniqueness: { scope: :account_id }, length: { maximum: 150 },
                     format: { with: /\A[a-z0-9\-_]+\z/, message: "can only contain lowercase letters, numbers, hyphens, and underscores" }
    validates :agent_type, presence: true, inclusion: {
      in: %w[assistant code_assistant data_analyst content_generator image_generator workflow_optimizer workflow_operations monitor],
      message: "is not included in the list"
    }
    validates :status, inclusion: { in: %w[active inactive paused error archived] }
    validates :mcp_capabilities, presence: true
    validates :version, format: { with: /\A\d+\.\d+\.\d+\z/, message: "must be in semantic version format (x.y.z)" }

    # JSON attributes for MCP data
    attribute :mcp_tool_manifest, :json, default: -> { {} }
    attribute :mcp_input_schema, :json, default: -> { default_input_schema }
    attribute :mcp_output_schema, :json, default: -> { default_output_schema }
    attribute :mcp_capabilities, :json, default: -> { [] }
    attribute :mcp_metadata, :json, default: -> { {} }

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :inactive, -> { where(status: "inactive") }
    scope :paused, -> { where(status: "paused") }
    scope :archived, -> { where(status: "archived") }
    scope :by_type, ->(type) { where(agent_type: type) }
    scope :by_creator, ->(user) { where(creator: user) }
    scope :mcp_enabled, -> { where.not(mcp_tool_manifest: {}) }
    scope :with_capability, ->(capability) { where("mcp_capabilities @> ?", [ capability ].to_json) }
    scope :recently_executed, ->(days = 30) { where("last_executed_at >= ?", days.days.ago) }
    scope :healthy, -> { where(status: "active") }
    scope :search_by_text, ->(query) {
      where("name ILIKE ? OR description ILIKE ?", "%#{query}%", "%#{query}%")
    }

    # Callbacks
    before_validation :generate_slug, if: -> { name.present? && (slug.blank? || name_changed?) }
    before_validation :normalize_agent_type
    before_validation :normalize_mcp_capabilities
    before_save :update_version_if_mcp_changed
    before_save :ensure_mcp_tool_manifest

    private

    def generate_slug
      return if name.blank?

      base_slug = name.downcase.gsub(/[^a-z0-9\s\-_]/, "").squeeze(" ").strip.gsub(/\s+/, "-")
      self.slug = base_slug

      # Ensure uniqueness within account
      counter = 1
      while account.ai_agents.where(slug: self.slug).where.not(id: id).exists?
        self.slug = "#{base_slug}-#{counter}"
        counter += 1
      end
    end

    def normalize_agent_type
      self.agent_type = agent_type&.downcase&.strip
    end

    def normalize_mcp_capabilities
      return unless mcp_capabilities.is_a?(Array)

      self.mcp_capabilities = mcp_capabilities.map(&:to_s).map(&:downcase).uniq.compact
    end

    def update_version_if_mcp_changed
      if mcp_tool_manifest_changed? || mcp_input_schema_changed? || mcp_output_schema_changed?
        increment_version
      end
    end

    def increment_version
      if version.present?
        version_parts = version.split(".").map(&:to_i)
        version_parts[2] += 1  # Increment patch version
        self.version = version_parts.join(".")
      else
        self.version = "1.0.0"
      end
    end

    def ensure_mcp_tool_manifest
      # Auto-generate MCP tool manifest if missing or incomplete, or if name changed
      if mcp_tool_manifest.blank? || !has_required_manifest_fields? || name_changed?
        self.mcp_tool_manifest = generate_mcp_tool_manifest
        self.mcp_registered_at = Time.current
      end
    end
  end
end
