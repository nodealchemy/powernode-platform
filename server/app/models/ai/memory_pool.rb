# frozen_string_literal: true

module Ai
  class MemoryPool < ApplicationRecord
    self.table_name = "ai_memory_pools"

    # ==================== Constants ====================
    POOL_TYPES = %w[shared agent_private team_shared task_scoped global].freeze
    SCOPES = %w[execution persistent session].freeze

    # ==================== Associations ====================
    belongs_to :account

    # ==================== Validations ====================
    validates :pool_id, presence: true, uniqueness: true
    validates :name, presence: true
    validates :pool_type, presence: true, inclusion: {
      in: POOL_TYPES,
      message: "%{value} is not a valid pool type"
    }
    validates :scope, presence: true, inclusion: {
      in: SCOPES,
      message: "%{value} is not a valid scope"
    }
    validates :version, presence: true, numericality: { only_integer: true, greater_than: 0 }

    # ==================== Scopes ====================
    scope :shared, -> { where(pool_type: "shared") }
    scope :agent_private, -> { where(pool_type: "agent_private") }
    scope :team_shared, -> { where(pool_type: "team_shared") }
    scope :task_scoped, -> { where(pool_type: "task_scoped") }
    scope :global, -> { where(pool_type: "global") }
    scope :for_agent, ->(agent_id) { where(owner_agent_id: agent_id) }
    scope :for_team, ->(team_id) { where(team_id: team_id) }
    scope :for_task, ->(task_id) { where(task_execution_id: task_id) }
    scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
    scope :expired, -> { where("expires_at <= ?", Time.current) }
    scope :persistent, -> { where(persist_across_executions: true) }
    scope :accessible_by, ->(agent_id) do
      where("access_control->>'agents' @> ?", [agent_id].to_json)
        .or(where(owner_agent_id: agent_id))
        .or(where("access_control->>'public' = 'true'"))
    end

    # ==================== Callbacks ====================
    before_validation :generate_pool_id, on: :create
    before_save :increment_version, if: :data_changed?
    before_save :calculate_data_size
    after_update :broadcast_pool_update

    # ==================== Instance Methods ====================

    def pool_summary
      {
        id: id,
        pool_id: pool_id,
        name: name,
        type: pool_type,
        scope: scope,
        owner: owner_agent_id,
        version: version,
        data_size_bytes: data_size_bytes,
        persist_across_executions: persist_across_executions,
        created_at: created_at,
        last_accessed: last_accessed_at,
        expires_at: expires_at
      }
    end

    def pool_details
      pool_summary.merge(
        data: data,
        access_control: access_control,
        metadata: metadata,
        retention_policy: retention_policy
      )
    end

    def read_data(key, agent_id:)
      raise ArgumentError, "Access denied" unless accessible_by?(agent_id)

      touch(:last_accessed_at)
      data.dig(*key.to_s.split("."))
    end

    def write_data(key, value, agent_id:)
      raise ArgumentError, "Access denied" unless accessible_by?(agent_id)
      raise ArgumentError, "Only owner can write" unless owner_agent_id == agent_id

      keys = key.to_s.split(".")
      update_nested_hash(data, keys, value)

      self.last_accessed_at = Time.current
      save!
    end

    def merge_data(data_hash, agent_id:)
      raise ArgumentError, "Access denied" unless accessible_by?(agent_id)
      raise ArgumentError, "Only owner can write" unless owner_agent_id == agent_id

      self.data = data.deep_merge(data_hash)
      self.last_accessed_at = Time.current
      save!
    end

    def accessible_by?(agent_id)
      return true if owner_agent_id == agent_id
      return true if access_control.dig("public") == true

      allowed_agents = access_control.dig("agents") || []
      allowed_agents.include?(agent_id)
    end

    def grant_access(agent_id)
      access_control["agents"] ||= []
      access_control["agents"] << agent_id unless access_control["agents"].include?(agent_id)
      save!
    end

    def revoke_access(agent_id)
      access_control["agents"] ||= []
      access_control["agents"].delete(agent_id)
      save!
    end

    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    def statistics
      {
        total_keys: count_keys(data),
        data_size_bytes: data_size_bytes,
        version: version,
        age_seconds: (Time.current - created_at).to_i,
        access_count: metadata.dig("access_count") || 0,
        last_access_ago: last_accessed_at ? (Time.current - last_accessed_at).to_i : nil
      }
    end

    private

    def generate_pool_id
      self.pool_id ||= "pool_#{pool_type}_#{SecureRandom.hex(8)}"
    end

    def increment_version
      self.version += 1
    end

    def calculate_data_size
      self.data_size_bytes = data.to_json.bytesize
    end

    def broadcast_pool_update
      return unless data_previously_changed?

      McpChannel.broadcast_to_account(
        account_id,
        {
          type: "memory_pool_update",
          pool_id: pool_id,
          version: version
        }
      )
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

    def count_keys(hash, count = 0)
      hash.each do |_key, value|
        count += 1
        count = count_keys(value, count) if value.is_a?(Hash)
      end
      count
    end
  end
end
