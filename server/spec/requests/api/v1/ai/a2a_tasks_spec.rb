# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::A2aTasks', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read_permission) { create(:user, account: account, permissions: ['ai.agents.read']) }
  let(:user_with_execute_permission) { create(:user, account: account, permissions: ['ai.agents.read', 'ai.agents.execute']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/ai/a2a/tasks' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create_list(:ai_a2a_task, 3, account: account)
    end

    context 'with ai.agents.read permission' do
      it 'returns list of tasks' do
        get '/api/v1/ai/a2a/tasks', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['items']).to be_an(Array)
        expect(data['items'].length).to eq(3)
      end

      it 'includes task summary' do
        get '/api/v1/ai/a2a/tasks', headers: headers, as: :json

        data = json_response_data
        first_task = data['items'].first

        expect(first_task).to include('task_id', 'status')
      end

      it 'includes pagination metadata' do
        get '/api/v1/ai/a2a/tasks', headers: headers, as: :json

        data = json_response_data
        expect(data['pagination']).to include('current_page', 'total_count', 'total_pages')
      end

      it 'filters by status' do
        create(:ai_a2a_task, :completed, account: account)

        get '/api/v1/ai/a2a/tasks?status=completed',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data

        statuses = data['items'].map { |t| t['status'] }
        expect(statuses.uniq).to eq(['completed'])
      end

      it 'filters by from_agent_id' do
        agent = create(:ai_agent, account: account)
        create(:ai_a2a_task, from_agent: agent, account: account)

        get "/api/v1/ai/a2a/tasks?from_agent_id=#{agent.id}",
            headers: headers,
            as: :json

        expect_success_response
      end

      it 'filters by to_agent_id' do
        agent = create(:ai_agent, account: account)
        create(:ai_a2a_task, to_agent: agent, account: account)

        get "/api/v1/ai/a2a/tasks?to_agent_id=#{agent.id}",
            headers: headers,
            as: :json

        expect_success_response
      end

      it 'filters by workflow_run_id' do
        workflow_run = create(:ai_workflow_run, account: account)
        create(:ai_a2a_task, :with_workflow_run, workflow_run: workflow_run, account: account)

        get "/api/v1/ai/a2a/tasks?workflow_run_id=#{workflow_run.id}",
            headers: headers,
            as: :json

        expect_success_response
      end

      it 'filters by since timestamp' do
        old_task = create(:ai_a2a_task, account: account, created_at: 2.days.ago)
        create(:ai_a2a_task, account: account, created_at: 1.hour.ago)

        get "/api/v1/ai/a2a/tasks?since=#{1.day.ago.iso8601}",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data

        task_ids = data['items'].map { |t| t['id'] }
        expect(task_ids).not_to include(old_task.id)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/ai/a2a/tasks', headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/ai/a2a/tasks/:task_id' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:task) { create(:ai_a2a_task, account: account) }

    it 'returns task in A2A JSON format' do
      get "/api/v1/ai/a2a/tasks/#{task.task_id}", headers: headers, as: :json

      expect_success_response
      data = json_response_data

      expect(data['task']).to include('id', 'status')
      expect(data['task']['id']).to eq(task.task_id)
    end

    it 'returns 404 for non-existent task' do
      get '/api/v1/ai/a2a/tasks/non-existent-id', headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v1/ai/a2a/tasks/:task_id/details' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:task) { create(:ai_a2a_task, :with_artifacts, account: account) }

    it 'returns detailed task information' do
      get "/api/v1/ai/a2a/tasks/#{task.task_id}/details", headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'POST /api/v1/ai/a2a/tasks' do
    let(:headers) { auth_headers_for(user_with_execute_permission) }
    let(:from_agent) { create(:ai_agent, account: account) }
    let(:to_agent_card) { create(:ai_agent_card, :published, account: account) }
    let(:valid_params) do
      {
        to_agent_card_id: to_agent_card.id,
        from_agent_id: from_agent.id,
        text: 'Hello, please process this task',
        metadata: { 'priority' => 'high' }
      }
    end

    context 'with valid params' do
      it 'creates a new A2A task' do
        expect {
          post '/api/v1/ai/a2a/tasks', headers: headers, params: valid_params, as: :json
        }.to change { Ai::A2aTask.count }.by(1)

        expect(response).to have_http_status(:created)
      end

      it 'returns the created task' do
        post '/api/v1/ai/a2a/tasks', headers: headers, params: valid_params, as: :json

        data = json_response_data
        expect(data['task']).to be_present
      end
    end

    context 'with structured message' do
      it 'accepts A2A message format' do
        params = {
          to_agent_card_id: to_agent_card.id,
          message: {
            role: 'user',
            parts: [{ type: 'text', text: 'Process this' }]
          }
        }

        post '/api/v1/ai/a2a/tasks', headers: headers, params: params, as: :json

        expect(response).to have_http_status(:created)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        post '/api/v1/ai/a2a/tasks', headers: headers, params: valid_params, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/ai/a2a/tasks/:task_id/cancel' do
    let(:headers) { auth_headers_for(user_with_execute_permission) }
    let(:task) { create(:ai_a2a_task, :active, account: account) }

    it 'cancels the task' do
      post "/api/v1/ai/a2a/tasks/#{task.task_id}/cancel",
           headers: headers,
           params: { reason: 'User requested cancellation' },
           as: :json

      expect_success_response
      expect(task.reload.status).to eq('cancelled')
    end

    it 'stores cancellation reason' do
      post "/api/v1/ai/a2a/tasks/#{task.task_id}/cancel",
           headers: headers,
           params: { reason: 'Timeout' },
           as: :json

      expect(task.reload.error_message).to eq('Timeout')
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        post "/api/v1/ai/a2a/tasks/#{task.task_id}/cancel", headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/ai/a2a/tasks/:task_id/input' do
    let(:headers) { auth_headers_for(user_with_execute_permission) }
    let(:task) { create(:ai_a2a_task, :input_required, account: account) }

    it 'provides input to waiting task' do
      post "/api/v1/ai/a2a/tasks/#{task.task_id}/input",
           headers: headers,
           params: { input: { 'additional_data' => 'value' } },
           as: :json

      expect_success_response
      expect(task.reload.status).to eq('active')
    end

    context 'for task not waiting for input' do
      let(:active_task) { create(:ai_a2a_task, :active, account: account) }

      it 'returns error' do
        post "/api/v1/ai/a2a/tasks/#{active_task.task_id}/input",
             headers: headers,
             params: { input: {} },
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'GET /api/v1/ai/a2a/tasks/:task_id/events/poll' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:task) { create(:ai_a2a_task, account: account) }

    before do
      create_list(:ai_a2a_task_event, 5, a2a_task: task)
    end

    it 'returns task events' do
      get "/api/v1/ai/a2a/tasks/#{task.task_id}/events/poll", headers: headers, as: :json

      expect_success_response
      data = json_response_data

      expect(data['events']).to be_an(Array)
    end

    it 'filters by since timestamp' do
      old_event = create(:ai_a2a_task_event, a2a_task: task, created_at: 1.hour.ago)
      create(:ai_a2a_task_event, a2a_task: task, created_at: 1.minute.ago)

      get "/api/v1/ai/a2a/tasks/#{task.task_id}/events/poll?since=#{30.minutes.ago.iso8601}",
          headers: headers,
          as: :json

      expect_success_response
      data = json_response_data

      event_ids = data['events'].map { |e| e['id'] }
      expect(event_ids).not_to include(old_event.id)
    end

    it 'limits results' do
      get "/api/v1/ai/a2a/tasks/#{task.task_id}/events/poll?limit=3",
          headers: headers,
          as: :json

      expect_success_response
      data = json_response_data

      expect(data['events'].length).to be <= 3
    end
  end

  describe 'GET /api/v1/ai/a2a/tasks/:task_id/artifacts' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:task) { create(:ai_a2a_task, :with_artifacts, account: account) }

    it 'returns task artifacts' do
      get "/api/v1/ai/a2a/tasks/#{task.task_id}/artifacts", headers: headers, as: :json

      expect_success_response
      data = json_response_data

      expect(data['artifacts']).to be_an(Array)
    end
  end

  describe 'GET /api/v1/ai/a2a/tasks/:task_id/artifacts/:artifact_id' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:task) { create(:ai_a2a_task, :with_artifacts, account: account) }

    it 'returns specific artifact' do
      artifact_id = task.artifacts.first['artifact_id']

      get "/api/v1/ai/a2a/tasks/#{task.task_id}/artifacts/#{artifact_id}",
          headers: headers,
          as: :json

      expect_success_response
    end

    it 'returns 404 for non-existent artifact' do
      get "/api/v1/ai/a2a/tasks/#{task.task_id}/artifacts/non-existent",
          headers: headers,
          as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
