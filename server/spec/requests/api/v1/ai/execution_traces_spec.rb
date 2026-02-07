# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::ExecutionTraces', type: :request do
  let(:account) { create(:account) }
  let(:user_with_permission) { create(:user, account: account, permissions: ['ai_monitoring.read']) }
  let(:user_without_permission) { create(:user, account: account, permissions: []) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, account: other_account, permissions: ['ai_monitoring.read']) }

  let(:headers) { auth_headers_for(user_with_permission) }
  let(:forbidden_headers) { auth_headers_for(user_without_permission) }
  let(:other_headers) { auth_headers_for(other_user) }

  # Helper to create execution traces
  let(:create_trace) do
    ->(attrs = {}) {
      Ai::ExecutionTrace.create!({
        account: account,
        trace_id: "trace-#{SecureRandom.hex(8)}",
        name: "Test Trace #{SecureRandom.hex(4)}",
        trace_type: 'agent',
        status: 'completed',
        started_at: 1.hour.ago,
        completed_at: Time.current,
        duration_ms: 3600000,
        total_tokens: 500,
        total_cost: 0.05,
        metadata: {}
      }.merge(attrs))
    }
  end

  # Helper to create trace spans
  let(:create_span) do
    ->(trace, attrs = {}) {
      Ai::ExecutionTraceSpan.create!({
        execution_trace: trace,
        span_id: "span-#{SecureRandom.hex(8)}",
        name: "Test Span #{SecureRandom.hex(4)}",
        span_type: 'llm_call',
        status: 'completed',
        started_at: trace.started_at,
        completed_at: trace.completed_at,
        duration_ms: 1000,
        tokens: { 'prompt' => 100, 'completion' => 50 },
        cost: 0.01,
        metadata: {}
      }.merge(attrs))
    }
  end

  describe 'GET /api/v1/ai/execution_traces' do
    before do
      3.times { create_trace.call }
    end

    context 'with ai_monitoring.read permission' do
      it 'returns list of execution traces' do
        allow(Ai::TracingService).to receive(:list_traces).and_return(
          traces: [
            { trace_id: 'trace-1', name: 'Test', status: 'completed' },
            { trace_id: 'trace-2', name: 'Test 2', status: 'completed' },
            { trace_id: 'trace-3', name: 'Test 3', status: 'completed' }
          ]
        )

        get '/api/v1/ai/execution_traces', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to be_present
      end

      it 'accepts limit parameter' do
        allow(Ai::TracingService).to receive(:list_traces).and_return(traces: [])

        get '/api/v1/ai/execution_traces?limit=10', headers: headers, as: :json

        expect_success_response
      end

      it 'accepts type filter' do
        allow(Ai::TracingService).to receive(:list_traces).and_return(traces: [])

        get '/api/v1/ai/execution_traces?type=agent', headers: headers, as: :json

        expect_success_response
      end

      it 'accepts status filter' do
        allow(Ai::TracingService).to receive(:list_traces).and_return(traces: [])

        get '/api/v1/ai/execution_traces?status=completed', headers: headers, as: :json

        expect_success_response
      end
    end

    context 'without ai_monitoring.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/ai/execution_traces', headers: forbidden_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/ai/execution_traces', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/ai/execution_traces/:id' do
    let(:trace) { create_trace.call }

    context 'with ai_monitoring.read permission' do
      it 'returns trace details' do
        allow(Ai::TracingService).to receive(:get_trace).and_return(
          trace_id: trace.trace_id,
          name: trace.name,
          status: trace.status,
          spans: []
        )

        get "/api/v1/ai/execution_traces/#{trace.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to be_present
      end

      it 'finds trace by trace_id' do
        allow(Ai::TracingService).to receive(:get_trace).and_return(
          trace_id: trace.trace_id,
          name: trace.name,
          status: trace.status
        )

        get "/api/v1/ai/execution_traces/#{trace.trace_id}", headers: headers, as: :json

        expect_success_response
      end

      it 'returns not found for non-existent trace' do
        get "/api/v1/ai/execution_traces/#{SecureRandom.uuid}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without ai_monitoring.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/ai/execution_traces/#{trace.id}", headers: forbidden_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'accessing trace from different account' do
      let(:other_trace) do
        Ai::ExecutionTrace.create!(
          account: other_account,
          trace_id: "trace-other-#{SecureRandom.hex(8)}",
          name: 'Other Account Trace',
          trace_type: 'agent',
          status: 'completed',
          started_at: 1.hour.ago,
          metadata: {}
        )
      end

      it 'returns not found error' do
        get "/api/v1/ai/execution_traces/#{other_trace.id}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /api/v1/ai/execution_traces/:id/spans' do
    let(:trace) { create_trace.call }

    before do
      3.times { create_span.call(trace) }
    end

    context 'with ai_monitoring.read permission' do
      it 'returns spans for the trace' do
        get "/api/v1/ai/execution_traces/#{trace.id}/spans", headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data).to include('trace_id', 'spans', 'summary')
        expect(data['spans']).to be_an(Array)
        expect(data['spans'].length).to eq(3)
      end

      it 'includes summary with span counts' do
        get "/api/v1/ai/execution_traces/#{trace.id}/spans", headers: headers, as: :json

        data = json_response_data
        summary = data['summary']

        expect(summary).to include('total', 'by_type', 'by_status')
        expect(summary['total']).to eq(3)
      end
    end

    context 'without ai_monitoring.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/ai/execution_traces/#{trace.id}/spans", headers: forbidden_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/ai/execution_traces/:id/timeline' do
    let(:trace) { create_trace.call }

    before do
      2.times { create_span.call(trace) }
    end

    context 'with ai_monitoring.read permission' do
      it 'returns timeline data for the trace' do
        get "/api/v1/ai/execution_traces/#{trace.id}/timeline", headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data).to include(
          'trace_id' => trace.trace_id,
          'name' => trace.name,
          'type' => trace.trace_type,
          'status' => trace.status
        )
        expect(data).to have_key('timeline')
        expect(data).to have_key('summary')
      end

      it 'includes summary with tokens and cost' do
        get "/api/v1/ai/execution_traces/#{trace.id}/timeline", headers: headers, as: :json

        data = json_response_data
        summary = data['summary']

        expect(summary).to include('total_tokens', 'total_cost', 'success_rate')
      end
    end

    context 'without ai_monitoring.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/ai/execution_traces/#{trace.id}/timeline", headers: forbidden_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/ai/execution_traces/summary' do
    before do
      create_trace.call(status: 'completed')
      create_trace.call(status: 'failed')
    end

    context 'with ai_monitoring.read permission' do
      it 'returns summary statistics' do
        get '/api/v1/ai/execution_traces/summary', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data).to include(
          'total_traces',
          'by_status',
          'by_type',
          'total_tokens',
          'total_cost',
          'error_rate',
          'time_range'
        )
      end

      it 'accepts time_range parameter' do
        get '/api/v1/ai/execution_traces/summary?time_range=7d', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['time_range']).to eq('7d')
      end

      it 'defaults to 24h time range' do
        get '/api/v1/ai/execution_traces/summary', headers: headers, as: :json

        data = json_response_data
        expect(data['time_range']).to eq('24h')
      end
    end

    context 'without ai_monitoring.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/ai/execution_traces/summary', headers: forbidden_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # Account isolation
  describe 'account isolation' do
    let(:own_trace) { create_trace.call }
    let(:other_trace) do
      Ai::ExecutionTrace.create!(
        account: other_account,
        trace_id: "trace-isolation-#{SecureRandom.hex(8)}",
        name: 'Isolated Trace',
        trace_type: 'agent',
        status: 'completed',
        started_at: 1.hour.ago,
        metadata: {}
      )
    end

    it 'cannot access traces from another account' do
      get "/api/v1/ai/execution_traces/#{other_trace.id}", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'cannot access spans from another account trace' do
      get "/api/v1/ai/execution_traces/#{other_trace.id}/spans", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'cannot access timeline from another account trace' do
      get "/api/v1/ai/execution_traces/#{other_trace.id}/timeline", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
