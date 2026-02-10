# frozen_string_literal: true

module Ai
  module AgentStorageConfig
    extend ActiveSupport::Concern

    included do
      # Storage configuration is stored in agent's metadata
    end

    # Base storage path scoped to this agent
    def storage_base_path
      "agents/#{account_id}/#{id}"
    end

    # Categories this agent is allowed to store files in
    def allowed_storage_categories
      config = metadata&.dig("storage_config") || {}
      config["allowed_categories"] || %w[workflow_output ai_generated agent_workspace]
    end

    # Maximum storage quota in bytes (default 1GB)
    def storage_quota_bytes
      config = metadata&.dig("storage_config") || {}
      (config["quota_bytes"] || 1.gigabyte).to_i
    end

    # Current storage usage in bytes
    def storage_usage_bytes
      FileManagement::Object
        .where(account_id: account_id)
        .where("storage_key LIKE ?", "#{storage_base_path}/%")
        .sum(:file_size)
    end

    # Check if agent has exceeded its storage quota
    def storage_quota_exceeded?
      storage_usage_bytes >= storage_quota_bytes
    end

    # Remaining storage capacity in bytes
    def storage_remaining_bytes
      [storage_quota_bytes - storage_usage_bytes, 0].max
    end

    # Get the default storage provider for this agent
    def default_storage
      FileManagement::Storage.where(account_id: account_id, is_default: true).first
    end
  end
end
