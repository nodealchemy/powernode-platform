# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::CodeFactory', type: :request do
  let(:account) { create(:account) }
  let(:user) { user_with_permissions('ai.code_factory.read', account: account) }
  let(:headers) { auth_headers_for(user) }

  describe 'GET /api/v1/ai/code_factory/harness_gaps/:id' do
    let!(:gap) { create(:ai_code_factory_harness_gap, account: account) }

    it 'returns the harness gap' do
      get "/api/v1/ai/code_factory/harness_gaps/#{gap.id}", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['harness_gap']).to be_present
      expect(data['harness_gap']['id']).to eq(gap.id)
      expect(data['harness_gap']['incident_id']).to eq(gap.incident_id)
      expect(data['harness_gap']['status']).to eq('open')
    end

    it 'returns 404 for an unknown id' do
      get "/api/v1/ai/code_factory/harness_gaps/#{SecureRandom.uuid}", headers: headers, as: :json

      expect_error_response('Harness gap not found', 404)
    end

    it 'does not expose harness gaps from another account' do
      other = create(:ai_code_factory_harness_gap, account: create(:account))

      get "/api/v1/ai/code_factory/harness_gaps/#{other.id}", headers: headers, as: :json

      expect_error_response('Harness gap not found', 404)
    end

    it 'forbids users without the read permission' do
      unprivileged = user_without_permissions(account: account)

      get "/api/v1/ai/code_factory/harness_gaps/#{gap.id}",
          headers: auth_headers_for(unprivileged), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'requires authentication' do
      get "/api/v1/ai/code_factory/harness_gaps/#{gap.id}", as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/ai/code_factory/evidence/:id' do
    let!(:manifest) { create(:ai_code_factory_evidence_manifest, :captured, account: account) }

    it 'returns the evidence manifest' do
      get "/api/v1/ai/code_factory/evidence/#{manifest.id}", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['evidence']).to be_present
      expect(data['evidence']['id']).to eq(manifest.id)
      expect(data['evidence']['manifest_type']).to eq('browser_test')
    end

    it 'returns 404 for an unknown id' do
      get "/api/v1/ai/code_factory/evidence/#{SecureRandom.uuid}", headers: headers, as: :json

      expect_error_response('Evidence manifest not found', 404)
    end

    it 'does not expose evidence manifests from another account' do
      other = create(:ai_code_factory_evidence_manifest, account: create(:account))

      get "/api/v1/ai/code_factory/evidence/#{other.id}", headers: headers, as: :json

      expect_error_response('Evidence manifest not found', 404)
    end

    it 'forbids users without the read permission' do
      unprivileged = user_without_permissions(account: account)

      get "/api/v1/ai/code_factory/evidence/#{manifest.id}",
          headers: auth_headers_for(unprivileged), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
