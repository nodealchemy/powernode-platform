# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::SandboxService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  subject(:service) { described_class.new(account) }

  describe '#initialize' do
    it 'initializes with account' do
      expect(service.account).to eq(account)
    end
  end

  describe '#create_sandbox' do
    it 'creates a sandbox with default settings' do
      sandbox = service.create_sandbox(name: 'Test Sandbox', user: user)

      expect(sandbox).to be_persisted
      expect(sandbox.name).to eq('Test Sandbox')
      expect(sandbox.sandbox_type).to eq('standard')
      expect(sandbox.status).to eq('inactive')
      expect(sandbox.account).to eq(account)
      expect(sandbox.created_by).to eq(user)
    end

    it 'creates sandbox with custom type' do
      sandbox = service.create_sandbox(
        name: 'Isolated Sandbox',
        sandbox_type: 'isolated',
        user: user,
        description: 'An isolated sandbox environment'
      )

      expect(sandbox.sandbox_type).to eq('isolated')
      expect(sandbox.description).to eq('An isolated sandbox environment')
    end

    it 'creates sandbox with configuration' do
      config = { 'max_tokens' => 5000, 'timeout_seconds' => 120 }
      sandbox = service.create_sandbox(
        name: 'Configured Sandbox',
        user: user,
        configuration: config
      )

      expect(sandbox.configuration).to eq(config)
    end

    it 'creates sandbox with expiration' do
      expires = 7.days.from_now
      sandbox = service.create_sandbox(
        name: 'Expiring Sandbox',
        user: user,
        expires_at: expires
      )

      expect(sandbox.expires_at).to be_within(1.second).of(expires)
    end
  end

  describe '#activate_sandbox' do
    let(:sandbox) { create(:ai_sandbox, :inactive, account: account, created_by: user) }

    it 'activates an inactive sandbox' do
      result = service.activate_sandbox(sandbox)

      expect(result[:success]).to be true
      expect(sandbox.reload.status).to eq('active')
    end

    context 'when sandbox is expired' do
      let(:expired_sandbox) { create(:ai_sandbox, :expired, account: account, created_by: user) }

      it 'returns failure' do
        result = service.activate_sandbox(expired_sandbox)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Sandbox expired')
      end
    end
  end

  describe '#get_sandbox' do
    let!(:sandbox) { create(:ai_sandbox, account: account, created_by: user) }

    it 'finds sandbox by id' do
      result = service.get_sandbox(sandbox.id)
      expect(result).to eq(sandbox)
    end

    it 'raises error for nonexistent sandbox' do
      expect {
        service.get_sandbox(SecureRandom.uuid)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe '#create_scenario' do
    let(:sandbox) { create(:ai_sandbox, account: account, created_by: user) }

    it 'creates a test scenario' do
      scenario = service.create_scenario(
        sandbox: sandbox,
        name: 'Test Scenario',
        scenario_type: 'unit',
        user: user,
        description: 'A unit test scenario',
        input_data: { 'query' => 'test' },
        expected_output: { 'response' => 'expected' },
        assertions: [{ 'type' => 'equals', 'field' => 'status', 'value' => 'success' }]
      )

      expect(scenario).to be_persisted
      expect(scenario.name).to eq('Test Scenario')
      expect(scenario.scenario_type).to eq('unit')
      expect(scenario.status).to eq('draft')
      expect(scenario.input_data).to eq({ 'query' => 'test' })
    end

    it 'creates scenario with custom timeout' do
      scenario = service.create_scenario(
        sandbox: sandbox,
        name: 'Long Scenario',
        scenario_type: 'integration',
        timeout_seconds: 600
      )

      expect(scenario.timeout_seconds).to eq(600)
    end
  end

  describe '#create_mock' do
    let(:sandbox) { create(:ai_sandbox, account: account, created_by: user) }

    it 'creates a mock response' do
      mock = service.create_mock(
        sandbox: sandbox,
        name: 'OpenAI Mock',
        provider_type: 'openai',
        match_type: 'contains',
        match_criteria: { 'content' => 'test' },
        response_data: { 'text' => 'Mocked response' },
        user: user
      )

      expect(mock).to be_persisted
      expect(mock.name).to eq('OpenAI Mock')
      expect(mock.provider_type).to eq('openai')
      expect(mock.is_active).to be true
    end

    it 'creates mock with custom latency and error rate' do
      mock = service.create_mock(
        sandbox: sandbox,
        name: 'Slow Mock',
        provider_type: 'anthropic',
        latency_ms: 500,
        error_rate: 10
      )

      expect(mock.latency_ms).to eq(500)
      expect(mock.error_rate).to eq(10)
    end
  end

  describe '#create_test_run' do
    let(:sandbox) { create(:ai_sandbox, account: account, created_by: user) }
    let(:scenario) do
      service.create_scenario(
        sandbox: sandbox,
        name: 'Scenario 1',
        scenario_type: 'unit'
      )
    end

    it 'creates a test run' do
      result = service.create_test_run(
        sandbox: sandbox,
        scenario_ids: [scenario.id],
        user: user
      )

      expect(result[:success]).to be true
      expect(result[:run]).to be_persisted
      expect(result[:run].status).to eq('pending')
      expect(result[:run].total_scenarios).to eq(1)
    end

    it 'creates run with custom run_type' do
      result = service.create_test_run(
        sandbox: sandbox,
        scenario_ids: [scenario.id],
        run_type: 'automated'
      )

      expect(result[:run].run_type).to eq('automated')
    end
  end

  describe '#execute_test_run' do
    let(:sandbox) { create(:ai_sandbox, account: account, created_by: user) }
    let(:scenario) do
      service.create_scenario(
        sandbox: sandbox,
        name: 'Executable Scenario',
        scenario_type: 'unit',
        input_data: { 'query' => 'test' }
      )
    end
    let(:run) do
      service.create_test_run(
        sandbox: sandbox,
        scenario_ids: [scenario.id],
        user: user
      )[:run]
    end

    context 'when sandbox is active' do
      before { sandbox.update!(status: 'active') }

      it 'executes the test run' do
        result = service.execute_test_run(run)

        expect(result[:success]).to be true
        expect(result[:run].status).to eq('completed')
      end
    end

    context 'when sandbox is not active' do
      before { sandbox.update!(status: 'inactive') }

      it 'returns failure' do
        result = service.execute_test_run(run)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Sandbox not active')
      end
    end

    context 'when run is not pending' do
      before do
        sandbox.update!(status: 'active')
        run.update!(status: 'completed')
      end

      it 'returns failure' do
        result = service.execute_test_run(run)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Run not pending')
      end
    end
  end

  describe '#start_recording / #stop_recording' do
    let(:sandbox) { create(:ai_sandbox, account: account, created_by: user) }

    it 'enables recording' do
      result = service.start_recording(sandbox)

      expect(result[:success]).to be true
      expect(sandbox.reload.recording_enabled).to be true
    end

    it 'disables recording' do
      sandbox.update!(recording_enabled: true)

      result = service.stop_recording(sandbox)

      expect(result[:success]).to be true
      expect(sandbox.reload.recording_enabled).to be false
    end
  end

  describe '#record_interaction' do
    let(:sandbox) { create(:ai_sandbox, :with_recording, account: account, created_by: user) }

    it 'records interaction when recording is enabled' do
      expect {
        service.record_interaction(
          sandbox: sandbox,
          interaction_type: 'llm_call',
          request_data: { 'prompt' => 'Hello' },
          response_data: { 'response' => 'Hi' },
          provider_type: 'openai',
          latency_ms: 150,
          tokens_input: 10,
          tokens_output: 5
        )
      }.to change { sandbox.recorded_interactions.count }.by(1)
    end

    context 'when recording is disabled' do
      let(:sandbox_no_rec) { create(:ai_sandbox, account: account, created_by: user, recording_enabled: false) }

      it 'does not record interaction' do
        expect {
          service.record_interaction(
            sandbox: sandbox_no_rec,
            interaction_type: 'llm_call',
            request_data: { 'prompt' => 'Hello' },
            response_data: { 'response' => 'Hi' }
          )
        }.not_to change { Ai::RecordedInteraction.count }
      end
    end
  end

  describe '#create_benchmark' do
    it 'creates a performance benchmark' do
      benchmark = service.create_benchmark(
        name: 'Latency Benchmark',
        user: user,
        description: 'Measure response latency',
        baseline_metrics: { 'latency_ms' => 1000 },
        thresholds: { 'latency_ms' => { 'max' => 2000 } }
      )

      expect(benchmark).to be_persisted
      expect(benchmark.name).to eq('Latency Benchmark')
      expect(benchmark.status).to eq('active')
    end
  end

  describe '#create_ab_test' do
    it 'creates an A/B test' do
      test = service.create_ab_test(
        name: 'Prompt A/B Test',
        target_type: 'agent',
        target_id: SecureRandom.uuid,
        variants: [
          { 'id' => 'a', 'name' => 'Variant A', 'config' => { 'temperature' => 0.5 } },
          { 'id' => 'b', 'name' => 'Variant B', 'config' => { 'temperature' => 0.8 } }
        ],
        traffic_allocation: { 'a' => 50, 'b' => 50 },
        success_metrics: ['response_quality'],
        user: user
      )

      expect(test).to be_persisted
      expect(test.name).to eq('Prompt A/B Test')
      expect(test.status).to eq('draft')
      expect(test.variants.length).to eq(2)
    end
  end

  describe '#start_ab_test' do
    let(:test) do
      service.create_ab_test(
        name: 'Start Test',
        target_type: 'agent',
        target_id: SecureRandom.uuid,
        variants: [
          { 'id' => 'a', 'name' => 'A' },
          { 'id' => 'b', 'name' => 'B' }
        ],
        user: user
      )
    end

    it 'starts test with sufficient variants' do
      result = service.start_ab_test(test)

      expect(result[:success]).to be true
      expect(test.reload.status).to eq('running')
    end

    context 'with insufficient variants' do
      let(:bad_test) do
        service.create_ab_test(
          name: 'Bad Test',
          target_type: 'agent',
          target_id: SecureRandom.uuid,
          variants: [{ 'id' => 'a', 'name' => 'A' }],
          user: user
        )
      end

      it 'returns failure' do
        result = service.start_ab_test(bad_test)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Insufficient variants')
      end
    end
  end
end
