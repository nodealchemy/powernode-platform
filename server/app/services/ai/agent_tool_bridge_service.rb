# frozen_string_literal: true

module Ai
  # Bridges PlatformApiToolRegistry definitions ↔ LLM function-calling format
  # and provides the shared agentic tool loop.
  #
  # Outbound: converts platform tool definitions to LLM-compatible tools array
  # Inbound:  dispatches tool calls from LLM responses through McpPlatformToolRegistrar
  # Loop:     iterative tool-calling loop shared by McpAgentExecutor and ConversationResponseJob
  #
  # Default behavior: tools enabled for all agents except mcp_client type.
  # Override via agent's mcp_metadata["tool_access"] JSONB:
  #   { "enabled": false, "allowed_tools": ["search_knowledge"], "max_iterations": 5 }
  #
  class AgentToolBridgeService
    MAX_RESULT_SIZE = 50.kilobytes
    DEFAULT_MAX_ITERATIONS = 10
    HARD_MAX_ITERATIONS = 25

    # SiteSetting (json) mapping agent_type → default tool families, applied when
    # an agent has neither allowed_tools nor its own tool_access.tool_families.
    # e.g. { "data_analyst" => ["data_source", "search", "query", "list", "get"] }
    FAMILY_DEFAULTS_SETTING = "ai_agent_tool_family_defaults"

    attr_reader :agent, :account

    def initialize(agent:, account: nil)
      @agent = agent
      @account = account || agent.account
      @tool_access_config = agent.mcp_metadata&.dig("tool_access") || {}
    end

    # LLM-facing name prefix for tools proxied from an external MCP server.
    # Chosen to satisfy OpenAI's function-name charset (^[a-zA-Z0-9_-]+$) and to
    # never collide with a platform tool (those carry no prefix in the LLM view).
    EXTERNAL_TOOL_PREFIX = "mcp__"

    # Whether this agent should receive ANY tools in LLM calls. External MCP tools
    # are governed by attachment + permission, independent of the platform-tool
    # access toggle — so an agent with servers attached (including the mcp_client
    # type, whose whole purpose is external tools) still gets a tool list even when
    # platform tools are off.
    def tools_enabled?
      platform_tools_enabled? || external_mcp_available?
    end

    # The historical tools_enabled? gate, now scoped to the platform (platform.*)
    # tool surface only.
    def platform_tools_enabled?
      return false if agent.agent_type == "mcp_client"

      if @tool_access_config.key?("enabled")
        return @tool_access_config["enabled"] == true
      end

      true
    end

    # External MCP tools are exposed only when the agent has servers attached AND
    # its creator holds mcp.tools.execute. Fail closed when the creator is absent.
    def external_mcp_available?
      return @external_mcp_available if defined?(@external_mcp_available)

      # Cheap attachment check first (reads mcp_metadata, no query) so a
      # server-less agent never triggers a permission lookup.
      creator = agent.creator
      @external_mcp_available =
        agent.mcp_server_ids.present? &&
        creator.present? &&
        creator.has_permission?("mcp.tools.execute")
    end

    # Maximum agentic loop iterations
    def max_iterations
      configured = @tool_access_config["max_iterations"].to_i
      configured = DEFAULT_MAX_ITERATIONS if configured <= 0
      [configured, HARD_MAX_ITERATIONS].min
    end

    # Per-provider tool-count cap. OpenAI rejects >128 with HTTP 400; Anthropic
    # is higher. We add a safety margin so a tool list that brushes the cap
    # doesn't 400 if a future provider pads its array.
    OPENAI_TOOL_CAP = 100
    ANTHROPIC_TOOL_CAP = 200
    DEFAULT_TOOL_CAP = 100

    def max_tools_for_provider(llm_client)
      provider_type = llm_client.respond_to?(:provider_type) ? llm_client.provider_type.to_s : ""
      case provider_type
      when "openai" then OPENAI_TOOL_CAP
      when "anthropic" then ANTHROPIC_TOOL_CAP
      else DEFAULT_TOOL_CAP
      end
    end

    # Convert platform tool definitions to LLM function-calling format
    def tool_definitions_for_llm
      @tool_definitions_for_llm ||= build_tool_definitions
    end

    # Dispatch a tool call from an LLM response through the platform tool registrar.
    # Tools whose results should be surfaced (non-truncated) to the chat UI as
    # rich cards. Each entry maps a tool name to a card kind that the frontend
    # uses to pick a renderer. Add new entries as cards land.
    CARD_TOOLS = {
      "platform_provisioning_capture_brief" => "provisioning_brief",
      "platform_provisioning_compose_plan"  => "provisioning_plan",
      "platform_provisioning_approve_plan"  => "provisioning_plan_approved",
      "platform_provisioning_status"        => "provisioning_status",
      "platform_provisioning_adapt"         => "provisioning_adaptation",
      # D3 — Platform deployment wizard. Two-shape payload: wizard form
      # (no mode supplied) or deployment-done envelope (mode set). The
      # frontend renderer distinguishes via `payload.card.phase`.
      "system_deploy_platform"              => "platform_deployment_wizard"
    }.freeze

    # Dispatch a tool call. Returns the truncated JSON string the LLM sees as
    # the tool result message. Used by external callers (worker channel,
    # llm_proxy_controller, action-grammar fallback). The agent loop uses
    # #dispatch_tool_call_capturing instead so it can also surface
    # non-truncated payloads to the chat UI.
    def dispatch_tool_call(tool_call)
      dispatch_tool_call_capturing(tool_call).first
    end

    # Internal: dispatch a tool call and return [truncated_json, full_result].
    # The full result hash is captured for surfacing to the chat UI when the
    # tool is whitelisted in CARD_TOOLS.
    def dispatch_tool_call_capturing(tool_call)
      tool_name = tool_call[:name] || tool_call["name"]
      arguments = tool_call[:arguments] || tool_call["arguments"] || {}
      arguments = JSON.parse(arguments) if arguments.is_a?(String)

      Rails.logger.info "[AgentToolBridge] Dispatching tool: #{tool_name} for agent #{agent.id}"

      # External MCP tools are proxied to their origin server via the sync client,
      # not the platform registrar. Resolve against the (permission-gated) index.
      if tool_name.to_s.start_with?(EXTERNAL_TOOL_PREFIX) && external_tool_index.key?(tool_name.to_s)
        args = arguments.is_a?(Hash) ? arguments : {}
        return dispatch_external_mcp_tool(tool_name.to_s, args)
      end

      result = Ai::Tools::McpPlatformToolRegistrar.execute_tool(
        "platform.#{tool_name}",
        params: arguments.stringify_keys,
        account: account,
        user: agent.creator,
        agent_id: agent.id,
        mcp_agent: agent
      )

      [truncate_result(result.to_json), result]
    rescue ArgumentError => e
      Rails.logger.warn "[AgentToolBridge] Unknown tool: #{tool_name} - #{e.message}"
      [{ error: "Unknown tool: #{tool_name}", message: e.message }.to_json, nil]
    rescue ::Mcp::ProtocolService::PermissionDeniedError => e
      Rails.logger.warn "[AgentToolBridge] Permission denied: #{tool_name} - #{e.message}"
      [{ error: "Permission denied", tool: tool_name, message: e.message }.to_json, nil]
    rescue Ai::Introspection::RateLimiter::RateLimitExceeded => e
      Rails.logger.warn "[AgentToolBridge] Rate limited: #{tool_name} - #{e.message}"
      [{ error: "Rate limit exceeded", tool: tool_name, message: e.message }.to_json, nil]
    rescue StandardError => e
      Rails.logger.error "[AgentToolBridge] Tool error: #{tool_name} - #{e.message}"
      [{ error: "Tool execution failed", tool: tool_name, message: e.message }.to_json, nil]
    end

    # Shared agentic tool loop — call LLM with tools, dispatch calls, repeat.
    #
    # @param llm_client [WorkerLlmClient]
    # @param messages [Array<Hash>] conversation messages (mutated in place)
    # @param model [String] model ID
    # @param opts [Hash] max_tokens, temperature, system_prompt, etc.
    # @return [Hash] { content:, usage:, tool_calls_log:, finish_reason: }
    def execute_tool_loop(llm_client:, messages:, model:, **opts)
      tools = tool_definitions_for_llm

      # Provider tool-count cap — OpenAI rejects >128, Anthropic rejects ~256.
      # Filter to an intent-relevant subset based on the user's most recent
      # message so we never blow the cap. See Ai::ToolRelevanceFilter.
      max_tools = max_tools_for_provider(llm_client)
      if tools.size > max_tools
        latest_user_message = messages.reverse.find do |m|
          (m[:role] || m["role"])&.to_s == "user"
        end
        user_content = latest_user_message&.dig(:content) || latest_user_message&.dig("content")
        before_count = tools.size
        tools = ::Ai::ToolRelevanceFilter.filter(tools, user_message: user_content, max_tools: max_tools)
        Rails.logger.info "[AgentToolBridge] Tool relevance filter: #{before_count} → #{tools.size} (cap=#{max_tools})"
      end

      max_iter = max_iterations
      iteration = 0
      accumulated_usage = { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 }
      tool_calls_log = []
      # Surface non-truncated results for tools whitelisted in CARD_TOOLS.
      # Frontend reads these from message.content_metadata.cards.
      chat_cards = []
      # Served-by attribution: carry the model that ACTUALLY served (when the
      # maker's call refused and fell back) through to the caller so the ralph
      # maker/checker served-by logic isn't defeated on the tool-bridge path.
      last_served_by = nil
      last_refusal_recovery = nil

      tool_names = tools.map { |t| t[:name] || t.dig(:function, :name) }.compact
      Rails.logger.info "[AgentToolBridge] Starting loop: model=#{model} tools=#{tool_names.length} (#{tool_names.join(', ')}) messages=#{messages.length} system_prompt_length=#{opts[:system_prompt]&.length}"

      loop do
        iteration += 1
        Rails.logger.info "[AgentToolBridge] Iteration #{iteration}/#{max_iter} for agent #{agent.id}"

        # tool_choice only applies to the first iteration (forced tool call);
        # subsequent iterations use auto so the model can generate a text response
        iter_opts = iteration > 1 ? opts.except(:tool_choice) : opts

        response = llm_client.complete_with_tools(
          messages: messages, tools: tools, model: model, **iter_opts
        )

        Rails.logger.info "[AgentToolBridge] Response: has_tool_calls=#{response.has_tool_calls?} finish_reason=#{response.finish_reason} content_length=#{response.content&.length} usage=#{response.usage}"

        accumulate_usage(accumulated_usage, response.usage)

        # Track served-by / recovery across iterations (sticky to the fallback
        # model once a refusal fell back, so later iterations don't re-refuse).
        if response.respond_to?(:served_by) && response.served_by.present?
          last_served_by = response.served_by
          model = response.served_by if response.served_by != model
        end
        if response.respond_to?(:refusal_recovery) && response.refusal_recovery.present?
          last_refusal_recovery = response.refusal_recovery
        end

        # Return if text-only response or iteration cap reached
        unless response.has_tool_calls? && iteration < max_iter
          if response.has_tool_calls?
            Rails.logger.warn "[AgentToolBridge] Max iterations (#{max_iter}) reached with pending tool calls"
          end

          return {
            content: response.content,
            usage: accumulated_usage,
            tool_calls_log: tool_calls_log,
            chat_cards: chat_cards,
            finish_reason: response.finish_reason,
            served_by: last_served_by,
            refusal_recovery: last_refusal_recovery,
            refusal: (response.respond_to?(:refusal) ? response.refusal : nil)
          }
        end

        # Dispatch each tool call and append results to conversation
        response.tool_calls.each do |tool_call|
          tool_name = tool_call[:name] || tool_call["name"]
          tool_call_id = tool_call[:id] || tool_call["id"] || SecureRandom.uuid
          call_start = Time.current

          result_json, full_result = dispatch_tool_call_capturing(tool_call)
          call_duration_ms = ((Time.current - call_start) * 1000).round

          tool_calls_log << {
            iteration: iteration, tool: tool_name,
            duration_ms: call_duration_ms,
            result_preview: result_json.to_s.truncate(200)
          }

          # Surface non-truncated payload as a chat card when whitelisted.
          card_kind = CARD_TOOLS[tool_name]
          if card_kind && full_result.is_a?(Hash)
            payload = card_payload_from_result(full_result)
            if payload
              chat_cards << {
                kind: card_kind, tool: tool_name,
                arguments: tool_call[:arguments] || tool_call["arguments"] || {},
                payload: payload
              }
            end
          end

          Rails.logger.info "[AgentToolBridge] Tool #{tool_name} completed in #{call_duration_ms}ms"

          messages << {
            role: "assistant", content: nil,
            tool_calls: [{
              id: tool_call_id,
              name: tool_name,
              arguments: tool_call[:arguments] || tool_call["arguments"] || {}
            }]
          }
          messages << { role: "tool", tool_call_id: tool_call_id, content: result_json }
        end
      end
    end

    # Pull the structured payload out of a tool result. Tool results from the
    # Ai::Tools::* family come in two common shapes:
    #   - { success: true, data: {...} }    (most platform tools)
    #   - { ...top-level payload... }       (a few legacy tools)
    # We prefer :data when present so the frontend reads the same shape it
    # would get from the corresponding REST endpoint.
    def card_payload_from_result(result)
      return nil unless result.is_a?(Hash)
      return nil if result[:success] == false || result["success"] == false
      result[:data] || result["data"] || result
    end

    # Extended agentic loop with optional reasoning, reflection, and evaluation.
    #
    # @param llm_client [WorkerLlmClient]
    # @param messages [Array<Hash>] conversation messages
    # @param model [String] model ID
    # @param reasoning_mode [Symbol, String, nil] :chain_of_thought, :plan_and_execute, or nil
    # @param reflection_enabled [Boolean] run self-critique after execution
    # @param evaluation_config [Hash, nil] { enabled: true, evaluator_model: "...", max_revisions: 2 }
    # @param opts [Hash] max_tokens, temperature, system_prompt, etc.
    # @return [Hash] { content:, usage:, tool_calls_log:, finish_reason:, reasoning:, reflection:, evaluation: }
    def execute_with_reasoning(llm_client:, messages:, model:, reasoning_mode: nil, reflection_enabled: false, evaluation_config: nil, **opts)
      reasoning_result = nil
      reflection_result = nil
      evaluation_result = nil
      task_text = messages.last&.dig(:content) || messages.last&.dig("content") || ""

      # Phase 1: Pre-execution reasoning
      if reasoning_mode.present?
        reasoning_mode = reasoning_mode.to_sym

        # Fable/Mythos have always-on adaptive thinking AND run a reasoning_extraction
        # safety classifier. The chain_of_thought / star scaffolds make the model emit
        # its own reasoning as text and inject it back as an assistant turn — redundant
        # on a native reasoner and a refusal trigger there. Skip them for that family
        # (plan_and_execute produces subtasks, not a reasoning transcript, so it is
        # unaffected). See guidance-fable5-compliance.
        if %i[chain_of_thought star].include?(reasoning_mode) &&
           ::Ai::Llm::ModelCapabilities.refusal_capable?(model)
          Rails.logger.info "[AgentToolBridge] Skipping #{reasoning_mode} scaffold for adaptive-thinking model #{model} (native reasoning; avoids reasoning_extraction refusal)"
          reasoning_mode = nil
        end
      end

      if reasoning_mode.present?
        Rails.logger.info "[AgentToolBridge] Reasoning mode: #{reasoning_mode} for agent #{agent.id}"

        case reasoning_mode
        when :chain_of_thought
          cot_service = Ai::Reasoning::ChainOfThoughtService.new(account: account)
          reasoning_result = cot_service.reason(
            task: task_text, llm_client: llm_client, model: model, **opts
          )

          # Inject reasoning into messages
          if reasoning_result[:reasoning_steps].present?
            reasoning_text = cot_service.format_reasoning_for_injection(reasoning_result)
            messages << { role: "assistant", content: reasoning_text }
            messages << { role: "user", content: "Based on this reasoning, please proceed with the task." }
          end

        when :star
          star_service = Ai::Reasoning::StarReasoningService.new(account: account)
          reasoning_result = star_service.reason(
            task: task_text,
            context: extract_context_from_messages(messages),
            llm_client: llm_client, model: model, **opts
          )

          if reasoning_result[:confidence] > 0.0
            reasoning_text = star_service.format_reasoning_for_injection(reasoning_result)
            messages << { role: "assistant", content: reasoning_text }
            messages << { role: "user", content: "Based on this STAR analysis, proceed with the task. Pay special attention to the implicit constraints and success criteria identified in the Task section." }
          end

        when :plan_and_execute
          plan_service = Ai::Planning::TaskDecompositionService.new(account: account)
          plan = plan_service.decompose(
            task: task_text, llm_client: llm_client, model: model, **opts
          )

          if plan[:valid] && plan[:subtasks].present?
            executor = Ai::Planning::PlanExecutorService.new(account: account, user: agent.creator)
            dag_execution = executor.execute_plan(
              plan: plan, agent_id: agent.id, input_context: { task: task_text }
            )
            reasoning_result = { plan: plan, dag_execution_id: dag_execution.id }

            # Use DAG results as context
            if dag_execution.status == "completed"
              outputs = dag_execution.final_outputs || {}
              synthesis = outputs.map { |node_id, r| "#{node_id}: #{r[:output].to_s.truncate(500)}" }.join("\n")
              messages << { role: "assistant", content: "Subtask results:\n#{synthesis}" }
              messages << { role: "user", content: "Please synthesize these results into a final response." }
            end
          end
        end
      end

      # Phase 2: Execute tool loop
      result = execute_tool_loop(llm_client: llm_client, messages: messages, model: model, **opts)

      # Phase 3: Post-execution reflection
      if reflection_enabled
        Rails.logger.info "[AgentToolBridge] Running reflection for agent #{agent.id}"
        reflection_service = Ai::Reasoning::ReflectionService.new(account: account)
        reflection_result = reflection_service.reflect(
          task: task_text, output: result[:content],
          llm_client: llm_client, model: model, **opts
        )

        # Re-execute if reflection says to retry
        if reflection_result[:should_retry] && result[:content].present?
          Rails.logger.info "[AgentToolBridge] Reflection triggered retry for agent #{agent.id}"
          feedback = "Self-critique feedback:\n- Issues: #{reflection_result[:issues].join(', ')}\n- Improvements: #{reflection_result[:improvements].join(', ')}\nPlease address these issues."
          messages << { role: "assistant", content: result[:content] }
          messages << { role: "user", content: feedback }
          result = execute_tool_loop(llm_client: llm_client, messages: messages, model: model, **opts)
        end
      end

      # Phase 4: Output evaluation
      eval_config = evaluation_config || agent.mcp_metadata&.dig("evaluation") || {}
      if eval_config["enabled"]
        Rails.logger.info "[AgentToolBridge] Running output evaluation for agent #{agent.id}"
        evaluator = Ai::Reasoning::OutputEvaluatorService.new(account: account)
        max_revisions = eval_config["max_revisions"] || 2
        revision_count = 0

        loop do
          evaluation_result = evaluator.evaluate(
            task: task_text, output: result[:content],
            llm_client: llm_client, model: eval_config["evaluator_model"] || model, **opts
          )

          break if evaluation_result[:verdict] == "pass"
          break if evaluation_result[:verdict] == "reject"
          break if revision_count >= max_revisions

          # Revise
          revision_count += 1
          messages << { role: "assistant", content: result[:content] }
          messages << { role: "user", content: "Evaluator feedback: #{evaluation_result[:feedback]}\nPlease revise your response." }
          result = execute_tool_loop(llm_client: llm_client, messages: messages, model: model, **opts)
        end
      end

      result.merge(
        reasoning: reasoning_result,
        reflection: reflection_result,
        evaluation: evaluation_result
      )
    end

    private

    # Extract any pre-injected context from the message history so STAR
    # can reason about both the task and the surrounding context.
    def extract_context_from_messages(messages)
      context_parts = messages.select { |m| m[:role] == "system" || m["role"] == "system" }
                              .map { |m| m[:content] || m["content"] }
                              .compact

      # Also pull context from assistant messages that look like injected context
      messages.select { |m| (m[:role] || m["role"]) == "assistant" }
              .each do |m|
        content = m[:content] || m["content"]
        context_parts << content if content.present? && content.length > 100
      end

      context_parts.join("\n\n").presence
    end

    def allowed_tool_names
      allowed = @tool_access_config["allowed_tools"]
      return nil if allowed.blank? || allowed == ["*"]

      allowed
    end

    def build_tool_definitions
      platform_tool_definitions + external_mcp_tool_definitions
    end

    def platform_tool_definitions
      return [] unless platform_tools_enabled?

      # When allowed_tools is explicitly configured, use the full registry (agent: nil)
      # to skip per-tool permitted? checks — the whitelist IS the authorization gate.
      # Without an explicit whitelist, use agent-scoped definitions for permission
      # filtering, then narrow to the agent's tool families (prompt-size/cost measure;
      # dispatch-side authorization is unchanged and remains the security boundary).
      if (allowed = allowed_tool_names)
        definitions = Ai::Tools::PlatformApiToolRegistry.tool_definitions(agent: nil)
        definitions = definitions.select { |d| allowed.include?(d[:name].to_s) }
      else
        definitions = scope_to_tool_families(
          Ai::Tools::PlatformApiToolRegistry.tool_definitions(agent: agent)
        )
      end

      definitions.map { |defn| convert_to_llm_tool(defn) }
    end

    # LLM tool definitions for the agent's attached external MCP tools. Empty
    # unless external MCP is available (attached + creator permitted). The
    # combined list is capped downstream by the same provider tool-count filter
    # that governs platform tools (see #execute_tool_loop), so no separate cap
    # is applied here.
    def external_mcp_tool_definitions
      external_tool_index.map do |name, tool|
        convert_mcp_tool_to_llm(name, tool)
      end
    end

    # Map of LLM-facing name => McpTool for this agent's attached, connected,
    # enabled external tools. Built once; the single source of truth for both
    # advertisement and dispatch resolution. Empty unless external_mcp_available?.
    def external_tool_index
      @external_tool_index ||= build_external_tool_index
    end

    def build_external_tool_index
      return {} unless external_mcp_available?

      index = {}
      agent.available_mcp_tools.each do |tool|
        name = namespaced_mcp_name(tool)
        if index.key?(name)
          # Two tool names that slug to the same LLM name — keep the first and
          # log the drop rather than silently shadow one.
          Rails.logger.warn "[AgentToolBridge] Duplicate external MCP tool name " \
                            "#{name} for agent #{agent.id} — keeping first, dropping #{tool.id}"
          next
        end
        index[name] = tool
      end
      index
    end

    # mcp__<server>__<tool>, sanitized to the OpenAI function-name charset. The
    # exact name is stored in the index, so slugging never breaks dispatch.
    def namespaced_mcp_name(tool)
      server_part = mcp_slug(tool.mcp_server&.name.presence || tool.mcp_server_id)
      "#{EXTERNAL_TOOL_PREFIX}#{server_part}__#{mcp_slug(tool.name)}"
    end

    def mcp_slug(value)
      value.to_s.strip.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "").presence || "x"
    end

    def convert_mcp_tool_to_llm(name, tool)
      schema = tool.input_schema
      schema = {} unless schema.is_a?(Hash)
      schema = { "type" => "object", "properties" => {}, "required" => [] } if schema.blank?

      {
        name: name,
        description: mcp_tool_description(tool),
        parameters: schema
      }
    end

    def mcp_tool_description(tool)
      desc = tool.try(:description)
      return desc if desc.present?

      "External MCP tool #{tool.name} (server: #{tool.mcp_server&.name})"
    end

    # Proxy an external MCP tool call through the synchronous client. Gates on the
    # coarse permission (defense in depth — the index is already gated) and the
    # per-tool Mcp::PermissionValidator, records an mcp_tool_executions row, and
    # returns the same [truncated_json, full_result] shape the loop expects.
    def dispatch_external_mcp_tool(tool_name, arguments)
      mcp_tool = external_tool_index[tool_name]

      unless external_mcp_available?
        return [{ error: "Permission denied", tool: tool_name,
                  message: "Agent lacks mcp.tools.execute" }.to_json, nil]
      end

      creator = agent.creator
      unless mcp_tool.can_execute?(user: creator, account: account)
        status = mcp_tool.authorization_status(user: creator, account: account)
        message = Array(status[:errors]).map { |e| e[:message] }.join("; ")
        Rails.logger.warn "[AgentToolBridge] External MCP permission denied: #{tool_name} - #{message}"
        return [{ error: "Permission denied", tool: tool_name, message: message }.to_json, nil]
      end

      execution = mcp_tool.mcp_tool_executions.create!(
        user: creator, status: "running", parameters: arguments, started_at: Time.current
      )
      started = Time.current

      begin
        result = ::Mcp::SyncExecutionService.new(
          server: mcp_tool.mcp_server,
          tool: mcp_tool,
          parameters: arguments,
          user: creator,
          account: account
        ).execute

        execution.update!(
          status: "completed",
          result: (result.is_a?(Hash) ? result : { "value" => result }),
          completed_at: Time.current,
          duration_ms: ((Time.current - started) * 1000).round
        )
        [truncate_result(result.to_json), result]
      rescue StandardError => e
        execution.update!(
          status: "failed", error_message: e.message,
          completed_at: Time.current, duration_ms: ((Time.current - started) * 1000).round
        )
        Rails.logger.error "[AgentToolBridge] External MCP tool error: #{tool_name} - #{e.message}"
        [{ error: "Tool execution failed", tool: tool_name, message: e.message }.to_json, nil]
      end
    end

    # Narrow the registry to the agent's tool families (IMP-011ac658a671). Without
    # scoping every whitelist-less agent received ALL registry tools (561, ~72k
    # prompt tokens per call). A family entry matches a tool by exact name or by
    # `<family>_` prefix, so a list doubles as a compact allowlist. Resolution:
    #   1. tool_access["full_registry"] == true  → unscoped (broad/orchestrator agents)
    #   2. tool_access["tool_families"]          → per-agent scope
    #   3. SiteSetting FAMILY_DEFAULTS_SETTING   → per-agent-type default scope
    #   4. nothing configured                    → unscoped (behavior-neutral default)
    # A families list that matches NOTHING fails open to the full registry —
    # misconfiguration must not silently disarm an agent.
    def scope_to_tool_families(definitions)
      return definitions if @tool_access_config["full_registry"] == true

      families = tool_families
      if families.blank?
        Rails.logger.info "[AgentToolBridge] No tool-family scope for agent #{agent.id} " \
                          "(#{agent.agent_type}) — serving full registry (#{definitions.size} tools)"
        return definitions
      end

      scoped = definitions.select { |d| tool_in_families?(d[:name].to_s, families) }
      if scoped.empty?
        Rails.logger.warn "[AgentToolBridge] tool_families #{families.inspect} matched 0 of " \
                          "#{definitions.size} tools for agent #{agent.id} — failing open to full registry"
        return definitions
      end

      Rails.logger.info "[AgentToolBridge] Scoped agent #{agent.id} (#{agent.agent_type}) to " \
                        "#{scoped.size}/#{definitions.size} tools via families #{families.inspect}"
      scoped
    end

    def tool_families
      configured = @tool_access_config["tool_families"]
      return Array(configured).map(&:to_s) if configured.present?

      defaults = SiteSetting.get(FAMILY_DEFAULTS_SETTING)
      return nil unless defaults.is_a?(Hash)

      family_list = defaults[agent.agent_type]
      family_list.present? ? Array(family_list).map(&:to_s) : nil
    rescue StandardError => e
      Rails.logger.warn "[AgentToolBridge] Tool-family defaults lookup failed: #{e.message}"
      nil
    end

    def tool_in_families?(name, families)
      families.any? { |family| name == family || name.start_with?("#{family}_") }
    end

    def convert_to_llm_tool(definition)
      params = definition[:parameters] || {}
      params = params.except(:action, "action")

      {
        name: definition[:name].to_s,
        description: definition[:description].to_s,
        parameters: convert_to_json_schema(params)
      }
    end

    def convert_to_json_schema(parameters)
      return { type: "object", properties: {}, required: [] } if parameters.blank?

      properties = {}
      required = []

      parameters.each do |param_name, param_def|
        next unless param_def.is_a?(Hash)

        prop = { type: param_def[:type] || "string" }
        prop[:description] = param_def[:description] if param_def[:description].present?
        prop[:enum] = param_def[:enum] if param_def[:enum].present?

        # OpenAI requires `items` on array types and `properties` on object types
        if prop[:type] == "array" && param_def[:items].nil?
          prop[:items] = { type: "string" }
        elsif prop[:type] == "array" && param_def[:items]
          prop[:items] = param_def[:items]
        end

        if prop[:type] == "object" && param_def[:properties].nil?
          prop[:additionalProperties] = true
        elsif prop[:type] == "object" && param_def[:properties]
          prop[:properties] = param_def[:properties]
        end

        properties[param_name.to_s] = prop
        required << param_name.to_s if param_def[:required]
      end

      { type: "object", properties: properties, required: required }
    end

    def accumulate_usage(accumulated, response_usage)
      return unless response_usage

      accumulated[:prompt_tokens] += (response_usage[:prompt_tokens] || 0)
      accumulated[:completion_tokens] += (response_usage[:completion_tokens] || 0)
      accumulated[:total_tokens] += (response_usage[:total_tokens] || 0)
    end

    def truncate_result(json_string)
      return json_string if json_string.bytesize <= MAX_RESULT_SIZE

      truncated = json_string.byteslice(0, MAX_RESULT_SIZE)
      "#{truncated}... [truncated, #{json_string.bytesize} bytes total]"
    end
  end
end
