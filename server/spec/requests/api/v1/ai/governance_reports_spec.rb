# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::GovernanceReports', type: :request do
  let(:account) { create(:account) }
  # Governance reports are gated on the dedicated ai.governance.* family:
  # reads -> ai.governance.read, resolve (write) -> ai.governance.manage.
  let(:manage_user) { create(:user, account: account, permissions: [ 'ai.governance.read', 'ai.governance.manage' ]) }
  let(:read_only_user) { create(:user, account: account, permissions: [ 'ai.governance.read' ]) }
  let(:coarse_ai_user) { create(:user, account: account, permissions: [ 'ai.manage' ]) }
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

    it 'forbids users without any governance permission' do
      get '/api/v1/ai/governance_reports',
          headers: auth_headers_for(unauthorized_user), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'forbids a user holding only the coarse ai.manage (decoupled from governance)' do
      get '/api/v1/ai/governance_reports',
          headers: auth_headers_for(coarse_ai_user), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'permits a read-only governance holder (ai.governance.read)' do
      get '/api/v1/ai/governance_reports',
          headers: auth_headers_for(read_only_user), as: :json

      expect(response).not_to have_http_status(:forbidden)
    end
  end

  # The write gate (ai.governance.manage) runs as a before_action, BEFORE the
  # action looks the report up — so these assert the gate without a real record
  # (a permitted request 404s on the missing id, which is still NOT forbidden).
  describe 'PUT /api/v1/ai/governance_reports/:id/resolve' do
    let(:report_id) { SecureRandom.uuid }

    it 'permits resolve with ai.governance.manage (reaches the action, not 403)' do
      put "/api/v1/ai/governance_reports/#{report_id}/resolve",
          params: { notes: 'done' }, headers: headers, as: :json

      expect(response).not_to have_http_status(:forbidden)
    end

    it 'forbids resolve with only ai.governance.read (read cannot write)' do
      put "/api/v1/ai/governance_reports/#{report_id}/resolve",
          params: { notes: 'done' }, headers: auth_headers_for(read_only_user), as: :json

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
