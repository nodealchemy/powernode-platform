# frozen_string_literal: true

# Async context assembly for long conversations
# Queue: ai_conversations (priority 2)
#
# Pre-builds optimized context windows for chat conversations:
# - System prompt + agent config
# - RAG results (if applicable)
# - Memory injection (compound learnings, context entries)
# - Recent message history with token budget awareness
#
# Stores assembled context in Redis working memory for
# AiChatResponseJob to consume, enabling context pre-computation
# while the user is still typing.
class AiChatContextBuilderJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_conversations', retry: 1

  # Default token budget for context assembly
  DEFAULT_TOKEN_BUDGET = 4096
  CONTEXT_TTL = 300 # 5 minutes

  def execute(conversation_id, agent_id, account_id, options = {})
    validate_required_params(
      { 'conversation_id' => conversation_id, 'agent_id' => agent_id,
        'account_id' => account_id },
      'conversation_id', 'agent_id', 'account_id'
    )

    log_info("Building chat context",
      conversation_id: conversation_id,
      agent_id: agent_id
    )

    start_time = Time.current

    begin
      # Fetch agent configuration
      agent = fetch_agent(agent_id)
      return unless agent

      # Fetch conversation with recent messages
      conversation = fetch_conversation(conversation_id)
      return unless conversation

      # Build context components
      token_budget = (options['token_budget'] || DEFAULT_TOKEN_BUDGET).to_i
      context = assemble_context(agent, conversation, token_budget)

      # Store in Redis for consumption by AiChatResponseJob
      cache_key = "chat_context:#{conversation_id}"
      store_context(cache_key, context)

      duration_ms = ((Time.current - start_time) * 1000).to_i

      log_info("Chat context built successfully",
        conversation_id: conversation_id,
        components: context[:components].size,
        estimated_tokens: context[:estimated_tokens],
        duration_ms: duration_ms
      )

    rescue StandardError => e
      log_error("Context build failed",
        conversation_id: conversation_id,
        error: e.message
      )
      # Non-critical - chat can still work without pre-built context
    end
  end

  private

  def fetch_agent(agent_id)
    response = backend_api_get("/api/v1/ai/agents/#{agent_id}")

    if response['success']
      response['data']['agent'] || response['data']
    else
      log_error("Failed to fetch agent for context build", agent_id: agent_id)
      nil
    end
  end

  def fetch_conversation(conversation_id)
    response = backend_api_get("/api/v1/ai/conversations/#{conversation_id}")

    if response['success']
      response['data']['conversation']
    else
      log_error("Failed to fetch conversation for context build", conversation_id: conversation_id)
      nil
    end
  end

  def assemble_context(agent, conversation, token_budget)
    components = []
    tokens_used = 0

    # 1. System prompt (highest priority, always included)
    if agent['system_prompt'].present?
      system_tokens = estimate_tokens(agent['system_prompt'])
      components << {
        type: 'system_prompt',
        content: agent['system_prompt'],
        tokens: system_tokens,
        priority: 1
      }
      tokens_used += system_tokens
    end

    # 2. Agent skills/capabilities
    skills = agent['skills'] || []
    active_skills = skills.select { |s| s['is_active'] != false && s['status'] == 'active' }
    if active_skills.any?
      skill_text = active_skills.map { |s|
        parts = [s['name']]
        parts << s['system_prompt'] if s['system_prompt'].present?
        parts.join(': ')
      }.join("\n")

      skill_tokens = estimate_tokens(skill_text)
      if tokens_used + skill_tokens <= token_budget
        components << {
          type: 'skills',
          content: skill_text,
          tokens: skill_tokens,
          priority: 2
        }
        tokens_used += skill_tokens
      end
    end

    # 3. Recent message history (critical for continuity)
    messages = conversation['recent_messages'] || []
    messages.each do |msg|
      next if msg['role'] == 'system'

      msg_tokens = estimate_tokens(msg['content'] || '')
      break if tokens_used + msg_tokens > token_budget * 0.7 # Reserve 30% for response

      components << {
        type: 'message',
        role: msg['role'],
        content: msg['content'],
        tokens: msg_tokens,
        priority: 3
      }
      tokens_used += msg_tokens
    end

    # 4. Memory/context injection (if budget allows)
    remaining_budget = (token_budget * 0.7) - tokens_used
    if remaining_budget > 200
      memory_context = fetch_memory_context(agent, conversation, remaining_budget.to_i)
      if memory_context.present?
        mem_tokens = estimate_tokens(memory_context)
        components << {
          type: 'memory',
          content: memory_context,
          tokens: mem_tokens,
          priority: 4
        }
        tokens_used += mem_tokens
      end
    end

    {
      components: components,
      estimated_tokens: tokens_used,
      token_budget: token_budget,
      built_at: Time.current.iso8601
    }
  end

  def fetch_memory_context(agent, conversation, token_budget)
    # Try to get compound learnings for the agent
    last_message = (conversation['recent_messages'] || []).last
    return nil unless last_message

    response = backend_api_post("/api/v1/ai/memory/context", {
      agent_id: agent['id'],
      query: last_message['content'],
      token_budget: token_budget
    })

    if response['success']
      response['data']['context']
    else
      nil
    end
  rescue StandardError => e
    log_info("Memory context fetch skipped: #{e.message}")
    nil
  end

  def estimate_tokens(text)
    return 0 if text.blank?

    # Rough estimation: ~4 chars per token for English text
    (text.length / 4.0).ceil
  end

  def store_context(cache_key, context)
    Sidekiq.redis do |conn|
      conn.set(cache_key, context.to_json, ex: CONTEXT_TTL)
    end
  end
end
