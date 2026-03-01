# frozen_string_literal: true

require_relative 'credential_resolver'
require_relative 'ai/llm/client'

# LLM client that calls AI providers directly from the worker process.
#
# For pure LLM calls (complete, complete_with_tools, complete_structured):
#   Resolves credentials via CredentialResolver and calls the provider directly.
#
# For tool-related calls (tool_definitions, dispatch_tool):
#   Delegates to the server which owns tool registries and execution.
#
# For orchestration calls (execute_tool_loop, execute_with_reasoning):
#   Runs the LLM loop locally, dispatching tool calls through the server.
#
class LlmProxyClient
  TOOL_LOOP_MAX_ITERATIONS = 10
  SERVER_TOOL_PATH = "/api/v1/internal/ai/llm"

  # @param api_post_method [Method] a bound method reference to backend_api_post
  def initialize(api_post_method)
    @api_post = api_post_method
    @credential_resolver = CredentialResolver.new(api_post_method)
    @llm_clients = {} # Cache per credential_id
  end

  # Standard LLM completion -- calls provider directly
  def complete(agent_id:, messages:, model: nil, **opts)
    provider_config = fetch_provider_config(agent_id)
    client = build_llm_client(provider_config)
    model ||= provider_config["model"]

    response = client.complete(messages: messages, model: model, **opts)
    format_response(response)
  end

  # LLM completion with tool-calling -- calls provider directly
  def complete_with_tools(agent_id:, messages:, tools: [], model: nil, **opts)
    provider_config = fetch_provider_config(agent_id)
    client = build_llm_client(provider_config)
    model ||= provider_config["model"]

    tools = symbolize_tools(tools)
    response = client.complete_with_tools(messages: messages, tools: tools, model: model, **opts)
    format_response(response)
  end

  # Structured output (JSON schema enforced) -- calls provider directly
  def complete_structured(agent_id:, messages:, schema:, model: nil, **opts)
    provider_config = fetch_provider_config(agent_id)
    client = build_llm_client(provider_config)
    model ||= provider_config["model"]

    schema = deep_symbolize(schema)
    response = client.complete_structured(messages: messages, schema: schema, model: model, **opts)
    format_response(response)
  end

  # Get tool definitions available to an agent (server-side, no LLM call)
  def tool_definitions(agent_id:)
    call_server(:tool_definitions, agent_id: agent_id)
  end

  # Dispatch a single tool call through the server (no LLM call)
  def dispatch_tool(agent_id:, tool_call:)
    call_server(:dispatch_tool, agent_id: agent_id, tool_call: tool_call)
  end

  # Run the full agentic tool loop -- LLM calls happen locally,
  # tool definitions and dispatch go through the server.
  def execute_tool_loop(agent_id:, messages:, model: nil, **opts)
    provider_config = fetch_provider_config(agent_id)
    client = build_llm_client(provider_config)
    model ||= provider_config["model"]

    # Fetch tool definitions from server
    tools_response = call_server(:tool_definitions, agent_id: agent_id)
    tools = tools_response["tools"] || []
    tools_enabled = tools_response["tools_enabled"]

    # If tools disabled, fall back to simple completion
    unless tools_enabled && tools.any?
      response = client.complete(messages: messages, model: model, **opts)
      return format_response(response)
    end

    tool_calls_log = []
    current_messages = deep_copy_messages(messages)
    total_usage = { prompt_tokens: 0, completion_tokens: 0, cached_tokens: 0, total_tokens: 0 }
    last_response = nil
    max_iterations = opts.delete(:max_iterations) || TOOL_LOOP_MAX_ITERATIONS

    max_iterations.times do |iteration|
      # Call LLM with tools -- provider called directly
      symbolized_tools = symbolize_tools(tools)
      response = client.complete_with_tools(
        messages: current_messages, tools: symbolized_tools, model: model, **opts
      )

      accumulate_usage(total_usage, response.usage)
      last_response = response

      # If no tool calls, we're done
      unless response.has_tool_calls?
        return {
          "content" => response.content,
          "usage" => total_usage,
          "tool_calls_log" => tool_calls_log,
          "finish_reason" => response.finish_reason
        }
      end

      # Add assistant message with tool calls to conversation
      current_messages << {
        role: "assistant",
        content: response.content,
        tool_calls: response.tool_calls
      }

      # Dispatch each tool call through the server
      response.tool_calls.each do |tool_call|
        begin
          result = call_server(:dispatch_tool, agent_id: agent_id, tool_call: tool_call)
          tool_output = result.is_a?(Hash) ? (result["result"] || result).to_json : result.to_s

          tool_calls_log << {
            iteration: iteration + 1,
            tool_name: tool_call[:name],
            tool_call_id: tool_call[:id],
            success: true
          }

          current_messages << {
            role: "tool",
            tool_call_id: tool_call[:id],
            content: tool_output
          }
        rescue StandardError => e
          tool_calls_log << {
            iteration: iteration + 1,
            tool_name: tool_call[:name],
            tool_call_id: tool_call[:id],
            success: false,
            error: e.message
          }

          current_messages << {
            role: "tool",
            tool_call_id: tool_call[:id],
            content: { error: e.message }.to_json
          }
        end
      end
    end

    # Hit max iterations
    {
      "content" => last_response&.content,
      "usage" => total_usage,
      "tool_calls_log" => tool_calls_log,
      "finish_reason" => "max_iterations"
    }
  end

  # Run the full agentic tool loop with reasoning/reflection.
  # Delegates to server since reasoning orchestration involves complex
  # server-side services (STAR reasoning, evaluation, reflection).
  def execute_with_reasoning(agent_id:, messages:, model: nil, reasoning_mode: nil, reflection_enabled: false, **opts)
    call_server(:execute_with_reasoning,
      agent_id: agent_id, messages: messages, model: model,
      reasoning_mode: reasoning_mode, reflection_enabled: reflection_enabled, **opts
    )
  end

  private

  # Fetch provider configuration for an agent from the server.
  # Returns: { "provider_type", "provider_credential_id", "provider_base_url",
  #            "provider_name", "model" }
  def fetch_provider_config(agent_id)
    cache_key = "provider_config:#{agent_id}"
    cached = @provider_config_cache&.dig(cache_key)
    if cached && cached[:expires_at] > Time.current
      return cached[:data]
    end

    response = @api_post.call("/api/v1/internal/ai/provider_config", { agent_id: agent_id })

    data = if response.is_a?(Hash) && response["success"]
             response["data"]
           elsif response.is_a?(Hash) && response["provider_type"]
             response
           else
             raise "Failed to fetch provider config for agent #{agent_id}: #{response}"
           end

    @provider_config_cache ||= {}
    @provider_config_cache[cache_key] = { data: data, expires_at: Time.current + 60 }
    data
  end

  # Build or retrieve a cached LLM client for a provider configuration
  def build_llm_client(provider_config)
    credential_id = provider_config["provider_credential_id"]
    cache_key = credential_id

    cached_client = @llm_clients[cache_key]
    return cached_client if cached_client

    # Resolve credentials (decrypted API key)
    credentials = @credential_resolver.resolve(credential_id)
    api_key = credentials["api_key"]
    raise "No API key found for credential #{credential_id}" unless api_key

    client = Ai::Llm::Client.for_credentials(
      provider_type: provider_config["provider_type"],
      api_key: api_key,
      base_url: provider_config["provider_base_url"],
      provider_name: provider_config["provider_name"]
    )

    @llm_clients[cache_key] = client
    client
  end

  # Call a server-side action (tool definitions, dispatch, reasoning)
  def call_server(action, **payload)
    response = @api_post.call("#{SERVER_TOOL_PATH}/#{action}", payload)

    if response.is_a?(Hash) && response["success"]
      response["data"]
    elsif response.is_a?(Hash)
      raise "LLM server error (#{action}): #{response['error'] || response['message'] || 'Unknown error'}"
    else
      response
    end
  end

  def format_response(response)
    {
      "content" => response.content,
      "usage" => response.usage,
      "finish_reason" => response.finish_reason,
      "model" => response.model,
      "tool_calls" => response.tool_calls.presence,
      "cost" => response.cost,
      "thinking_content" => response.thinking_content
    }.compact
  end

  def accumulate_usage(total, iteration_usage)
    return unless iteration_usage

    total[:prompt_tokens] += (iteration_usage[:prompt_tokens] || 0)
    total[:completion_tokens] += (iteration_usage[:completion_tokens] || 0)
    total[:cached_tokens] += (iteration_usage[:cached_tokens] || 0)
    total[:total_tokens] += (iteration_usage[:total_tokens] || 0)
  end

  def deep_copy_messages(messages)
    messages.map { |m| m.is_a?(Hash) ? m.deep_dup : m.dup }
  end

  def symbolize_tools(tools)
    return [] unless tools

    tools.map { |t| deep_symbolize(t) }
  end

  def deep_symbolize(obj)
    case obj
    when Hash
      obj.transform_keys(&:to_sym).transform_values { |v| deep_symbolize(v) }
    when Array
      obj.map { |v| deep_symbolize(v) }
    else
      obj
    end
  end
end
