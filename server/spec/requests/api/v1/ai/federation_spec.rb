# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::Federation', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.agents.read', 'ai.agents.create', 'ai.agents.update', 'ai.agents.delete']) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, account: other_account, permissions: ['ai.agents.read']) }

  let(:headers) { auth_headers_for(user) }
  let(:other_headers) { auth_headers_for(other_user) }

  describe 'GET /api/v1/ai/federation/partners' do
    let!(:partner1) { create(:federation_partner, account: account) }
    let!(:partner2) { create(:federation_partner, :active, account: account) }
    let!(:other_partner) { create(:federation_partner, account: other_account) }

    context 'with authentication' do
      it 'returns list of federation partners for current account' do
        get '/api/v1/ai/federation/partners', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['items']).to be_an(Array)
        expect(data['items'].length).to eq(2)
        expect(data['items'].none? { |p| p['id'] == other_partner.id }).to be true
      end

      it 'includes pagination metadata' do
        get '/api/v1/ai/federation/partners', headers: headers, as: :json

        data = json_response_data
        expect(data['pagination']).to include('current_page', 'total_count', 'total_pages')
      end

      it 'filters by status' do
        get '/api/v1/ai/federation/partners?status=active', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        statuses = data['items'].map { |p| p['status'] }
        expect(statuses.uniq).to eq(['active'])
      end

      it 'supports pagination' do
        get '/api/v1/ai/federation/partners?page=1&per_page=1', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['pagination']).to include(
          'current_page' => 1,
          'per_page' => 1
        )
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/ai/federation/partners', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/ai/federation/partners/:id' do
    let(:partner) { create(:federation_partner, account: account) }

    context 'with authentication' do
      it 'returns partner details' do
        get "/api/v1/ai/federation/partners/#{partner.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['partner']).to include(
          'id' => partner.id,
          'name' => partner.name
        )
      end

      it 'returns not found for non-existent partner' do
        get "/api/v1/ai/federation/partners/#{SecureRandom.uuid}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'accessing partner from different account' do
      let(:other_partner) { create(:federation_partner, account: other_account) }

      it 'returns not found error' do
        get "/api/v1/ai/federation/partners/#{other_partner.id}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/ai/federation/partners' do
    let(:valid_params) do
      {
        partner: {
          organization_name: 'Test Federation Org',
          organization_id: "test-org-#{SecureRandom.hex(4)}",
          endpoint_url: 'https://partner.example.com/a2a',
          contact_email: 'admin@partner.example.com',
          trust_level: 3
        }
      }
    end

    context 'with valid params' do
      it 'creates a new federation partner' do
        expect {
          post '/api/v1/ai/federation/partners', params: valid_params, headers: headers, as: :json
        }.to change { account.federation_partners.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['partner']).to be_present
        expect(data['partner']['name']).to eq('Test Federation Org')
      end

      it 'sets the current user as initiator' do
        post '/api/v1/ai/federation/partners', params: valid_params, headers: headers, as: :json

        expect_success_response
        partner = FederationPartner.last
        expect(partner.created_by_id).to eq(user.id)
      end
    end

    context 'with invalid params' do
      it 'returns validation error for missing organization_id' do
        invalid_params = { partner: { organization_name: 'Test' } }

        post '/api/v1/ai/federation/partners', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/ai/federation/partners', params: valid_params, as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/ai/federation/partners/:id' do
    let(:partner) { create(:federation_partner, account: account) }

    context 'with valid params' do
      it 'updates the partner' do
        patch "/api/v1/ai/federation/partners/#{partner.id}",
              params: { partner: { trust_level: 4 } },
              headers: headers,
              as: :json

        expect_success_response
        data = json_response_data
        expect(data['partner']['trust_level']).to eq(4)
      end
    end

    context 'accessing partner from different account' do
      let(:other_partner) { create(:federation_partner, account: other_account) }

      it 'returns not found error' do
        patch "/api/v1/ai/federation/partners/#{other_partner.id}",
              params: { partner: { trust_level: 5 } },
              headers: headers,
              as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE /api/v1/ai/federation/partners/:id' do
    let(:partner) { create(:federation_partner, account: account) }

    context 'with authentication' do
      it 'deletes the partner' do
        partner_id = partner.id

        delete "/api/v1/ai/federation/partners/#{partner_id}", headers: headers, as: :json

        expect_success_response
        expect(FederationPartner.find_by(id: partner_id)).to be_nil
      end
    end

    context 'accessing partner from different account' do
      let(:other_partner) { create(:federation_partner, account: other_account) }

      it 'returns not found error' do
        delete "/api/v1/ai/federation/partners/#{other_partner.id}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/ai/federation/partners/:id/verify' do
    let(:partner) { create(:federation_partner, account: account) }

    context 'with successful verification' do
      it 'verifies the partner connection' do
        allow_any_instance_of(FederationPartner).to receive(:verify_connection!)
          .and_return({ success: true })

        post "/api/v1/ai/federation/partners/#{partner.id}/verify",
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to include('verified')
      end
    end

    context 'with failed verification' do
      it 'returns error' do
        allow_any_instance_of(FederationPartner).to receive(:verify_connection!)
          .and_return({ success: false, error: 'Connection timed out' })

        post "/api/v1/ai/federation/partners/#{partner.id}/verify",
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'GET /api/v1/ai/federation/partners/:id/agents' do
    let(:partner) { create(:federation_partner, :active, account: account, approved_at: 1.day.ago) }

    context 'when partner is verified' do
      it 'returns agents from the partner' do
        allow_any_instance_of(FederationPartner).to receive(:fetch_agents)
          .and_return({ success: true, agents: [{ name: 'Remote Agent', category: 'automation' }] })

        get "/api/v1/ai/federation/partners/#{partner.id}/agents",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data['agents']).to be_an(Array)
      end
    end

    context 'when partner is not verified' do
      let(:unverified_partner) { create(:federation_partner, account: account) }

      it 'returns error' do
        get "/api/v1/ai/federation/partners/#{unverified_partner.id}/agents",
            headers: headers,
            as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'POST /api/v1/ai/federation/partners/:id/sync' do
    let(:partner) { create(:federation_partner, :active, account: account) }

    context 'with successful sync' do
      it 'syncs agents from the partner' do
        allow_any_instance_of(FederationPartner).to receive(:sync_agents!)
          .and_return({ success: true, count: 5 })

        post "/api/v1/ai/federation/partners/#{partner.id}/sync",
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to include('Synced')
      end
    end

    context 'with failed sync' do
      it 'returns error' do
        allow_any_instance_of(FederationPartner).to receive(:sync_agents!)
          .and_return({ success: false, error: 'Connection refused' })

        post "/api/v1/ai/federation/partners/#{partner.id}/sync",
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'POST /api/v1/ai/federation/register' do
    context 'with valid registration data' do
      let(:registration_params) do
        {
          organization_name: 'External Org',
          organization_id: "ext-org-#{SecureRandom.hex(4)}",
          endpoint_url: 'https://external.example.com/a2a',
          contact_email: 'admin@external.example.com'
        }
      end

      it 'registers an external federation partner' do
        post '/api/v1/ai/federation/register',
             params: registration_params,
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to include('Registration received')
        expect(data['status']).to eq('pending_verification')
      end
    end

    context 'with missing required fields' do
      it 'returns error' do
        post '/api/v1/ai/federation/register',
             params: { organization_name: 'Test' },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'POST /api/v1/ai/federation/verify_key' do
    context 'with valid federation key' do
      let(:partner) { create(:federation_partner, :active, account: account) }

      it 'verifies the key and returns organization info' do
        allow(FederationPartner).to receive(:find_by).and_return(partner)

        post '/api/v1/ai/federation/verify_key',
             params: { federation_key: 'valid-key' },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['valid']).to be true
      end
    end

    context 'with invalid federation key' do
      it 'returns valid: false' do
        post '/api/v1/ai/federation/verify_key',
             params: { federation_key: 'invalid-key' },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['valid']).to be false
      end
    end
  end

  describe 'GET /api/v1/ai/federation/discover' do
    context 'with active federation partners' do
      it 'discovers agents across federated partners' do
        get '/api/v1/ai/federation/discover', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['agents']).to be_an(Array)
      end
    end
  end

  # Account isolation
  describe 'account isolation' do
    let(:own_partner) { create(:federation_partner, account: account) }
    let(:other_partner) { create(:federation_partner, account: other_account) }

    it 'cannot access partners from another account via show' do
      get "/api/v1/ai/federation/partners/#{other_partner.id}", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'cannot update partners from another account' do
      patch "/api/v1/ai/federation/partners/#{other_partner.id}",
            params: { partner: { trust_level: 5 } },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'cannot delete partners from another account' do
      delete "/api/v1/ai/federation/partners/#{other_partner.id}", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'cannot verify partners from another account' do
      post "/api/v1/ai/federation/partners/#{other_partner.id}/verify",
           headers: headers,
           as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
