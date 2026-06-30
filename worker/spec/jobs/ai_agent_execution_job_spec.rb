# frozen_string_literal: true

require 'rails_helper'

# AiAgentExecutionJob was re-architected (commit cb41df3f) to delegate all LLM
# work to LlmProxyClient (+ Ai::Llm::Client). The job is now a thin ORCHESTRATOR:
#
#   fetch execution -> kill-switch -> state/budget gates -> mark running ->
#   build context + run via the proxy -> clean response -> mark completed/failed,
#   emitting telemetry + a trust evaluation along the way.
#
# This spec therefore covers the JOB's orchestration only. The proxy seam
# (#execute_tool_loop / #execute_with_reasoning) is stubbed, because the things
# the job used to do itself — credential fetch/decrypt, per-provider HTTP
# (OpenAI/Anthropic/Ollama) request shaping, the multi-turn tool loop — now live
# behind LlmProxyClient and Ai::Llm::Client and are exercised by their own specs
# (spec/services/llm_proxy_client_spec.rb, spec/services/ai/llm/*). Re-asserting
# them here would test the wrong unit and duplicate that coverage.
RSpec.describe AiAgentExecutionJob, type: :job do
  subject { described_class }

  # Shared examples for base job behavior
  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'
  it_behaves_like 'a job with retry logic'
  it_behaves_like 'a job with logging'
  it_behaves_like 'a job with timing metrics'

  let(:agent_execution_id) { 'execution-123' }
  let(:agent_id) { 'agent-456' }
  let(:account_id) { 'account-789' }

  # Used by shared examples for job argument handling
  let(:job_args) { agent_execution_id }

  let(:agent_data) do
    {
      'id' => agent_id,
      'name' => 'Test AI Agent',
      'agent_type' => 'assistant',
      'system_prompt' => 'You are a helpful AI assistant.'
    }
  end

  let(:agent_execution_data) do
    {
      'id' => agent_execution_id,
      'account_id' => account_id,
      'status' => 'pending',
      'input_parameters' => {
        'input' => 'Explain Ruby on Rails testing',
        'context' => { 'topic' => 'RSpec best practices' }
      },
      'ai_agent' => agent_data
    }
  end

  # Memory-enriched context the server returns from POST /execution_contexts.
  # The job reads execution_context/system_prompt/model/max_tokens/temperature
  # off of it and turns it into the proxy call.
  let(:execution_context_response) do
    {
      'execution_context' => {
        'input' => 'Explain Ruby on Rails testing',
        'additional_context' => nil
      },
      'system_prompt' => 'You are a helpful AI assistant.',
      'model' => 'gpt-4o-mini',
      'max_tokens' => 2000,
      'temperature' => 0.7
    }
  end

  # Shape mirrors LlmProxyClient#execute_tool_loop's real return value:
  # string top-level keys, symbol-keyed usage hash.
  let(:proxy_content) { 'RSpec is a behaviour-driven testing framework for Ruby.' }
  let(:proxy_result) { build_proxy_result(proxy_content) }

  # Strict verifying double for the LLM proxy seam. instance_double will flag
  # any signature drift in execute_tool_loop / execute_with_reasoning.
  let(:proxy) { instance_double(LlmProxyClient) }

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    # Bypass runaway loop detection in tests (it uses Redis)
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  after do
    Sidekiq::Worker.clear_all
  end

  # ---- helpers --------------------------------------------------------------

  def build_proxy_result(content, cost: 0.003, usage: nil)
    {
      'content' => content,
      'usage' => usage || { prompt_tokens: 50, completion_tokens: 100, cached_tokens: 0, total_tokens: 150 },
      'tool_calls_log' => [],
      'finish_reason' => 'stop',
      'cost' => cost
    }
  end

  # Stub the backend endpoints the JOB itself calls during a happy-path run.
  # Every shared/first-run collaborator (kill-switch path, budget gate, telemetry,
  # trust eval, the execution-context fetch) is stubbed up front: an unstubbed
  # call leaks as a WebMock/mock error from inside a rescue and quietly poisons
  # the whole run, so the failure never points at the real cause.
  def stub_execution_lifecycle_endpoints(execution: agent_execution_data)
    stub_backend_api_success(:get, "/api/v1/internal/ai/executions/#{agent_execution_id}", {
      'success' => true,
      'data' => { 'agent_execution' => execution }
    })
    stub_backend_api_success(:patch, "/api/v1/internal/ai/executions/#{agent_execution_id}", { 'success' => true })
    stub_backend_api_success(:post, '/api/v1/internal/ai/execution_contexts', {
      'success' => true,
      'data' => execution_context_response
    })
    stub_backend_api_success(:get, '/api/v1/ai/autonomy/budgets/alerts', { 'success' => true, 'data' => [] })
    stub_backend_api_success(:post, '/api/v1/ai/autonomy/telemetry', { 'success' => true })
    stub_backend_api_success(
      :post, "/api/v1/ai/autonomy/trust_scores/#{agent_id}/evaluate_from_execution", { 'success' => true }
    )
  end

  # Stub the LLM proxy seam. Both proxy methods are stubbed even though only one
  # runs per example: a strict instance_double raises a (non-StandardError)
  # MockExpectationError on any unstubbed message, which would bypass the job's
  # `rescue StandardError` and detonate every example.
  def stub_proxy_seam
    allow_any_instance_of(described_class).to receive(:llm_proxy_with_websocket).and_return(nil)
    allow_any_instance_of(described_class).to receive(:llm_proxy).and_return(proxy)
    allow(proxy).to receive(:execute_tool_loop).and_return(proxy_result)
    allow(proxy).to receive(:execute_with_reasoning).and_return(proxy_result)
  end

  describe 'job configuration' do
    it 'is configured with correct queue' do
      expect(described_class.sidekiq_options['queue'].to_s).to eq('ai_agents')
    end

    it 'is configured with correct retry count' do
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end

    it 'includes AiJobsConcern' do
      expect(described_class.included_modules).to include(AiJobsConcern)
    end

    it 'includes AiLlmProxyConcern (delegates LLM work to the server proxy)' do
      expect(described_class.included_modules).to include(AiLlmProxyConcern)
    end

    it 'includes AiSuspensionCheckConcern (honors the per-account kill switch)' do
      expect(described_class.included_modules).to include(AiSuspensionCheckConcern)
    end
  end

  describe '#execute' do
    let(:job_instance) { described_class.new }

    before do
      stub_execution_lifecycle_endpoints
      stub_proxy_seam
      # Not suspended by default; the kill-switch context overrides this.
      allow_any_instance_of(described_class).to receive(:ai_suspended?).and_return(false)
    end

    context 'with a successful execution' do
      it 'completes the agent execution' do
        expect { job_instance.execute(agent_execution_id) }.not_to raise_error

        expect(WebMock).to have_requested(:patch, %r{api/v1/internal/ai/executions/#{agent_execution_id}})
          .with(body: hash_including(
            'agent_execution' => hash_including('status' => 'completed')
          ))
      end

      it 'marks the execution running before delegating to the proxy' do
        # Pin the temporal invariant the name claims: the 'running' transition
        # must happen BEFORE the (potentially long) LLM call, not after it.
        # A plain `have_requested(... status => running)` would still pass if the
        # two steps were reordered, so capture order explicitly.
        marked_running = false
        running_before_proxy = nil
        allow(job_instance).to receive(:update_execution_status).and_wrap_original do |orig, status, *rest|
          marked_running = true if status == 'running'
          orig.call(status, *rest)
        end
        allow(proxy).to receive(:execute_tool_loop) do |**_kwargs|
          running_before_proxy = marked_running
          proxy_result
        end

        job_instance.execute(agent_execution_id)

        expect(running_before_proxy).to be(true)
        expect(WebMock).to have_requested(:patch, %r{api/v1/internal/ai/executions/#{agent_execution_id}})
          .with(body: hash_including(
            'agent_execution' => hash_including('status' => 'running')
          ))
      end

      it 'logs execution start and completion' do
        logger_double = mock_logger
        job_instance.execute(agent_execution_id)

        expect(logger_double).to have_received(:info).with(
          a_string_matching(/Starting AI agent execution/)
        ).at_least(:once)
        expect(logger_double).to have_received(:info).with(
          a_string_matching(/AI agent execution completed successfully/)
        ).at_least(:once)
      end

      it 'runs through the LLM proxy with context-built messages' do
        captured = nil
        allow(proxy).to receive(:execute_tool_loop) do |**kwargs|
          captured = kwargs
          proxy_result
        end

        job_instance.execute(agent_execution_id)

        expect(captured).to include(
          agent_id: agent_id,
          model: 'gpt-4o-mini',
          system_prompt: 'You are a helpful AI assistant.'
        )
        expect(captured[:messages]).to include(
          a_hash_including(role: 'user', content: a_string_matching(/Explain Ruby on Rails testing/))
        )
      end

      it 'records cost, token, and model metrics in the completion payload' do
        job_instance.execute(agent_execution_id)

        expect(WebMock).to have_requested(:patch, %r{api/v1/internal/ai/executions/#{agent_execution_id}})
          .with(body: hash_including(
            'agent_execution' => hash_including(
              'status' => 'completed',
              'cost_usd' => 0.003,
              'tokens_used' => 150,
              # output_data carries the per-bucket usage the job pulls off the
              # (symbol-keyed) proxy usage hash, plus the resolved model.
              'output_data' => hash_including(
                'model_used' => 'gpt-4o-mini',
                'tokens_used' => 150,
                'prompt_tokens' => 50,
                'completion_tokens' => 100,
                'cost_usd' => 0.003
              )
            )
          ))
      end

      it 'emits start and completion telemetry' do
        job_instance.execute(agent_execution_id)

        expect(WebMock).to have_requested(:post, %r{api/v1/ai/autonomy/telemetry})
          .with(body: hash_including('event_type' => 'agent_execution_started'))
        expect(WebMock).to have_requested(:post, %r{api/v1/ai/autonomy/telemetry})
          .with(body: hash_including('event_type' => 'agent_execution_completed', 'outcome' => 'success'))
      end

      it 'submits a trust evaluation for the agent after completing' do
        job_instance.execute(agent_execution_id)

        expect(WebMock).to have_requested(
          :post, %r{api/v1/ai/autonomy/trust_scores/#{agent_id}/evaluate_from_execution}
        ).with(body: hash_including('execution_id' => agent_execution_id, 'success' => true))
      end

    end

    context 'when the execution context carries additional context' do
      # Override the let so the #execute before-block builds the
      # /execution_contexts stub with additional_context populated (the stub
      # serializes its body eagerly, so this must be set before the before runs).
      let(:execution_context_response) do
        {
          'execution_context' => {
            'input' => 'Explain Ruby on Rails testing',
            'additional_context' => 'Prefer minitest examples'
          },
          'system_prompt' => 'You are a helpful AI assistant.',
          'model' => 'gpt-4o-mini',
          'max_tokens' => 2000,
          'temperature' => 0.7
        }
      end

      it 'folds memory-enriched additional context into the user message' do
        captured = nil
        allow(proxy).to receive(:execute_tool_loop) do |**kwargs|
          captured = kwargs
          proxy_result
        end

        job_instance.execute(agent_execution_id)

        expect(captured[:messages]).to include(
          a_hash_including(
            role: 'user',
            content: a_string_matching(/Explain Ruby on Rails testing.*Additional Context:.*Prefer minitest examples/m)
          )
        )
      end
    end

    context 'with an exhausted budget' do
      before do
        # An 'exhausted' alert for this agent flips check_budget_gate to
        # disallow, which must fail the execution before any proxy call.
        stub_backend_api_success(:get, '/api/v1/ai/autonomy/budgets/alerts', {
          'success' => true,
          'data' => [{ 'agent_id' => agent_id, 'level' => 'exhausted', 'remaining_cents' => 0 }]
        })
      end

      it 'fails the execution and skips the proxy when the budget is exhausted' do
        job_instance.execute(agent_execution_id)

        expect(proxy).not_to have_received(:execute_tool_loop)
        expect(WebMock).to have_requested(:patch, %r{api/v1/internal/ai/executions/#{agent_execution_id}})
          .with(body: hash_including(
            'agent_execution' => hash_including(
              'status' => 'failed',
              'error_message' => a_string_matching(/Budget exhausted/)
            )
          ))
      end
    end

    context 'with a reasoning-mode agent' do
      let(:reasoning_agent) do
        agent_data.merge('mcp_metadata' => { 'reasoning' => { 'mode' => 'star', 'reflection_enabled' => true } })
      end
      let(:reasoning_execution) { agent_execution_data.merge('ai_agent' => reasoning_agent) }

      before do
        stub_execution_lifecycle_endpoints(execution: reasoning_execution)
      end

      it 'routes through execute_with_reasoning instead of the tool loop' do
        captured = nil
        allow(proxy).to receive(:execute_with_reasoning) do |**kwargs|
          captured = kwargs
          proxy_result
        end

        job_instance.execute(agent_execution_id)

        expect(proxy).to have_received(:execute_with_reasoning)
        expect(proxy).not_to have_received(:execute_tool_loop)
        expect(captured).to include(reasoning_mode: 'star', reflection_enabled: true)
      end
    end

    context 'with state validation' do
      it 'does not execute agents in a completed state' do
        stub_execution_lifecycle_endpoints(execution: agent_execution_data.merge('status' => 'completed'))

        logger_double = mock_logger
        job_instance.execute(agent_execution_id)

        expect(logger_double).to have_received(:warn).with(
          a_string_matching(/Agent execution not in executable state/)
        )
        # Bails before transitioning state — no status PATCH.
        expect(WebMock).not_to have_requested(:patch, %r{api/v1/internal/ai/executions/#{agent_execution_id}})
      end

      it 'does not execute agents in a failed state' do
        stub_execution_lifecycle_endpoints(execution: agent_execution_data.merge('status' => 'failed'))

        logger_double = mock_logger
        job_instance.execute(agent_execution_id)

        expect(logger_double).to have_received(:warn).with(
          a_string_matching(/Agent execution not in executable state/)
        )
        expect(WebMock).not_to have_requested(:patch, %r{api/v1/internal/ai/executions/#{agent_execution_id}})
      end

      it 'executes agents in a queued state' do
        stub_execution_lifecycle_endpoints(execution: agent_execution_data.merge('status' => 'queued'))

        expect { job_instance.execute(agent_execution_id) }.not_to raise_error

        expect(WebMock).to have_requested(:patch, %r{api/v1/internal/ai/executions/#{agent_execution_id}})
          .with(body: hash_including('agent_execution' => hash_including('status' => 'running')))
      end

      it 'aborts when the execution has no agent data' do
        stub_execution_lifecycle_endpoints(execution: agent_execution_data.merge('ai_agent' => nil))

        logger_double = mock_logger
        job_instance.execute(agent_execution_id)

        expect(logger_double).to have_received(:error).with(
          a_string_matching(/Agent execution missing agent data/)
        )
        expect(proxy).not_to have_received(:execute_tool_loop)
      end
    end

    context 'with the kill switch active' do
      it 'bails before transitioning state when AI is suspended for the account' do
        allow_any_instance_of(described_class).to receive(:ai_suspended?).with(account_id).and_return(true)

        job_instance.execute(agent_execution_id)

        expect(proxy).not_to have_received(:execute_tool_loop)
        expect(WebMock).not_to have_requested(:patch, %r{api/v1/internal/ai/executions/#{agent_execution_id}})
      end
    end

    context 'with failures' do
      it 'logs and aborts when the execution cannot be fetched' do
        stub_backend_api_success(:get, "/api/v1/internal/ai/executions/#{agent_execution_id}", {
          'success' => false,
          'error' => 'Execution not found'
        })

        logger_double = mock_logger
        job_instance.execute(agent_execution_id)

        expect(logger_double).to have_received(:error).with(
          a_string_matching(/Failed to fetch agent execution/)
        )
        expect(proxy).not_to have_received(:execute_tool_loop)
      end

      it 'marks the execution failed when the proxy raises' do
        allow(proxy).to receive(:execute_tool_loop).and_raise(StandardError.new('provider unavailable'))

        expect { job_instance.execute(agent_execution_id) }.not_to raise_error

        expect(WebMock).to have_requested(:patch, %r{api/v1/internal/ai/executions/#{agent_execution_id}})
          .with(body: hash_including(
            'agent_execution' => hash_including(
              'status' => 'failed',
              'error_message' => a_string_matching(/Proxy execution failed.*provider unavailable/)
            )
          ))
      end

      it 'emits failure telemetry when the proxy raises' do
        allow(proxy).to receive(:execute_tool_loop).and_raise(StandardError.new('provider unavailable'))

        job_instance.execute(agent_execution_id)

        expect(WebMock).to have_requested(:post, %r{api/v1/ai/autonomy/telemetry})
          .with(body: hash_including('event_type' => 'agent_execution_failed', 'outcome' => 'failure'))
      end

      it 're-raises unexpected StandardErrors raised while fetching the execution' do
        # GET happens before the begin/rescue in #execute, so a raw transport
        # error propagates out of the job (Sidekiq then handles the retry).
        stub_request(:get, %r{/api/v1/internal/ai/executions/#{agent_execution_id}})
          .to_raise(StandardError.new('Unexpected error'))

        logger_double = mock_logger
        expect { job_instance.execute(agent_execution_id) }.to raise_error(StandardError, 'Unexpected error')
        expect(logger_double).to have_received(:error).at_least(:once)
      end
    end

    context 'with response processing' do
      it 'strips <think> reasoning tags from the stored content' do
        allow(proxy).to receive(:execute_tool_loop)
          .and_return(build_proxy_result('<think>Internal reasoning here</think>Actual response content'))

        job_instance.execute(agent_execution_id)

        expect(WebMock).to have_requested(:patch, %r{api/v1/internal/ai/executions/#{agent_execution_id}})
          .with(body: hash_including(
            'agent_execution' => hash_including(
              'output_data' => hash_including('content' => 'Actual response content')
            )
          ))
      end

      it 'truncates excessively long responses' do
        allow(proxy).to receive(:execute_tool_loop).and_return(build_proxy_result('a' * 15_000))

        job_instance.execute(agent_execution_id)

        expect(WebMock).to have_requested(:patch, %r{api/v1/internal/ai/executions/#{agent_execution_id}})
          .with(body: hash_including(
            'agent_execution' => hash_including(
              'output_data' => hash_including(
                'content' => a_string_matching(/Response truncated due to length/)
              )
            )
          ))
      end

      it 'stores both content and response fields for compatibility' do
        allow(proxy).to receive(:execute_tool_loop).and_return(build_proxy_result('Test response'))

        job_instance.execute(agent_execution_id)

        expect(WebMock).to have_requested(:patch, %r{api/v1/internal/ai/executions/#{agent_execution_id}})
          .with(body: hash_including(
            'agent_execution' => hash_including(
              'output_data' => hash_including(
                'content' => 'Test response',
                'response' => 'Test response'
              )
            )
          ))
      end
    end
  end

  describe 'error handling semantics' do
    let(:job_instance) { described_class.new }

    before do
      stub_execution_lifecycle_endpoints
      stub_proxy_seam
      allow_any_instance_of(described_class).to receive(:ai_suspended?).and_return(false)
    end

    it 'swallows proxy execution failures (marks failed, does not raise for Sidekiq retry)' do
      allow(proxy).to receive(:execute_tool_loop).and_raise(StandardError.new('service unavailable'))

      expect { job_instance.execute(agent_execution_id) }.not_to raise_error

      expect(WebMock).to have_requested(:patch, %r{api/v1/internal/ai/executions/#{agent_execution_id}})
        .with(body: hash_including('agent_execution' => hash_including('status' => 'failed')))
    end
  end
end
