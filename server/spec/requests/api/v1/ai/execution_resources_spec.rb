# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::ExecutionResources', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.agents.read', 'ai.workflows.read']) }
  let(:no_perm_user) { create(:user, account: account, permissions: []) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, account: other_account, permissions: ['ai.agents.read']) }

  let(:headers) { auth_headers_for(user) }
  let(:no_perm_headers) { auth_headers_for(no_perm_user) }
  let(:other_headers) { auth_headers_for(other_user) }

  # =============================================================================
  # INDEX
  # =============================================================================

  describe 'GET /api/v1/ai/execution_resources' do
    let(:session) { create(:ai_worktree_session, account: account, initiated_by: user) }
    let!(:worktree1) { create(:ai_worktree, worktree_session: session, branch_name: "feature/branch-1", status: "ready") }
    let!(:worktree2) { create(:ai_worktree, worktree_session: session, branch_name: "feature/branch-2", status: "completed") }

    context 'with valid permissions' do
      it 'returns aggregated resources' do
        get '/api/v1/ai/execution_resources', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['items']).to be_an(Array)
        expect(data['pagination']).to include('current_page', 'total_pages', 'total_count', 'per_page')
      end

      it 'filters by type' do
        get '/api/v1/ai/execution_resources?type=git_branch', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        types = data['items'].map { |r| r['resource_type'] }
        expect(types.uniq).to eq(['git_branch'])
      end

      it 'filters by status' do
        get '/api/v1/ai/execution_resources?type=git_branch&status=ready', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        statuses = data['items'].map { |r| r['status'] }
        expect(statuses).to all(eq('ready'))
      end

      it 'supports search' do
        get '/api/v1/ai/execution_resources?type=git_branch&search=branch-1', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['items'].length).to eq(1)
        expect(data['items'].first['name']).to include('branch-1')
      end

      it 'supports pagination' do
        get '/api/v1/ai/execution_resources?type=git_branch&page=1&per_page=1', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['items'].length).to eq(1)
        expect(data['pagination']['per_page']).to eq(1)
        expect(data['pagination']['total_count']).to eq(2)
      end
    end

    context 'without permission' do
      it 'returns forbidden' do
        get '/api/v1/ai/execution_resources', headers: no_perm_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        get '/api/v1/ai/execution_resources', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'cross-account isolation' do
      let(:other_session) { create(:ai_worktree_session, account: other_account, initiated_by: other_user) }
      let!(:other_worktree) { create(:ai_worktree, worktree_session: other_session) }

      it 'does not include resources from other accounts' do
        get '/api/v1/ai/execution_resources?type=git_branch', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        ids = data['items'].map { |r| r['source_id'] }
        expect(ids).not_to include(other_worktree.id)
      end
    end
  end

  # =============================================================================
  # COUNTS
  # =============================================================================

  describe 'GET /api/v1/ai/execution_resources/counts' do
    context 'with valid permissions' do
      it 'returns resource counts by type' do
        get '/api/v1/ai/execution_resources/counts', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['counts']).to include('total')
      end
    end

    context 'without permission' do
      it 'returns forbidden' do
        get '/api/v1/ai/execution_resources/counts', headers: no_perm_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =============================================================================
  # SHOW
  # =============================================================================

  describe 'GET /api/v1/ai/execution_resources/:resource_type/:id' do
    let(:session) { create(:ai_worktree_session, account: account, initiated_by: user) }
    let!(:worktree) { create(:ai_worktree, worktree_session: session, status: "ready") }

    context 'with valid resource' do
      it 'returns the resource details' do
        get "/api/v1/ai/execution_resources/git_branch/#{worktree.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['resource']['resource_type']).to eq('git_branch')
        expect(data['resource']['source_id']).to eq(worktree.id)
      end
    end

    context 'with non-existent resource' do
      it 'returns not found' do
        get "/api/v1/ai/execution_resources/git_branch/nonexistent-id", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without permission' do
      it 'returns forbidden' do
        get "/api/v1/ai/execution_resources/git_branch/#{worktree.id}", headers: no_perm_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
