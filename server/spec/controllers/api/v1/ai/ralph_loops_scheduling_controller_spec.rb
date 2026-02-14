# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::RalphLoopsSchedulingController", type: :request do
  let(:account) { create(:account) }
  let(:execute_user) { user_with_permissions('ai.workflows.execute', account: account) }
  let(:create_user) { user_with_permissions('ai.workflows.create', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  let!(:ralph_loop) { create(:ai_ralph_loop, :scheduled, account: account) }
  let(:base_path) { "/api/v1/ai/ralph_loops/#{ralph_loop.id}" }

  # Service mock
  let(:mock_execution_service) { instance_double(::Ai::Ralph::ExecutionService) }

  before do
    allow(::Ai::Ralph::ExecutionService).to receive(:new).and_return(mock_execution_service)
    allow(Audit::LoggingService).to receive_message_chain(:instance, :log)
  end

  # =========================================================================
  # RUN ITERATION (ai.workflows.execute)
  # =========================================================================
  describe "POST /api/v1/ai/ralph_loops/:id/run_iteration" do
    let(:path) { "#{base_path}/run_iteration" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.execute permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.workflows.execute permission' do
      allow(mock_execution_service).to receive(:run_iteration).and_return({
        success: true, iteration: 1, status: "completed"
      })

      post path, headers: auth_headers_for(execute_user)
      expect(response).to have_http_status(:success)
    end

    it 'returns 404 when ralph loop not found' do
      post "/api/v1/ai/ralph_loops/#{SecureRandom.uuid}/run_iteration",
           headers: auth_headers_for(execute_user)
      expect(response).to have_http_status(:not_found)
    end
  end

  # =========================================================================
  # RUN ALL (ai.workflows.execute)
  # =========================================================================
  describe "POST /api/v1/ai/ralph_loops/:id/run_all" do
    let(:path) { "#{base_path}/run_all" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.execute permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has permission' do
      allow(mock_execution_service).to receive(:run_all).and_return({
        success: true, iterations_completed: 5
      })

      post path, headers: auth_headers_for(execute_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # STOP RUN ALL (ai.workflows.execute)
  # =========================================================================
  describe "POST /api/v1/ai/ralph_loops/:id/stop_run_all" do
    let(:path) { "#{base_path}/stop_run_all" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has permission' do
      allow(mock_execution_service).to receive(:stop_run_all).and_return({ success: true })

      post path, headers: auth_headers_for(execute_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # PAUSE SCHEDULE (ai.workflows.execute)
  # =========================================================================
  describe "POST /api/v1/ai/ralph_loops/:id/pause_schedule" do
    let(:path) { "#{base_path}/pause_schedule" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when loop is schedulable and not paused' do
      allow(ralph_loop).to receive(:schedulable?).and_return(true)
      allow(ralph_loop).to receive(:schedule_paused?).and_return(false)

      post path, headers: auth_headers_for(execute_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # RESUME SCHEDULE (ai.workflows.execute)
  # =========================================================================
  describe "POST /api/v1/ai/ralph_loops/:id/resume_schedule" do
    let(:path) { "#{base_path}/resume_schedule" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns error when schedule is not paused' do
      post path, headers: auth_headers_for(execute_user)
      expect(response).to have_http_status(:bad_request)
    end
  end

  # =========================================================================
  # REGENERATE WEBHOOK TOKEN (ai.workflows.execute)
  # =========================================================================
  describe "POST /api/v1/ai/ralph_loops/:id/regenerate_webhook_token" do
    let(:path) { "#{base_path}/regenerate_webhook_token" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns error when loop is not event-triggered' do
      post path, headers: auth_headers_for(execute_user)
      expect(response).to have_http_status(:bad_request)
    end
  end

  # =========================================================================
  # PARSE PRD (ai.workflows.create)
  # =========================================================================
  describe "POST /api/v1/ai/ralph_loops/:id/parse_prd" do
    let(:path) { "#{base_path}/parse_prd" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.create permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 400 when prd data is missing' do
      post path, headers: auth_headers_for(create_user)
      expect(response).to have_http_status(:bad_request)
    end

    it 'returns success when prd data is provided' do
      allow(mock_execution_service).to receive(:parse_prd).and_return({
        success: true, tasks: []
      })

      post path, params: { prd: { title: "Test PRD", description: "A test" } },
                 headers: auth_headers_for(create_user),
                 as: :json
      expect(response).to have_http_status(:success)
    end
  end
end
