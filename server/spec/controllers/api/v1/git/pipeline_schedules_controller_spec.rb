# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Git::PipelineSchedulesController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  # Permission users
  let(:schedule_read_user) { create(:user, account: account, permissions: ['git.schedules.read']) }
  let(:schedule_manage_user) do
    create(:user, account: account, permissions: %w[
      git.schedules.read git.schedules.manage
    ])
  end
  let(:user_without_permissions) { create(:user, account: account, permissions: []) }

  let(:provider) { create(:git_provider, :github) }
  let(:credential) { create(:git_provider_credential, provider: provider, account: account) }
  let(:repository) { create(:git_repository, credential: credential, account: account) }

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'
  end

  # =============================================================================
  # INDEX
  # =============================================================================

  describe 'GET #index' do
    let!(:schedule1) { create(:git_pipeline_schedule, :active, repository: repository, account: account) }
    let!(:schedule2) { create(:git_pipeline_schedule, :inactive, repository: repository, account: account) }

    context 'with valid permissions' do
      before { sign_in schedule_read_user }

      it 'returns schedules for the repository' do
        get :index, params: { repository_id: repository.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['schedules'].length).to eq(2)
      end

      it 'includes pagination metadata' do
        get :index, params: { repository_id: repository.id }

        json = JSON.parse(response.body)
        expect(json['data']['pagination']).to be_present
      end

      it 'filters by active status' do
        get :index, params: { repository_id: repository.id, active: 'true' }

        json = JSON.parse(response.body)
        expect(json['data']['schedules'].length).to eq(1)
        expect(json['data']['schedules'].first['is_active']).to be true
      end

      it 'filters by inactive status' do
        get :index, params: { repository_id: repository.id, active: 'false' }

        json = JSON.parse(response.body)
        expect(json['data']['schedules'].length).to eq(1)
        expect(json['data']['schedules'].first['is_active']).to be false
      end

      it 'supports sorting by name' do
        schedule1.update!(name: 'ZZZ Schedule')
        schedule2.update!(name: 'AAA Schedule')

        get :index, params: { repository_id: repository.id, sort: 'name', direction: 'asc' }

        json = JSON.parse(response.body)
        names = json['data']['schedules'].map { |s| s['name'] }
        expect(names.first).to eq('AAA Schedule')
      end
    end

    context 'without permissions' do
      before { sign_in user_without_permissions }

      it 'returns forbidden error' do
        get :index, params: { repository_id: repository.id }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when repository not found' do
      before { sign_in schedule_read_user }

      it 'returns not found error' do
        get :index, params: { repository_id: 'non-existent-id' }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # =============================================================================
  # SHOW
  # =============================================================================

  describe 'GET #show' do
    let(:schedule) { create(:git_pipeline_schedule, :with_history, repository: repository, account: account) }

    context 'with valid permissions' do
      before { sign_in schedule_read_user }

      it 'returns schedule details' do
        get :show, params: { id: schedule.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['schedule']['id']).to eq(schedule.id)
      end

      it 'includes schedule statistics' do
        get :show, params: { id: schedule.id }

        json = JSON.parse(response.body)
        expect(json['data']['schedule']).to include('success_count', 'failure_count', 'success_rate')
      end

      it 'includes next_runs array' do
        get :show, params: { id: schedule.id }

        json = JSON.parse(response.body)
        expect(json['data']['schedule']['next_runs']).to be_an(Array)
      end

      it 'includes human_schedule' do
        get :show, params: { id: schedule.id }

        json = JSON.parse(response.body)
        expect(json['data']['schedule']['human_schedule']).to be_present
      end
    end

    context 'when schedule belongs to another account' do
      let(:other_schedule) { create(:git_pipeline_schedule) }
      before { sign_in schedule_read_user }

      it 'returns not found error' do
        get :show, params: { id: other_schedule.id }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # =============================================================================
  # CREATE
  # =============================================================================

  describe 'POST #create' do
    let(:valid_params) do
      {
        repository_id: repository.id,
        schedule: {
          name: 'Nightly Build',
          cron_expression: '0 2 * * *',
          timezone: 'UTC',
          ref: 'main',
          description: 'Runs every night at 2 AM',
          workflow_file: '.github/workflows/nightly.yml'
        }
      }
    end

    context 'with valid permissions' do
      before { sign_in schedule_manage_user }

      it 'creates a new schedule' do
        expect {
          post :create, params: valid_params
        }.to change(Git::PipelineSchedule, :count).by(1)

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json['data']['schedule']['name']).to eq('Nightly Build')
      end

      it 'sets created_by to current user' do
        post :create, params: valid_params

        schedule = Git::PipelineSchedule.last
        expect(schedule.created_by).to eq(schedule_manage_user)
      end

      it 'sets account' do
        post :create, params: valid_params

        schedule = Git::PipelineSchedule.last
        expect(schedule.account).to eq(account)
      end

      it 'returns validation errors for invalid cron' do
        invalid_params = valid_params.deep_dup
        invalid_params[:schedule][:cron_expression] = 'invalid'

        post :create, params: invalid_params

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
      end

      it 'returns validation errors for invalid timezone' do
        invalid_params = valid_params.deep_dup
        invalid_params[:schedule][:timezone] = 'Invalid/Zone'

        post :create, params: invalid_params

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'without permissions' do
      before { sign_in schedule_read_user }

      it 'returns forbidden error' do
        post :create, params: valid_params

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =============================================================================
  # UPDATE
  # =============================================================================

  describe 'PUT #update' do
    let(:schedule) { create(:git_pipeline_schedule, repository: repository, account: account) }

    context 'with valid permissions' do
      before { sign_in schedule_manage_user }

      it 'updates the schedule' do
        put :update, params: { id: schedule.id, schedule: { name: 'Updated Name' } }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['schedule']['name']).to eq('Updated Name')
        expect(schedule.reload.name).to eq('Updated Name')
      end

      it 'returns validation errors for invalid data' do
        put :update, params: { id: schedule.id, schedule: { cron_expression: 'invalid' } }

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'without permissions' do
      before { sign_in schedule_read_user }

      it 'returns forbidden error' do
        put :update, params: { id: schedule.id, schedule: { name: 'New Name' } }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =============================================================================
  # DESTROY
  # =============================================================================

  describe 'DELETE #destroy' do
    let!(:schedule) { create(:git_pipeline_schedule, repository: repository, account: account) }

    context 'with valid permissions' do
      before { sign_in schedule_manage_user }

      it 'deletes the schedule' do
        expect {
          delete :destroy, params: { id: schedule.id }
        }.to change(Git::PipelineSchedule, :count).by(-1)

        expect(response).to have_http_status(:success)
      end
    end

    context 'without permissions' do
      before { sign_in schedule_read_user }

      it 'returns forbidden error' do
        delete :destroy, params: { id: schedule.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =============================================================================
  # TRIGGER
  # =============================================================================

  describe 'POST #trigger' do
    let(:schedule) { create(:git_pipeline_schedule, repository: repository, account: account) }
    let(:mock_client) { double('GitApiClient') }

    before do
      allow(::Git::ApiClient).to receive(:for).and_return(mock_client)
    end

    context 'with valid permissions' do
      before { sign_in schedule_manage_user }

      it 'triggers the pipeline' do
        allow(mock_client).to receive(:trigger_workflow).and_return({
          success: true,
          id: 'run_123'
        })

        post :trigger, params: { id: schedule.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['message']).to include('triggered')
        expect(json['data']['pipeline_id']).to eq('run_123')
      end

      it 'increments run_count and updates last_run_at' do
        allow(mock_client).to receive(:trigger_workflow).and_return({ success: true, id: '123' })
        original_count = schedule.run_count

        post :trigger, params: { id: schedule.id }

        schedule.reload
        expect(schedule.run_count).to eq(original_count + 1)
        expect(schedule.last_run_at).to be_within(1.second).of(Time.current)
      end

      it 'returns error when trigger fails' do
        allow(mock_client).to receive(:trigger_workflow).and_return({
          success: false,
          error: 'Workflow not found'
        })

        post :trigger, params: { id: schedule.id }

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'without permissions' do
      before { sign_in schedule_read_user }

      it 'returns forbidden error' do
        post :trigger, params: { id: schedule.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =============================================================================
  # PAUSE
  # =============================================================================

  describe 'POST #pause' do
    let(:schedule) { create(:git_pipeline_schedule, :active, repository: repository, account: account) }

    context 'with valid permissions' do
      before { sign_in schedule_manage_user }

      it 'deactivates the schedule' do
        post :pause, params: { id: schedule.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['schedule']['is_active']).to be false
        expect(schedule.reload.is_active).to be false
      end
    end

    context 'without permissions' do
      before { sign_in schedule_read_user }

      it 'returns forbidden error' do
        post :pause, params: { id: schedule.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =============================================================================
  # RESUME
  # =============================================================================

  describe 'POST #resume' do
    let(:schedule) { create(:git_pipeline_schedule, :inactive, repository: repository, account: account) }

    context 'with valid permissions' do
      before { sign_in schedule_manage_user }

      it 'activates the schedule' do
        post :resume, params: { id: schedule.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['schedule']['is_active']).to be true
        expect(schedule.reload.is_active).to be true
      end

      it 'recalculates next_run_at' do
        post :resume, params: { id: schedule.id }

        expect(schedule.reload.next_run_at).to be_present
      end
    end

    context 'without permissions' do
      before { sign_in schedule_read_user }

      it 'returns forbidden error' do
        post :resume, params: { id: schedule.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
