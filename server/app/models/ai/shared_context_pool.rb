# frozen_string_literal: true

module Ai
  class SharedContextPool < ApplicationRecord
    # ==================== Associations ====================
    belongs_to :workflow_run, class_name: "Ai::WorkflowRun", foreign_key: "ai_workflow_run_id"

    # ==================== Validations ====================
    validates :pool_id, presence: true, uniqueness: true
    validates :pool_type, presence: true, inclusion: {
      in: %w[shared_memory tool_cache result_cache knowledge_base blackboard],
      message: "%{value} is not a valid pool type"
    }
    validates :scope, presence: true, inclusion: {
      in: %w[workflow agent_group global temporary],
      message: "%{value} is not a valid scope"
    }
    validates :context_data, presence: true
    validates :version, presence: true, numericality: { only_integer: true, greater_than: 0 }

    # ==================== Scopes ====================
    scope :for_run, ->(run_id) { where(ai_workflow_run_id: run_id) }
    scope :by_type, ->(type) { where(pool_type: type) }
    scope :by_scope, ->(scope) { where(scope: scope) }
    scope :owned_by, ->(agent_id) { where(owner_agent_id: agent_id) }
    scope :accessible_by, ->(agent_id) do
      where("access_control->>'agents' @> ?", [agent_id].to_json)
        .or(where(owner_agent_id: agent_id))
        .or(where("access_control->>'public' = 'true'"))
    end
    scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
    scope :expired, -> { where("expires_at <= ?", Time.current) }
    scope :shared_memories, -> { where(pool_type: "shared_memory") }
    scope :tool_caches, -> { where(pool_type: "tool_cache") }
    scope :blackboards, -> { where(pool_type: "blackboard") }

    # ==================== Callbacks ====================
    before_validation :generate_pool_id, on: :create
    before_save :increment_version, if: :context_data_changed?
    after_update :broadcast_context_update

    # ==================== Instance Methods ====================

    # Get pool summary
    def pool_summary
      {
        id: id,
        pool_id: pool_id,
        type: pool_type,
        scope: scope,
        owner: owner_agent_id,
        version: version,
        size: context_data.size,
        created_at: created_at,
        last_accessed: last_accessed_at,
        expires_at: expires_at
      }
    end

    # Full pool details
    def pool_details
      pool_summary.merge(
        context_data: context_data,
        access_control: access_control,
        metadata: metadata
      )
    end

    # Check if agent has access
    def accessible_by?(agent_id)
      return true if owner_agent_id == agent_id
      return true if access_control.dig("public") == true

      allowed_agents = access_control.dig("agents") || []
      allowed_agents.include?(agent_id)
    end

    # Grant access to agent
    def grant_access(agent_id)
      access_control["agents"] ||= []
      access_control["agents"] << agent_id unless access_control["agents"].include?(agent_id)
      save!
    end

    # Revoke access from agent
    def revoke_access(agent_id)
      access_control["agents"] ||= []
      access_control["agents"].delete(agent_id)
      save!
    end

    # Make pool public
    def make_public!
      update!(access_control: access_control.merge("public" => true))
    end

    # Make pool private
    def make_private!
      update!(access_control: access_control.merge("public" => false))
    end

    # Read data from pool
    def read_data(key, agent_id:)
      raise ArgumentError, "Access denied" unless accessible_by?(agent_id)

      touch(:last_accessed_at)
      context_data.dig(*key.to_s.split("."))
    end

    # Write data to pool
    def write_data(key, value, agent_id:)
      raise ArgumentError, "Access denied" unless accessible_by?(agent_id)
      raise ArgumentError, "Only owner can write" unless owner_agent_id == agent_id

      keys = key.to_s.split(".")
      update_nested_hash(context_data, keys, value)

      self.last_accessed_at = Time.current
      save!
    end

    # Merge data into pool
    def merge_data(data_hash, agent_id:)
      raise ArgumentError, "Access denied" unless accessible_by?(agent_id)
      raise ArgumentError, "Only owner can write" unless owner_agent_id == agent_id

      self.context_data = context_data.deep_merge(data_hash)
      self.last_accessed_at = Time.current
      save!
    end

    # Clear all data
    def clear_data!(agent_id:)
      raise ArgumentError, "Only owner can clear" unless owner_agent_id == agent_id

      self.context_data = {}
      save!
    end

    # Check if pool is expired
    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    # Set expiration time
    def set_expiration(duration)
      update!(expires_at: Time.current + duration)
    end

    # Get pool statistics
    def statistics
      {
        total_keys: count_keys(context_data),
        data_size_bytes: context_data.to_json.bytesize,
        version: version,
        age_seconds: (Time.current - created_at).to_i,
        access_count: metadata.dig("access_count") || 0,
        last_access_ago: last_accessed_at ? (Time.current - last_accessed_at).to_i : nil
      }
    end

    # Create snapshot of current state
    def create_snapshot
      {
        pool_id: pool_id,
        version: version,
        snapshot_at: Time.current.iso8601,
        data: context_data.deep_dup,
        metadata: {
          "snapshot_version" => version,
          "data_hash" => Digest::SHA256.hexdigest(context_data.to_json)
        }
      }
    end

    # Restore from snapshot
    def restore_from_snapshot(snapshot, agent_id:)
      raise ArgumentError, "Only owner can restore" unless owner_agent_id == agent_id

      self.context_data = snapshot["data"]
      self.metadata = metadata.merge(
        "restored_from_version" => snapshot["version"],
        "restored_at" => Time.current.iso8601
      )
      save!
    end

    private

    # Generate unique pool ID
    def generate_pool_id
      self.pool_id ||= "pool_#{pool_type}_#{SecureRandom.hex(8)}"
    end

    # Increment version on data change
    def increment_version
      self.version += 1
    end

    # Broadcast context update via WebSocket
    def broadcast_context_update
      return unless context_data_previously_changed?

      McpChannel.broadcast_to(
        "account_#{workflow_run.account_id}",
        {
          type: "context_pool_update",
          workflow_run_id: workflow_run.run_id,
          pool_id: pool_id,
          version: version
        }
      )
    end

    # Update nested hash with dot notation
    def update_nested_hash(hash, keys, value)
      if keys.length == 1
        hash[keys.first] = value
      else
        key = keys.shift
        hash[key] ||= {}
        update_nested_hash(hash[key], keys, value)
      end
    end

    # Count total keys in nested hash
    def count_keys(hash, count = 0)
      hash.each do |_key, value|
        count += 1
        count = count_keys(value, count) if value.is_a?(Hash)
      end
      count
    end
  end
end
