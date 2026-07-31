# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::ApprovalChainsController, type: :request do
  let(:account) { create(:account) }
  let(:user) { user_with_permissions('ai.approval_chains.manage') }
  let(:headers) { auth_headers_for(user) }

  let(:valid_payload) do
    {
      approval_chain: {
        name: 'SRE then Manager',
        description: 'Two-step example',
        is_sequential: true,
        timeout_hours: 4,
        timeout_action: 'reject',
        steps: [
          {
            name: 'SRE',
            approvers: [{ type: 'permission', value: 'system.infra_tasks.control' }],
            required_approvals: 1
          },
          {
            name: 'Manager',
            approvers: [{ type: 'role', value: 'admin' }],
            required_approvals: 1
          }
        ]
      }
    }
  end

  describe 'GET /api/v1/ai/approval_chains' do
    it 'returns chains for the current account, ordered by name' do
      Ai::ApprovalChain.create!(
        account: user.account, name: 'B-chain', trigger_type: 'autonomy_action',
        status: 'active', is_sequential: true, timeout_hours: 4, timeout_action: 'reject',
        steps: [{ 'name' => 's', 'approvers' => ['*'], 'required_approvals' => 1 }]
      )
      Ai::ApprovalChain.create!(
        account: user.account, name: 'A-chain', trigger_type: 'autonomy_action',
        status: 'active', is_sequential: true, timeout_hours: 4, timeout_action: 'reject',
        steps: [{ 'name' => 's', 'approvers' => ['*'], 'required_approvals' => 1 }]
      )

      get '/api/v1/ai/approval_chains', headers: headers
      expect(response).to have_http_status(:ok)
      names = json_response['data'].map { |c| c['name'] }
      expect(names).to eq(%w[A-chain B-chain])
    end
  end

  describe 'POST /api/v1/ai/approval_chains' do
    it 'creates a chain with multi-step + typed approver shape' do
      expect {
        post '/api/v1/ai/approval_chains', params: valid_payload.to_json, headers: headers.merge('Content-Type' => 'application/json')
      }.to change(Ai::ApprovalChain, :count).by(1)

      expect(response).to have_http_status(:created)
      chain = Ai::ApprovalChain.find(json_response['data']['id'])
      expect(chain.steps.size).to eq(2)
      expect(chain.steps.first['approvers'].first['type']).to eq('permission')
    end

    it 'rejects malformed step shapes' do
      payload = valid_payload.deep_dup
      payload[:approval_chain][:steps] = [{ name: 'broken', approvers: [], required_approvals: 1 }]
      post '/api/v1/ai/approval_chains', params: payload.to_json, headers: headers.merge('Content-Type' => 'application/json')
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'DELETE /api/v1/ai/approval_chains/:id' do
    let!(:chain) do
      Ai::ApprovalChain.create!(
        account: user.account, name: 'doomed', trigger_type: 'autonomy_action',
        status: 'active', is_sequential: true, timeout_hours: 4, timeout_action: 'reject',
        steps: [{ 'name' => 's', 'approvers' => ['*'], 'required_approvals' => 1 }]
      )
    end

    it 'soft-deletes the chain' do
      delete "/api/v1/ai/approval_chains/#{chain.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(chain.reload.status).to eq('disabled')
    end

    it 'refuses delete when pending requests exist' do
      chain.create_request!(
        source_type: 'Test', source_id: SecureRandom.uuid, description: 'open'
      )
      delete "/api/v1/ai/approval_chains/#{chain.id}", headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(chain.reload.status).to eq('active')
    end
  end

  describe 'permission gating' do
    let(:no_perm_user) { create(:user, account: account, permissions: []) }
    let(:no_perm_headers) { auth_headers_for(no_perm_user) }

    it 'rejects unauthorized users' do
      get '/api/v1/ai/approval_chains', headers: no_perm_headers
      expect(response).to have_http_status(:forbidden).or have_http_status(:unauthorized)
    end
  end
end
