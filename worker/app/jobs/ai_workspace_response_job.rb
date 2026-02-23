# frozen_string_literal: true

# Generates AI responses for non-primary workspace team member agents.
# Dispatched after the concierge (primary agent) responds in a workspace conversation.
# Each team member agent runs independently and broadcasts its response via ActionCable.
#
# Queue: ai_conversations (same priority as regular chat responses)
# Retry: 1 (workspace responses are best-effort, not critical path)
class AiWorkspaceResponseJob < BaseJob
  include AiJobsConcern
  include ChatStreamingConcern
  include ChatFallbackProvidersConcern

  sidekiq_options queue: 'ai_conversations', retry: 1

  def execute(conversation_id, message_id, agent_id, account_id)
    validate_required_params(
      { 'conversation_id' => conversation_id, 'message_id' => message_id,
        'agent_id' => agent_id, 'account_id' => account_id },
      'conversation_id', 'message_id', 'agent_id', 'account_id'
    )

    # Idempotency check — keyed per agent to allow parallel execution
    idempotency_key = "workspace_response:#{message_id}:#{agent_id}"
    if already_processed?(idempotency_key)
      log_info("Workspace response already processed", message_id: message_id, agent_id: agent_id)
      return
    end

    log_info("Starting workspace response generation",
      conversation_id: conversation_id,
      message_id: message_id,
      agent_id: agent_id
    )

    @conversation_id = conversation_id
    @message_id = message_id
    @agent_id = agent_id
    start_time = Time.current

    begin
      # Fetch conversation data from backend
      conv_response = backend_api_get("/api/v1/ai/conversations/#{conversation_id}")
      unless conv_response['success']
        broadcast_error(conversation_id, "Failed to fetch conversation")
        return
      end

      conversation_data = conv_response['data']['conversation']

      # Fetch agent data
      agent = fetch_agent(agent_id, account_id)
      return unless agent

      @agent_name = agent['name'] || 'AI Assistant'

      provider = agent['ai_provider'] || agent['provider']
      return broadcast_error(conversation_id, "Agent has no provider configured") unless provider

      # Fetch credentials
      credentials = fetch_credentials(provider['id'])
      return broadcast_error(conversation_id, "No active credentials for provider") unless credentials

      # Build workspace-aware messages with context injection
      messages = build_workspace_messages(conversation_data, agent)

      # Call AI provider with streaming
      ai_result = call_provider_streaming(provider, credentials, agent, messages)

      duration_ms = ((Time.current - start_time) * 1000).to_i

      if ai_result[:success]
        # Broadcast completion with agent_id for correct attribution
        broadcast_workspace_complete(
          conversation_id,
          message_id,
          ai_result[:content],
          token_count: ai_result[:tokens_used] || 0,
          cost_usd: ai_result[:cost] || 0.0,
          model: ai_result[:model],
          duration_ms: duration_ms
        )

        mark_processed(idempotency_key, ttl: 3600)

        log_info("Workspace response completed",
          conversation_id: conversation_id,
          agent_id: agent_id,
          agent_name: @agent_name,
          duration_ms: duration_ms,
          tokens: ai_result[:tokens_used],
          cost: ai_result[:cost]
        )
      else
        broadcast_error(conversation_id, ai_result[:error] || "AI provider error")

        log_error("Workspace response failed",
          conversation_id: conversation_id,
          agent_id: agent_id,
          error: ai_result[:error]
        )
      end
    rescue StandardError => e
      broadcast_error(conversation_id, "Internal error generating workspace response")
      handle_ai_processing_error(e, {
        conversation_id: conversation_id,
        message_id: message_id,
        agent_id: agent_id,
        job_type: "workspace_response"
      })
    end
  end

  private

  def fetch_agent(agent_id, _account_id)
    response = backend_api_get("/api/v1/ai/agents/#{agent_id}")

    if response['success']
      response['data']['agent'] || response['data']
    else
      log_error("Failed to fetch agent", agent_id: agent_id)
      broadcast_error(nil, "Agent not found")
      nil
    end
  end

  def fetch_credentials(provider_id)
    # List credentials to find the default active one
    list_response = backend_api_get("/api/v1/ai/providers/#{provider_id}/credentials", {
      default_only: true,
      active: true
    })

    return nil unless list_response['success']

    creds = list_response['data']['credentials']
    cred = creds.is_a?(Array) ? creds.first : creds
    return nil unless cred

    # Fetch credential detail to get decrypted keys (workers get full access)
    detail_response = backend_api_get("/api/v1/ai/providers/#{provider_id}/credentials/#{cred['id']}")
    return nil unless detail_response['success']

    detail_response['data']['credential'] || cred
  end

  def build_workspace_messages(conversation_data, agent)
    messages = []

    # Build workspace context injection
    workspace_context = build_workspace_context(conversation_data, agent)

    # System prompt: agent's own prompt + workspace context
    system_prompt = agent['system_prompt'] || ""
    full_system = [workspace_context, system_prompt].reject(&:blank?).join("\n\n")
    messages << { role: 'system', content: full_system } if full_system.present?

    # Add recent messages from conversation in chronological order
    # (recent_messages come from the API in desc order — reverse to asc for the LLM)
    if conversation_data && conversation_data['recent_messages'].is_a?(Array)
      conversation_data['recent_messages'].reverse.last(20).each do |msg|
        next if msg['role'] == 'system'

        messages << { role: msg['role'], content: msg['content'] }
      end
    end

    # Trim trailing assistant messages so the array ends with the user's message.
    # By the time this job runs, the concierge has already responded, placing an
    # assistant message at the end of history. The LLM needs a user message last
    # to know what to respond to.
    messages.pop while messages.last && messages.last[:role] == 'assistant'

    messages
  end

  def build_workspace_context(conversation_data, agent)
    workspace_name = conversation_data&.dig('agent_team', 'name') ||
                     conversation_data&.dig('title') ||
                     "Workspace"

    # Build participant list from team members if available
    participants = []
    team_members = conversation_data&.dig('agent_team', 'members')
    if team_members.is_a?(Array)
      team_members.each do |member|
        member_agent = member['agent'] || member
        name = member_agent['name'] || 'Unknown Agent'
        agent_type = member_agent['agent_type'] || 'assistant'
        participants << "#{name} (#{agent_type})"
      end
    end

    agent_name = agent['name'] || 'AI Assistant'
    participant_list = participants.any? ? participants.join(", ") : "multiple agents"

    <<~CONTEXT.strip
      You are participating in a collaborative workspace called "#{workspace_name}".
      Other participants: #{participant_list}.
      A user has sent a message. Respond from your perspective as #{agent_name}.
      Keep your response focused and concise — other agents are also responding.
    CONTEXT
  end

  # Override broadcast_complete to include agent_id for correct message attribution
  def broadcast_workspace_complete(conversation_id, message_id, content, token_count:, cost_usd:, model:, duration_ms:)
    backend_api_post("/api/v1/ai/conversations/#{conversation_id}/worker_complete", {
      message_id: message_id,
      content: content,
      token_count: token_count,
      cost_usd: cost_usd,
      model: model,
      duration_ms: duration_ms,
      agent_id: @agent_id
    })
  rescue StandardError => e
    log_error("Failed to broadcast workspace completion", error: e.message, agent_id: @agent_id)
  end

  def call_provider_streaming(provider, credentials, agent, messages)
    provider_type = provider['provider_type']&.downcase || 'openai'
    model = agent['model'] || provider['default_model'] || 'gpt-4'
    temperature = agent['temperature'] || 0.7
    max_tokens = agent['max_tokens'] || 2048

    # Extract API key from credential detail (workers receive decrypted credentials)
    cred_data = credentials['credentials'] || {}
    api_key = cred_data['api_key'] || cred_data['key']
    base_url = cred_data['base_url'] || provider['base_url']

    case provider_type
    when 'openai', 'openai_compatible'
      call_openai_streaming(api_key, base_url, model, messages, temperature, max_tokens)
    when 'anthropic'
      call_anthropic_streaming(api_key, base_url, model, messages, temperature, max_tokens)
    when 'ollama'
      call_ollama_streaming(base_url, model, messages, temperature, max_tokens)
    else
      call_generic(api_key, base_url, model, messages, temperature, max_tokens)
    end
  end
end
