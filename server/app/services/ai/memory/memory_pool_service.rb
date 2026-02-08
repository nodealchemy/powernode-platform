# frozen_string_literal: true

module Ai
  module Memory
    class MemoryPoolService
      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Create a new memory pool
      def create_pool(params)
        pool = Ai::MemoryPool.new(
          account: account,
          name: params[:name],
          pool_type: params[:pool_type] || "shared_memory",
          scope: params[:scope] || "team",
          owner_agent_id: params[:owner_agent_id],
          team_id: params[:team_id],
          task_execution_id: params[:task_execution_id],
          data: params[:data] || {},
          access_control: build_access_control(params[:access_control]),
          retention_policy: params[:retention_policy] || {},
          persist_across_executions: params[:persist_across_executions] || false,
          expires_at: params[:expires_at],
          metadata: params[:metadata] || {}
        )

        pool.save!
        Rails.logger.info("Created memory pool #{pool.pool_id} for account #{account.id}")
        pool
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("Failed to create memory pool: #{e.message}")
        raise
      end

      # Update pool attributes
      def update_pool(pool, params)
        updatable = params.slice(
          :name, :scope, :access_control, :retention_policy,
          :persist_across_executions, :expires_at, :metadata
        )

        pool.update!(updatable)
        Rails.logger.info("Updated memory pool #{pool.pool_id}")
        pool
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("Failed to update memory pool #{pool.pool_id}: #{e.message}")
        raise
      end

      # Delete pool with cleanup
      def delete_pool(pool)
        pool_id = pool.pool_id
        pool.destroy!
        Rails.logger.info("Deleted memory pool #{pool_id}")
        true
      end

      # Read data with access control
      def read_data(pool, key, agent_id:)
        unless pool.accessible_by?(agent_id)
          Rails.logger.warn("Access denied: agent #{agent_id} reading pool #{pool.pool_id}")
          raise ArgumentError, "Access denied for agent #{agent_id}"
        end

        pool.touch(:last_accessed_at)
        keys = key.to_s.split(".")
        pool.data.dig(*keys)
      end

      # Write data with access control
      def write_data(pool, key, value, agent_id:)
        unless pool.accessible_by?(agent_id)
          Rails.logger.warn("Access denied: agent #{agent_id} writing pool #{pool.pool_id}")
          raise ArgumentError, "Access denied for agent #{agent_id}"
        end

        keys = key.to_s.split(".")
        update_nested_hash(pool.data, keys, value)
        pool.data_size_bytes = pool.data.to_json.bytesize
        pool.last_accessed_at = Time.current
        pool.save!
        value
      end

      # Query pools with filters
      def query_pools(filters = {})
        scope = Ai::MemoryPool.where(account: account)

        scope = scope.where(scope: filters[:scope]) if filters[:scope].present?
        scope = scope.where(pool_type: filters[:pool_type]) if filters[:pool_type].present?
        scope = scope.where(owner_agent_id: filters[:agent_id]) if filters[:agent_id].present?
        scope = scope.where(team_id: filters[:team_id]) if filters[:team_id].present?
        scope = scope.where("expires_at IS NULL OR expires_at > ?", Time.current) unless filters[:include_expired]

        scope.order(updated_at: :desc)
      end

      # Auto-create a team execution pool with pre-structured data
      def create_team_execution_pool(team_execution:, team:)
        create_pool(
          name: "Team Execution: #{team.name} - #{team_execution&.id.to_s[0..7]}",
          pool_type: "team_shared",
          scope: "execution",
          team_id: team.id,
          task_execution_id: team_execution&.id,
          data: {
            "learnings" => [],
            "shared_state" => {},
            "member_outputs" => {}
          },
          access_control: { public: true, agents: [] },
          persist_across_executions: false,
          metadata: {
            "team_name" => team.name,
            "team_type" => team.team_type,
            "created_by" => "auto"
          }
        )
      end

      # Find or create the global learning pool for cross-execution learning
      def ensure_global_learning_pool
        Ai::MemoryPool.find_or_create_by!(
          account: account,
          name: "Global Learnings",
          pool_type: "global",
          scope: "persistent"
        ) do |pool|
          pool.data = { "learnings" => [] }
          pool.access_control = { "public" => true, "agents" => [] }
          pool.persist_across_executions = true
          pool.metadata = { "created_by" => "auto", "purpose" => "cross_execution_learning" }
        end
      rescue ActiveRecord::RecordInvalid
        Ai::MemoryPool.find_by(
          account: account,
          name: "Global Learnings",
          pool_type: "global",
          scope: "persistent"
        )
      end

      private

      def build_access_control(config)
        return { "public" => false, "agents" => [] } if config.blank?

        {
          "public" => config[:public] || false,
          "agents" => config[:agents] || [],
          "read_only_agents" => config[:read_only_agents] || []
        }
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
end
