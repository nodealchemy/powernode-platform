# frozen_string_literal: true

require "rails_helper"

# IMP-9370797fac9f — the setup wizard's AI step must end with a WORKING provider:
# models synced, provider active, and never a key attached to the synthetic
# Claude Code local-sessions scope.
RSpec.describe "Api::V1::Ai::ProviderCredentials onboarding sync", type: :request do
  let(:account) { create(:account) }
  let(:user) do
    create(:user, account: account,
                  permissions: %w[ai.providers.read admin.ai.providers.read ai.providers.create ai.providers.update ai.credentials.create ai.credentials.read])
  end
  let(:headers) { auth_headers_for(user) }
  # Obviously fake — never a real key shape.
  let(:fake_secret) { "sk-ant-fake-placeholder-not-real" }
  let(:models_url) { "https://api.anthropic.com/v1/models" }

  let!(:provider) do
    create(:ai_provider, account: account, provider_type: "anthropic", name: "Real Anthropic",
                         slug: "real-anthropic", is_active: false, supported_models: [],
                         metadata: {})
  end

  before do
    allow_any_instance_of(Ai::ProviderManagementService)
      .to receive(:test_with_details_simple).and_return({ success: true })
  end

  def stub_models(status: 200)
    body = status == 200 ? { data: [ { id: "synced-model-a", display_name: "A" }, { id: "synced-model-b", display_name: "B" } ] } : { error: "denied" }
    stub_request(:get, models_url).to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def create_credential(target = provider)
    post "/api/v1/ai/providers/#{target.id}/credentials",
         params: { credential: { name: "Onboarding", credentials: { api_key: fake_secret }, is_active: true, is_default: true } },
         headers: headers, as: :json
  end

  describe "POST /ai/providers/:id/credentials" do
    it "syncs the models, activates the provider and reports the count" do
      stub_models

      create_credential

      expect(response).to have_http_status(:created)
      sync = json_response_data["model_sync"]
      expect(sync).to include("success" => true, "model_count" => 2)
      provider.reload
      expect(provider.is_active).to be(true)
      expect(provider.supported_models.map { |m| m["id"] }).to contain_exactly("synced-model-a", "synced-model-b")
    end

    it "runs the credential test AFTER the sync, against the synced default chat model" do
      stub_models
      seen = nil
      allow_any_instance_of(Ai::ProviderManagementService).to receive(:test_with_details_simple) do |svc|
        seen = svc.instance_variable_get(:@provider).reload.default_model
        { success: true }
      end

      create_credential

      expect(seen).to eq("synced-model-a")
    end

    it "never returns the key" do
      stub_models

      create_credential

      expect(response.body).not_to include(fake_secret)
    end

    it "reports a failed sync in the response instead of swallowing it" do
      stub_models(status: 401)

      create_credential

      expect(response).to have_http_status(:created)
      sync = json_response_data["model_sync"]
      expect(sync["success"]).to be(false)
      expect(sync["error"]).to be_present
      expect(response.body).not_to include(fake_secret)
      expect(provider.reload.is_active).to be(false)
    end

    it "makes the first working provider the account default" do
      stub_models

      create_credential

      expect(json_response_data["model_sync"]["default"]).to be(true)
      expect(provider.reload.metadata["is_default"]).to be(true)
      expect(provider.priority_order).to eq(1)
    end
  end

  describe "a bad key on a provider that already works" do
    let(:other_secret) { "sk-ant-fake-second-placeholder" }

    before do
      stub_request(:get, models_url).with(headers: { "X-Api-Key" => fake_secret })
        .to_return(status: 200, body: { data: [ { id: "synced-model-a" } ] }.to_json, headers: { "Content-Type" => "application/json" })
      stub_request(:get, models_url).with(headers: { "X-Api-Key" => other_secret })
        .to_return(status: 401, body: { error: "denied" }.to_json, headers: { "Content-Type" => "application/json" })
      create_credential
      expect(provider.reload.supported_models).to be_present
    end

    it "keeps the provider active with its models and records the failure on the new credential" do
      post "/api/v1/ai/providers/#{provider.id}/credentials",
           params: { credential: { name: "Second", credentials: { api_key: other_secret }, is_active: true } },
           headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json_response_data["model_sync"]["success"]).to be(false)
      provider.reload
      expect(provider.is_active).to be(true)
      expect(provider.supported_models.map { |m| m["id"] }).to eq([ "synced-model-a" ])
      bad = provider.provider_credentials.find_by(name: "Second")
      expect(bad.consecutive_failures).to be >= 1
    end
  end

  describe "syncing with the credential just saved" do
    it "uses the new credential even when an older active one is stale" do
      old_secret = "sk-ant-fake-stale-placeholder"
      new_secret = "sk-ant-fake-new-placeholder"
      create(:ai_provider_credential, account: account, provider: provider, credentials: { "api_key" => old_secret })
      stub_request(:get, models_url).with(headers: { "X-Api-Key" => old_secret }).to_return(status: 401, body: "{}")
      stub_request(:get, models_url).with(headers: { "X-Api-Key" => new_secret })
        .to_return(status: 200, body: { data: [ { id: "synced-model-a" } ] }.to_json, headers: { "Content-Type" => "application/json" })

      post "/api/v1/ai/providers/#{provider.id}/credentials",
           params: { credential: { name: "Fresh", credentials: { api_key: new_secret }, is_active: true } },
           headers: headers, as: :json

      expect(json_response_data["model_sync"]).to include("success" => true)
      expect(provider.reload.is_active).to be(true)
    end
  end

  describe "provider creation when the upstream is unreachable" do
    it "keeps the provider active with the sync deferred, and flags it for retry" do
      stub_request(:get, "http://localhost:11434/api/tags").to_timeout
      stub_request(:get, "http://localhost:11434/ollama/api/tags").to_timeout

      post "/api/v1/ai/providers",
           params: { provider: { provider_type: "ollama", name: "Slow Ollama", api_base_url: "http://localhost:11434", is_active: true } },
           headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json_response_data["model_sync"]).to include("success" => false, "deferred" => true)
      created = Ai::Provider.find(json_response_data["provider"]["id"])
      expect(created.is_active).to be(true)
      expect(created.supported_models).to be_present
      expect(created.metadata["model_sync_pending_at"]).to be_present
    end
  end

  describe "recovery after a failed create-time sync" do
    it "re-flags an INACTIVE provider for sync when its URL is corrected" do
      parked = create(:ai_provider, account: account, provider_type: "ollama", is_active: false,
                                    api_base_url: "http://localhost:11434", api_endpoint: "http://localhost:11434")

      parked.update!(api_base_url: "http://localhost:11435", api_endpoint: "http://localhost:11435")

      expect(parked.reload.metadata["model_sync_pending_at"]).to be_present
    end
  end

  describe "error text" do
    it "masks query strings (a ?key= credential) in the recorded sync error" do
      masked = Ai::ProviderManagementService.send(
        :record_sync_failure, provider, "GET https://example.test/v1/models?key=fake-query-secret&alt=json failed"
      )

      expect(masked).to be(false)
      expect(provider.reload.metadata["last_sync_error"]).not_to include("fake-query-secret")
      expect(provider.metadata["last_sync_error"]).to include("https://example.test/v1/models")
    end
  end

  describe "POST /ai/providers (creation)" do
    it "syncs the models the moment the provider is created" do
      stub_request(:get, "http://localhost:11434/api/tags")
        .to_return(status: 200, body: { models: [ { "name" => "local-model:1b", "size" => 1, "details" => {} } ] }.to_json,
                   headers: { "Content-Type" => "application/json" })

      post "/api/v1/ai/providers",
           params: { provider: { provider_type: "ollama", name: "Local Ollama", api_base_url: "http://localhost:11434" } },
           headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json_response_data["model_sync"]).to include("success" => true, "model_count" => 1)
      created = Ai::Provider.find(json_response_data["provider"]["id"])
      expect(created.supported_models.map { |m| m["id"] || m["name"] }).to include("local-model:1b")
    end

    it "defers (without a request) for a type that needs a credential first" do
      post "/api/v1/ai/providers", params: { provider: { provider_type: "openai", name: "OpenAI Real" } },
                                   headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json_response_data["model_sync"]).to include("success" => false, "deferred" => true)
    end
  end

  describe "the Claude Code local-sessions scope" do
    let!(:scope) { Ai::ClaudeExport::ProviderScopeSeeder.ensure_for!(account) }

    it "refuses a credential and creates none" do
      expect { create_credential(scope) }.not_to change(Ai::ProviderCredential, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).not_to include(fake_secret)
    end

    it "is left out of the provider lookup when platform_routable is requested" do
      get "/api/v1/ai/providers", params: { provider_type: "anthropic", platform_routable: true }, headers: headers

      ids = json_response_data["items"].map { |i| i["id"] }
      expect(ids).to include(provider.id)
      expect(ids).not_to include(scope.id)
    end
  end
end
