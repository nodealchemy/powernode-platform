# frozen_string_literal: true

module Ai
  class PersistentContext < ApplicationRecord
    self.table_name = "ai_persistent_contexts"

    # ==================== Concerns ====================
    include Auditable

    # ==================== Constants ====================
    CONTEXT_TYPES = %w[agent_memory knowledge_base shared_context].freeze
    SCOPES = %w[account agent team workflow].freeze

    # ==================== Associations ====================
    belongs_to :account
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id", optional: true  # null = account-wide context
    belongs_to :created_by_user, class_name: "User", optional: true

    has_many :context_entries, class_name: "Ai::ContextEntry", foreign_key: "ai_persistent_context_id", dependent: :destroy
    has_many :context_access_logs, class_name: "Ai::ContextAccessLog", foreign_key: "ai_persistent_context_id", dependent: :destroy

    # ==================== Validations ====================
    validates :context_id, presence: true, uniqueness: true
    validates :name, presence: true, length: { maximum: 255 }
    validates :context_type, presence: true, inclusion: { in: CONTEXT_TYPES }
    validates :scope, presence: true, inclusion: { in: SCOPES }
    validates :version, presence: true, numericality: { only_integer: true, greater_than: 0 }
    validate :agent_required_for_agent_scope
    validate :valid_retention_policy

    # ==================== Scopes ====================
    scope :active, -> { where(archived_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }
    scope :archived, -> { where.not(archived_at: nil) }
    scope :expired, -> { where("expires_at <= ?", Time.current) }
    scope :by_type, ->(type) { where(context_type: type) }
    scope :by_scope, ->(scope_name) { where(scope: scope_name) }
    scope :agent_memories, -> { where(context_type: "agent_memory") }
    scope :knowledge_bases, -> { where(context_type: "knowledge_base") }
    scope :shared_contexts, -> { where(context_type: "shared_context") }
    scope :for_agent, ->(agent_id) { where(ai_agent_id: agent_id) }
    scope :account_wide, -> { where(ai_agent_id: nil) }
    scope :accessible_by_agent, ->(agent_id) do
      where(ai_agent_id: agent_id)
        .or(where(ai_agent_id: nil, scope: %w[account team]))
        .or(where("access_control->>'agents' @> ?", [agent_id].to_json))
    end
    scope :recent, -> { order(last_accessed_at: :desc) }

    # ==================== Callbacks ====================
    before_validation :generate_context_id, on: :create
    before_save :sanitize_jsonb_fields
    before_save :update_data_size
    before_save :increment_version, if: :context_data_changed?

    # ==================== Instance Methods ====================

    def context_summary
      {
        id: id,
        context_id: context_id,
        name: name,
        context_type: context_type,
        scope: scope,
        agent_id: ai_agent_id,
        version: version,
        entry_count: entry_count,
        data_size_bytes: data_size_bytes,
        last_accessed_at: last_accessed_at
      }
    end

    def context_details
      context_summary.merge(
        description: description,
        context_data: context_data,
        metadata: metadata,
        access_control: access_control,
        retention_policy: retention_policy,
        expires_at: expires_at,
        archived_at: archived_at,
        access_count: access_count,
        created_at: created_at,
        updated_at: updated_at
      )
    end

    def accessible_by?(accessor_id, accessor_type: :user)
      return true if access_control.dig("public") == true

      case accessor_type
      when :user
        allowed_users = access_control.dig("users") || []
        allowed_users.include?(accessor_id) || created_by_user_id == accessor_id
      when :agent
        return true if ai_agent_id == accessor_id
        allowed_agents = access_control.dig("agents") || []
        allowed_agents.include?(accessor_id)
      else
        false
      end
    end

    def grant_access(accessor_id, accessor_type: :user)
      key = accessor_type == :agent ? "agents" : "users"
      access_control[key] ||= []
      access_control[key] << accessor_id unless access_control[key].include?(accessor_id)
      save!
    end

    def revoke_access(accessor_id, accessor_type: :user)
      key = accessor_type == :agent ? "agents" : "users"
      access_control[key] ||= []
      access_control[key].delete(accessor_id)
      save!
    end

    def read_data(key = nil)
      touch(:last_accessed_at)
      increment!(:access_count)

      if key.present?
        keys = key.to_s.split(".")
        context_data.dig(*keys)
      else
        context_data
      end
    end

    def write_data(key, value)
      keys = key.to_s.split(".")
      update_nested_hash(context_data, keys, value)
      self.last_modified_at = Time.current
      save!
    end

    def merge_data(data_hash)
      self.context_data = context_data.deep_merge(data_hash)
      self.last_modified_at = Time.current
      save!
    end

    def clear_data!
      self.context_data = {}
      self.last_modified_at = Time.current
      save!
      context_entries.destroy_all
    end

    def archive!
      update!(archived_at: Time.current)
    end

    def unarchive!
      update!(archived_at: nil)
    end

    def archived?
      archived_at.present?
    end

    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    def set_expiration(duration)
      update!(expires_at: Time.current + duration)
    end

    def create_snapshot
      {
        context_id: context_id,
        version: version,
        snapshot_at: Time.current.iso8601,
        context_data: context_data.deep_dup,
        entries: context_entries.map(&:entry_snapshot),
        metadata: {
          "snapshot_version" => version,
          "data_hash" => Digest::SHA256.hexdigest(context_data.to_json),
          "entry_count" => entry_count
        }
      }
    end

    def restore_from_snapshot(snapshot)
      transaction do
        self.context_data = snapshot["context_data"]
        self.metadata = metadata.merge(
          "restored_from_version" => snapshot["version"],
          "restored_at" => Time.current.iso8601
        )
        save!

        # Optionally restore entries if included
        if snapshot["entries"].present?
          context_entries.destroy_all
          snapshot["entries"].each do |entry_data|
            context_entries.create!(entry_data.except("id", "created_at", "updated_at"))
          end
        end
      end
    end

    def statistics
      {
        entry_count: entry_count,
        data_size_bytes: data_size_bytes,
        version: version,
        age_days: ((Time.current - created_at) / 1.day).to_i,
        access_count: access_count,
        last_access_ago: last_accessed_at ? (Time.current - last_accessed_at).to_i : nil,
        last_modified_ago: last_modified_at ? (Time.current - last_modified_at).to_i : nil
      }
    end

    private

    def generate_context_id
      return if context_id.present?

      prefix = case context_type
               when "agent_memory" then "mem"
               when "knowledge_base" then "kb"
               when "shared_context" then "ctx"
               else "ctx"
               end

      self.context_id = "#{prefix}_#{SecureRandom.hex(12)}"
    end

    def sanitize_jsonb_fields
      self.context_data = {} if context_data.blank?
      self.metadata = {} if metadata.blank?
      self.access_control = {} if access_control.blank?
      self.retention_policy = {} if retention_policy.blank?
    end

    def update_data_size
      self.data_size_bytes = context_data.to_json.bytesize
    end

    def increment_version
      self.version += 1
    end

    def agent_required_for_agent_scope
      if scope == "agent" && ai_agent_id.blank?
        errors.add(:agent, "is required for agent-scoped contexts")
      end
    end

    def valid_retention_policy
      return if retention_policy.blank?

      unless retention_policy.is_a?(Hash)
        errors.add(:retention_policy, "must be a valid JSON object")
      end
    end

    def update_nested_hash(hash, keys, value)
      if keys.length == 1
        hash[keys.first] = value
      else
        key = keys.shift
        hash[key] ||= {}
        update_nested_hash(hash[key], keys, value)
      end
    end
  end
end
