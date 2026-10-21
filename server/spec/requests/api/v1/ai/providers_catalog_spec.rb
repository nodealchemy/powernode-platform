# frozen_string_literal: true

require 'rails_helper'

# Read-only provider-type catalog: the single source the setup wizard and the
# AI providers page use to auto-fill the provider form on type selection.
RSpec.describe 'Api::V1::Ai::Providers catalog', type: :request do
  let(:account) { create(:account) }
  let(:reader) { create(:user, account: account, permissions: [ 'ai.providers.read' ]) }
  let(:nobody) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/ai/providers/catalog' do
    it 'returns every known type with the auto-fill fields' do
      get '/api/v1/ai/providers/catalog', headers: auth_headers_for(reader), as: :json

      expect(response).to have_http_status(:ok)
      items = json_response_data['items']
      expect(items.map { |i| i['provider_type'] }).to contain_exactly('openai', 'grok', 'ollama', 'anthropic')

      openai = items.find { |i| i['provider_type'] == 'openai' }
      expect(openai).to include('name' => 'OpenAI', 'slug' => 'openai', 'api_base_url' => 'https://api.openai.com/v1')
      expect(openai['capabilities']).to include('text_embedding')
      expect(openai['default_model']).to be_present
      expect(openai['requires_auth']).to be(true)
      expect(openai['credential_fields'].map { |f| f['key'] }).to include('api_key')
      expect(openai['credential_fields'].find { |f| f['key'] == 'api_key' }['type']).to eq('password')
    end

    it 'describes Ollama as base-url shaped with no API key' do
      get '/api/v1/ai/providers/catalog', headers: auth_headers_for(reader), as: :json

      ollama = json_response_data['items'].find { |i| i['provider_type'] == 'ollama' }
      expect(ollama['requires_auth']).to be(false)
      keys = ollama['credential_fields'].map { |f| f['key'] }
      expect(keys).to include('base_url')
      expect(keys).not_to include('api_key')
    end

    it 'never carries secrets or env key names' do
      get '/api/v1/ai/providers/catalog', headers: auth_headers_for(reader), as: :json

      body = response.body
      expect(body).not_to match(/api_key_env|_API_KEY"/)
      expect(json_response_data['items'].flat_map(&:keys)).not_to include('api_key', 'credentials', 'metadata')
    end

    it 'serves the backend known capability list and keeps every type within it' do
      get '/api/v1/ai/providers/catalog', headers: auth_headers_for(reader), as: :json

      known = json_response_data['known_capabilities']
      expect(known).to eq(Ai::Provider::KNOWN_CAPABILITIES)
      expect(known).not_to include('embeddings')
      json_response_data['items'].each do |item|
        expect(item['capabilities'] - known).to be_empty, item['provider_type']
      end
    end

    it 'is permission gated' do
      get '/api/v1/ai/providers/catalog', headers: auth_headers_for(nobody), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
