# frozen_string_literal: true

require 'rails_helper'

# C3b2 review B1: the approvals LIST carries `current_step_can_approve`, computed
# for the viewer. The client used to show the quick Approve/Reject row on the
# permission alone until a card's detail loaded, so a holder of
# ai.autonomy.approve who is not an approver of the current step saw buttons
# whose click drew a 422.
RSpec.describe 'GET /api/v1/ai/autonomy/approvals — current_step_can_approve per viewer', type: :request do
  let(:account) { create(:account) }
  let(:perm) { 'system.infra_tasks.control' }
  let!(:approver) { create(:user, account: account, permissions: [ 'ai.agents.read', 'ai.autonomy.approve', perm ]) }
  let!(:other_approver) { create(:user, account: account, permissions: [ 'ai.agents.read', 'ai.autonomy.approve', perm ]) }
  # Holds the approve permission, but is not an approver of this chain's step.
  let!(:not_on_step) { create(:user, account: account, permissions: %w[ai.agents.read ai.autonomy.approve]) }

  let!(:request_row) do
    Ai::ApprovalChain.create!(
      account: account, name: "chain-#{SecureRandom.hex(4)}",
      trigger_type: 'autonomy_action', status: 'active',
      is_sequential: true, timeout_hours: 4, timeout_action: 'reject',
      steps: [ { 'name' => 'Two keys', 'approvers' => [ { 'type' => 'permission', 'value' => perm } ], 'required_approvals' => 2 } ]
    ).create_request!(source_type: 'X', source_id: SecureRandom.uuid, description: 'd')
  end

  def listed_for(user)
    get '/api/v1/ai/autonomy/approvals', headers: auth_headers_for(user), as: :json
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)['data'].find { |row| row['id'] == request_row.id }
  end

  it 'is true for an approver of the current step and false for a permission holder who is not on it' do
    expect(listed_for(approver)['current_step_can_approve']).to be(true)
    expect(listed_for(not_on_step)['current_step_can_approve']).to be(false)
  end

  it 'turns false for an approver once they have decided the step, and stays true for the other key' do
    request_row.record_decision!(approver: approver, decision: 'approved')

    expect(listed_for(approver)['current_step_can_approve']).to be(false)
    expect(listed_for(other_approver)['current_step_can_approve']).to be(true)
  end
end
