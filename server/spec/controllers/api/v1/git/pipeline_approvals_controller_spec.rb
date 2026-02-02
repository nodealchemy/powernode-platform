# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Git::PipelineApprovalsController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  # Permission users
  let(:approval_read_user) { create(:user, account: account, permissions: [ 'git.approvals.read' ]) }
  let(:approval_manage_user) do
    create(:user, account: account, permissions: %w[
      git.approvals.read git.approvals.manage
    ])
  end
  let(:user_without_permissions) { create(:user, account: account, permissions: []) }

  let(:provider) { create(:git_provider, :github) }
  let(:credential) { create(:git_provider_credential, provider: provider, account: account) }
  let(:repository) { create(:git_repository, credential: credential, account: account) }
  let(:pipeline) { create(:git_pipeline, repository: repository, account: account) }

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'
  end

  # =============================================================================
  # INDEX
  # =============================================================================

  describe 'GET #index' do
    let!(:pending_approval) { create(:git_pipeline_approval, :pending, pipeline: pipeline, account: account) }
    let!(:approved_approval) { create(:git_pipeline_approval, :approved, pipeline: pipeline, account: account) }
    let!(:other_approval) { create(:git_pipeline_approval) }

    context 'with valid permissions' do
      before { sign_in approval_read_user }

      it 'returns approvals for the account' do
        get :index

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['approvals'].length).to eq(2)
      end

      it 'excludes approvals from other accounts' do
        get :index

        json = JSON.parse(response.body)
        approval_ids = json['data']['approvals'].map { |a| a['id'] }
        expect(approval_ids).not_to include(other_approval.id)
      end

      it 'includes stats' do
        get :index

        json = JSON.parse(response.body)
        expect(json['data']['stats']).to be_present
        expect(json['data']['stats']['pending']).to eq(1)
        expect(json['data']['stats']['approved']).to eq(1)
      end

      it 'includes pagination metadata' do
        get :index

        json = JSON.parse(response.body)
        expect(json['data']['pagination']).to be_present
      end

      it 'filters by status' do
        get :index, params: { status: 'pending' }

        json = JSON.parse(response.body)
        expect(json['data']['approvals'].length).to eq(1)
        expect(json['data']['approvals'].first['status']).to eq('pending')
      end

      it 'filters by environment' do
        pending_approval.update!(environment: 'production')
        approved_approval.update!(environment: 'staging')

        get :index, params: { environment: 'production' }

        json = JSON.parse(response.body)
        environments = json['data']['approvals'].map { |a| a['environment'] }
        expect(environments).to all(eq('production'))
      end

      it 'filters by pipeline_id' do
        other_pipeline = create(:git_pipeline, repository: repository, account: account)
        other_approval = create(:git_pipeline_approval, pipeline: other_pipeline, account: account)

        get :index, params: { pipeline_id: pipeline.id }

        json = JSON.parse(response.body)
        approval_ids = json['data']['approvals'].map { |a| a['id'] }
        expect(approval_ids).to include(pending_approval.id)
        expect(approval_ids).not_to include(other_approval.id)
      end
    end

    context 'without permissions' do
      before { sign_in user_without_permissions }

      it 'returns forbidden error' do
        get :index

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =============================================================================
  # PENDING
  # =============================================================================

  describe 'GET #pending' do
    let!(:pending_approval) { create(:git_pipeline_approval, :pending, expires_at: 1.hour.from_now, pipeline: pipeline, account: account) }
    let!(:expired_pending) { create(:git_pipeline_approval, :pending, expires_at: 1.hour.ago, pipeline: pipeline, account: account) }
    let!(:approved_approval) { create(:git_pipeline_approval, :approved, pipeline: pipeline, account: account) }

    context 'with valid permissions' do
      before { sign_in approval_read_user }

      it 'returns only active pending approvals' do
        get :pending

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        approval_ids = json['data']['approvals'].map { |a| a['id'] }
        expect(approval_ids).to include(pending_approval.id)
        expect(approval_ids).not_to include(expired_pending.id, approved_approval.id)
      end

      it 'includes count' do
        get :pending

        json = JSON.parse(response.body)
        expect(json['data']['count']).to eq(1)
      end

      it 'orders by expiry date ascending' do
        another_pending = create(:git_pipeline_approval, :pending, expires_at: 30.minutes.from_now, pipeline: pipeline, account: account)

        get :pending

        json = JSON.parse(response.body)
        ids = json['data']['approvals'].map { |a| a['id'] }
        expect(ids.first).to eq(another_pending.id)
      end
    end
  end

  # =============================================================================
  # SHOW
  # =============================================================================

  describe 'GET #show' do
    let(:approval) { create(:git_pipeline_approval, :pending, pipeline: pipeline, account: account) }

    context 'with valid permissions' do
      before { sign_in approval_read_user }

      it 'returns approval details' do
        get :show, params: { id: approval.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['approval']['id']).to eq(approval.id)
      end

      it 'includes detailed information' do
        get :show, params: { id: approval.id }

        json = JSON.parse(response.body)
        expect(json['data']['approval']).to include(
          'can_respond',
          'can_user_approve',
          'time_until_expiry',
          'required_approvers'
        )
      end

      it 'includes pipeline info' do
        get :show, params: { id: approval.id }

        json = JSON.parse(response.body)
        expect(json['data']['approval']['pipeline']).to be_present
        expect(json['data']['approval']['pipeline']['id']).to eq(pipeline.id)
      end
    end

    context 'when approval belongs to another account' do
      let(:other_approval) { create(:git_pipeline_approval) }
      before { sign_in approval_read_user }

      it 'returns not found error' do
        get :show, params: { id: other_approval.id }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # =============================================================================
  # APPROVE
  # =============================================================================

  describe 'POST #approve' do
    let(:approval) { create(:git_pipeline_approval, :pending, expires_at: 1.hour.from_now, pipeline: pipeline, account: account) }

    context 'with valid permissions' do
      before { sign_in approval_manage_user }

      it 'approves the request' do
        post :approve, params: { id: approval.id, comment: 'Looks good!' }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['approval']['status']).to eq('approved')
        expect(json['data']['message']).to include('granted')
      end

      it 'sets responded_by to current user' do
        post :approve, params: { id: approval.id }

        approval.reload
        expect(approval.responded_by).to eq(approval_manage_user)
      end

      it 'sets responded_at' do
        post :approve, params: { id: approval.id }

        approval.reload
        expect(approval.responded_at).to be_within(1.second).of(Time.current)
      end

      it 'saves the comment' do
        post :approve, params: { id: approval.id, comment: 'Approved for deployment' }

        approval.reload
        expect(approval.response_comment).to eq('Approved for deployment')
      end
    end

    context 'when approval is expired' do
      let(:expired_approval) { create(:git_pipeline_approval, :pending, expires_at: 1.hour.ago, pipeline: pipeline, account: account) }
      before { sign_in approval_manage_user }

      it 'returns error' do
        post :approve, params: { id: expired_approval.id }

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Cannot approve')
      end
    end

    context 'when approval already responded' do
      let(:already_approved) { create(:git_pipeline_approval, :approved, pipeline: pipeline, account: account) }
      before { sign_in approval_manage_user }

      it 'returns error' do
        post :approve, params: { id: already_approved.id }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'when user not in required_approvers' do
      let(:restricted_approval) do
        other_user = create(:user, account: account)
        create(:git_pipeline_approval, :pending, expires_at: 1.hour.from_now,
               required_approvers: [ other_user.id ], pipeline: pipeline, account: account)
      end
      before { sign_in approval_manage_user }

      it 'returns forbidden error' do
        post :approve, params: { id: restricted_approval.id }

        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json['error']).to include('not authorized')
      end
    end

    context 'without permissions' do
      before { sign_in approval_read_user }

      it 'returns forbidden error' do
        post :approve, params: { id: approval.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =============================================================================
  # REJECT
  # =============================================================================

  describe 'POST #reject' do
    let(:approval) { create(:git_pipeline_approval, :pending, expires_at: 1.hour.from_now, pipeline: pipeline, account: account) }

    context 'with valid permissions' do
      before { sign_in approval_manage_user }

      it 'rejects the request' do
        post :reject, params: { id: approval.id, comment: 'Tests are failing' }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['approval']['status']).to eq('rejected')
        expect(json['data']['message']).to include('rejected')
      end

      it 'sets responded_by to current user' do
        post :reject, params: { id: approval.id }

        approval.reload
        expect(approval.responded_by).to eq(approval_manage_user)
      end

      it 'saves the comment' do
        post :reject, params: { id: approval.id, comment: 'Not ready for production' }

        approval.reload
        expect(approval.response_comment).to eq('Not ready for production')
      end
    end

    context 'when approval cannot be responded to' do
      let(:approved_approval) { create(:git_pipeline_approval, :approved, pipeline: pipeline, account: account) }
      before { sign_in approval_manage_user }

      it 'returns error' do
        post :reject, params: { id: approved_approval.id }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without permissions' do
      before { sign_in approval_read_user }

      it 'returns forbidden error' do
        post :reject, params: { id: approval.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =============================================================================
  # CANCEL
  # =============================================================================

  describe 'POST #cancel' do
    let(:approval) { create(:git_pipeline_approval, :pending, pipeline: pipeline, account: account) }

    context 'with valid permissions' do
      before { sign_in approval_manage_user }

      it 'cancels the approval request' do
        post :cancel, params: { id: approval.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['approval']['status']).to eq('cancelled')
        expect(json['data']['message']).to include('cancelled')
      end
    end

    context 'when approval is not pending' do
      let(:approved_approval) { create(:git_pipeline_approval, :approved, pipeline: pipeline, account: account) }
      before { sign_in approval_manage_user }

      it 'returns error' do
        post :cancel, params: { id: approved_approval.id }

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['error']).to include('pending')
      end
    end

    context 'without permissions' do
      before { sign_in approval_read_user }

      it 'returns forbidden error' do
        post :cancel, params: { id: approval.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
