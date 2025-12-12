# frozen_string_literal: true

module Mcp
  # Manages multi-agent communication and coordination
  # Enables LangGraph-style agent-to-agent messaging and shared context
  class MultiAgentCommunicationHub
    attr_reader :workflow_run

    def initialize(workflow_run:)
      @workflow_run = workflow_run
    end

    # Send direct message from one agent to another
    def send_direct_message(from_agent_id:, to_agent_id:, content:, pattern: "request_response")
      AiAgentMessage.create!(
        ai_workflow_run: workflow_run,
        from_agent_id: from_agent_id,
        to_agent_id: to_agent_id,
        message_type: "direct",
        communication_pattern: pattern,
        message_content: content,
        metadata: {
          "sent_at" => Time.current.iso8601,
          "pattern" => pattern
        }
      )
    end

    # Broadcast message to all agents
    def broadcast_message(from_agent_id:, content:, pattern: "publish_subscribe")
      AiAgentMessage.create!(
        ai_workflow_run: workflow_run,
        from_agent_id: from_agent_id,
        to_agent_id: nil, # Broadcast has no specific recipient
        message_type: "broadcast",
        communication_pattern: pattern,
        message_content: content,
        metadata: {
          "broadcast" => true,
          "sent_at" => Time.current.iso8601
        }
      )
    end

    # Send request and wait for response
    def request_response(from_agent_id:, to_agent_id:, request_content:, timeout: 30)
      request_msg = send_direct_message(
        from_agent_id: from_agent_id,
        to_agent_id: to_agent_id,
        content: request_content,
        pattern: "request_response"
      )

      # Wait for response with timeout
      start_time = Time.current
      response = nil

      while (Time.current - start_time) < timeout
        response = AiAgentMessage.find_by(
          ai_workflow_run_id: workflow_run.id,
          in_reply_to_message_id: request_msg.message_id,
          message_type: "response"
        )

        break if response
        sleep 0.1 # Poll every 100ms
      end

      if response
        response.mark_delivered!
        { success: true, response: response.message_content, message: response }
      else
        { success: false, error: "Response timeout", timeout: timeout }
      end
    end

    # Fire and forget message (no response expected)
    def fire_and_forget(from_agent_id:, to_agent_id:, content:)
      send_direct_message(
        from_agent_id: from_agent_id,
        to_agent_id: to_agent_id,
        content: content,
        pattern: "fire_and_forget"
      ).tap do |msg|
        msg.mark_delivered!
      end
    end

    # Get unread messages for an agent
    def get_unread_messages(agent_id)
      AiAgentMessage.unread_for_agent(agent_id, workflow_run.id)
    end

    # Mark message as read
    def mark_message_read(message_id, agent_id)
      message = AiAgentMessage.find_by(message_id: message_id, ai_workflow_run_id: workflow_run.id)
      raise ArgumentError, "Message not found" unless message
      raise ArgumentError, "Not the recipient" unless message.to_agent_id == agent_id

      message.mark_acknowledged!
    end

    # Get conversation between two agents
    def get_conversation(agent_a_id, agent_b_id)
      AiAgentMessage.conversation_between(agent_a_id, agent_b_id, workflow_run.id)
                    .map(&:message_summary)
    end

    # Create or get shared context pool
    def create_context_pool(owner_agent_id:, pool_type: "shared_memory", scope: "workflow", initial_data: {})
      AiSharedContextPool.create!(
        ai_workflow_run: workflow_run,
        pool_type: pool_type,
        scope: scope,
        owner_agent_id: owner_agent_id,
        context_data: initial_data,
        access_control: {
          "owner" => owner_agent_id,
          "public" => false,
          "agents" => []
        },
        metadata: {
          "created_at" => Time.current.iso8601,
          "access_count" => 0
        }
      )
    end

    # Get context pool by ID
    def get_context_pool(pool_id)
      AiSharedContextPool.find_by(pool_id: pool_id, ai_workflow_run_id: workflow_run.id)
    end

    # List context pools
    def list_context_pools(pool_type: nil, scope: nil, agent_id: nil)
      pools = AiSharedContextPool.for_run(workflow_run.id).active

      pools = pools.by_type(pool_type) if pool_type
      pools = pools.by_scope(scope) if scope
      pools = pools.accessible_by(agent_id) if agent_id

      pools.map(&:pool_summary)
    end

    # Write to shared context pool
    def write_to_pool(pool_id:, key:, value:, agent_id:)
      pool = get_context_pool(pool_id)
      raise ArgumentError, "Pool not found" unless pool

      pool.write_data(key, value, agent_id: agent_id)

      # Increment access count
      pool.metadata["access_count"] = (pool.metadata["access_count"] || 0) + 1
      pool.save!

      { success: true, version: pool.version }
    end

    # Read from shared context pool
    def read_from_pool(pool_id:, key:, agent_id:)
      pool = get_context_pool(pool_id)
      raise ArgumentError, "Pool not found" unless pool

      value = pool.read_data(key, agent_id: agent_id)

      # Increment access count
      pool.metadata["access_count"] = (pool.metadata["access_count"] || 0) + 1
      pool.save!

      { success: true, value: value, version: pool.version }
    end

    # Blackboard pattern - post partial solution
    def post_to_blackboard(blackboard_id:, agent_id:, contribution:)
      pool = get_context_pool(blackboard_id)
      raise ArgumentError, "Blackboard not found" unless pool
      raise ArgumentError, "Not a blackboard pool" unless pool.pool_type == "blackboard"

      # Append contribution to blackboard
      contributions = pool.context_data["contributions"] || []
      contributions << {
        "agent_id" => agent_id,
        "contribution" => contribution,
        "timestamp" => Time.current.iso8601,
        "sequence" => contributions.length
      }

      pool.write_data("contributions", contributions, agent_id: pool.owner_agent_id)

      broadcast_message(
        from_agent_id: agent_id,
        content: {
          "type" => "blackboard_update",
          "blackboard_id" => blackboard_id,
          "contribution" => contribution
        },
        pattern: "publish_subscribe"
      )

      { success: true, contribution_index: contributions.length - 1 }
    end

    # Read all blackboard contributions
    def read_blackboard(blackboard_id:, agent_id:)
      pool = get_context_pool(blackboard_id)
      raise ArgumentError, "Blackboard not found" unless pool
      raise ArgumentError, "Not a blackboard pool" unless pool.pool_type == "blackboard"

      contributions = pool.read_data("contributions", agent_id: agent_id) || []

      { success: true, contributions: contributions, total: contributions.length }
    end

    # Tool result caching
    def cache_tool_result(tool_name:, input_hash:, result:, agent_id:)
      cache_key = "#{tool_name}_#{Digest::SHA256.hexdigest(input_hash.to_json)}"

      # Find or create tool cache pool
      cache_pool = AiSharedContextPool.for_run(workflow_run.id)
                                     .by_type("tool_cache")
                                     .by_scope("workflow")
                                     .first

      cache_pool ||= create_context_pool(
        owner_agent_id: agent_id,
        pool_type: "tool_cache",
        scope: "workflow"
      )

      write_to_pool(
        pool_id: cache_pool.pool_id,
        key: cache_key,
        value: {
          "result" => result,
          "cached_at" => Time.current.iso8601,
          "tool_name" => tool_name,
          "input_hash" => input_hash
        },
        agent_id: agent_id
      )
    end

    # Get cached tool result
    def get_cached_tool_result(tool_name:, input_hash:)
      cache_key = "#{tool_name}_#{Digest::SHA256.hexdigest(input_hash.to_json)}"

      cache_pool = AiSharedContextPool.for_run(workflow_run.id)
                                     .by_type("tool_cache")
                                     .by_scope("workflow")
                                     .first

      return { success: false, cached: false } unless cache_pool

      begin
        cached_data = cache_pool.read_data(cache_key, agent_id: cache_pool.owner_agent_id)
        return { success: false, cached: false } unless cached_data

        { success: true, cached: true, result: cached_data["result"], cached_at: cached_data["cached_at"] }
      rescue ArgumentError
        { success: false, cached: false }
      end
    end

    # Hierarchical agent coordination
    def send_command(coordinator_agent_id:, worker_agent_id:, command:)
      send_direct_message(
        from_agent_id: coordinator_agent_id,
        to_agent_id: worker_agent_id,
        content: {
          "type" => "command",
          "command" => command,
          "timestamp" => Time.current.iso8601
        },
        pattern: "command_query"
      ).tap do |msg|
        msg.update(metadata: msg.metadata.merge("command" => true))
      end
    end

    # Worker reports result back to coordinator
    def report_result(worker_agent_id:, coordinator_agent_id:, result:, command_message_id:)
      command_msg = AiAgentMessage.find_by(message_id: command_message_id)

      command_msg.create_reply(
        from_agent_id: worker_agent_id,
        content: {
          "type" => "result",
          "result" => result,
          "timestamp" => Time.current.iso8601
        },
        type: "response"
      )
    end

    # Get communication statistics
    def communication_stats
      messages = AiAgentMessage.for_run(workflow_run.id)

      {
        total_messages: messages.count,
        by_type: messages.group(:message_type).count,
        by_pattern: messages.group(:communication_pattern).count,
        by_status: messages.group(:status).count,
        active_agents: messages.distinct.pluck(:from_agent_id).compact.count,
        active_context_pools: AiSharedContextPool.for_run(workflow_run.id).active.count,
        broadcasts: messages.broadcasts.count,
        direct_messages: messages.direct_messages.count
      }
    end
  end
end
