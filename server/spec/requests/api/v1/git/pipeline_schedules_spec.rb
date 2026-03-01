# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Git::PipelineSchedules', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'git.schedules.read', 'git.schedules.manage' ]) }
  let(:read_only_user) { create(:user, account: account, permissions: [ 'git.schedules.read' ]) }
  let(:no_permission_user) { create(:user, account: account, permissions: []) }
  let(:other_account) { create(:account) }

  let(:headers) { auth_headers_for(user) }
  let(:read_only_headers) { auth_headers_for(read_only_user) }
  let(:no_permission_headers) { auth_headers_for(no_permission_user) }

  let(:repository) { create(:devops_git_repository, account: account) }
  let(:other_repository) { create(:devops_git_repository, account: other_account) }

  describe 'GET /api/v1/git/repositories/:repository_id/schedules' do
    let!(:schedule1) { create(:devops_git_pipeline_schedule, repository: repository, account: account, is_active: true) }
    let!(:schedule2) { create(:devops_git_pipeline_schedule, repository: repository, account: account, is_active: false) }

    context 'with proper permissions' do
      it 'returns list of pipeline schedules for repository' do
        get "/api/v1/git/repositories/#{repository.id}/schedules", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['schedules']).to be_an(Array)
        expect(data['schedules'].length).to eq(2)
        expect(data['pagination']).to include('current_page', 'per_page', 'total_count', 'total_pages')
      end

      it 'filters by active status' do
        get "/api/v1/git/repositories/#{repository.id}/schedules", params: { active: 'true' }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['schedules'].length).to eq(1)
        expect(data['schedules'].first['is_active']).to be true
      end

      it 'supports pagination' do
        get "/api/v1/git/repositories/#{repository.id}/schedules", params: { page: 1, per_page: 1 }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['schedules'].length).to eq(1)
        expect(data['pagination']['per_page']).to eq(1)
      end

      it 'sorts by name' do
        get "/api/v1/git/repositories/#{repository.id}/schedules", params: { sort: 'name', direction: 'asc' }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['schedules']).to be_an(Array)
      end
    end

    context 'with repository from different account' do
      it 'returns not found error' do
        get "/api/v1/git/repositories/#{other_repository.id}/schedules", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without git.schedules.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/git/repositories/#{repository.id}/schedules", headers: no_permission_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/git/repositories/#{repository.id}/schedules", as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/git/pipeline_schedules/:id' do
    let(:schedule) { create(:devops_git_pipeline_schedule, repository: repository, account: account) }
    let(:other_schedule) { create(:devops_git_pipeline_schedule, repository: other_repository, account: other_account) }

    context 'with proper permissions' do
      it 'returns schedule details' do
        get "/api/v1/git/pipeline_schedules/#{schedule.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['schedule']).to include(
          'id' => schedule.id,
          'name' => schedule.name,
          'cron_expression' => schedule.cron_expression
        )
      end

      it 'returns not found for non-existent schedule' do
        get "/api/v1/git/pipeline_schedules/#{SecureRandom.uuid}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'accessing schedule from different account' do
      it 'returns not found error' do
        get "/api/v1/git/pipeline_schedules/#{other_schedule.id}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without git.schedules.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/git/pipeline_schedules/#{schedule.id}", headers: no_permission_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/git/repositories/:repository_id/schedules' do
    let(:valid_params) do
      {
        schedule: {
          name: 'Daily Build',
          description: 'Run daily build',
          cron_expression: '0 0 * * *',
          timezone: 'UTC',
          ref: 'main',
          workflow_file: '.github/workflows/build.yml',
          is_active: true
        }
      }
    end

    context 'with proper permissions' do
      it 'creates a new pipeline schedule' do
        expect {
          post "/api/v1/git/repositories/#{repository.id}/schedules",
               params: valid_params,
               headers: headers,
               as: :json
        }.to change { repository.git_pipeline_schedules.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['schedule']).to include(
          'name' => 'Daily Build',
          'cron_expression' => '0 0 * * *'
        )
      end

      it 'returns validation errors for invalid params' do
        invalid_params = valid_params.deep_merge(schedule: { name: nil })

        post "/api/v1/git/repositories/#{repository.id}/schedules",
             params: invalid_params,
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
      end
    end

    context 'without git.schedules.manage permission' do
      it 'returns forbidden error' do
        post "/api/v1/git/repositories/#{repository.id}/schedules",
             params: valid_params,
             headers: read_only_headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PUT /api/v1/git/pipeline_schedules/:id' do
    let(:schedule) { create(:devops_git_pipeline_schedule, repository: repository, account: account) }
    let(:update_params) do
      {
        schedule: {
          name: 'Updated Schedule',
          description: 'Updated description'
        }
      }
    end

    context 'with proper permissions' do
      it 'updates the pipeline schedule' do
        put "/api/v1/git/pipeline_schedules/#{schedule.id}",
            params: update_params,
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data['schedule']['name']).to eq('Updated Schedule')
        expect(data['schedule']['description']).to eq('Updated description')
      end

      it 'returns validation errors for invalid update' do
        invalid_params = { schedule: { cron_expression: 'invalid' } }

        put "/api/v1/git/pipeline_schedules/#{schedule.id}",
            params: invalid_params,
            headers: headers,
            as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without git.schedules.manage permission' do
      it 'returns forbidden error' do
        put "/api/v1/git/pipeline_schedules/#{schedule.id}",
            params: update_params,
            headers: read_only_headers,
            as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'DELETE /api/v1/git/pipeline_schedules/:id' do
    let!(:schedule) { create(:devops_git_pipeline_schedule, repository: repository, account: account) }

    context 'with proper permissions' do
      it 'deletes the pipeline schedule' do
        expect {
          delete "/api/v1/git/pipeline_schedules/#{schedule.id}", headers: headers, as: :json
        }.to change { Devops::GitPipelineSchedule.count }.by(-1)

        expect_success_response
        expect(json_response_data['message']).to eq('Schedule deleted successfully')
      end
    end

    context 'without git.schedules.manage permission' do
      it 'returns forbidden error' do
        delete "/api/v1/git/pipeline_schedules/#{schedule.id}", headers: read_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/git/pipeline_schedules/:id/trigger' do
    let(:schedule) { create(:devops_git_pipeline_schedule, repository: repository, account: account) }

    context 'with proper permissions' do
      before do
        allow_any_instance_of(Devops::GitProviderCredential).to receive(:can_be_used?).and_return(true)
        allow_any_instance_of(Devops::GitPipelineSchedule).to receive(:git_provider).and_return(double(provider_type: 'github'))
        allow(Devops::Git::ApiClient).to receive(:for).and_return(double(trigger_workflow: { success: true, id: 'pipeline-123' }))
      end

      it 'triggers the pipeline schedule' do
        post "/api/v1/git/pipeline_schedules/#{schedule.id}/trigger", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('Pipeline triggered successfully')
        expect(data['pipeline_id']).to eq('pipeline-123')
      end

      it 'returns error when credential is not available' do
        allow_any_instance_of(Devops::GitProviderCredential).to receive(:can_be_used?).and_return(false)

        post "/api/v1/git/pipeline_schedules/#{schedule.id}/trigger", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['error']).to eq('Credential not available')
      end
    end

    context 'without git.schedules.manage permission' do
      it 'returns forbidden error' do
        post "/api/v1/git/pipeline_schedules/#{schedule.id}/trigger", headers: read_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/git/pipeline_schedules/:id/pause' do
    let(:schedule) { create(:devops_git_pipeline_schedule, repository: repository, account: account, is_active: true) }

    context 'with proper permissions' do
      before do
        allow_any_instance_of(Devops::GitPipelineSchedule).to receive(:deactivate!)
      end

      it 'pauses the pipeline schedule' do
        post "/api/v1/git/pipeline_schedules/#{schedule.id}/pause", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['schedule']).to be_present
      end
    end

    context 'without git.schedules.manage permission' do
      it 'returns forbidden error' do
        post "/api/v1/git/pipeline_schedules/#{schedule.id}/pause", headers: read_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/git/pipeline_schedules/:id/resume' do
    let(:schedule) { create(:devops_git_pipeline_schedule, repository: repository, account: account, is_active: false) }

    context 'with proper permissions' do
      before do
        allow_any_instance_of(Devops::GitPipelineSchedule).to receive(:activate!)
      end

      it 'resumes the pipeline schedule' do
        post "/api/v1/git/pipeline_schedules/#{schedule.id}/resume", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['schedule']).to be_present
      end
    end

    context 'without git.schedules.manage permission' do
      it 'returns forbidden error' do
        post "/api/v1/git/pipeline_schedules/#{schedule.id}/resume", headers: read_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
