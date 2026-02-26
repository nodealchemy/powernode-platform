# frozen_string_literal: true

# Thin HTTP client wrapping backend API calls to server-side LLM proxy endpoints.
# Mirrors Ai::Llm::Client's interface so worker jobs can use tool-calling,
# structured output, and memory injection without direct DB access.
class LlmProxyClient
  BASE_PATH = "/api/v1/internal/ai/llm"

  # @param api_post_method [Method] a bound method reference to backend_api_post
  def initialize(api_post_method)
    @api_post = api_post_method
  end

  # Standard LLM completion via server proxy
  def complete(agent_id:, messages:, model: nil, **opts)
    call_proxy(:complete, agent_id: agent_id, messages: messages, model: model, **opts)
  end

  # LLM completion with tool-calling via server proxy
  def complete_with_tools(agent_id:, messages:, tools: [], model: nil, **opts)
    call_proxy(:complete_with_tools,
      agent_id: agent_id, messages: messages, tools: tools, model: model, **opts
    )
  end

  # Structured output (JSON schema enforced) via server proxy
  def complete_structured(agent_id:, messages:, schema:, model: nil, **opts)
    call_proxy(:complete_structured,
      agent_id: agent_id, messages: messages, schema: schema, model: model, **opts
    )
  end

  # Get tool definitions available to an agent
  def tool_definitions(agent_id:)
    call_proxy(:tool_definitions, agent_id: agent_id)
  end

  # Dispatch a single tool call through the server
  def dispatch_tool(agent_id:, tool_call:)
    call_proxy(:dispatch_tool, agent_id: agent_id, tool_call: tool_call)
  end

  # Run the full agentic tool loop server-side
  # This is the primary execution method — the server handles:
  # - Tool definitions lookup
  # - Iterative LLM ↔ tool dispatch loop
  # - Memory injection
  # - Result formatting
  def execute_tool_loop(agent_id:, messages:, model: nil, **opts)
    call_proxy(:execute_tool_loop,
      agent_id: agent_id, messages: messages, model: model, **opts
    )
  end

  # Run the full agentic tool loop with reasoning/reflection
  def execute_with_reasoning(agent_id:, messages:, model: nil, reasoning_mode: nil, reflection_enabled: false, **opts)
    call_proxy(:execute_with_reasoning,
      agent_id: agent_id, messages: messages, model: model,
      reasoning_mode: reasoning_mode, reflection_enabled: reflection_enabled, **opts
    )
  end

  private

  def call_proxy(action, **payload)
    response = @api_post.call("#{BASE_PATH}/#{action}", payload)

    if response.is_a?(Hash) && response["success"]
      response["data"]
    elsif response.is_a?(Hash)
      raise "LLM proxy error (#{action}): #{response['error'] || response['message'] || 'Unknown error'}"
    else
      response
    end
  end
end
