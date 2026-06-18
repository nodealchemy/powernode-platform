# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::GovernanceReports', type: :request do
  let(:account) { create(:account) }
  let(:manage_user) { create(:user, account: account, permissions: ['ai.manage']) }
  let(:unauthorized_user) { create(:user, account: account, permissions: []) }
  let(:headers) { auth_headers_for(manage_user) }

  # Regression: validate_permissions called a non-existent `authorize_permission!`
  # helper, raising NoMethodError (500) on every governance_reports endpoint
  # (governance reports degraded to empty in the Governance dashboard). The
  # canonical helper is `require_permission`.
  describe 'GET /api/v1/ai/governance_reports' do
    it 'returns governance reports for an authorized user' do
      get '/api/v1/ai/governance_reports', headers: headers, as: :json

      expect_success_response
      expect(json_response_data['items']).to be_an(Array)
    end

    it 'forbids users without ai.manage' do
      get '/api/v1/ai/governance_reports',
          headers: auth_headers_for(unauthorized_user), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /api/v1/ai/governance_reports/summary' do
    it 'returns the governance report summary' do
      get '/api/v1/ai/governance_reports/summary', headers: headers, as: :json

      expect_success_response
      expect(json_response_data['summary']).to be_present
    end
  end

  describe 'GET /api/v1/ai/governance_reports/collusion_indicators' do
    it 'returns collusion indicators' do
      get '/api/v1/ai/governance_reports/collusion_indicators', headers: headers, as: :json

      expect_success_response
      expect(json_response_data['items']).to be_an(Array)
    end
  end
end
