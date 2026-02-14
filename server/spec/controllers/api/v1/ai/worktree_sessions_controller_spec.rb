# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::WorktreeSessionsController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.workflows.read', 'ai.workflows.create', 'ai.workflows.execute']) }
  let(:read_only_user) { create(:user, account: account, permissions: ['ai.workflows.read']) }
  let(:no_perms_user) { create(:user, account: account, permissions: []) }

  let!(:session) { create(:ai_worktree_session, :active, account: account, initiated_by: user) }

  before do
    sign_in_as_user(user)
    allow(Audit::LoggingService.instance).to receive(:log).and_return(true)
  end

  # ============================================================================
  # AUTHENTICATION
  # ============================================================================

  describe 'authentication' do
    it 'returns 401 without token' do
      @request.env.delete('HTTP_AUTHORIZATION')
      get :index
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ============================================================================
  # AUTHORIZATION
  # ============================================================================

  describe 'authorization' do
    context 'without permissions' do
      before { sign_in_as_user(no_perms_user) }

      it 'returns 403 for index' do
        get :index
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for show' do
        get :show, params: { id: session.id }
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for create' do
        post :create, params: { tasks: [{ branch_suffix: 'test' }] }
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for cancel' do
        post :cancel, params: { id: session.id }
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for status' do
        get :status, params: { id: session.id }
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with read-only permissions' do
      before { sign_in_as_user(read_only_user) }

      it 'allows index access' do
        get :index
        expect(response).to have_http_status(:ok)
      end

      it 'allows show access' do
        get :show, params: { id: session.id }
        expect(response).to have_http_status(:ok)
      end

      it 'returns 403 for create' do
        post :create, params: { tasks: [{ branch_suffix: 'test' }] }
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for cancel' do
        post :cancel, params: { id: session.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ============================================================================
  # INDEX
  # ============================================================================

  describe 'GET #index' do
    it 'returns worktree sessions' do
      get :index
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['items']).to be_an(Array)
    end

    it 'filters by status' do
      create(:ai_worktree_session, :completed, account: account, initiated_by: user)

      get :index, params: { status: 'active' }
      expect(response).to have_http_status(:ok)
    end

    it 'filters by source_type' do
      get :index, params: { source_type: 'Ai::RalphLoop' }
      expect(response).to have_http_status(:ok)
    end
  end

  # ============================================================================
  # SHOW
  # ============================================================================

  describe 'GET #show' do
    it 'returns session details' do
      get :show, params: { id: session.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['session']).to be_present
    end

    it 'returns 404 for non-existent session' do
      get :show, params: { id: SecureRandom.uuid }
      expect(response).to have_http_status(:not_found)
    end
  end

  # ============================================================================
  # CREATE
  # ============================================================================

  describe 'POST #create' do
    let(:parallel_service) { instance_double(Ai::ParallelExecutionService) }

    before do
      allow(Ai::ParallelExecutionService).to receive(:new).and_return(parallel_service)
    end

    it 'creates a new worktree session' do
      allow(parallel_service).to receive(:start_session).and_return({
        success: true,
        session_id: SecureRandom.uuid,
        worktrees: []
      })

      post :create, params: {
        tasks: [{ branch_suffix: 'feature-a', agent_id: SecureRandom.uuid }],
        repository_path: '/tmp/repo',
        base_branch: 'main'
      }
      expect(response).to have_http_status(:created)
      expect(json_response['success']).to be true
    end

    it 'returns error when tasks are blank' do
      post :create, params: { tasks: [] }
      expect(response).to have_http_status(:bad_request)
    end

    it 'returns error on service failure' do
      allow(parallel_service).to receive(:start_session).and_return({
        success: false,
        error: 'Repository not found'
      })

      post :create, params: {
        tasks: [{ branch_suffix: 'test' }],
        repository_path: '/tmp/nonexistent'
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # ============================================================================
  # CANCEL
  # ============================================================================

  describe 'POST #cancel' do
    let(:parallel_service) { instance_double(Ai::ParallelExecutionService) }

    before do
      allow(Ai::ParallelExecutionService).to receive(:new).and_return(parallel_service)
    end

    it 'cancels a session' do
      allow(parallel_service).to receive(:cancel_session).and_return({ success: true })

      post :cancel, params: { id: session.id, reason: 'No longer needed' }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end

    it 'returns error on cancel failure' do
      allow(parallel_service).to receive(:cancel_session).and_return({
        success: false,
        error: 'Session already completed'
      })

      post :cancel, params: { id: session.id }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # ============================================================================
  # STATUS
  # ============================================================================

  describe 'GET #status' do
    it 'returns session status' do
      parallel_service = instance_double(Ai::ParallelExecutionService)
      allow(Ai::ParallelExecutionService).to receive(:new).and_return(parallel_service)
      allow(parallel_service).to receive(:session_status).and_return({
        status: 'active',
        progress: 50
      })

      get :status, params: { id: session.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end
  end

  # ============================================================================
  # MERGE OPERATIONS
  # ============================================================================

  describe 'GET #merge_operations' do
    it 'returns merge operations for session' do
      get :merge_operations, params: { id: session.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['items']).to be_an(Array)
    end
  end

  # ============================================================================
  # RETRY MERGE
  # ============================================================================

  describe 'POST #retry_merge' do
    it 'returns error if session is not in failed state' do
      post :retry_merge, params: { id: session.id }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'retries merge for failed session' do
      failed_session = create(:ai_worktree_session, :failed, account: account, initiated_by: user)
      allow(Ai::MergeExecutionJob).to receive(:perform_later).and_return(true)

      post :retry_merge, params: { id: failed_session.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end
  end

  # ============================================================================
  # CONFLICTS
  # ============================================================================

  describe 'GET #conflicts' do
    it 'returns conflict detection results' do
      conflict_service = instance_double(Ai::Git::ConflictDetectionService)
      allow(Ai::Git::ConflictDetectionService).to receive(:new).and_return(conflict_service)
      allow(conflict_service).to receive(:detect).and_return({ conflicts: [], has_conflicts: false })

      get :conflicts, params: { id: session.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end
  end

  # ============================================================================
  # FILE LOCKS
  # ============================================================================

  describe 'GET #file_locks' do
    it 'returns active file locks' do
      lock_service = instance_double(Ai::FileLockService)
      allow(Ai::FileLockService).to receive(:new).and_return(lock_service)
      allow(lock_service).to receive(:active_locks).and_return([])

      get :file_locks, params: { id: session.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end
  end
end
