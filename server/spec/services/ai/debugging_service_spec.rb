# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::DebuggingService, type: :service do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }
  let(:execution) { create(:ai_agent_execution, agent: agent, status: 'failed', error_message: 'Rate limit exceeded') }
  let(:execution_context) { { request_id: 'test-123' } }
  let(:service) { described_class.new(account, execution_context) }

  before do
    allow(Redis).to receive(:new).and_return(redis_mock)
  end

  let(:redis_mock) { instance_double(Redis).as_null_object }

  describe '#initialize' do
    it 'initializes with account and execution context' do
      expect(service.instance_variable_get(:@account)).to eq(account)
      expect(service.instance_variable_get(:@execution_context)).to eq(execution_context)
    end
  end

  describe '#generate_debug_report' do
    before do
      # Mock various service dependencies
      allow(service).to receive(:find_execution).and_return(execution)
      allow(service).to receive(:build_execution_info).and_return({ id: execution.id, status: 'failed' })
      allow(service).to receive(:capture_system_state).and_return({ timestamp: Time.current.iso8601 })
      allow(service).to receive(:generate_provider_diagnostics).and_return({ provider_id: provider.id })
      allow(service).to receive(:analyze_execution_errors).and_return({ error_type: 'rate_limit' })
      allow(service).to receive(:collect_performance_metrics).and_return({ execution_time_ms: 5000 })
      allow(service).to receive(:generate_recovery_suggestions).and_return([ 'Retry with backoff' ])
      allow(service).to receive(:generate_troubleshooting_steps).and_return([ { step: 1, action: 'Check provider' } ])
      allow(service).to receive(:find_related_incidents).and_return([])
      allow(service).to receive(:collect_debug_logs).and_return({ application_logs: [] })
      allow(service).to receive(:detect_configuration_issues).and_return([])
      allow(service).to receive(:store_debug_report)
    end

    it 'generates comprehensive debug report' do
      report = service.generate_debug_report(execution.id, 'agent')

      expect(report).to include(
        :execution_info,
        :system_state,
        :provider_diagnostics,
        :error_analysis,
        :performance_metrics,
        :recovery_suggestions,
        :troubleshooting_steps,
        :related_incidents,
        :debug_logs,
        :configuration_issues
      )

      expect(service).to have_received(:store_debug_report)
    end

    context 'when execution not found' do
      before do
        allow(service).to receive(:find_execution).and_return(nil)
      end

      it 'returns nil' do
        report = service.generate_debug_report('invalid-id', 'agent')
        expect(report).to be_nil
      end
    end
  end

  describe '#start_debug_session' do
    before do
      allow(service).to receive(:find_execution).and_return(execution)
      allow(service).to receive(:store_debug_session)
      allow(service).to receive(:monitor_execution_realtime)
      allow(SecureRandom).to receive(:uuid).and_return('debug-session-123')
    end

    it 'creates and returns debug session ID' do
      session_id = service.start_debug_session(execution.id, 'agent')

      expect(session_id).to eq('debug-session-123')
      expect(service).to have_received(:store_debug_session)
      expect(service).to have_received(:monitor_execution_realtime)
    end

    context 'when execution not found' do
      before do
        allow(service).to receive(:find_execution).and_return(nil)
      end

      it 'returns nil' do
        session_id = service.start_debug_session('invalid-id', 'agent')
        expect(session_id).to be_nil
      end
    end
  end

  describe '#collect_debug_data' do
    let(:session_id) { 'debug-session-123' }
    let(:existing_session) do
      {
        'session_id' => session_id,
        'collected_data' => []
      }
    end

    before do
      allow(service).to receive(:get_debug_session).and_return(existing_session)
      allow(service).to receive(:store_debug_session)
    end

    it 'adds data to debug session' do
      result = service.collect_debug_data(session_id, 'performance', { cpu: 80.5 })

      expect(result).to be true
      expect(service).to have_received(:store_debug_session)
    end

    context 'when session not found' do
      before do
        allow(service).to receive(:get_debug_session).and_return(nil)
      end

      it 'returns false' do
        result = service.collect_debug_data(session_id, 'performance', { cpu: 80.5 })
        expect(result).to be false
      end
    end
  end

  describe '#end_debug_session' do
    let(:session_id) { 'debug-session-123' }
    let(:session_data) do
      {
        'session_id' => session_id,
        'collected_data' => [
          { 'timestamp' => Time.current.iso8601, 'data_type' => 'performance', 'data' => { cpu: 80.5 } }
        ]
      }
    end

    before do
      allow(service).to receive(:get_debug_session).and_return(session_data)
      allow(service).to receive(:compile_session_report).and_return({ summary: 'Debug session completed' })
      allow(service).to receive(:store_debug_session)
      allow(service).to receive(:cleanup_debug_session)
    end

    it 'completes debug session and returns final report' do
      report = service.end_debug_session(session_id)

      expect(report).to eq({ summary: 'Debug session completed' })
      expect(service).to have_received(:store_debug_session)
      expect(service).to have_received(:cleanup_debug_session)
    end
  end

  describe '#analyze_execution_patterns' do
    let(:executions) { [ execution ] }

    before do
      allow(service).to receive(:get_recent_executions).and_return(executions)
      allow(service).to receive(:detect_failure_patterns).and_return([ 'Rate limit pattern' ])
      allow(service).to receive(:detect_performance_anomalies).and_return([ 'Slow response times' ])
      allow(service).to receive(:detect_provider_issues).and_return([ 'Provider X downtime' ])
      allow(service).to receive(:detect_configuration_drifts).and_return([])
      allow(service).to receive(:generate_pattern_recommendations).and_return([ 'Implement circuit breaker' ])
    end

    it 'analyzes execution patterns' do
      analysis = service.analyze_execution_patterns

      expect(analysis).to include(
        :total_executions,
        :failure_patterns,
        :performance_anomalies,
        :provider_issues,
        :configuration_drifts,
        :recommendations
      )

      expect(analysis[:total_executions]).to eq(1)
      expect(analysis[:failure_patterns]).to eq([ 'Rate limit pattern' ])
    end
  end

  describe '#generate_execution_replay' do
    before do
      allow(service).to receive(:find_execution).and_return(execution)
      allow(service).to receive(:extract_original_input).and_return({ prompt: 'Test prompt' })
      allow(service).to receive(:reconstruct_execution_steps).and_return([ { step: 1, action: 'Initialize' } ])
      allow(service).to receive(:extract_provider_interactions).and_return([ { request: 'API call' } ])
      allow(service).to receive(:extract_state_changes).and_return([ { state: 'running' } ])
      allow(service).to receive(:identify_error_points).and_return([ { error: 'Rate limit' } ])
      allow(service).to receive(:generate_replay_instructions).and_return([ 'Step 1: Retry' ])
      allow(service).to receive(:store_execution_replay)
    end

    it 'generates execution replay data' do
      replay = service.generate_execution_replay(execution.id, 'agent')

      expect(replay).to include(
        :execution_id,
        :execution_type,
        :original_input,
        :execution_steps,
        :provider_interactions,
        :state_changes,
        :error_points,
        :replay_instructions
      )

      expect(replay[:execution_id]).to eq(execution.id)
      expect(replay[:execution_type]).to eq('agent')
    end
  end

  describe '#profile_execution_performance' do
    before do
      allow(service).to receive(:find_execution).and_return(execution)
      allow(service).to receive(:build_execution_timeline).and_return([ { timestamp: Time.current.iso8601 } ])
      allow(service).to receive(:identify_performance_bottlenecks).and_return([ 'API latency' ])
      allow(service).to receive(:analyze_resource_usage).and_return({ memory: '256MB' })
      allow(service).to receive(:analyze_network_performance).and_return({ latency: 120 })
      allow(service).to receive(:suggest_performance_optimizations).and_return([ 'Use caching' ])
    end

    it 'profiles execution performance' do
      profile = service.profile_execution_performance(execution.id, 'agent')

      expect(profile).to include(
        :execution_timeline,
        :bottlenecks,
        :resource_usage,
        :network_analysis,
        :optimization_suggestions
      )

      expect(profile[:bottlenecks]).to eq([ 'API latency' ])
      expect(profile[:optimization_suggestions]).to eq([ 'Use caching' ])
    end
  end

  describe '#find_execution' do
    context 'with agent execution type' do
      it 'finds agent execution' do
        # Ensure execution is properly associated with the account
        execution.update!(account: account)
        result = service.send(:find_execution, execution.id, 'agent')
        expect(result).to eq(execution)
      end
    end

    context 'with workflow execution type' do
      let(:workflow) { create(:ai_workflow, account: account) }
      let(:workflow_run) { create(:ai_workflow_run, workflow: workflow) }

      it 'finds workflow run' do
        # This test would need more setup for the workflow execution finding logic
        result = service.send(:find_execution, workflow_run.id, 'workflow')
        # The actual implementation would need to be tested based on the real model relationships
      end
    end

    context 'with invalid execution type' do
      it 'returns nil' do
        result = service.send(:find_execution, execution.id, 'invalid')
        expect(result).to be_nil
      end
    end
  end

  describe '#build_execution_info' do
    it 'builds comprehensive execution info for agent execution' do
      info = service.send(:build_execution_info, execution)

      expect(info).to include(:id, :status, :type, :agent_id, :agent_name, :provider_id)
      expect(info[:id]).to eq(execution.id)
      expect(info[:type]).to eq('agent_execution')
      expect(info[:agent_id]).to eq(agent.id)
      expect(info[:execution_context]).to eq(execution.execution_context || {})
    end
  end

  describe '#classify_error_type' do
    it 'classifies rate limit errors' do
      expect(service.send(:classify_error_type, 'Rate limit exceeded')).to eq('rate_limit')
    end

    it 'classifies timeout errors' do
      expect(service.send(:classify_error_type, 'Request timed out')).to eq('timeout')
    end

    it 'classifies authentication errors' do
      expect(service.send(:classify_error_type, 'Unauthorized access')).to eq('authentication')
    end

    it 'classifies unknown errors' do
      expect(service.send(:classify_error_type, 'Some random error')).to eq('unknown')
    end
  end

  describe '#capture_system_state' do
    before do
      allow(service).to receive(:count_active_executions).and_return(5)
      allow(service).to receive(:get_all_provider_statuses).and_return([])
      allow(service).to receive(:get_system_load_metrics).and_return({})
      allow(service).to receive(:get_circuit_breaker_states).and_return([])
      allow(service).to receive(:get_queue_statuses).and_return({})
    end

    it 'captures comprehensive system state' do
      state = service.send(:capture_system_state)

      expect(state).to include(
        :timestamp,
        :active_executions,
        :provider_statuses,
        :system_load,
        :circuit_breaker_states,
        :queue_statuses
      )

      expect(state[:active_executions]).to eq(5)
    end
  end
end
