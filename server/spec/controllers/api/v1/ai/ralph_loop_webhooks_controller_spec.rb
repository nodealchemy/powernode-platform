# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::RalphLoopWebhooksController", type: :request do
  let(:account) { create(:account) }

  # Ralph loop with webhook token for event-triggered mode
  let(:webhook_token) { SecureRandom.urlsafe_base64(32) }
  let(:ralph_loop) do
    create(:ai_ralph_loop, :running,
      account: account,
      scheduling_mode: "event_triggered",
      webhook_token: webhook_token,
      schedule_config: {
        "max_iterations_per_day" => 100,
        "start_at" => 1.day.ago.iso8601,
        "end_at" => 1.day.from_now.iso8601
      }
    )
  end

  let(:trigger_path) { "/api/v1/ai/ralph_loops/webhook/#{webhook_token}" }
  let(:status_path) { "/api/v1/ai/ralph_loops/webhook/#{webhook_token}/status" }

  # Service double
  let(:execution_service) { instance_double(Ai::Ralph::ExecutionService) }

  before do
    allow(Ai::Ralph::ExecutionService).to receive(:new).and_return(execution_service)
    # Prevent actual AuditLog creation in tests
    allow(AuditLog).to receive(:create)
  end

  # =========================================================================
  # TRIGGER (webhook token auth, no standard auth)
  # =========================================================================
  describe "POST /api/v1/ai/ralph_loops/webhook/:token" do
    it 'returns 401 with invalid token' do
      post "/api/v1/ai/ralph_loops/webhook/invalid_token", headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
      expect(json_response['error']).to include('Invalid webhook token')
    end

    it 'triggers execution for running event-triggered loop' do
      ralph_loop # ensure created in DB before request
      allow(execution_service).to receive(:run_iteration).and_return({ success: true, iteration: 1 })
      allow_any_instance_of(Ai::RalphLoop).to receive(:increment_daily_iteration_count!)

      post trigger_path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:success)
      expect(json_response['data']['loop_id']).to eq(ralph_loop.id)
      expect(json_response['data']['triggered_at']).to be_present
    end

    it 'starts a pending loop on trigger' do
      ralph_loop.update_columns(status: 'pending', started_at: nil)
      allow(execution_service).to receive(:start_loop).and_return({ success: true })
      allow_any_instance_of(Ai::RalphLoop).to receive(:increment_daily_iteration_count!)

      post trigger_path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:success)
    end

    it 'resumes a paused loop on trigger' do
      ralph_loop.update_columns(status: 'paused')
      allow(execution_service).to receive(:resume_loop).and_return({ success: true })
      allow_any_instance_of(Ai::RalphLoop).to receive(:increment_daily_iteration_count!)

      post trigger_path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:success)
    end

    it 'returns error when loop is not event-triggered' do
      ralph_loop.update_columns(scheduling_mode: 'manual')
      post trigger_path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response['error']).to include('not event-triggered')
    end

    it 'returns error when schedule is paused' do
      ralph_loop.update_columns(schedule_paused: true, schedule_paused_reason: "Maintenance")
      post trigger_path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response['error']).to include('paused')
    end

    it 'returns error when loop is in terminal state' do
      ralph_loop.update_columns(status: 'completed', completed_at: Time.current)
      post trigger_path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response['error']).to include('terminal state')
    end

    it 'returns error when execution fails' do
      ralph_loop # ensure created in DB before request
      allow(execution_service).to receive(:run_iteration).and_return({ success: false, error: "Execution error" })

      post trigger_path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response['error']).to include('Execution error')
    end
  end

  # =========================================================================
  # STATUS (webhook token auth, no standard auth)
  # =========================================================================
  describe "GET /api/v1/ai/ralph_loops/webhook/:token/status" do
    it 'returns 401 with invalid token' do
      get "/api/v1/ai/ralph_loops/webhook/invalid_token/status", headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns loop status information' do
      ralph_loop # create
      get status_path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:success)
      expect(json_response['data']['loop_id']).to eq(ralph_loop.id)
      expect(json_response['data']['status']).to eq('running')
      expect(json_response['data']['scheduling_mode']).to eq('event_triggered')
    end
  end
end
