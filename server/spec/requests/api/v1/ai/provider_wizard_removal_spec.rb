# frozen_string_literal: true

require "rails_helper"

# The wizard removes an AI entry by deleting the provider it created. The
# credential it saved is default-and-only, which used to block the delete with a
# 422 (and, had it succeeded, left a dead default).
RSpec.describe "Wizard AI provider add and remove", type: :request do
  let(:account) { create(:account) }
  let(:user) do
    create(:user, account: account,
                  permissions: %w[ai.providers.read admin.ai.providers.read ai.providers.create ai.providers.update
                                  ai.providers.delete ai.credentials.create ai.credentials.read ai.credentials.delete])
  end
  let(:headers) { auth_headers_for(user) }
  let(:fake_secret) { "sk-ant-fake-placeholder-not-real" }

  before do
    allow_any_instance_of(Ai::ProviderManagementService).to receive(:test_with_details_simple).and_return({ success: true })
    stub_request(:get, "https://api.anthropic.com/v1/models")
      .to_return(status: 200, body: { data: [ { id: "synced-model-a" } ] }.to_json, headers: { "Content-Type" => "application/json" })
  end

  def add_entry
    post "/api/v1/ai/providers", params: { provider: { provider_type: "anthropic", name: "Claude AI (Anthropic)" }, dedupe_name: true },
                                 headers: headers, as: :json
    expect(response).to have_http_status(:created)
    provider_id = json_response_data["provider"]["id"]
    post "/api/v1/ai/providers/#{provider_id}/credentials",
         params: { credential: { name: "Onboarding", credentials: { api_key: fake_secret }, is_active: true, is_default: true } },
         headers: headers, as: :json
    expect(response).to have_http_status(:created)
    provider_id
  end

  it "gives each entry its own provider row, deduplicating the name" do
    first = add_entry
    second = add_entry

    expect(first).not_to eq(second)
    names = account.ai_providers.where(provider_type: "anthropic").pluck(:name)
    expect(names).to contain_exactly("Claude AI (Anthropic)", "Claude AI (Anthropic) (2)")
  end

  it "removes the provider with its default-only credential, without a 422" do
    provider_id = add_entry

    delete "/api/v1/ai/providers/#{provider_id}", headers: headers

    expect(response).to have_http_status(:ok)
    expect(Ai::Provider.where(id: provider_id)).to be_empty
    expect(Ai::ProviderCredential.where(ai_provider_id: provider_id)).to be_empty
  end

  it "leaves a working default behind when the default entry is removed" do
    first = add_entry
    second = add_entry
    expect(Ai::Provider.default_for_account(account).id).to eq(first)

    delete "/api/v1/ai/providers/#{first}", headers: headers

    expect(response).to have_http_status(:ok)
    expect(Ai::Provider.default_for_account(account).id).to eq(second)
  end

  it "heals the default when its credential is deleted through the API" do
    first = add_entry
    second = add_entry
    first_credential = Ai::ProviderCredential.find_by(ai_provider_id: first)
    create(:ai_provider_credential, account: account, provider: Ai::Provider.find(first), is_active: false)

    delete "/api/v1/ai/providers/#{first}/credentials/#{first_credential.id}", headers: headers

    expect(Ai::Provider.default_for_account(account)&.id).to eq(second)
  end

  describe "claiming an unconfigured seeded row" do
    def seeded(type: "anthropic", name: "Claude AI (Anthropic)", **extra)
      create(:ai_provider, account: account, provider_type: type, name: name, is_active: true, **extra)
    end

    def post_entry(name: "My Claude", base_url: "https://api.example-anthropic.test/v1")
      post "/api/v1/ai/providers",
           params: { provider: { provider_type: "anthropic", name: name, api_base_url: base_url }, dedupe_name: true },
           headers: headers, as: :json
      expect(response).to have_http_status(:created)
      Ai::Provider.find(json_response_data["provider"]["id"])
    end

    it "takes over a same-type row with no credentials and no customisation, updating name and base URL" do
      row = seeded

      claimed = post_entry
      expect(json_response_data["claimed"]).to be(true)

      expect(claimed.id).to eq(row.id)
      expect(claimed.reload.name).to eq("My Claude")
      expect(claimed.api_base_url).to eq("https://api.example-anthropic.test/v1")
      expect(account.ai_providers.where(provider_type: "anthropic").count).to eq(1)
    end

    it "reports a row it created as not claimed" do
      row = seeded
      create(:ai_provider_credential, account: account, provider: row)

      post_entry

      expect(json_response_data["claimed"]).to be(false)
    end

    it "claims inside a lock that skips rows another request holds, so two entries never share a row" do
      first = seeded(name: "Seeded A")
      second = seeded(name: "Seeded B")
      statements = []
      callback = ->(*, payload) { statements << payload[:sql] if payload[:sql].include?("SKIP LOCKED") }

      ids = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        [ post_entry(name: "Entry One").id, post_entry(name: "Entry Two").id ]
      end

      expect(statements).not_to be_empty
      expect(ids).to contain_exactly(first.id, second.id)
    end

    it "does not claim a row that has a credential" do
      row = seeded
      create(:ai_provider_credential, account: account, provider: row)

      expect(post_entry.id).not_to eq(row.id)
    end

    it "does not claim the default, a synced row, or the Claude Code scope" do
      default_row = seeded(name: "Default One", metadata: { "is_default" => true })
      synced_row = seeded(name: "Synced One", metadata: { "last_sync_error" => "denied" })
      scope = Ai::ClaudeExport::ProviderScopeSeeder.ensure_for!(account)

      created = post_entry

      expect([ default_row.id, synced_row.id, scope.id ]).not_to include(created.id)
    end

    it "numbers a new row only when every same-type row is configured" do
      row = seeded
      create(:ai_provider_credential, account: account, provider: row)

      post_entry(name: "Claude AI (Anthropic)")

      expect(account.ai_providers.where(provider_type: "anthropic").pluck(:name))
        .to contain_exactly("Claude AI (Anthropic)", "Claude AI (Anthropic) (2)")
    end
  end

  describe "releasing a claimed row (the wizard did not create it)" do
    let!(:row) do
      create(:ai_provider, account: account, provider_type: "anthropic", name: "Claude AI (Anthropic)",
                           api_base_url: "https://api.anthropic.com/v1", is_active: true)
    end

    def claim_and_configure
      post "/api/v1/ai/providers",
           params: { provider: { provider_type: "anthropic", name: "My Claude", api_base_url: "https://proxy.example-anthropic.test/v1" }, dedupe_name: true },
           headers: headers, as: :json
      expect(json_response_data["claimed"]).to be(true)
      post "/api/v1/ai/providers/#{row.id}/credentials",
           params: { credential: { name: "Onboarding", credentials: { api_key: fake_secret }, is_active: true, is_default: true } },
           headers: headers, as: :json
      expect(response).to have_http_status(:created)
    end

    it "restores the catalog name and base URL, removes the credential and clears the default, keeping the row" do
      claim_and_configure
      expect(row.reload.metadata["is_default"]).to be(true)

      post "/api/v1/ai/providers/#{row.id}/release", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      row.reload
      expect(row.name).to eq("Claude AI (Anthropic)")
      expect(row.api_base_url).to eq("https://api.anthropic.com/v1")
      expect(row.provider_credentials).to be_empty
      expect(row.metadata["is_default"]).to be(false)
      expect(row.metadata).not_to have_key("claimed_from")
    end

    it "can be claimed again after a release" do
      claim_and_configure
      post "/api/v1/ai/providers/#{row.id}/release", headers: headers, as: :json

      post "/api/v1/ai/providers",
           params: { provider: { provider_type: "anthropic", name: "Again" }, dedupe_name: true }, headers: headers, as: :json

      expect(json_response_data["provider"]["id"]).to eq(row.id)
    end

    it "refuses to release a provider the wizard did not claim" do
      post "/api/v1/ai/providers/#{row.id}/release", headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "is gated by the update permission and scoped to the account" do
      claim_and_configure
      reader = create(:user, account: account, permissions: %w[ai.providers.read])
      stranger = create(:user, account: create(:account), permissions: %w[ai.providers.read ai.providers.update])

      post "/api/v1/ai/providers/#{row.id}/release", headers: auth_headers_for(reader), as: :json
      expect(response).to have_http_status(:forbidden)

      post "/api/v1/ai/providers/#{row.id}/release", headers: auth_headers_for(stranger), as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "removing a provider that has resolver-minted clones" do
    let(:creator) { user }

    def clone_on(provider)
      create(:ai_agent, account: account, creator: creator, provider: provider,
                        cloned_from_id: create(:ai_agent, :global, owner_account: account).id)
    end

    it "deletes the only provider by removing its idle clones, which re-mint on demand" do
      provider_id = add_entry
      clone = clone_on(Ai::Provider.find(provider_id))

      delete "/api/v1/ai/providers/#{provider_id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(Ai::Provider.where(id: provider_id)).to be_empty
      expect(Ai::Agent.where(id: clone.id)).to be_empty
    end

    it "answers 409 naming the agent when a clone has conversations, and removes nothing" do
      provider_id = add_entry
      clone = clone_on(Ai::Provider.find(provider_id))
      create(:ai_conversation, account: account, agent: clone, user: user, provider: Ai::Provider.find(provider_id))

      delete "/api/v1/ai/providers/#{provider_id}", headers: headers

      expect(response).to have_http_status(:conflict)
      expect(response.body).to include(clone.name)
      expect(Ai::Provider.where(id: provider_id)).to exist
      expect(Ai::Agent.where(id: clone.id)).to exist
    end

    it "moves clones to another working provider instead, when there is one" do
      first = add_entry
      second = add_entry
      clone = clone_on(Ai::Provider.find(first))

      delete "/api/v1/ai/providers/#{first}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(clone.reload.ai_provider_id).to eq(second)
    end
  end
end
