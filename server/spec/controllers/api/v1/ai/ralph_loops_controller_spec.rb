# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::RalphLoopsController", type: :request do
  let(:account) { create(:account) }
  let(:base_path) { "/api/v1/ai/ralph_loops" }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai.workflows.read', account: account) }
  let(:create_user) { user_with_permissions('ai.workflows.create', account: account) }
  let(:update_user) { user_with_permissions('ai.workflows.update', account: account) }
  let(:delete_user) { user_with_permissions('ai.workflows.delete', account: account) }
  let(:execute_user) { user_with_permissions('ai.workflows.execute', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let(:ralph_loop) { create(:ai_ralph_loop, account: account) }
  let(:completed_loop) { create(:ai_ralph_loop, :completed, account: account) }

  # =========================================================================
  # INDEX (ai.workflows.read)
  # =========================================================================
  describe "GET /api/v1/ai/ralph_loops" do
    let(:path) { base_path }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.workflows.read permission' do
      ralph_loop # create
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # SHOW (ai.workflows.read)
  # =========================================================================
  describe "GET /api/v1/ai/ralph_loops/:id" do
    let(:path) { "#{base_path}/#{ralph_loop.id}" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.workflows.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # CREATE (ai.workflows.create)
  # =========================================================================
  describe "POST /api/v1/ai/ralph_loops" do
    let(:path) { base_path }
    let(:agent) { create(:ai_agent, account: account) }
    let(:valid_params) do
      {
        ralph_loop: {
          name: "Test Loop",
          description: "A test Ralph loop",
          default_agent_id: agent.id,
          max_iterations: 5,
          branch: "main"
        }
      }
    end

    it 'returns 401 when unauthenticated' do
      post path, params: valid_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.create permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'creates a ralph loop when user has ai.workflows.create permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(create_user)
      expect(response).to have_http_status(:created)
    end
  end

  # =========================================================================
  # UPDATE (ai.workflows.update)
  # =========================================================================
  describe "PATCH /api/v1/ai/ralph_loops/:id" do
    let(:path) { "#{base_path}/#{ralph_loop.id}" }
    let(:update_params) { { ralph_loop: { name: "Updated Loop Name" } } }

    it 'returns 401 when unauthenticated' do
      patch path, params: update_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.update permission' do
      patch path, params: update_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'updates the ralph loop when user has ai.workflows.update permission' do
      patch path, params: update_params.to_json, headers: auth_headers_for(update_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # DESTROY (ai.workflows.delete)
  # =========================================================================
  describe "DELETE /api/v1/ai/ralph_loops/:id" do
    let(:path) { "#{base_path}/#{ralph_loop.id}" }

    it 'returns 401 when unauthenticated' do
      delete path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.delete permission' do
      delete path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'deletes a pending ralph loop when user has ai.workflows.delete permission' do
      delete path, headers: auth_headers_for(delete_user)
      expect(response).to have_http_status(:success)
    end

    it 'rejects deletion of a running ralph loop' do
      running_loop = create(:ai_ralph_loop, :running, account: account)
      delete "#{base_path}/#{running_loop.id}", headers: auth_headers_for(delete_user)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # =========================================================================
  # START (ai.workflows.execute)
  # =========================================================================
  describe "POST /api/v1/ai/ralph_loops/:id/start" do
    let(:path) { "#{base_path}/#{ralph_loop.id}/start" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.execute permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.workflows.execute permission' do
      service = instance_double(::Ai::Ralph::ExecutionService)
      allow(::Ai::Ralph::ExecutionService).to receive(:new).and_return(service)
      allow(service).to receive(:start_loop).and_return({ success: true, ralph_loop: ralph_loop.loop_summary })

      post path, headers: auth_headers_for(execute_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # PAUSE (ai.workflows.execute)
  # =========================================================================
  describe "POST /api/v1/ai/ralph_loops/:id/pause" do
    let(:running_loop) { create(:ai_ralph_loop, :running, account: account) }
    let(:path) { "#{base_path}/#{running_loop.id}/pause" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.execute permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.workflows.execute permission' do
      service = instance_double(::Ai::Ralph::ExecutionService)
      allow(::Ai::Ralph::ExecutionService).to receive(:new).and_return(service)
      allow(service).to receive(:pause_loop).and_return({ success: true })

      post path, headers: auth_headers_for(execute_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # CANCEL (ai.workflows.execute)
  # =========================================================================
  describe "POST /api/v1/ai/ralph_loops/:id/cancel" do
    let(:running_loop) { create(:ai_ralph_loop, :running, account: account) }
    let(:path) { "#{base_path}/#{running_loop.id}/cancel" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.execute permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.workflows.execute permission' do
      service = instance_double(::Ai::Ralph::ExecutionService)
      allow(::Ai::Ralph::ExecutionService).to receive(:new).and_return(service)
      allow(service).to receive(:cancel_loop).and_return({ success: true })

      post path, headers: auth_headers_for(execute_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # TASKS (ai.workflows.read)
  # =========================================================================
  describe "GET /api/v1/ai/ralph_loops/:id/tasks" do
    let(:path) { "#{base_path}/#{ralph_loop.id}/tasks" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.workflows.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # ITERATIONS (ai.workflows.read)
  # =========================================================================
  describe "GET /api/v1/ai/ralph_loops/:id/iterations" do
    let(:path) { "#{base_path}/#{ralph_loop.id}/iterations" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.workflows.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # STATISTICS (ai.workflows.read)
  # =========================================================================
  describe "GET /api/v1/ai/ralph_loops/statistics" do
    let(:path) { "#{base_path}/statistics" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.workflows.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # LEARNINGS (ai.workflows.read)
  # =========================================================================
  describe "GET /api/v1/ai/ralph_loops/:id/learnings" do
    let(:path) { "#{base_path}/#{ralph_loop.id}/learnings" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.workflows.read permission' do
      service = instance_double(::Ai::Ralph::ExecutionService)
      allow(::Ai::Ralph::ExecutionService).to receive(:new).and_return(service)
      allow(service).to receive(:learnings).and_return({ learnings: [] })

      get path, headers: auth_headers_for(read_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # PROGRESS (ai.workflows.read)
  # =========================================================================
  describe "GET /api/v1/ai/ralph_loops/:id/progress" do
    let(:path) { "#{base_path}/#{ralph_loop.id}/progress" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.workflows.read permission' do
      service = instance_double(::Ai::Ralph::ExecutionService)
      allow(::Ai::Ralph::ExecutionService).to receive(:new).and_return(service)
      allow(service).to receive(:status).and_return({ status: "pending" })

      get path, headers: auth_headers_for(read_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end
end
