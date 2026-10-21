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
end
