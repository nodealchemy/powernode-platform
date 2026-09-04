# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::McpAgentExecutor, type: :service do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }
  let(:execution) do
    double('execution', id: SecureRandom.uuid, execution_id: SecureRandom.uuid, status: 'running',
           cost_usd: 0.0, agent_id: nil, account_id: nil).as_null_object.tap do |e|
      allow(e).to receive(:update!)
    end
  end

  subject(:executor) { described_class.new(agent: agent, execution: execution, account: account) }

  describe '#execute' do
    let(:input_parameters) { { "input" => "Hello, world!" } }
    let(:validator) { instance_double(JsonSchemaValidator) }
    let(:guardrail_pipeline) { instance_double(Ai::Guardrails::Pipeline) }
    let(:llm_client) { instance_double(WorkerLlmClient) }
    let(:tool_bridge) { instance_double(Ai::AgentToolBridgeService) }

    let(:llm_response) do
      Ai::Llm::Response.new(
        content: "Hello! How can I help you?",
        tool_calls: [],
        finish_reason: "stop",
        model: "test-model-1",
        provider: "custom",
        usage: { prompt_tokens: 20, completion_tokens: 30, total_tokens: 50 }
      )
    end

    before do
      # Stub validation
      allow(JsonSchemaValidator).to receive(:new).and_return(validator)
      allow(validator).to receive(:valid?).and_return(true)

      # Stub rate limits
      ai_executions_rel = double('executions_relation')
      allow(account).to receive(:ai_agent_executions).and_return(ai_executions_rel)
      allow(ai_executions_rel).to receive(:where).and_return(ai_executions_rel)
      allow(ai_executions_rel).to receive(:count).and_return(0)

      # Stub security gate
      security_gate = instance_double(Ai::Security::SecurityGateService)
      allow(Ai::Security::SecurityGateService).to receive(:new).and_return(security_gate)
      allow(security_gate).to receive(:pre_execution_gate).and_return({ allowed: true, checks: [], degraded: false })
      allow(security_gate).to receive(:post_execution_gate).and_return({ allowed: true, checks: [], degraded: false })
      allow(security_gate).to receive(:record_execution_telemetry)

      # Stub guardrails
      allow(Ai::Guardrails::Pipeline).to receive(:new).and_return(guardrail_pipeline)
      allow(guardrail_pipeline).to receive(:check_input).and_return({ allowed: true, violations: [], blocked: false })
      allow(guardrail_pipeline).to receive(:check_output).and_return({ allowed: true, violations: [], blocked: false })

      # Stub provider credential chain (used by build_llm_client)
      credential = double('credential', provider: provider, credentials: { "api_key" => "test-key" })
      provider_credentials = double('provider_credentials')
      allow(agent).to receive(:provider).and_return(provider)
      allow(provider).to receive(:is_active?).and_return(true)
      allow(provider).to receive(:provider_credentials).and_return(provider_credentials)
      allow(provider_credentials).to receive(:where).and_return(provider_credentials)
      allow(provider_credentials).to receive(:active).and_return(provider_credentials)
      allow(provider_credentials).to receive(:first).and_return(credential)
      allow(WorkerLlmClient).to receive(:new).and_return(llm_client)

      # Stub tool bridge — tools disabled by default for simpler specs
      allow(Ai::AgentToolBridgeService).to receive(:new).and_return(tool_bridge)
      allow(tool_bridge).to receive(:tools_enabled?).and_return(false)
      allow(tool_bridge).to receive(:tool_definitions_for_llm).and_return([])

      # Stub simple completion
      allow(llm_client).to receive(:complete).and_return(llm_response)
    end

    context 'successful execution' do
      it 'returns an MCP-formatted response' do
        result = executor.execute(input_parameters)

        expect(result).to have_key("result")
        expect(result).to have_key("tool_id")
        expect(result).to have_key("execution_id")
        expect(result).to have_key("telemetry")
        expect(result["result"]["output"]).to eq("Hello! How can I help you?")
      end

      it 'includes telemetry data' do
        result = executor.execute(input_parameters)

        expect(result["telemetry"]["tokens_used"]).to eq(50)
        expect(result["telemetry"]["execution_time_ms"]).to be_a(Integer)
      end
    end

    context 'with tools enabled' do
      let(:tool_loop_result) do
        {
          content: "Based on the knowledge search, permissions work like this...",
          usage: { prompt_tokens: 55, completion_tokens: 40, total_tokens: 125 },
          tool_calls_log: [{ iteration: 1, tool: "search_knowledge", duration_ms: 50 }],
          finish_reason: "stop"
        }
      end

      before do
        allow(tool_bridge).to receive(:tools_enabled?).and_return(true)
        allow(tool_bridge).to receive(:tool_definitions_for_llm).and_return([
          { name: "search_knowledge", description: "Search knowledge", parameters: { type: "object", properties: {} } }
        ])
        allow(tool_bridge).to receive(:execute_tool_loop).and_return(tool_loop_result)
      end

      it 'executes the agentic tool loop via the bridge' do
        result = executor.execute(input_parameters)

        expect(result["result"]["output"]).to eq("Based on the knowledge search, permissions work like this...")
        expect(result["result"]["metadata"]["tool_call_count"]).to eq(1)
        expect(tool_bridge).to have_received(:execute_tool_loop)
      end

      it 'includes accumulated tokens in metadata' do
        result = executor.execute(input_parameters)

        expect(result["result"]["metadata"]["tokens_used"]).to eq(125)
      end
    end

    context 'when input validation fails' do
      before do
        allow(validator).to receive(:valid?).and_return(false)
        allow(validator).to receive(:detailed_errors).and_return([{ path: "input", message: "required" }])
      end

      it 'raises ValidationError' do
        expect {
          executor.execute(input_parameters)
        }.to raise_error(Ai::McpAgentExecutor::ValidationError, /Input validation failed/)
      end
    end

    context 'when input guardrail blocks' do
      before do
        allow(guardrail_pipeline).to receive(:check_input).and_return({
          blocked: true,
          violations: [{ message: "Toxic content detected" }]
        })
      end

      it 'returns a guardrail block response' do
        result = executor.execute(input_parameters)

        expect(result["error"]["type"]).to eq("GuardrailViolation")
        expect(result["error"]["message"]).to include("input guardrail")
      end
    end

    context 'when output guardrail blocks' do
      before do
        allow(llm_client).to receive(:complete).and_return(
          Ai::Llm::Response.new(content: "Harmful content", usage: { total_tokens: 10 })
        )

        allow(guardrail_pipeline).to receive(:check_output).and_return({
          blocked: true,
          violations: [{ message: "Output policy violation" }]
        })
      end

      it 'returns a guardrail block response for output' do
        result = executor.execute(input_parameters)

        expect(result["error"]["message"]).to include("output guardrail")
      end
    end

    context 'when LLM returns no content' do
      before do
        allow(llm_client).to receive(:complete).and_return(
          Ai::Llm::Response.new(content: nil, finish_reason: "error")
        )
      end

      it 'returns an error response' do
        result = executor.execute(input_parameters)

        expect(result).to have_key("error")
        expect(result["error"]["type"]).to eq("Ai::McpAgentExecutor::ProviderError")
      end
    end

    context 'when rate limit is exceeded' do
      before do
        ai_executions_rel = double('executions_relation')
        allow(account).to receive(:ai_agent_executions).and_return(ai_executions_rel)
        allow(ai_executions_rel).to receive(:where).and_return(ai_executions_rel)
        allow(ai_executions_rel).to receive(:count).and_return(200)
      end

      it 'raises ValidationError for rate limit' do
        expect {
          executor.execute(input_parameters)
        }.to raise_error(Ai::McpAgentExecutor::ValidationError, /Rate limit exceeded/)
      end
    end

    context 'when provider is not active' do
      before do
        # Exercise the REAL gate: build_llm_client checks the agent's RESOLVED
        # provider (@agent.resolved_provider&.is_active?), not the raw
        # agent.provider association — stub the resolution to land on this
        # provider so the inactive flag actually reaches the gate.
        allow(agent).to receive(:resolved_provider).and_return(provider)
        allow(provider).to receive(:is_active?).and_return(false)
      end

      it 'returns a ProviderError result' do
        result = executor.execute(input_parameters)
        expect(result).to include("error")
        expect(result["error"]["type"]).to eq("Ai::McpAgentExecutor::ProviderError")
        expect(result["error"]["message"]).to match(/not active/i)
      end
    end

    context 'when no credentials exist' do
      before do
        provider_credentials = double('provider_credentials')
        allow(provider).to receive(:provider_credentials).and_return(provider_credentials)
        allow(provider_credentials).to receive(:where).and_return(provider_credentials)
        allow(provider_credentials).to receive(:active).and_return(provider_credentials)
        allow(provider_credentials).to receive(:first).and_return(nil)
        # The credential chain no longer raises in-process — the WorkerLlmClient
        # is constructed without validating credentials. Simulate a provider-level
        # failure by making the LLM client raise.
        allow(WorkerLlmClient).to receive(:new).and_raise(
          Ai::McpAgentExecutor::ProviderError, "No active credentials found for provider"
        )
      end

      it 'returns error result' do
        result = executor.execute(input_parameters)
        expect(result).to include("error")
      end
    end

    context 'when input size exceeds limit' do
      let(:large_input) { { "input" => "x" * 200_000 } }

      it 'raises ValidationError for oversized input' do
        expect {
          executor.execute(large_input)
        }.to raise_error(Ai::McpAgentExecutor::ValidationError, /Input size/)
      end
    end
  end

  describe 'build_execution_context (private)' do
    it 'builds context with agent info' do
      context = executor.send(:build_execution_context, { "input" => "test" })

      expect(context[:agent_id]).to eq(agent.id)
      expect(context[:agent_name]).to eq(agent.name)
      expect(context[:input]).to eq("test")
    end

    it 'merges additional context from parameters' do
      params = { "input" => "test", "context" => { "temperature" => 0.5 } }
      context = executor.send(:build_execution_context, params)

      expect(context[:temperature]).to eq(0.5)
    end

    # Superseded by IMP-c51ef070f4ca. The original lock (IMP-573fbbd9a2b7)
    # asserted WorkingMemoryService was never CONSTRUCTED — but that pinned a
    # bug as correct behavior: injection hard-gated on `task.present?`, and
    # nothing on this path passes a task, so working memory silently never
    # fired. That fix's real target was proactive DB->Redis hydration ahead of
    # the read, not the read itself. Assert that instead, and let the read run.
    #
    # Request-level counterpart:
    #   spec/requests/api/v1/internal/ai/execution_contexts_working_memory_spec.rb
    # IMP-e55984da015d — the injector's token_estimate + breakdown were held
    # in memory and discarded; per-operation context size is now persisted
    # into the execution's performance_metrics jsonb (update_columns: the
    # execution is mid-flight, and completed-execution validations must not
    # fire on a metrics write).
    it 'persists the context token metrics onto the execution record' do
      real_execution = create(:ai_agent_execution, account: account, agent: agent)
      injector = instance_double(Ai::Memory::ContextInjectorService)
      allow(Ai::Memory::ContextInjectorService).to receive(:new).and_return(injector)
      allow(injector).to receive(:build_context).and_return(
        context: "## Known Facts\nx", token_estimate: 123,
        breakdown: { factual: 100, working: 23 }
      )
      persisting = described_class.new(agent: agent, execution: real_execution, account: account)

      persisting.send(:build_execution_context, { "input" => "test" })

      ctx = real_execution.reload.performance_metrics["context"]
      expect(ctx["total_tokens"]).to eq(123)
      expect(ctx["sections"]).to eq({ "factual" => 100, "working" => 23 })
    end

    it 'reads working memory without proactively hydrating it from the database' do
      expect_any_instance_of(Ai::Memory::WorkingMemoryService).not_to receive(:load_from_database)

      context = executor.send(:build_execution_context, { "input" => "test" })

      expect(context[:agent_id]).to eq(agent.id)
      expect(context[:input]).to eq("test")
    end
  end

  describe 'build_prompt_from_context (private)' do
    it 'returns the input as the base prompt' do
      context = { input: "Hello" }
      prompt = executor.send(:build_prompt_from_context, context)
      expect(prompt).to eq("Hello")
    end

    it 'includes conversation history when present' do
      context = {
        input: "Follow up question",
        conversation_history: [
          { "role" => "user", "content" => "First message" },
          { "role" => "assistant", "content" => "Response" }
        ]
      }
      prompt = executor.send(:build_prompt_from_context, context)

      expect(prompt).to include("Previous conversation")
      expect(prompt).to include("First message")
      expect(prompt).to include("Follow up question")
    end

    it 'includes additional context when present' do
      context = { input: "Question", additional_context: "Extra info" }
      prompt = executor.send(:build_prompt_from_context, context)

      expect(prompt).to include("Additional Context: Extra info")
    end
  end

  describe 'error code mapping' do
    it 'maps ValidationError to -32602' do
      code = executor.send(:map_error_code, Ai::McpAgentExecutor::ValidationError.new)
      expect(code).to eq(-32602)
    end

    it 'maps ProviderError to -32603' do
      code = executor.send(:map_error_code, Ai::McpAgentExecutor::ProviderError.new)
      expect(code).to eq(-32603)
    end

    it 'maps unknown errors to -32603' do
      code = executor.send(:map_error_code, StandardError.new)
      expect(code).to eq(-32603)
    end
  end

  describe 'resolve_model_config (private) — inc2 governed tier routing + inc3 effort parity' do
    let(:execution_context) { { context: {}, input: "hi" } }
    let(:messages) { [{ role: "user", content: "hi" }] }

    before do
      allow(agent).to receive(:resolved_model).and_return('claude-sonnet-4-6')
      allow(agent).to receive(:build_system_prompt_with_profile).and_return('sys')
    end

    context 'when the account gate is OFF (default)' do
      it 'never invokes the resolver and keeps the baseline resolved_model' do
        expect(Ai::Routing::TaskTierResolver).not_to receive(:resolve)
        model, = executor.send(:resolve_model_config, execution_context, messages)
        expect(model).to eq('claude-sonnet-4-6')
      end

      it 'populates no :effort (inertness — byte-identical to pre-inc3 behavior)' do
        _model, opts = executor.send(:resolve_model_config, execution_context, messages)
        expect(opts).not_to have_key(:effort)
      end
    end

    context 'when the account gate is ON' do
      let(:resolution) do
        instance_double(Ai::Routing::TaskTierResolver::Resolution,
                        model: 'claude-opus-4-8', effort: 'xhigh')
      end

      before do
        allow(Ai::Routing::TaskTierResolver).to receive(:enabled_for?).with(account).and_return(true)
        allow(Ai::Routing::TaskTierResolver).to receive(:resolve).and_return(resolution)
        allow(resolution).to receive(:persist!)
      end

      it 'takes MODEL from the resolver tier' do
        model, = executor.send(:resolve_model_config, execution_context, messages)
        expect(model).to eq('claude-opus-4-8')
      end

      it 'wires the resolved effort onto opts (inc3) for an effort-capable model' do
        _model, opts = executor.send(:resolve_model_config, execution_context, messages)
        expect(opts[:effort]).to eq('xhigh')
      end

      it 'persists the governance record' do
        expect(resolution).to receive(:persist!)
        executor.send(:resolve_model_config, execution_context, messages)
      end

      context 'when the resolver model is not effort-capable (e.g. claude-haiku-4-5)' do
        let(:resolution) do
          instance_double(Ai::Routing::TaskTierResolver::Resolution,
                          model: 'claude-haiku-4-5', effort: nil)
        end

        it 'omits :effort from opts (EffortMapper already returned nil upstream)' do
          expect(Ai::Llm::ModelCapabilities.supports_effort?('claude-haiku-4-5')).to be(false)
          _model, opts = executor.send(:resolve_model_config, execution_context, messages)
          expect(opts).not_to have_key(:effort)
        end
      end
    end
  end

  # IMP-6cda93db7f31: ai_agents.ai_provider_id is nullable on a GLOBAL row, so
  # a canonical seeded before any provider existed carries none. Ruling 8 says
  # such a principal never executes (Ai::Tools::BaseTool refuses it at the tool
  # seam), but the refusal does not live on THIS path — Ai::Agent#execute
  # reaches the executor directly — so the telemetry line must not be the thing
  # that decides, with a NoMethodError, what a global principal may do.
  describe '#format_mcp_response with a provider-less agent' do
    let(:canonical) do
      create(:ai_agent, :global, is_system: true).tap { |a| a.update_columns(ai_provider_id: nil) }
    end
    subject(:canonical_executor) do
      described_class.new(agent: canonical.reload, execution: execution, account: account)
    end

    it 'reports no provider instead of raising' do
      response = canonical_executor.send(:format_mcp_response, { "content" => "ok" })

      expect(response.dig("telemetry", "provider_used")).to be_nil
      expect(response["result"]).to eq({ "content" => "ok" })
    end
  end

end
