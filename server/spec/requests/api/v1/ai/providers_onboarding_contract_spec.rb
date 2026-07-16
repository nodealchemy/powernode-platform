# frozen_string_literal: true

require 'rails_helper'

# Regression coverage for the AI-provider onboarding wizard contract: the
# wizard POSTs only { provider_type, name } (see frontend onboarding), and
# Ai::Provider validates presence of api_endpoint/capabilities/
# supported_models/configuration_schema. Ai::ProviderCatalog fills those in
# for known provider_types so the minimal payload succeeds.
RSpec.describe 'Api::V1::Ai::Providers onboarding contract', type: :request do
  let(:account) { create(:account) }
  let(:user_with_create_permission) { create(:user, account: account, permissions: [ 'ai.providers.read', 'ai.providers.create' ]) }
  let(:headers) { auth_headers_for(user_with_create_permission) }

  describe 'POST /api/v1/ai/providers with the wizard minimal payload' do
    context 'provider_type: openai' do
      let(:params) do
        { provider: { provider_type: 'openai', name: 'OpenAI' } }
      end

      it 'creates the provider filled in from the catalog' do
        expect {
          post '/api/v1/ai/providers', params: params, headers: headers, as: :json
        }.to change(Ai::Provider, :count).by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data

        provider = Ai::Provider.find(data['provider']['id'])
        expect(provider).to be_valid
        expect(provider.name).to eq('OpenAI')
        expect(provider.provider_type).to eq('openai')
        expect(provider.api_endpoint).to eq('https://api.openai.com/v1/chat/completions')
        expect(provider.capabilities).to be_present
        expect(provider.supported_models).to be_present
        expect(provider.configuration_schema).to be_present
      end
    end

    context 'provider_type: anthropic' do
      let(:params) do
        { provider: { provider_type: 'anthropic', name: 'Claude' } }
      end

      it 'creates the provider filled in from the catalog' do
        expect {
          post '/api/v1/ai/providers', params: params, headers: headers, as: :json
        }.to change(Ai::Provider, :count).by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data

        provider = Ai::Provider.find(data['provider']['id'])
        expect(provider).to be_valid
        expect(provider.name).to eq('Claude')
        expect(provider.provider_type).to eq('anthropic')
        expect(provider.api_endpoint).to eq('https://api.anthropic.com/v1/messages')
        expect(provider.capabilities).to be_present
        expect(provider.supported_models).to be_present
        expect(provider.configuration_schema).to be_present
      end
    end

    context 'provider_type: totally_unknown_xyz (no catalog entry)' do
      let(:params) do
        { provider: { provider_type: 'totally_unknown_xyz', name: 'X' } }
      end

      it 'still returns 422 — the catalog cannot fill unknown provider types' do
        expect {
          post '/api/v1/ai/providers', params: params, headers: headers, as: :json
        }.not_to change(Ai::Provider, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end
