# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Internal::Ai::Security token_scope_audit (G7)", type: :request do
  include_context "internal api auth"

  let(:path) { "/api/v1/internal/ai/security/token_scope_audit" }

  it "runs the token-scope audit and returns findings + count" do
    create(:ai_provider_credential, access_scopes: ["*"])

    post path, headers: service_headers, as: :json

    expect(response).to have_http_status(:ok)
    data = JSON.parse(response.body)["data"]
    expect(data["over_provisioned_count"]).to be >= 1
    expect(data["findings"]).to be_present
    expect(data["findings"]).to all(include("subject_type", "subject_id", "scopes", "issues"))
  end

  it "returns an empty audit (no findings) when nothing is over-provisioned" do
    create(:ai_provider_credential, access_scopes: ["models:read"])

    post path, headers: service_headers, as: :json

    expect(response).to have_http_status(:ok)
    data = JSON.parse(response.body)["data"]
    expect(data["over_provisioned_count"]).to eq(0)
    expect(data["findings"]).to eq([])
  end

  it "logs a warning when over-provisioning is detected" do
    create(:ai_provider_credential, access_scopes: ["*"])

    expect(Rails.logger).to receive(:warn).with(/TokenScopeAudit/i).at_least(:once)

    post path, headers: service_headers, as: :json
  end

  it "never surfaces secret values in the response body" do
    secret = "sk-supersecret-#{SecureRandom.hex(12)}"
    create(:ai_provider_credential, access_scopes: ["*"],
                                    credentials: { "api_key" => secret, "model" => "test-model" })

    post path, headers: service_headers, as: :json

    expect(response.body).not_to include(secret)
  end
end
