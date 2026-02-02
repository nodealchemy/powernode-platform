# frozen_string_literal: true

module Ai
  module Memory
    # Working Memory Service - Active task state, current execution context
    # Redis-backed for speed, auto-cleanup on task completion
    class WorkingMemoryService
      REDIS_PREFIX = "ai:working_memory"
      DEFAULT_TTL = 1.hour
      MAX_TTL = 24.hours

      def initialize(agent:, account:, task: nil, workflow_run: nil)
        @agent = agent
        @account = account
        @task = task
        @workflow_run = workflow_run
        @redis = redis_client
      end

      def redis_client
        if Rails.application.config.respond_to?(:redis_client) && Rails.application.config.redis_client
          Rails.application.config.redis_client
        else
          Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
        end
      end

      # ==================== Core Operations ====================

      # Store working memory value
      def store(key, value, ttl: DEFAULT_TTL)
        full_key = build_key(key)
        serialized = serialize_value(value)

        @redis.setex(full_key, [ ttl.to_i, MAX_TTL.to_i ].min, serialized)

        # Also track in a set for cleanup
        @redis.sadd(context_keys_set, full_key)
        @redis.expire(context_keys_set, MAX_TTL.to_i)

        value
      end

      # Retrieve working memory value
      def retrieve(key)
        full_key = build_key(key)
        serialized = @redis.get(full_key)

        return nil unless serialized

        deserialize_value(serialized)
      end

      # Check if key exists
      def exists?(key)
        @redis.exists?(build_key(key))
      end

      # Remove specific key
      def remove(key)
        full_key = build_key(key)
        @redis.del(full_key)
        @redis.srem(context_keys_set, full_key)
      end

      # Get all keys for current context
      def keys
        @redis.smembers(context_keys_set).map do |full_key|
          full_key.sub("#{context_prefix}:", "")
        end
      end

      # Get all working memory for current context
      def all
        keys.each_with_object({}) do |key, hash|
          value = retrieve(key)
          hash[key] = value if value
        end
      end

      # Clear all working memory for current context
      def clear
        keys_to_delete = @redis.smembers(context_keys_set)
        @redis.del(*keys_to_delete) if keys_to_delete.any?
        @redis.del(context_keys_set)
      end

      # ==================== Specialized Operations ====================

      # Store current task state
      def store_task_state(state)
        store("task_state", state, ttl: 2.hours)
      end

      def retrieve_task_state
        retrieve("task_state")
      end

      # Store intermediate results
      def store_intermediate_result(step_name, result)
        store("intermediate:#{step_name}", result)
      end

      def retrieve_intermediate_result(step_name)
        retrieve("intermediate:#{step_name}")
      end

      def all_intermediate_results
        keys.select { |k| k.start_with?("intermediate:") }
            .each_with_object({}) do |key, hash|
              step = key.sub("intermediate:", "")
              hash[step] = retrieve(key)
            end
      end

      # Store conversation context for multi-turn
      def store_conversation_context(messages)
        store("conversation_context", messages, ttl: 4.hours)
      end

      def retrieve_conversation_context
        retrieve("conversation_context") || []
      end

      def append_to_conversation(role:, content:)
        context = retrieve_conversation_context
        context << { "role" => role, "content" => content, "timestamp" => Time.current.iso8601 }
        store_conversation_context(context)
      end

      # Store tool execution state
      def store_tool_state(tool_name, state)
        store("tool:#{tool_name}", state)
      end

      def retrieve_tool_state(tool_name)
        retrieve("tool:#{tool_name}")
      end

      # Store scratch pad for agent reasoning
      def store_scratch_pad(content)
        store("scratch_pad", content, ttl: 1.hour)
      end

      def retrieve_scratch_pad
        retrieve("scratch_pad")
      end

      def append_to_scratch_pad(content)
        existing = retrieve_scratch_pad || ""
        store_scratch_pad("#{existing}\n\n#{content}")
      end

      # ==================== Workflow Integration ====================

      # Get working memory for entire workflow run
      def workflow_memory
        return {} unless @workflow_run

        WorkingMemoryService.new(
          agent: @agent,
          account: @account,
          workflow_run: @workflow_run
        ).all
      end

      # Share memory between agents in a workflow
      def share_with_agent(target_agent, key, value, ttl: DEFAULT_TTL)
        target_service = WorkingMemoryService.new(
          agent: target_agent,
          account: @account,
          workflow_run: @workflow_run
        )

        target_service.store("shared:#{@agent.id}:#{key}", value, ttl: ttl)
      end

      # Retrieve shared memory from another agent
      def retrieve_shared(source_agent_id, key)
        retrieve("shared:#{source_agent_id}:#{key}")
      end

      # ==================== Persistence ====================

      # Persist important working memory to database
      def persist_to_database(key, importance: 0.5)
        value = retrieve(key)
        return unless value

        # Store as working memory type in context entry
        persistent_context = find_or_create_context

        persistent_context.context_entries.create!(
          entry_key: "working:#{context_id}:#{key}",
          entry_type: "memory",
          memory_type: "working",
          content: { "value" => value, "persisted_at" => Time.current.iso8601 },
          ai_agent_id: @agent.id,
          importance_score: importance,
          confidence_score: 1.0,
          expires_at: 24.hours.from_now,  # Working memory expires quickly
          version: 1
        )
      end

      # Load persisted working memory back to Redis
      def load_from_database
        persistent_context = find_or_create_context
        prefix = "working:#{context_id}:"

        persistent_context.context_entries
          .active
          .working
          .where("entry_key LIKE ?", "#{prefix}%")
          .find_each do |entry|
            key = entry.entry_key.sub(prefix, "")
            value = entry.content["value"]
            store(key, value) if value
          end
      end

      # ==================== Statistics ====================

      def statistics
        all_keys = @redis.smembers(context_keys_set)

        total_size = all_keys.sum do |key|
          (@redis.get(key)&.bytesize || 0)
        end

        {
          key_count: all_keys.size,
          total_size_bytes: total_size,
          context_id: context_id,
          agent_id: @agent.id,
          task_id: @task&.task_id,
          workflow_run_id: @workflow_run&.run_id
        }
      end

      private

      def build_key(key)
        "#{context_prefix}:#{key}"
      end

      def context_prefix
        "#{REDIS_PREFIX}:#{context_id}"
      end

      def context_keys_set
        "#{context_prefix}:__keys__"
      end

      def context_id
        @context_id ||= begin
          parts = [ @account.id, @agent.id ]
          parts << @workflow_run.id if @workflow_run
          parts << @task.id if @task
          parts.join(":")
        end
      end

      def serialize_value(value)
        case value
        when String, Numeric, TrueClass, FalseClass, NilClass
          { type: "primitive", value: value }.to_json
        when Hash, Array
          { type: "json", value: value }.to_json
        else
          { type: "marshal", value: Base64.encode64(Marshal.dump(value)) }.to_json
        end
      end

      def deserialize_value(serialized)
        data = JSON.parse(serialized)

        case data["type"]
        when "primitive"
          data["value"]
        when "json"
          data["value"]
        when "marshal"
          Marshal.load(Base64.decode64(data["value"]))
        else
          data["value"]
        end
      rescue JSON::ParserError
        serialized
      end

      def find_or_create_context
        Ai::PersistentContext.find_or_create_by!(
          account_id: @account.id,
          context_type: "agent_memory",
          scope: "agent",
          ai_agent_id: @agent.id,
          name: "#{@agent.name} Working Memory"
        ) do |ctx|
          ctx.access_control = { "level" => "private" }
          ctx.retention_policy = {
            "max_entries" => 1000,
            "max_age_days" => 7
          }
        end
      end
    end
  end
end
