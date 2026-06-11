# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Ai::ProviderSync", type: :request do
  let(:user) { user_with_permissions("ai.providers.update") }
  let(:provider) do
    create(:ai_provider, account: user.account, provider_type: "ollama",
           api_base_url: "http://localhost:11434",
           api_endpoint: "http://localhost:11434")
  end

  describe "POST /api/v1/ai/providers/:id/sync_models" do
    context "with an inactive provider that has no models (activation deadlock)" do
      before do
        provider.update_columns(is_active: false, supported_models: [])
      end

      it "syncs models for the inactive provider so it can be activated" do
        stub_request(:get, "http://localhost:11434/api/tags")
          .to_return(status: 200,
                     body: { models: [{ "name" => "llama3:8b", "size" => 1, "details" => {} }] }.to_json,
                     headers: { "Content-Type" => "application/json" })

        post "/api/v1/ai/providers/#{provider.id}/sync_models", headers: auth_headers_for(user)

        expect_success_response
        expect(provider.reload.supported_models).to be_present
      end

      it "surfaces the recorded failure reason when the upstream is unreachable" do
        stub_request(:get, "http://localhost:11434/api/tags").to_timeout
        stub_request(:get, "http://localhost:11434/ollama/api/tags").to_timeout

        post "/api/v1/ai/providers/#{provider.id}/sync_models", headers: auth_headers_for(user)

        expect_error_response("Could not connect to Ollama API", :unprocessable_content)
      end
    end
  end
end
