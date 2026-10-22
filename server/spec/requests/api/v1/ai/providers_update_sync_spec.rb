# frozen_string_literal: true

require 'rails_helper'

# PATCH /api/v1/ai/providers/:id syncs models inline when the edit touches the
# connection (base URL, endpoint, type) or turns the provider on. Enabling
# saves every other edit first, then syncs; it activates only on a sync that
# returned models, and otherwise answers 422 with the sync's reason.
RSpec.describe 'Api::V1::Ai::Providers update syncs models', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'ai.providers.read', 'ai.providers.update' ]) }
  let(:headers) { auth_headers_for(user) }
  let(:provider) { create(:ai_provider, :ollama, account: account) }
  let(:old_models) { provider.supported_models }
  let(:new_url) { 'http://ollama.internal:11434' }
  let(:tags_body) do
    { models: [
      { name: 'llama3:latest', size: 4_000_000_000, details: { family: 'llama', parameter_size: '8B' } },
      { name: 'qwen2:latest', size: 2_000_000_000, details: { family: 'qwen2', parameter_size: '7B' } }
    ] }.to_json
  end

  def stub_tags_ok
    stub_request(:get, "#{new_url}/api/tags")
      .to_return(status: 200, body: tags_body, headers: { 'Content-Type' => 'application/json' })
  end

  def stub_tags_down
    stub_request(:get, /ollama\.internal/).to_return(status: 502, body: 'bad gateway')
  end

  # Creating the provider flags it for the sweep; start each example clean so
  # the flag assertions measure the PATCH alone.
  before { provider.clear_model_sync_pending! }

  def patch_provider(attrs)
    patch "/api/v1/ai/providers/#{provider.id}", params: { provider: attrs }, headers: headers, as: :json
  end

  def body
    JSON.parse(response.body)
  end

  # The state a provider lands in after a failed sync: inactive, no models.
  def park_without_models!
    Ai::Provider.where(id: provider.id).update_all(supported_models: [], is_active: false)
    provider.reload
  end

  context 'URL change plus enable on a provider with no models' do
    before { park_without_models! }

    it '(a) syncs, activates and returns the sync outcome when the sync returns models' do
      stub_tags_ok

      patch_provider(api_base_url: new_url, is_active: true)

      expect(response).to have_http_status(:ok)
      provider.reload
      expect(provider.is_active).to be(true)
      expect(provider.api_base_url).to eq(new_url)
      expect(provider.supported_models.map { |m| m['id'] }).to contain_exactly('llama3:latest', 'qwen2:latest')
      expect(body.dig('data', 'model_sync')).to include('success' => true, 'model_count' => 2, 'activated' => true)
      expect(body.dig('data', 'provider', 'is_active')).to be(true)
    end

    it '(e) clears the pending-sync flag when the inline sync succeeds' do
      stub_tags_ok

      patch_provider(api_base_url: new_url, is_active: true)

      expect(response).to have_http_status(:ok)
      expect(provider.reload.metadata).not_to have_key('model_sync_pending_at')
    end

    it '(b) keeps the URL change, stays inactive and answers 422 naming the URL and the reason' do
      stub_tags_down

      patch_provider(api_base_url: new_url, description: 'moved hosts', is_active: true)

      expect(response).to have_http_status(:unprocessable_content)
      provider.reload
      expect(provider.api_base_url).to eq(new_url)
      expect(provider.description).to eq('moved hosts')
      expect(provider.is_active).to be(false)

      expect(body['success']).to be(false)
      expect(body['error']).to include(new_url)
      expect(body['error']).to include('Could not connect to Ollama API')
      expect(body['error']).not_to match(/supported models can't be blank/i)
      expect(body.dig('details', 'model_sync')).to include('success' => false)
      expect(body.dig('details', 'model_sync', 'error')).to be_present
      expect(body.dig('details', 'provider', 'id')).to eq(provider.id)
      expect(body.dig('details', 'provider', 'is_active')).to be(false)
    end

    it '(b) leaves the provider flagged for the worker sweep when the inline sync fails' do
      stub_tags_down

      patch_provider(api_base_url: new_url, is_active: true)

      expect(provider.reload.metadata).to have_key('model_sync_pending_at')
    end

    it 'never puts URL credentials in the 422 message' do
      secret_url = 'http://ops:s3cr3t-pass@ollama.internal:11434'
      stub_tags_down

      patch_provider(api_base_url: secret_url, is_active: true)

      expect(response).to have_http_status(:unprocessable_content)
      expect(body['error']).not_to include('s3cr3t-pass')
      expect(body.dig('details', 'model_sync', 'error')).not_to include('s3cr3t-pass')
      expect(provider.reload.metadata.to_json).not_to include('s3cr3t-pass')
      expect(body['error']).to include('http://ollama.internal:11434')
    end
  end

  context 'URL change on an already-active provider' do
    before { old_models }

    it '(c) keeps it active with its old models and returns 200 with the failed sync' do
      stub_tags_down

      patch_provider(api_base_url: new_url)

      expect(response).to have_http_status(:ok)
      provider.reload
      expect(provider.api_base_url).to eq(new_url)
      expect(provider.is_active).to be(true)
      expect(provider.supported_models).to eq(old_models)
      expect(body.dig('data', 'model_sync')).to include('success' => false)
      expect(body.dig('data', 'model_sync', 'error')).to include('Could not connect to Ollama API')
      expect(provider.metadata).to have_key('model_sync_pending_at')
    end

    it '(e) replaces the models and clears the pending flag on success' do
      stub_tags_ok

      patch_provider(api_base_url: new_url)

      expect(response).to have_http_status(:ok)
      provider.reload
      expect(provider.supported_models.size).to eq(2)
      expect(provider.metadata).not_to have_key('model_sync_pending_at')
      expect(body.dig('data', 'model_sync')).to include('success' => true, 'model_count' => 2)
    end
  end

  context 'edits unrelated to the connection' do
    it '(d) does not sync on a name-only edit' do
      expect(Ai::Providers::ModelSyncAndActivate).not_to receive(:call)

      patch_provider(name: 'Ollama (lab)')

      expect(response).to have_http_status(:ok)
      provider.reload
      expect(provider.name).to eq('Ollama (lab)')
      expect(provider.metadata || {}).not_to have_key('model_sync_pending_at')
      expect(body['data']).not_to have_key('model_sync')
    end

    it 'does not sync on description, priority or rate-limit edits' do
      expect(Ai::Providers::ModelSyncAndActivate).not_to receive(:call)

      patch_provider(description: 'x', priority_order: 3, rate_limits: { requests_per_minute: 10 })

      expect(response).to have_http_status(:ok)
    end
  end

  context 'enabling a type with no live model sync' do
    let(:provider) { create(:ai_provider, account: account, is_active: false) }

    it 'activates on the models it already has, without a sync' do
      expect(Ai::Providers::ModelSyncAndActivate).not_to receive(:call)

      patch_provider(is_active: true)

      expect(response).to have_http_status(:ok)
      expect(provider.reload.is_active).to be(true)
    end
  end
end
