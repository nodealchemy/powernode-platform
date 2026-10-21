# frozen_string_literal: true

require "rails_helper"

# IMP-9370797fac9f — the operator picks the account's default AI provider. The
# choice reuses the existing mechanism (priority_order 1 + metadata is_default)
# rather than a parallel flag, and only a provider whose model sync succeeded
# can be chosen.
RSpec.describe "Api::V1::Ai::Providers default", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: %w[ai.providers.read ai.providers.update]) }
  let(:headers) { auth_headers_for(user) }

  def working_provider(name, order)
    create(:ai_provider, account: account, name: name, provider_type: "custom", priority_order: order, is_active: true).tap do |p|
      create(:ai_provider_credential, account: account, provider: p)
    end
  end

  let!(:provider_a) { working_provider("Provider A", 1).tap { |p| p.update_columns(metadata: { "is_default" => true }) } }
  let!(:provider_b) { working_provider("Provider B", 2) }

  describe "POST /api/v1/ai/providers/:id/make_default" do
    it "makes B the default through priority_order and the is_default flag" do
      post "/api/v1/ai/providers/#{provider_b.id}/make_default", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(provider_b.reload.priority_order).to eq(1)
      expect(provider_b.metadata["is_default"]).to be(true)
      expect(provider_a.reload.priority_order).to be > 1
      expect(provider_a.metadata["is_default"]).to be(false)
      expect(account.ai_providers.ordered_by_priority.first).to eq(provider_b)
      expect(Ai::Provider.default_for_account(account)).to eq(provider_b)
    end

    it "is reported by the providers listing" do
      post "/api/v1/ai/providers/#{provider_b.id}/make_default", headers: headers, as: :json

      get "/api/v1/ai/providers", headers: headers
      defaults = json_response_data["items"].select { |i| i["is_default"] }
      expect(defaults.map { |i| i["id"] }).to eq([ provider_b.id ])
    end

    it "refuses a provider whose model sync failed" do
      failed = working_provider("Failed", 3)
      failed.update_columns(is_active: false, supported_models: [], metadata: { "last_sync_error" => "denied" })

      post "/api/v1/ai/providers/#{failed.id}/make_default", headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(account.ai_providers.ordered_by_priority.first).to eq(provider_a)
    end

    it "refuses a provider with no credential" do
      bare = create(:ai_provider, account: account, name: "Bare", priority_order: 4, is_active: true)

      post "/api/v1/ai/providers/#{bare.id}/make_default", headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "requires the update permission" do
      reader = create(:user, account: account, permissions: %w[ai.providers.read])

      post "/api/v1/ai/providers/#{provider_b.id}/make_default", headers: auth_headers_for(reader), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "does not reach another account's provider" do
      foreign = create(:ai_provider, account: create(:account))

      post "/api/v1/ai/providers/#{foreign.id}/make_default", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
