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

    # The inline sync leaves the provider serving its old models only until the
    # background retry: if that retry fails too, the sweep disables it. The
    # answer says so instead of presenting the interim state as settled.
    it '(c) saves, keeps the old models for now, and warns the retry may disable it' do
      stub_tags_down

      patch_provider(api_base_url: new_url)

      expect(response).to have_http_status(:ok)
      provider.reload
      expect(provider.api_base_url).to eq(new_url)
      expect(provider.is_active).to be(true)
      expect(provider.supported_models).to eq(old_models)
      expect(provider.metadata).to have_key('model_sync_pending_at')
      expect(body.dig('data', 'model_sync')).to include('success' => false)
      expect(body.dig('data', 'model_sync', 'error')).to include('Could not connect to Ollama API')
      expect(body.dig('data', 'warning')).to include(new_url)
      expect(body.dig('data', 'warning')).to match(/disabled if the background retry also fails/i)
    end

    # M3: a write that lands while the sync's HTTP call is in flight survives
    # the failed sync's restore.
    it 'keeps a make_default that happened during the failed sync' do
      create(:ai_provider_credential, account: account, provider: provider)
      provider.clear_model_sync_pending!
      stub_request(:get, /ollama\.internal/).to_return do
        Ai::ProviderDefaultService.set_default!(Ai::Provider.find(provider.id)) unless Ai::Provider.find(provider.id).metadata['is_default']
        { status: 502, body: 'bad gateway' }
      end

      patch_provider(api_base_url: new_url)

      expect(response).to have_http_status(:ok)
      provider.reload
      expect(provider.metadata['is_default']).to be(true)
      expect(provider.is_active).to be(true)
      expect(provider.supported_models).to eq(old_models)
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

  context 'enabling a bearer-type provider that has no credential (sync skipped)' do
    let(:provider) { create(:ai_provider, :openai, account: account, is_active: false) }

    it 'activates on the models it already has and reports the sync as skipped' do
      patch_provider(description: 'turn it on', is_active: true)

      expect(response).to have_http_status(:ok)
      provider.reload
      expect(provider.is_active).to be(true)
      expect(provider.description).to eq('turn it on')
      expect(provider.supported_models).to be_present
      expect(body.dig('data', 'model_sync')).to include('success' => false, 'skipped' => true)
      expect(body.dig('data', 'model_sync', 'error')).to match(/no active credential/i)
    end

    it 'refuses with 422 naming the skip reason when there are no models at all' do
      Ai::Provider.where(id: provider.id).update_all(
        supported_models: [], metadata: { 'last_sync_error' => 'stale failure from last week' }
      )

      patch_provider(is_active: true)

      expect(response).to have_http_status(:unprocessable_content)
      expect(body['error']).to match(/no active credential/i)
      expect(body['error']).not_to include('stale failure from last week')
      expect(body.dig('details', 'model_sync', 'error')).to match(/no active credential/i)
      expect(provider.reload.is_active).to be(false)
    end

    it 'enables with a key saved in the same edit: credential first, then the PATCH' do
      stub_request(:get, 'https://api.openai.com/v1/models')
        .to_return(status: 200, body: { data: [ { id: 'gpt-4o' }, { id: 'gpt-4o-mini' } ] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      cred_user = create(:user, account: account,
                                permissions: %w[ai.providers.read ai.providers.update ai.credentials.create])
      cred_headers = auth_headers_for(cred_user)

      post "/api/v1/ai/providers/#{provider.id}/credentials",
           params: { credential: { name: 'Key', credentials: { api_key: 'sk-placeholder-not-real' } } },
           headers: cred_headers, as: :json
      expect(response).to have_http_status(:created)

      patch "/api/v1/ai/providers/#{provider.id}", params: { provider: { is_active: true } },
                                                   headers: cred_headers, as: :json

      expect(response).to have_http_status(:ok)
      provider.reload
      expect(provider.is_active).to be(true)
      expect(provider.provider_credentials.count).to eq(1)
    end
  end

  context 'the stored sync error' do
    before { park_without_models! }

    it 'is cleared by a successful sync' do
      Ai::Provider.where(id: provider.id).update_all(metadata: { 'last_sync_error' => 'old', 'last_sync_failed_at' => 1.day.ago.iso8601 })
      stub_tags_ok

      patch_provider(api_base_url: new_url, is_active: true)

      expect(response).to have_http_status(:ok)
      expect(provider.reload.metadata.keys).not_to include('last_sync_error', 'last_sync_failed_at')
    end
  end

  context 'becoming the account default' do
    before do
      park_without_models!
      create(:ai_provider_credential, account: account, provider: provider)
      provider.clear_model_sync_pending!
    end

    it 'says so when enabling made it the default' do
      stub_tags_ok

      patch_provider(api_base_url: new_url, is_active: true)

      expect(response).to have_http_status(:ok)
      expect(provider.reload.metadata['is_default']).to be(true)
      expect(body.dig('data', 'became_default')).to be(true)
    end
  end

  context 'audit trail' do
    before { park_without_models! }

    it 'marks a refused activation on the update audit row' do
      stub_tags_down

      patch_provider(api_base_url: new_url, is_active: true)

      row = AuditLog.where(action: 'ai.providers.update', resource_id: provider.id).order(:created_at).last
      expect(row.metadata).to include('activation_refused' => true)
      expect(row.metadata['changes']).to include('api_base_url')
    end
  end

  context 'logs' do
    before { park_without_models! }

    # The sync's own log lines (app/services), not ActiveRecord's SQL echo of
    # the stored column, which the test environment logs at debug.
    it 'never log the credentials of the base URL' do
      logged = []
      %i[debug info warn error].each do |level|
        allow(Rails.logger).to receive(level).and_wrap_original do |original, *args, &blk|
          from_services = caller_locations(1, 20).any? { |l| l.path.include?('/app/services/') }
          logged << (args.first || blk&.call).to_s if from_services
          original.call(*args, &blk)
        end
      end
      stub_tags_down

      patch_provider(api_base_url: 'http://ops:p@ss-s3cr3t@ollama.internal:11434', is_active: true)

      expect(logged.join("\n")).to include('ollama.internal')
      expect(logged.join("\n")).not_to include('s3cr3t')
    end
  end

  context 'changing to a type with no live sync while enabling' do
    before do
      old_models
      Ai::Provider.where(id: provider.id).update_all(is_active: false)
    end

    it 'activates on the supplied models and does not flag the sweep to overwrite them' do
      patch_provider(provider_type: 'custom', is_active: true)

      expect(response).to have_http_status(:ok)
      provider.reload
      expect(provider.is_active).to be(true)
      expect(provider.supported_models).to eq(old_models)
      expect(provider.metadata || {}).not_to have_key('model_sync_pending_at')
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
