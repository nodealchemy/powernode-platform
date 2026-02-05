# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::WorktreeSessions', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.workflows.read', 'ai.workflows.create', 'ai.workflows.execute']) }
  let(:read_only_user) { create(:user, account: account, permissions: ['ai.workflows.read']) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, account: other_account, permissions: ['ai.workflows.read']) }

  let(:headers) { auth_headers_for(user) }
  let(:read_only_headers) { auth_headers_for(read_only_user) }
  let(:other_headers) { auth_headers_for(other_user) }

  # =============================================================================
  # INDEX
  # =============================================================================

  describe 'GET /api/v1/ai/worktree_sessions' do
    let!(:session1) { create(:ai_worktree_session, account: account, status: 'active', started_at: 1.hour.ago) }
    let!(:session2) { create(:ai_worktree_session, account: account, status: 'completed', started_at: 2.hours.ago, completed_at: 1.hour.ago) }
    let!(:session3) { create(:ai_worktree_session, account: account, status: 'pending') }
    let!(:other_session) { create(:ai_worktree_session, account: other_account) }

    context 'with ai.workflows.read permission' do
      it 'returns list of sessions for current account' do
        get '/api/v1/ai/worktree_sessions', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['items']).to be_an(Array)
        expect(data['items'].length).to eq(3)
      end

      it 'does not include sessions from other accounts' do
        get '/api/v1/ai/worktree_sessions', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        ids = data['items'].map { |s| s['id'] }
        expect(ids).not_to include(other_session.id)
      end

      it 'supports status filter' do
        get '/api/v1/ai/worktree_sessions?status=active', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        statuses = data['items'].map { |s| s['status'] }
        expect(statuses.uniq).to eq(['active'])
      end

      it 'supports pagination' do
        get '/api/v1/ai/worktree_sessions?page=1&per_page=2', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['pagination']).to include(
          'current_page' => 1,
          'per_page' => 2
        )
        expect(data['items'].length).to eq(2)
      end

      it 'returns session summary data in each item' do
        get '/api/v1/ai/worktree_sessions', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        item = data['items'].first
        expect(item).to include(
          'id', 'status', 'repository_path', 'base_branch',
          'merge_strategy', 'total_worktrees', 'progress_percentage'
        )
      end
    end

    context 'without ai.workflows.read permission' do
      it 'returns forbidden error' do
        user_without_permission = create(:user, account: account, permissions: [])
        headers_without_permission = auth_headers_for(user_without_permission)

        get '/api/v1/ai/worktree_sessions', headers: headers_without_permission, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/ai/worktree_sessions', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  # =============================================================================
  # SHOW
  # =============================================================================

  describe 'GET /api/v1/ai/worktree_sessions/:id' do
    let(:session) { create(:ai_worktree_session, :active, :with_worktrees, account: account) }

    context 'with ai.workflows.read permission' do
      it 'returns session with worktrees and merge operations' do
        # Create merge operations for the session
        worktree = session.worktrees.first
        create(:ai_merge_operation, worktree_session: session, worktree: worktree, account: account)

        get "/api/v1/ai/worktree_sessions/#{session.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['session']).to include(
          'id' => session.id,
          'status' => 'active'
        )
        expect(data['worktrees']).to be_an(Array)
        expect(data['worktrees'].length).to eq(3)
        expect(data['merge_operations']).to be_an(Array)
        expect(data['merge_operations'].length).to eq(1)
      end

      it 'returns session summary fields' do
        get "/api/v1/ai/worktree_sessions/#{session.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['session']).to include(
          'repository_path', 'base_branch', 'merge_strategy',
          'max_parallel', 'total_worktrees', 'completed_worktrees',
          'failed_worktrees', 'progress_percentage'
        )
      end

      it 'returns not found for non-existent session' do
        get "/api/v1/ai/worktree_sessions/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('Worktree session not found', 404)
      end
    end

    context 'accessing session from different account' do
      let(:other_session) { create(:ai_worktree_session, account: other_account) }

      it 'returns not found error' do
        get "/api/v1/ai/worktree_sessions/#{other_session.id}", headers: headers, as: :json

        expect_error_response('Worktree session not found', 404)
      end
    end
  end

  # =============================================================================
  # CREATE
  # =============================================================================

  describe 'POST /api/v1/ai/worktree_sessions' do
    let(:repository_path) { '/tmp/test-repo' }
    let(:valid_params) do
      {
        repository_path: repository_path,
        base_branch: 'main',
        merge_strategy: 'sequential',
        tasks: [
          { branch_suffix: 'task-1', metadata: { description: 'First task' } },
          { branch_suffix: 'task-2', metadata: { description: 'Second task' } }
        ]
      }
    end

    before do
      allow(File).to receive(:directory?).and_call_original
      allow(File).to receive(:directory?).with(repository_path).and_return(true)
    end

    context 'with ai.workflows.create permission' do
      it 'creates a session with valid params' do
        expect {
          post '/api/v1/ai/worktree_sessions', params: valid_params, headers: headers, as: :json
        }.to change { account.ai_worktree_sessions.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['session']).to be_present
        expect(data['message']).to include('2 worktrees')
      end

      it 'enqueues a WorktreeProvisioningJob' do
        expect {
          post '/api/v1/ai/worktree_sessions', params: valid_params, headers: headers, as: :json
        }.to have_enqueued_job(Ai::WorktreeProvisioningJob)
      end

      it 'returns 400 for missing tasks' do
        params_without_tasks = valid_params.except(:tasks)

        post '/api/v1/ai/worktree_sessions', params: params_without_tasks, headers: headers, as: :json

        expect_error_response('Tasks are required', 400)
      end

      it 'returns 400 for empty tasks array' do
        params_with_empty_tasks = valid_params.merge(tasks: [])

        post '/api/v1/ai/worktree_sessions', params: params_with_empty_tasks, headers: headers, as: :json

        expect_error_response('Tasks are required', 400)
      end

      it 'returns 422 for invalid repository path' do
        allow(File).to receive(:directory?).with('/nonexistent/repo').and_return(false)
        invalid_params = valid_params.merge(repository_path: '/nonexistent/repo')

        post '/api/v1/ai/worktree_sessions', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without ai.workflows.create permission' do
      it 'returns forbidden error' do
        post '/api/v1/ai/worktree_sessions', params: valid_params, headers: read_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =============================================================================
  # CANCEL
  # =============================================================================

  describe 'POST /api/v1/ai/worktree_sessions/:id/cancel' do
    let(:active_session) { create(:ai_worktree_session, :active, account: account) }

    context 'with ai.workflows.execute permission' do
      it 'cancels an active session' do
        post "/api/v1/ai/worktree_sessions/#{active_session.id}/cancel",
             params: { reason: 'No longer needed' },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['session']['status']).to eq('cancelled')
        expect(data['message']).to eq('Session cancelled')
      end

      it 'returns error for a terminal session' do
        completed_session = create(:ai_worktree_session, :completed, account: account)

        post "/api/v1/ai/worktree_sessions/#{completed_session.id}/cancel",
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns error for a cancelled session' do
        cancelled_session = create(:ai_worktree_session, :cancelled, account: account)

        post "/api/v1/ai/worktree_sessions/#{cancelled_session.id}/cancel",
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns not found for non-existent session' do
        post "/api/v1/ai/worktree_sessions/#{SecureRandom.uuid}/cancel",
             headers: headers,
             as: :json

        expect_error_response('Worktree session not found', 404)
      end
    end

    context 'without ai.workflows.execute permission' do
      it 'returns forbidden error' do
        post "/api/v1/ai/worktree_sessions/#{active_session.id}/cancel",
             headers: read_only_headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =============================================================================
  # STATUS
  # =============================================================================

  describe 'GET /api/v1/ai/worktree_sessions/:id/status' do
    let(:session) { create(:ai_worktree_session, :active, :with_worktrees, account: account) }

    context 'with ai.workflows.read permission' do
      it 'returns detailed session status' do
        get "/api/v1/ai/worktree_sessions/#{session.id}/status", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['session']).to include('id' => session.id, 'status' => 'active')
        expect(data['worktrees']).to be_an(Array)
        expect(data['merge_operations']).to be_an(Array)
      end

      it 'returns not found for non-existent session' do
        get "/api/v1/ai/worktree_sessions/#{SecureRandom.uuid}/status", headers: headers, as: :json

        expect_error_response('Worktree session not found', 404)
      end
    end

    context 'accessing status from different account' do
      let(:other_session) { create(:ai_worktree_session, account: other_account) }

      it 'returns not found error' do
        get "/api/v1/ai/worktree_sessions/#{other_session.id}/status", headers: headers, as: :json

        expect_error_response('Worktree session not found', 404)
      end
    end
  end

  # =============================================================================
  # MERGE OPERATIONS
  # =============================================================================

  describe 'GET /api/v1/ai/worktree_sessions/:id/merge_operations' do
    let(:session) { create(:ai_worktree_session, :active, :with_worktrees, account: account) }

    context 'with ai.workflows.read permission' do
      it 'returns merge operations for session' do
        worktree1 = session.worktrees.first
        worktree2 = session.worktrees.second
        create(:ai_merge_operation, worktree_session: session, worktree: worktree1, account: account, merge_order: 0)
        create(:ai_merge_operation, worktree_session: session, worktree: worktree2, account: account, merge_order: 1)

        get "/api/v1/ai/worktree_sessions/#{session.id}/merge_operations", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['items']).to be_an(Array)
        expect(data['items'].length).to eq(2)
      end

      it 'returns empty array when no merge operations exist' do
        get "/api/v1/ai/worktree_sessions/#{session.id}/merge_operations", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['items']).to eq([])
      end

      it 'returns merge operations ordered by merge_order' do
        worktree1 = session.worktrees.first
        worktree2 = session.worktrees.second
        create(:ai_merge_operation, worktree_session: session, worktree: worktree2, account: account, merge_order: 1)
        create(:ai_merge_operation, worktree_session: session, worktree: worktree1, account: account, merge_order: 0)

        get "/api/v1/ai/worktree_sessions/#{session.id}/merge_operations", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        orders = data['items'].map { |op| op['merge_order'] }
        expect(orders).to eq([0, 1])
      end

      it 'returns not found for non-existent session' do
        get "/api/v1/ai/worktree_sessions/#{SecureRandom.uuid}/merge_operations", headers: headers, as: :json

        expect_error_response('Worktree session not found', 404)
      end
    end
  end

  # =============================================================================
  # RETRY MERGE
  # =============================================================================

  describe 'POST /api/v1/ai/worktree_sessions/:id/retry_merge' do
    let(:failed_session) { create(:ai_worktree_session, :failed, account: account) }

    context 'with ai.workflows.execute permission' do
      it 'retries merge on a failed session' do
        post "/api/v1/ai/worktree_sessions/#{failed_session.id}/retry_merge",
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['session']['status']).to eq('merging')
        expect(json_response['message']).to eq('Merge retry started')
      end

      it 'enqueues a MergeExecutionJob' do
        expect {
          post "/api/v1/ai/worktree_sessions/#{failed_session.id}/retry_merge",
               headers: headers,
               as: :json
        }.to have_enqueued_job(Ai::MergeExecutionJob)
      end

      it 'clears failed merge operations' do
        worktree = create(:ai_worktree, :completed, worktree_session: failed_session, account: failed_session.account)
        create(:ai_merge_operation, :failed, worktree_session: failed_session, worktree: worktree, account: failed_session.account)
        create(:ai_merge_operation, :conflict, worktree_session: failed_session, worktree: worktree, account: failed_session.account)

        expect {
          post "/api/v1/ai/worktree_sessions/#{failed_session.id}/retry_merge",
               headers: headers,
               as: :json
        }.to change { failed_session.merge_operations.count }.by(-2)

        expect_success_response
      end

      it 'returns error for non-failed session' do
        active_session = create(:ai_worktree_session, :active, account: account)

        post "/api/v1/ai/worktree_sessions/#{active_session.id}/retry_merge",
             headers: headers,
             as: :json

        expect_error_response('Session is not in failed state', 422)
      end

      it 'returns error for completed session' do
        completed_session = create(:ai_worktree_session, :completed, account: account)

        post "/api/v1/ai/worktree_sessions/#{completed_session.id}/retry_merge",
             headers: headers,
             as: :json

        expect_error_response('Session is not in failed state', 422)
      end

      it 'returns not found for non-existent session' do
        post "/api/v1/ai/worktree_sessions/#{SecureRandom.uuid}/retry_merge",
             headers: headers,
             as: :json

        expect_error_response('Worktree session not found', 404)
      end
    end

    context 'without ai.workflows.execute permission' do
      it 'returns forbidden error' do
        post "/api/v1/ai/worktree_sessions/#{failed_session.id}/retry_merge",
             headers: read_only_headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =============================================================================
  # CONFLICTS
  # =============================================================================

  describe 'GET /api/v1/ai/worktree_sessions/:id/conflicts' do
    let(:session) { create(:ai_worktree_session, :active, :with_worktrees, account: account) }
    let(:conflict_data) do
      {
        conflicts: [
          { file_path: 'src/file1.rb', worktrees: %w[worktree-1 worktree-2], severity: 'high' }
        ],
        total_conflicts: 1
      }
    end

    before do
      conflict_service = instance_double(::Ai::Git::ConflictDetectionService)
      allow(::Ai::Git::ConflictDetectionService).to receive(:new).with(session: session).and_return(conflict_service)
      allow(conflict_service).to receive(:detect).and_return(conflict_data)
    end

    context 'with ai.workflows.read permission' do
      it 'returns conflict detection results' do
        get "/api/v1/ai/worktree_sessions/#{session.id}/conflicts", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['conflicts']).to be_an(Array)
        expect(data['conflicts'].length).to eq(1)
        expect(data['total_conflicts']).to eq(1)
      end

      it 'returns not found for non-existent session' do
        get "/api/v1/ai/worktree_sessions/#{SecureRandom.uuid}/conflicts", headers: headers, as: :json

        expect_error_response('Worktree session not found', 404)
      end
    end

    context 'without ai.workflows.read permission' do
      it 'returns forbidden error' do
        user_without_permission = create(:user, account: account, permissions: [])
        headers_without_permission = auth_headers_for(user_without_permission)

        get "/api/v1/ai/worktree_sessions/#{session.id}/conflicts", headers: headers_without_permission, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'accessing conflicts from different account' do
      let(:other_session) { create(:ai_worktree_session, :active, account: other_account) }

      it 'returns not found error' do
        get "/api/v1/ai/worktree_sessions/#{other_session.id}/conflicts", headers: headers, as: :json

        expect_error_response('Worktree session not found', 404)
      end
    end
  end

  # =============================================================================
  # FILE LOCKS
  # =============================================================================

  describe 'GET /api/v1/ai/worktree_sessions/:id/file_locks' do
    let(:session) { create(:ai_worktree_session, :active, :with_worktrees, account: account) }
    let(:lock_data) do
      [
        { id: SecureRandom.uuid, file_path: 'src/file1.rb', lock_type: 'exclusive', worktree_id: session.worktrees.first&.id },
        { id: SecureRandom.uuid, file_path: 'src/file2.rb', lock_type: 'shared', worktree_id: session.worktrees.first&.id }
      ]
    end

    before do
      lock_service = instance_double(::Ai::FileLockService)
      allow(::Ai::FileLockService).to receive(:new).with(session: session).and_return(lock_service)
      allow(lock_service).to receive(:active_locks).and_return(lock_data)
    end

    context 'with ai.workflows.read permission' do
      it 'returns active file locks' do
        get "/api/v1/ai/worktree_sessions/#{session.id}/file_locks", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['items']).to be_an(Array)
        expect(data['items'].length).to eq(2)
      end

      it 'returns not found for non-existent session' do
        get "/api/v1/ai/worktree_sessions/#{SecureRandom.uuid}/file_locks", headers: headers, as: :json

        expect_error_response('Worktree session not found', 404)
      end
    end

    context 'without ai.workflows.read permission' do
      it 'returns forbidden error' do
        user_without_permission = create(:user, account: account, permissions: [])
        headers_without_permission = auth_headers_for(user_without_permission)

        get "/api/v1/ai/worktree_sessions/#{session.id}/file_locks", headers: headers_without_permission, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'accessing file locks from different account' do
      let(:other_session) { create(:ai_worktree_session, :active, account: other_account) }

      it 'returns not found error' do
        get "/api/v1/ai/worktree_sessions/#{other_session.id}/file_locks", headers: headers, as: :json

        expect_error_response('Worktree session not found', 404)
      end
    end
  end

  # =============================================================================
  # ACQUIRE LOCKS
  # =============================================================================

  describe 'POST /api/v1/ai/worktree_sessions/:id/acquire_locks' do
    let(:session) { create(:ai_worktree_session, :active, :with_worktrees, account: account) }
    let(:worktree) { session.worktrees.first }
    let(:lock_service) { instance_double(::Ai::FileLockService) }

    before do
      allow(::Ai::FileLockService).to receive(:new).with(session: session).and_return(lock_service)
    end

    context 'with ai.workflows.execute permission' do
      it 'acquires locks successfully' do
        allow(lock_service).to receive(:acquire).with(
          worktree: worktree,
          file_paths: ['src/file1.rb', 'src/file2.rb'],
          lock_type: 'exclusive',
          ttl_seconds: nil
        ).and_return({ success: true, locks: [{ file_path: 'src/file1.rb' }, { file_path: 'src/file2.rb' }] })

        post "/api/v1/ai/worktree_sessions/#{session.id}/acquire_locks",
             params: { worktree_id: worktree.id, file_paths: ['src/file1.rb', 'src/file2.rb'] },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['locks']).to be_an(Array)
        expect(data['locks'].length).to eq(2)
      end

      it 'acquires shared locks with TTL' do
        allow(lock_service).to receive(:acquire).with(
          worktree: worktree,
          file_paths: ['src/file1.rb'],
          lock_type: 'shared',
          ttl_seconds: 3600
        ).and_return({ success: true, locks: [{ file_path: 'src/file1.rb', lock_type: 'shared' }] })

        post "/api/v1/ai/worktree_sessions/#{session.id}/acquire_locks",
             params: { worktree_id: worktree.id, file_paths: ['src/file1.rb'], lock_type: 'shared', ttl_seconds: 3600 },
             headers: headers,
             as: :json

        expect_success_response
      end

      it 'returns conflict when locks cannot be acquired' do
        allow(lock_service).to receive(:acquire).with(
          worktree: worktree,
          file_paths: ['src/file1.rb'],
          lock_type: 'exclusive',
          ttl_seconds: nil
        ).and_return({ success: false, conflicts: [{ file_path: 'src/file1.rb', held_by: 'other-worktree' }] })

        post "/api/v1/ai/worktree_sessions/#{session.id}/acquire_locks",
             params: { worktree_id: worktree.id, file_paths: ['src/file1.rb'] },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:conflict)
      end

      it 'returns not found for non-existent session' do
        post "/api/v1/ai/worktree_sessions/#{SecureRandom.uuid}/acquire_locks",
             params: { worktree_id: worktree.id, file_paths: ['src/file1.rb'] },
             headers: headers,
             as: :json

        expect_error_response('Worktree session not found', 404)
      end

      it 'returns not found for non-existent worktree' do
        post "/api/v1/ai/worktree_sessions/#{session.id}/acquire_locks",
             params: { worktree_id: SecureRandom.uuid, file_paths: ['src/file1.rb'] },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without ai.workflows.execute permission' do
      it 'returns forbidden error' do
        post "/api/v1/ai/worktree_sessions/#{session.id}/acquire_locks",
             params: { worktree_id: worktree.id, file_paths: ['src/file1.rb'] },
             headers: read_only_headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'accessing session from different account' do
      let(:other_session) { create(:ai_worktree_session, :active, :with_worktrees, account: other_account) }

      it 'returns not found error' do
        post "/api/v1/ai/worktree_sessions/#{other_session.id}/acquire_locks",
             params: { worktree_id: SecureRandom.uuid, file_paths: ['src/file1.rb'] },
             headers: headers,
             as: :json

        expect_error_response('Worktree session not found', 404)
      end
    end
  end

  # =============================================================================
  # RELEASE LOCKS
  # =============================================================================

  describe 'POST /api/v1/ai/worktree_sessions/:id/release_locks' do
    let(:session) { create(:ai_worktree_session, :active, :with_worktrees, account: account) }
    let(:worktree) { session.worktrees.first }
    let(:lock_service) { instance_double(::Ai::FileLockService) }

    before do
      allow(::Ai::FileLockService).to receive(:new).with(session: session).and_return(lock_service)
    end

    context 'with ai.workflows.execute permission' do
      it 'releases all locks for a worktree' do
        allow(lock_service).to receive(:release).with(worktree: worktree).and_return({ released: 3 })

        post "/api/v1/ai/worktree_sessions/#{session.id}/release_locks",
             params: { worktree_id: worktree.id },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['released']).to eq(3)
      end

      it 'releases specific file locks' do
        allow(lock_service).to receive(:release_files).with(
          worktree: worktree,
          file_paths: ['src/file1.rb', 'src/file2.rb']
        ).and_return({ released: 2 })

        post "/api/v1/ai/worktree_sessions/#{session.id}/release_locks",
             params: { worktree_id: worktree.id, file_paths: ['src/file1.rb', 'src/file2.rb'] },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['released']).to eq(2)
      end

      it 'returns not found for non-existent session' do
        post "/api/v1/ai/worktree_sessions/#{SecureRandom.uuid}/release_locks",
             params: { worktree_id: worktree.id },
             headers: headers,
             as: :json

        expect_error_response('Worktree session not found', 404)
      end

      it 'returns not found for non-existent worktree' do
        post "/api/v1/ai/worktree_sessions/#{session.id}/release_locks",
             params: { worktree_id: SecureRandom.uuid },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without ai.workflows.execute permission' do
      it 'returns forbidden error' do
        post "/api/v1/ai/worktree_sessions/#{session.id}/release_locks",
             params: { worktree_id: worktree.id },
             headers: read_only_headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'accessing session from different account' do
      let(:other_session) { create(:ai_worktree_session, :active, :with_worktrees, account: other_account) }

      it 'returns not found error' do
        post "/api/v1/ai/worktree_sessions/#{other_session.id}/release_locks",
             params: { worktree_id: SecureRandom.uuid },
             headers: headers,
             as: :json

        expect_error_response('Worktree session not found', 404)
      end
    end
  end

  # =============================================================================
  # ACCOUNT ISOLATION
  # =============================================================================

  describe 'account isolation' do
    let(:other_session) { create(:ai_worktree_session, account: other_account) }

    it 'cannot access sessions from another account via show' do
      get "/api/v1/ai/worktree_sessions/#{other_session.id}", headers: headers, as: :json

      expect_error_response('Worktree session not found', 404)
    end

    it 'cannot access sessions from another account via status' do
      get "/api/v1/ai/worktree_sessions/#{other_session.id}/status", headers: headers, as: :json

      expect_error_response('Worktree session not found', 404)
    end

    it 'cannot access sessions from another account via merge_operations' do
      get "/api/v1/ai/worktree_sessions/#{other_session.id}/merge_operations", headers: headers, as: :json

      expect_error_response('Worktree session not found', 404)
    end

    it 'cannot cancel sessions from another account' do
      post "/api/v1/ai/worktree_sessions/#{other_session.id}/cancel", headers: headers, as: :json

      expect_error_response('Worktree session not found', 404)
    end

    it 'cannot retry merge on sessions from another account' do
      other_failed = create(:ai_worktree_session, :failed, account: other_account)

      post "/api/v1/ai/worktree_sessions/#{other_failed.id}/retry_merge", headers: headers, as: :json

      expect_error_response('Worktree session not found', 404)
    end

    it 'cannot access conflicts from another account' do
      get "/api/v1/ai/worktree_sessions/#{other_session.id}/conflicts", headers: headers, as: :json

      expect_error_response('Worktree session not found', 404)
    end

    it 'cannot access file locks from another account' do
      get "/api/v1/ai/worktree_sessions/#{other_session.id}/file_locks", headers: headers, as: :json

      expect_error_response('Worktree session not found', 404)
    end

    it 'cannot acquire locks on sessions from another account' do
      post "/api/v1/ai/worktree_sessions/#{other_session.id}/acquire_locks",
           params: { worktree_id: SecureRandom.uuid, file_paths: ['src/file1.rb'] },
           headers: headers,
           as: :json

      expect_error_response('Worktree session not found', 404)
    end

    it 'cannot release locks on sessions from another account' do
      post "/api/v1/ai/worktree_sessions/#{other_session.id}/release_locks",
           params: { worktree_id: SecureRandom.uuid },
           headers: headers,
           as: :json

      expect_error_response('Worktree session not found', 404)
    end

    it 'does not list sessions from other accounts in index' do
      create(:ai_worktree_session, account: account)
      create(:ai_worktree_session, account: other_account)

      get '/api/v1/ai/worktree_sessions', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      ids = data['items'].map { |s| s['id'] }
      expect(ids).not_to include(other_session.id)
    end
  end
end
