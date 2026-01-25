# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::Sandboxes', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  let(:headers) { auth_headers_for(user) }

  let(:sandbox_service) { instance_double(Ai::SandboxService) }

  before do
    allow(Ai::SandboxService).to receive(:new).and_return(sandbox_service)
  end

  describe 'GET /api/v1/ai/sandboxes' do
    let!(:sandbox1) { create(:ai_sandbox, account: account, sandbox_type: 'standard') }
    let!(:sandbox2) { create(:ai_sandbox, account: account, sandbox_type: 'isolated') }

    context 'with authentication' do
      it 'returns list of sandboxes' do
        get '/api/v1/ai/sandboxes', headers: headers

        expect_success_response
        data = json_response_data
        expect(data['sandboxes']).to be_an(Array)
        expect(data['sandboxes'].length).to eq(2)
      end

      it 'filters by sandbox_type' do
        get "/api/v1/ai/sandboxes?sandbox_type=standard", headers: headers

        expect_success_response
        data = json_response_data
        expect(data['sandboxes'].all? { |s| s['sandbox_type'] == 'standard' }).to be true
      end

      it 'filters by status' do
        get "/api/v1/ai/sandboxes?status=active", headers: headers

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/sandboxes' do
    let(:valid_params) do
      {
        name: 'Test Sandbox',
        sandbox_type: 'standard',
        description: 'A test sandbox'
      }
    end

    context 'with authentication' do
      it 'creates a new sandbox' do
        sandbox = build(:ai_sandbox, id: SecureRandom.uuid, name: 'Test Sandbox', account: account)
        allow(sandbox_service).to receive(:create_sandbox).and_return(sandbox)

        post '/api/v1/ai/sandboxes', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(sandbox_service).to have_received(:create_sandbox)
          .with(hash_including(name: 'Test Sandbox', user: user))
      end
    end
  end

  describe 'GET /api/v1/ai/sandboxes/:id' do
    let(:sandbox) { create(:ai_sandbox, account: account) }

    context 'with authentication' do
      it 'returns sandbox details' do
        get "/api/v1/ai/sandboxes/#{sandbox.id}", headers: headers

        expect_success_response
        data = json_response_data
        expect(data['sandbox']['id']).to eq(sandbox.id)
      end
    end
  end

  describe 'PUT /api/v1/ai/sandboxes/:id' do
    let(:sandbox) { create(:ai_sandbox, account: account) }
    let(:update_params) { { name: 'Updated Sandbox' } }

    context 'with authentication' do
      it 'updates the sandbox' do
        put "/api/v1/ai/sandboxes/#{sandbox.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        expect(sandbox.reload.name).to eq('Updated Sandbox')
      end
    end
  end

  describe 'DELETE /api/v1/ai/sandboxes/:id' do
    let(:sandbox) { create(:ai_sandbox, account: account) }

    context 'with authentication' do
      it 'marks sandbox as deleted' do
        delete "/api/v1/ai/sandboxes/#{sandbox.id}", headers: headers

        expect_success_response
        expect(sandbox.reload.status).to eq('deleted')
      end
    end
  end

  describe 'PUT /api/v1/ai/sandboxes/:id/activate' do
    let(:sandbox) { create(:ai_sandbox, account: account, status: 'inactive') }

    context 'with authentication' do
      it 'activates the sandbox' do
        result = { success: true, sandbox: sandbox }
        allow(sandbox_service).to receive(:activate_sandbox).and_return(result)

        put "/api/v1/ai/sandboxes/#{sandbox.id}/activate", headers: headers

        expect_success_response
        expect(sandbox_service).to have_received(:activate_sandbox)
      end

      it 'returns error on activation failure' do
        result = { success: false, error: 'Activation failed' }
        allow(sandbox_service).to receive(:activate_sandbox).and_return(result)

        put "/api/v1/ai/sandboxes/#{sandbox.id}/activate", headers: headers

        expect_error_response('Activation failed', 422)
      end
    end
  end

  describe 'PUT /api/v1/ai/sandboxes/:id/deactivate' do
    let(:sandbox) { create(:ai_sandbox, account: account, status: 'active') }

    context 'with authentication' do
      it 'deactivates the sandbox' do
        put "/api/v1/ai/sandboxes/#{sandbox.id}/deactivate", headers: headers

        expect_success_response
        expect(sandbox.reload.status).to eq('inactive')
      end
    end
  end

  describe 'GET /api/v1/ai/sandboxes/:id/analytics' do
    let(:sandbox) { create(:ai_sandbox, account: account) }

    context 'with authentication' do
      it 'returns sandbox analytics' do
        analytics = { total_runs: 10, success_rate: 0.9 }
        allow(sandbox_service).to receive(:get_sandbox_analytics).and_return(analytics)

        get "/api/v1/ai/sandboxes/#{sandbox.id}/analytics", headers: headers

        expect_success_response
        data = json_response_data
        expect(data['analytics']).to eq(analytics.stringify_keys)
      end
    end
  end

  describe 'GET /api/v1/ai/sandboxes/:sandbox_id/scenarios' do
    let(:sandbox) { create(:ai_sandbox, account: account) }

    context 'with authentication' do
      it 'returns list of test scenarios' do
        get "/api/v1/ai/sandboxes/#{sandbox.id}/scenarios", headers: headers

        expect_success_response
        data = json_response_data
        expect(data['scenarios']).to be_an(Array)
      end
    end
  end

  describe 'POST /api/v1/ai/sandboxes/:sandbox_id/scenarios' do
    let(:sandbox) { create(:ai_sandbox, account: account) }
    let(:valid_params) do
      {
        name: 'Test Scenario',
        scenario_type: 'functional',
        input_data: { test: 'data' }
      }
    end

    context 'with authentication' do
      it 'creates a new test scenario' do
        scenario = double(
          id: 'scen123',
          name: 'Test Scenario',
          description: 'A test scenario',
          scenario_type: 'functional',
          status: 'active',
          target_type: nil,
          target_workflow_id: nil,
          target_agent_id: nil,
          input_data: { test: 'data' },
          expected_output: {},
          assertions: [],
          timeout_seconds: 300,
          run_count: 0,
          pass_count: 0,
          fail_count: 0,
          pass_rate: 0.0,
          last_run_at: nil,
          created_at: Time.current
        )
        allow(sandbox_service).to receive(:create_scenario).and_return(scenario)

        post "/api/v1/ai/sandboxes/#{sandbox.id}/scenarios", params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(sandbox_service).to have_received(:create_scenario)
      end
    end
  end

  describe 'GET /api/v1/ai/sandboxes/:sandbox_id/mocks' do
    let(:sandbox) { create(:ai_sandbox, account: account) }

    context 'with authentication' do
      it 'returns list of mock responses' do
        get "/api/v1/ai/sandboxes/#{sandbox.id}/mocks", headers: headers

        expect_success_response
        data = json_response_data
        expect(data['mocks']).to be_an(Array)
      end
    end
  end

  describe 'POST /api/v1/ai/sandboxes/:sandbox_id/mocks' do
    let(:sandbox) { create(:ai_sandbox, account: account) }
    let(:valid_params) do
      {
        name: 'Test Mock',
        provider_type: 'openai',
        response_data: { result: 'test' }
      }
    end

    context 'with authentication' do
      it 'creates a new mock response' do
        mock = double(
          id: 'mock123',
          name: 'Test Mock',
          provider_type: 'openai',
          model_name: 'gpt-4',
          endpoint: '/v1/chat/completions',
          match_type: 'exact',
          match_criteria: {},
          response_data: { result: 'test' },
          latency_ms: 100,
          error_rate: 0,
          is_active: true,
          priority: 1,
          hit_count: 0,
          last_hit_at: nil,
          created_at: Time.current
        )
        allow(sandbox_service).to receive(:create_mock).and_return(mock)

        post "/api/v1/ai/sandboxes/#{sandbox.id}/mocks", params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(sandbox_service).to have_received(:create_mock)
      end
    end
  end

  describe 'GET /api/v1/ai/sandboxes/:sandbox_id/runs' do
    let(:sandbox) { create(:ai_sandbox, account: account) }

    context 'with authentication' do
      it 'returns list of test runs' do
        get "/api/v1/ai/sandboxes/#{sandbox.id}/runs", headers: headers

        expect_success_response
        data = json_response_data
        expect(data['runs']).to be_an(Array)
      end
    end
  end

  describe 'POST /api/v1/ai/sandboxes/:sandbox_id/runs' do
    let(:sandbox) { create(:ai_sandbox, account: account) }
    let(:valid_params) do
      {
        scenario_ids: ['scen1', 'scen2'],
        run_type: 'manual'
      }
    end

    context 'with authentication' do
      it 'creates a new test run' do
        run = double(
          id: 'run123',
          run_id: SecureRandom.uuid,
          run_type: 'manual',
          status: 'pending',
          total_scenarios: 0,
          passed_scenarios: 0,
          failed_scenarios: 0,
          skipped_scenarios: 0,
          pass_rate: 0.0,
          duration_ms: nil,
          started_at: nil,
          completed_at: nil,
          created_at: Time.current
        )
        result = { success: true, run: run }
        allow(sandbox_service).to receive(:create_test_run).and_return(result)

        post "/api/v1/ai/sandboxes/#{sandbox.id}/runs", params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(sandbox_service).to have_received(:create_test_run)
      end

      it 'returns error on creation failure' do
        result = { success: false, error: 'Creation failed' }
        allow(sandbox_service).to receive(:create_test_run).and_return(result)

        post "/api/v1/ai/sandboxes/#{sandbox.id}/runs", params: valid_params, headers: headers, as: :json

        expect_error_response('Creation failed', 422)
      end
    end
  end

  describe 'POST /api/v1/ai/sandboxes/:sandbox_id/runs/:run_id/execute' do
    let(:sandbox) { create(:ai_sandbox, account: account) }
    let(:test_run) { create(:ai_test_run, account: account, sandbox: sandbox) }

    context 'with authentication' do
      it 'executes the test run' do
        result = { success: true, run: test_run }
        allow(sandbox_service).to receive(:execute_test_run).and_return(result)

        post "/api/v1/ai/sandboxes/#{sandbox.id}/runs/#{test_run.id}/execute", headers: headers

        expect_success_response
        expect(sandbox_service).to have_received(:execute_test_run)
      end
    end
  end

  describe 'GET /api/v1/ai/sandboxes/:sandbox_id/runs/:run_id' do
    let(:sandbox) { create(:ai_sandbox, account: account) }
    let(:test_run) { create(:ai_test_run, account: account, sandbox: sandbox) }

    context 'with authentication' do
      it 'returns test run details' do
        get "/api/v1/ai/sandboxes/#{sandbox.id}/runs/#{test_run.id}", headers: headers

        expect_success_response
        data = json_response_data
        expect(data['run']).to be_present
      end
    end
  end

  describe 'GET /api/v1/ai/sandboxes/:sandbox_id/benchmarks' do
    let(:sandbox) { create(:ai_sandbox, account: account) }

    context 'with authentication' do
      it 'returns list of performance benchmarks' do
        get "/api/v1/ai/sandboxes/#{sandbox.id}/benchmarks", headers: headers

        expect_success_response
        data = json_response_data
        expect(data['benchmarks']).to be_an(Array)
      end
    end
  end

  describe 'POST /api/v1/ai/sandboxes/:sandbox_id/benchmarks' do
    let(:sandbox) { create(:ai_sandbox, account: account) }
    let(:valid_params) do
      {
        name: 'Performance Benchmark',
        baseline_metrics: { latency: 100 }
      }
    end

    context 'with authentication' do
      it 'creates a new benchmark' do
        benchmark = double(
          id: 'bench123',
          benchmark_id: SecureRandom.uuid,
          name: 'Performance Benchmark',
          description: 'A performance benchmark',
          status: 'active',
          target_workflow_id: nil,
          target_agent_id: nil,
          baseline_metrics: { latency: 100 },
          thresholds: {},
          sample_size: 100,
          run_count: 0,
          latest_results: {},
          latest_score: nil,
          trend: 'stable',
          last_run_at: nil,
          created_at: Time.current
        )
        allow(sandbox_service).to receive(:create_benchmark).and_return(benchmark)

        post "/api/v1/ai/sandboxes/#{sandbox.id}/benchmarks", params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(sandbox_service).to have_received(:create_benchmark)
      end
    end
  end

  describe 'POST /api/v1/ai/sandboxes/:sandbox_id/benchmarks/:benchmark_id/run' do
    let(:sandbox) { create(:ai_sandbox, account: account) }
    let(:benchmark) { create(:ai_performance_benchmark, account: account, sandbox: sandbox) }

    context 'with authentication' do
      it 'runs the benchmark' do
        result = { success: true, benchmark: benchmark, results: { latency_ms: 150, throughput: 100 }, violations: [], comparison: {} }
        allow(sandbox_service).to receive(:run_benchmark).and_return(result)

        post "/api/v1/ai/sandboxes/#{sandbox.id}/benchmarks/#{benchmark.id}/run", headers: headers

        expect_success_response
        data = json_response_data
        expect(data['benchmark']).to be_present
        expect(data['results']).to be_present
      end
    end
  end

  describe 'GET /api/v1/ai/ab_tests' do
    context 'with authentication' do
      it 'returns list of A/B tests' do
        get '/api/v1/ai/ab_tests', headers: headers

        expect_success_response
        data = json_response_data
        expect(data['ab_tests']).to be_an(Array)
      end
    end
  end

  describe 'POST /api/v1/ai/ab_tests' do
    let(:valid_params) do
      {
        name: 'Test A/B',
        target_type: 'workflow',
        target_id: 'w123',
        variants: [{ name: 'A' }, { name: 'B' }]
      }
    end

    context 'with authentication' do
      it 'creates a new A/B test' do
        ab_test = double(
          id: 'test123',
          test_id: SecureRandom.uuid,
          name: 'Test A/B',
          description: nil,
          status: 'draft',
          target_type: 'workflow',
          target_id: 'w123',
          variants: [{ name: 'A' }, { name: 'B' }],
          traffic_allocation: {},
          success_metrics: [],
          total_impressions: 0,
          total_conversions: 0,
          winning_variant: nil,
          statistical_significance: nil,
          started_at: nil,
          ended_at: nil,
          created_at: Time.current
        )
        allow(sandbox_service).to receive(:create_ab_test).and_return(ab_test)

        post '/api/v1/ai/ab_tests', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(sandbox_service).to have_received(:create_ab_test)
      end
    end
  end

  describe 'PUT /api/v1/ai/ab_tests/:id/start' do
    let(:ab_test) { create(:ai_ab_test, account: account) }

    context 'with authentication' do
      it 'starts the A/B test' do
        result = { success: true, test: ab_test }
        allow(sandbox_service).to receive(:start_ab_test).and_return(result)

        put "/api/v1/ai/ab_tests/#{ab_test.id}/start", headers: headers

        expect_success_response
        expect(sandbox_service).to have_received(:start_ab_test)
      end
    end
  end

  describe 'GET /api/v1/ai/ab_tests/:id/results' do
    let(:ab_test) { create(:ai_ab_test, account: account) }

    context 'with authentication' do
      it 'returns A/B test results' do
        results = { winner: 'A', significance: 0.95 }
        allow(sandbox_service).to receive(:get_ab_test_results).and_return(results)

        get "/api/v1/ai/ab_tests/#{ab_test.id}/results", headers: headers

        expect_success_response
        data = json_response_data
        expect(data['results']).to eq(results.stringify_keys)
      end
    end
  end
end
