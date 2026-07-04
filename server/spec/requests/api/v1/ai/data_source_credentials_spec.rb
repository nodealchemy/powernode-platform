# frozen_string_literal: true

require "rails_helper"

# x-com-provider campaign (I2): request-level coverage for the OAuth2
# app-credential params added to Api::V1::Ai::DataSourceCredentialsController.
# Focuses on the new client_id/client_secret param surface; existing api_key
# create/update/index/show/destroy behavior is unchanged and untested here.
RSpec.describe "Api::V1::Ai::DataSourceCredentials OAuth2 params", type: :request do
  let(:account) { create(:account) }
  let(:creator) { user_with_permissions("ai.data_sources.create", account: account) }
  let!(:data_source) { create(:ai_data_source, account: account) }
  let(:base_path) { "/api/v1/ai/data_sources/#{data_source.id}/credentials" }

  before do
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
  end

  describe "POST /credentials" do
    it "persists client_id/client_secret via the OAuth2 param names" do
      post base_path, params: {
        credential: {
          name: "X.com OAuth app",
          client_id: "x-com-client-id",
          client_secret: "x-com-client-secret"
        }
      }, headers: auth_headers_for(creator), as: :json

      expect_success_response
      credential = Ai::DataSourceCredential.find(json_response_data["credential"]["id"])
      expect(credential.decrypted_client_id).to eq("x-com-client-id")
      expect(credential.decrypted_client_secret).to eq("x-com-client-secret")
    end

    it "does not persist access_token/refresh_token/access_token_expires_at from client params" do
      post base_path, params: {
        credential: {
          name: "X.com OAuth app",
          client_id: "x-com-client-id",
          access_token: "attacker-supplied-token",
          refresh_token: "attacker-supplied-refresh",
          access_token_expires_at: 1.year.from_now
        }
      }, headers: auth_headers_for(creator), as: :json

      expect_success_response
      credential = Ai::DataSourceCredential.find(json_response_data["credential"]["id"])
      expect(credential.decrypted_access_token).to be_nil
      expect(credential.decrypted_refresh_token).to be_nil
      expect(credential.access_token_expires_at).to be_nil
    end

    it "still supports the existing encrypted_api_key/encrypted_api_secret params unchanged" do
      post base_path, params: {
        credential: {
          name: "Legacy API key cred",
          encrypted_api_key: "legacy-key",
          encrypted_api_secret: "legacy-secret"
        }
      }, headers: auth_headers_for(creator), as: :json

      expect_success_response
      credential = Ai::DataSourceCredential.find(json_response_data["credential"]["id"])
      expect(credential.decrypted_api_key).to eq("legacy-key")
      expect(credential.decrypted_api_secret).to eq("legacy-secret")
    end
  end
end
