# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::RalphLoops', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read_permission) { create(:user, account: account, permissions: ['ai.workflows.read']) }
  let(:user_with_create_permission) { create(:user, account: account, permissions: ['ai.workflows.read', 'ai.workflows.create']) }
  let(:user_with_update_permission) { create(:user, account: account, permissions: ['ai.workflows.read', 'ai.workflows.update']) }
  let(:user_with_delete_permission) { create(:user, account: account, permissions: ['ai.workflows.read', 'ai.workflows.delete']) }
  let(:user_with_execute_permission) { create(:user, account: account, permissions: ['ai.workflows.read', 'ai.workflows.execute']) }
  let(:user_with_all_permissions) do
    create(:user, account: account, permissions: [
      'ai.workflows.read', 'ai.workflows.create', 'ai.workflows.update',
      'ai.workflows.delete', 'ai.workflows.execute'
    ])
  end
  let(:regular_user) { create(:user, account: account, permissions: []) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, account: other_account, permissions: ['ai.workflows.read']) }

  # =============================================================================
  # INDEX
  # =============================================================================

  describe 'GET /api/v1/ai/ralph_loops' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create_list(:ai_ralph_loop, 3, account: account)
    end

    context 'with ai.workflows.read permission' do
      it 'returns list of ralph loops' do
        get '/api/v1/ai/ralph_loops', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['items']).to be_an(Array)
        expect(data['items'].length).to eq(3)
      end

      it 'includes pagination metadata' do
        get '/api/v1/ai/ralph_loops', headers: headers, as: :json

        data = json_response_data
        expect(data['pagination']).to include('current_page', 'total_count', 'total_pages')
      end

      it 'filters by status' do
        create(:ai_ralph_loop, :running, account: account)

        get '/api/v1/ai/ralph_loops?status=running', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        statuses = data['items'].map { |l| l['status'] }
        expect(statuses.uniq).to eq(['running'])
      end

      it 'filters by default_agent_id' do
        agent = create(:ai_agent, account: account)
        create(:ai_ralph_loop, account: account, default_agent: agent)

        get "/api/v1/ai/ralph_loops?default_agent_id=#{agent.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data

        agent_ids = data['items'].map { |l| l['default_agent_id'] }
        expect(agent_ids).to all(eq(agent.id))
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/ai/ralph_loops', headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/ai/ralph_loops', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  # =============================================================================
  # SHOW
  # =============================================================================

  describe 'GET /api/v1/ai/ralph_loops/:id' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:ralph_loop) { create(:ai_ralph_loop, account: account) }

    context 'with ai.workflows.read permission' do
      it 'returns ralph loop details' do
        get "/api/v1/ai/ralph_loops/#{ralph_loop.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['ralph_loop']).to include(
          'id' => ralph_loop.id,
          'name' => ralph_loop.name,
          'status' => ralph_loop.status
        )
      end

      it 'includes tasks and iterations in details' do
        get "/api/v1/ai/ralph_loops/#{ralph_loop.id}", headers: headers, as: :json

        data = json_response_data
        expect(data['ralph_loop']).to have_key('tasks')
        expect(data['ralph_loop']).to have_key('recent_iterations')
      end
    end

    context 'when ralph loop does not exist' do
      it 'returns not found error' do
        get "/api/v1/ai/ralph_loops/#{SecureRandom.uuid}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when accessing other account ralph loop' do
      let(:other_loop) { create(:ai_ralph_loop, account: other_account) }

      it 'returns not found error' do
        get "/api/v1/ai/ralph_loops/#{other_loop.id}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # =============================================================================
  # CREATE
  # =============================================================================

  describe 'POST /api/v1/ai/ralph_loops' do
    let(:headers) { auth_headers_for(user_with_create_permission) }

    context 'with ai.workflows.create permission' do
      let(:agent) { create(:ai_agent, account: account) }
      let(:valid_params) do
        {
          ralph_loop: {
            name: 'New Ralph Loop',
            description: 'A test Ralph loop',
            default_agent_id: agent.id,
            max_iterations: 10,
            branch: 'main'
          }
        }
      end

      it 'creates a new ralph loop' do
        expect {
          post '/api/v1/ai/ralph_loops', params: valid_params, headers: headers, as: :json
        }.to change { account.ai_ralph_loops.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['ralph_loop']['name']).to eq('New Ralph Loop')
      end

      it 'sets default status to pending' do
        post '/api/v1/ai/ralph_loops', params: valid_params, headers: headers, as: :json

        data = json_response_data
        expect(data['ralph_loop']['status']).to eq('pending')
      end
    end

    context 'with invalid data' do
      it 'returns validation error for blank name' do
        post '/api/v1/ai/ralph_loops',
             params: { ralph_loop: { name: '', max_iterations: 10 } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        post '/api/v1/ai/ralph_loops',
             params: { ralph_loop: { name: 'Test', max_iterations: 10 } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =============================================================================
  # UPDATE
  # =============================================================================

  describe 'PATCH /api/v1/ai/ralph_loops/:id' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:ralph_loop) { create(:ai_ralph_loop, account: account) }

    context 'with ai.workflows.update permission' do
      it 'updates the ralph loop' do
        patch "/api/v1/ai/ralph_loops/#{ralph_loop.id}",
              params: { ralph_loop: { description: 'Updated description' } },
              headers: headers,
              as: :json

        expect_success_response
        data = json_response_data
        expect(data['ralph_loop']['description']).to eq('Updated description')
      end

      it 'updates the name' do
        patch "/api/v1/ai/ralph_loops/#{ralph_loop.id}",
              params: { ralph_loop: { name: 'Updated Loop Name' } },
              headers: headers,
              as: :json

        expect_success_response

        ralph_loop.reload
        expect(ralph_loop.name).to eq('Updated Loop Name')
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        patch "/api/v1/ai/ralph_loops/#{ralph_loop.id}",
              params: { ralph_loop: { name: 'Update' } },
              headers: headers,
              as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =============================================================================
  # DELETE
  # =============================================================================

  describe 'DELETE /api/v1/ai/ralph_loops/:id' do
    let(:headers) { auth_headers_for(user_with_delete_permission) }

    context 'with ai.workflows.delete permission' do
      it 'deletes a pending ralph loop' do
        ralph_loop = create(:ai_ralph_loop, :pending, account: account)
        loop_id = ralph_loop.id

        delete "/api/v1/ai/ralph_loops/#{loop_id}", headers: headers, as: :json

        expect_success_response
        expect(Ai::RalphLoop.find_by(id: loop_id)).to be_nil
      end

      it 'deletes a completed ralph loop' do
        ralph_loop = create(:ai_ralph_loop, :completed, account: account)

        delete "/api/v1/ai/ralph_loops/#{ralph_loop.id}", headers: headers, as: :json

        expect_success_response
      end

      it 'rejects deletion of a running ralph loop' do
        ralph_loop = create(:ai_ralph_loop, :running, account: account)

        delete "/api/v1/ai/ralph_loops/#{ralph_loop.id}", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        ralph_loop = create(:ai_ralph_loop, account: account)

        delete "/api/v1/ai/ralph_loops/#{ralph_loop.id}", headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =============================================================================
  # EXECUTION CONTROL ACTIONS
  # =============================================================================

  describe 'POST /api/v1/ai/ralph_loops/:id/start' do
    let(:headers) { auth_headers_for(user_with_execute_permission) }
    let(:ralph_loop) { create(:ai_ralph_loop, :pending, account: account) }

    context 'with ai.workflows.execute permission' do
      it 'starts the ralph loop' do
        service_result = { success: true, ralph_loop: ralph_loop.loop_summary }
        allow_any_instance_of(Ai::Ralph::ExecutionService).to receive(:start_loop)
          .and_return(service_result)

        post "/api/v1/ai/ralph_loops/#{ralph_loop.id}/start", headers: headers, as: :json

        expect_success_response
      end

      it 'returns error on failure' do
        service_result = { success: false, error: 'Cannot start loop' }
        allow_any_instance_of(Ai::Ralph::ExecutionService).to receive(:start_loop)
          .and_return(service_result)

        post "/api/v1/ai/ralph_loops/#{ralph_loop.id}/start", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        post "/api/v1/ai/ralph_loops/#{ralph_loop.id}/start", headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/ai/ralph_loops/:id/pause' do
    let(:headers) { auth_headers_for(user_with_execute_permission) }
    let(:ralph_loop) { create(:ai_ralph_loop, :running, account: account) }

    context 'with ai.workflows.execute permission' do
      it 'pauses the ralph loop' do
        service_result = { success: true, ralph_loop: ralph_loop.loop_summary }
        allow_any_instance_of(Ai::Ralph::ExecutionService).to receive(:pause_loop)
          .and_return(service_result)

        post "/api/v1/ai/ralph_loops/#{ralph_loop.id}/pause", headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/ralph_loops/:id/resume' do
    let(:headers) { auth_headers_for(user_with_execute_permission) }
    let(:ralph_loop) { create(:ai_ralph_loop, :paused, account: account) }

    context 'with ai.workflows.execute permission' do
      it 'resumes the ralph loop' do
        service_result = { success: true, ralph_loop: ralph_loop.loop_summary }
        allow_any_instance_of(Ai::Ralph::ExecutionService).to receive(:resume_loop)
          .and_return(service_result)

        post "/api/v1/ai/ralph_loops/#{ralph_loop.id}/resume", headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/ralph_loops/:id/cancel' do
    let(:headers) { auth_headers_for(user_with_execute_permission) }
    let(:ralph_loop) { create(:ai_ralph_loop, :running, account: account) }

    context 'with ai.workflows.execute permission' do
      it 'cancels the ralph loop' do
        service_result = { success: true, ralph_loop: ralph_loop.loop_summary }
        allow_any_instance_of(Ai::Ralph::ExecutionService).to receive(:cancel_loop)
          .and_return(service_result)

        post "/api/v1/ai/ralph_loops/#{ralph_loop.id}/cancel",
             params: { reason: 'No longer needed' },
             headers: headers,
             as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/ralph_loops/:id/reset' do
    let(:headers) { auth_headers_for(user_with_execute_permission) }
    let(:ralph_loop) { create(:ai_ralph_loop, :completed, account: account) }

    context 'with ai.workflows.execute permission' do
      it 'resets the ralph loop' do
        post "/api/v1/ai/ralph_loops/#{ralph_loop.id}/reset", headers: headers, as: :json

        expect_success_response

        ralph_loop.reload
        expect(ralph_loop.status).to eq('pending')
        expect(ralph_loop.current_iteration).to eq(0)
      end

      it 'returns error for non-terminal loop' do
        running_loop = create(:ai_ralph_loop, :running, account: account)

        post "/api/v1/ai/ralph_loops/#{running_loop.id}/reset", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'POST /api/v1/ai/ralph_loops/:id/run_iteration' do
    let(:headers) { auth_headers_for(user_with_execute_permission) }
    let(:ralph_loop) { create(:ai_ralph_loop, :running, account: account) }

    context 'with ai.workflows.execute permission' do
      it 'runs a single iteration' do
        service_result = { success: true, iteration: { number: 1 } }
        allow_any_instance_of(Ai::Ralph::ExecutionService).to receive(:run_iteration)
          .and_return(service_result)

        post "/api/v1/ai/ralph_loops/#{ralph_loop.id}/run_iteration",
             headers: headers,
             as: :json

        expect_success_response
      end
    end
  end

  # =============================================================================
  # TASK MANAGEMENT
  # =============================================================================

  describe 'GET /api/v1/ai/ralph_loops/:id/tasks' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:ralph_loop) { create(:ai_ralph_loop, :with_tasks, account: account) }

    context 'with ai.workflows.read permission' do
      it 'returns tasks for the ralph loop' do
        get "/api/v1/ai/ralph_loops/#{ralph_loop.id}/tasks", headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['items']).to be_an(Array)
        expect(data['items'].length).to eq(3)
      end

      it 'includes pagination metadata' do
        get "/api/v1/ai/ralph_loops/#{ralph_loop.id}/tasks", headers: headers, as: :json

        data = json_response_data
        expect(data['pagination']).to include('current_page', 'total_count', 'total_pages')
      end

      it 'filters tasks by status' do
        ralph_loop.ralph_tasks.first.update!(status: 'passed')

        get "/api/v1/ai/ralph_loops/#{ralph_loop.id}/tasks?status=passed",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data

        statuses = data['items'].map { |t| t['status'] }
        expect(statuses.uniq).to eq(['passed'])
      end
    end
  end

  describe 'GET /api/v1/ai/ralph_loops/:id/tasks/:task_id' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:ralph_loop) { create(:ai_ralph_loop, :with_tasks, account: account) }
    let(:task) { ralph_loop.ralph_tasks.first }

    context 'with ai.workflows.read permission' do
      it 'returns task details by id' do
        get "/api/v1/ai/ralph_loops/#{ralph_loop.id}/tasks/#{task.id}",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data['task']).to be_present
      end

      it 'returns task details by task_key' do
        get "/api/v1/ai/ralph_loops/#{ralph_loop.id}/tasks/#{task.task_key}",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data['task']).to be_present
      end

      it 'returns not found for non-existent task' do
        get "/api/v1/ai/ralph_loops/#{ralph_loop.id}/tasks/nonexistent",
            headers: headers,
            as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # =============================================================================
  # ITERATION MANAGEMENT
  # =============================================================================

  describe 'GET /api/v1/ai/ralph_loops/:id/iterations' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:ralph_loop) { create(:ai_ralph_loop, account: account) }

    context 'with ai.workflows.read permission' do
      it 'returns iterations for the ralph loop' do
        get "/api/v1/ai/ralph_loops/#{ralph_loop.id}/iterations",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data

        expect(data['items']).to be_an(Array)
      end

      it 'includes pagination metadata' do
        get "/api/v1/ai/ralph_loops/#{ralph_loop.id}/iterations",
            headers: headers,
            as: :json

        data = json_response_data
        expect(data['pagination']).to include('current_page', 'total_count', 'total_pages')
      end
    end
  end

  # =============================================================================
  # PROGRESS AND LEARNINGS
  # =============================================================================

  describe 'GET /api/v1/ai/ralph_loops/:id/learnings' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:ralph_loop) { create(:ai_ralph_loop, :with_learnings, account: account) }

    context 'with ai.workflows.read permission' do
      it 'returns learnings' do
        allow_any_instance_of(Ai::Ralph::ExecutionService).to receive(:learnings)
          .and_return(learnings: ralph_loop.learnings)

        get "/api/v1/ai/ralph_loops/#{ralph_loop.id}/learnings",
            headers: headers,
            as: :json

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/ai/ralph_loops/:id/progress' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:ralph_loop) { create(:ai_ralph_loop, account: account) }

    context 'with ai.workflows.read permission' do
      it 'returns progress data' do
        allow_any_instance_of(Ai::Ralph::ExecutionService).to receive(:status)
          .and_return('pending')

        get "/api/v1/ai/ralph_loops/#{ralph_loop.id}/progress",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data

        expect(data).to have_key('loop_status')
        expect(data).to have_key('progress_percentage')
        expect(data).to have_key('learnings')
        expect(data).to have_key('recent_commits')
      end
    end
  end

  # =============================================================================
  # STATISTICS
  # =============================================================================

  describe 'GET /api/v1/ai/ralph_loops/statistics' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create_list(:ai_ralph_loop, 3, account: account)
    end

    context 'with ai.workflows.read permission' do
      it 'returns overall statistics' do
        get '/api/v1/ai/ralph_loops/statistics', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['statistics']).to include(
          'total_loops',
          'by_status',
          'by_agent',
          'total_iterations',
          'total_tasks'
        )
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/ai/ralph_loops/statistics', headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =============================================================================
  # SCHEDULING ACTIONS
  # =============================================================================

  describe 'POST /api/v1/ai/ralph_loops/:id/pause_schedule' do
    let(:headers) { auth_headers_for(user_with_execute_permission) }
    let(:ralph_loop) do
      create(:ai_ralph_loop, :scheduled, account: account,
             schedule_config: { 'cron_expression' => '0 * * * *', 'timezone' => 'UTC' })
    end

    context 'with ai.workflows.execute permission' do
      it 'pauses the schedule' do
        post "/api/v1/ai/ralph_loops/#{ralph_loop.id}/pause_schedule",
             params: { reason: 'Maintenance window' },
             headers: headers,
             as: :json

        expect_success_response

        ralph_loop.reload
        expect(ralph_loop.schedule_paused).to be true
      end
    end
  end

  describe 'POST /api/v1/ai/ralph_loops/:id/resume_schedule' do
    let(:headers) { auth_headers_for(user_with_execute_permission) }
    let(:ralph_loop) do
      create(:ai_ralph_loop, :scheduled, account: account,
             schedule_paused: true, schedule_paused_at: Time.current,
             schedule_config: { 'cron_expression' => '0 * * * *', 'timezone' => 'UTC' })
    end

    context 'with ai.workflows.execute permission' do
      it 'resumes the schedule' do
        post "/api/v1/ai/ralph_loops/#{ralph_loop.id}/resume_schedule",
             headers: headers,
             as: :json

        expect_success_response

        ralph_loop.reload
        expect(ralph_loop.schedule_paused).to be false
      end
    end
  end

  describe 'POST /api/v1/ai/ralph_loops/:id/regenerate_webhook_token' do
    let(:headers) { auth_headers_for(user_with_execute_permission) }
    let(:ralph_loop) do
      create(:ai_ralph_loop, account: account,
             scheduling_mode: 'event_triggered',
             webhook_token: SecureRandom.urlsafe_base64(32))
    end

    context 'with ai.workflows.execute permission' do
      it 'regenerates the webhook token' do
        old_token = ralph_loop.webhook_token

        post "/api/v1/ai/ralph_loops/#{ralph_loop.id}/regenerate_webhook_token",
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data

        expect(data['webhook_token']).to be_present
        expect(data['webhook_token']).not_to eq(old_token)
      end
    end

    context 'when loop is not event-triggered' do
      let(:manual_loop) { create(:ai_ralph_loop, account: account, scheduling_mode: 'manual') }

      it 'returns error' do
        post "/api/v1/ai/ralph_loops/#{manual_loop.id}/regenerate_webhook_token",
             headers: headers,
             as: :json

        expect(response.status).to be >= 400
      end
    end
  end

  # =============================================================================
  # ACCOUNT ISOLATION
  # =============================================================================

  describe 'account isolation' do
    let(:headers) { auth_headers_for(user_with_all_permissions) }
    let(:other_loop) { create(:ai_ralph_loop, account: other_account) }

    it 'cannot access ralph loops from another account via show' do
      get "/api/v1/ai/ralph_loops/#{other_loop.id}", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'cannot update ralph loops from another account' do
      patch "/api/v1/ai/ralph_loops/#{other_loop.id}",
            params: { ralph_loop: { name: 'Hack' } },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'cannot delete ralph loops from another account' do
      delete "/api/v1/ai/ralph_loops/#{other_loop.id}", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'cannot start ralph loops from another account' do
      post "/api/v1/ai/ralph_loops/#{other_loop.id}/start", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
