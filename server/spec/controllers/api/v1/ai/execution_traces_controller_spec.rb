# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::ExecutionTracesController", type: :request do
  let(:account) { create(:account) }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai_monitoring.read', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let!(:trace) { create(:ai_execution_trace, :completed, account: account) }

  # =========================================================================
  # INDEX (ai_monitoring.read)
  # =========================================================================
  describe "GET /api/v1/ai/execution_traces" do
    let(:path) { "/api/v1/ai/execution_traces" }

    before do
      allow(Ai::TracingService).to receive(:list_traces).and_return([
        {
          trace_id: trace.trace_id,
          name: trace.name,
          type: trace.trace_type,
          status: trace.status,
          started_at: trace.started_at,
          completed_at: trace.completed_at,
          duration_ms: trace.duration_ms
        }
      ])
    end

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai_monitoring.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns list of traces' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      # render_success(data: traces) wraps traces array directly in data
      expect(json_response['data']).to be_an(Array)
    end

    it 'accepts filter parameters' do
      get path, params: { type: 'workflow', status: 'completed', limit: 10 }, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # SHOW (ai_monitoring.read)
  # =========================================================================
  describe "GET /api/v1/ai/execution_traces/:id" do
    before do
      allow(Ai::TracingService).to receive(:get_trace).and_return({
        trace_id: trace.trace_id,
        name: trace.name,
        type: trace.trace_type,
        status: trace.status,
        spans: []
      })
    end

    it 'returns 401 when unauthenticated' do
      get "/api/v1/ai/execution_traces/#{trace.id}", headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get "/api/v1/ai/execution_traces/#{trace.id}", headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns trace details' do
      get "/api/v1/ai/execution_traces/#{trace.id}", headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      expect(json_response['data']).to be_present
      expect(json_response['data']['trace_id']).to eq(trace.trace_id)
    end
  end

  # =========================================================================
  # SPANS (ai_monitoring.read)
  # =========================================================================
  describe "GET /api/v1/ai/execution_traces/:id/spans" do
    it 'returns 401 when unauthenticated' do
      get "/api/v1/ai/execution_traces/#{trace.id}/spans", headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get "/api/v1/ai/execution_traces/#{trace.id}/spans", headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns spans for a trace' do
      get "/api/v1/ai/execution_traces/#{trace.id}/spans", headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      data = json_response['data']
      expect(data['trace_id']).to eq(trace.trace_id)
      expect(data['spans']).to be_an(Array)
      expect(data['summary']).to include('total', 'by_type', 'by_status')
    end
  end

  # =========================================================================
  # TIMELINE (ai_monitoring.read)
  # =========================================================================
  describe "GET /api/v1/ai/execution_traces/:id/timeline" do
    it 'returns 401 when unauthenticated' do
      get "/api/v1/ai/execution_traces/#{trace.id}/timeline", headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get "/api/v1/ai/execution_traces/#{trace.id}/timeline", headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns timeline data for a trace' do
      get "/api/v1/ai/execution_traces/#{trace.id}/timeline", headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      data = json_response['data']
      expect(data['trace_id']).to eq(trace.trace_id)
      expect(data).to include('name', 'type', 'status', 'duration_ms')
      expect(data['summary']).to include('total_tokens', 'total_cost', 'success_rate')
    end
  end

  # =========================================================================
  # SUMMARY (ai_monitoring.read)
  # =========================================================================
  describe "GET /api/v1/ai/execution_traces/summary" do
    let(:path) { "/api/v1/ai/execution_traces/summary" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns summary statistics' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be true
      data = json_response['data']
      expect(data).to include('total_traces', 'by_status', 'by_type', 'time_range')
    end

    it 'accepts time_range parameter' do
      get path, params: { time_range: '7d' }, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['data']['time_range']).to eq('7d')
    end
  end
end
