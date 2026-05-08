# frozen_string_literal: true

require "rails_helper"

# M2 Self-Serve Hardening (BYOC) — onboarding bookkeeping endpoint.
RSpec.describe "Api::V1::OnboardingController", type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:user) { user_with_permissions(account: account) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/onboarding/status" do
    it "returns 401 without authentication" do
      get "/api/v1/onboarding/status"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns completed=false when the account has not finished onboarding" do
      get "/api/v1/onboarding/status", headers: headers

      expect(response).to have_http_status(:ok)
      data = json_response_data
      expect(data["completed"]).to eq(false)
      expect(data["has_credentials"]).to eq(false)
      expect(data["completed_at"]).to be_nil
    end

    it "returns completed=true when the account metadata has the timestamp" do
      account.mark_onboarding_complete!

      get "/api/v1/onboarding/status", headers: headers
      expect(response).to have_http_status(:ok)
      data = json_response_data
      expect(data["completed"]).to eq(true)
      expect(data["completed_at"]).to be_present
    end

    it "reports has_credentials=true when an active credential exists for the account" do
      provider = ::System::Provider.find_by(account: account, provider_type: "pro_cloud") ||
                 create(:system_provider, account: account, provider_type: "pro_cloud", name: "Pro Cloud Test")
      cred = ::System::ProviderCredential.new(
        account: account, provider: provider, name: "Default",
        credentials: { "api_key" => "secret" }, scope: :account_owned, is_active: true
      )
      cred.save!

      get "/api/v1/onboarding/status", headers: headers
      data = json_response_data
      expect(data["has_credentials"]).to eq(true)
    end

    it "reports has_credentials=false when only inactive credentials exist" do
      provider = ::System::Provider.find_by(account: account, provider_type: "pro_cloud") ||
                 create(:system_provider, account: account, provider_type: "pro_cloud", name: "Pro Cloud Test")
      cred = ::System::ProviderCredential.new(
        account: account, provider: provider, name: "Stale",
        credentials: { "api_key" => "secret" }, scope: :account_owned, is_active: false
      )
      cred.save!

      get "/api/v1/onboarding/status", headers: headers
      data = json_response_data
      expect(data["has_credentials"]).to eq(false)
    end

    it "scopes credentials lookup to the caller's account" do
      foreign_provider = ::System::Provider.find_by(account: other_account, provider_type: "pro_cloud") ||
                         create(:system_provider, account: other_account, provider_type: "pro_cloud", name: "Other")
      cred = ::System::ProviderCredential.new(
        account: other_account, provider: foreign_provider, name: "Other",
        credentials: { "api_key" => "secret" }, scope: :account_owned, is_active: true
      )
      cred.save!

      get "/api/v1/onboarding/status", headers: headers
      expect(json_response_data["has_credentials"]).to eq(false)
    end
  end

  describe "POST /api/v1/onboarding/complete" do
    before do
      # Account.after_create_commit already invoked the bootstrap; #complete
      # only re-runs the catalog seed body, which is idempotent. Stub
      # the seed call so the spec doesn't pay the multi-second catalog
      # generation cost just to verify wiring.
      allow(::System::AccountBootstrapService).to receive(:seed_templates_for)
    end

    it "returns 401 without authentication" do
      post "/api/v1/onboarding/complete"
      expect(response).to have_http_status(:unauthorized)
    end

    it "marks the account as complete and persists the timestamp" do
      expect(account.onboarding_completed?).to eq(false)

      post "/api/v1/onboarding/complete", headers: headers

      expect(response).to have_http_status(:ok)
      data = json_response_data
      expect(data["completed"]).to eq(true)
      expect(data["completed_at"]).to be_present

      account.reload
      expect(account.onboarding_completed?).to eq(true)
      expect(account.metadata["onboarding_completed_at"]).to be_present
    end

    it "kicks AccountBootstrapService.seed_templates_for on first completion" do
      expect(::System::AccountBootstrapService).to receive(:seed_templates_for)
        .with(an_instance_of(Account))
        .once

      post "/api/v1/onboarding/complete", headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "is idempotent — does not re-seed when already completed" do
      account.mark_onboarding_complete!
      expect(::System::AccountBootstrapService).not_to receive(:seed_templates_for)

      post "/api/v1/onboarding/complete", headers: headers
      expect(response).to have_http_status(:ok)
      expect(json_response_data["completed"]).to eq(true)
    end

    it "still returns success when seed_templates_for raises (logged, not propagated)" do
      allow(::System::AccountBootstrapService).to receive(:seed_templates_for)
        .and_raise(StandardError, "boom")
      allow(Rails.logger).to receive(:error)

      post "/api/v1/onboarding/complete", headers: headers

      expect(response).to have_http_status(:ok)
      expect(Rails.logger).to have_received(:error).with(/seed_templates_for failed/)
      account.reload
      expect(account.onboarding_completed?).to eq(true)
    end

    it "accepts the wizard's { provider_credential_id, provider_type } body shape and stores audit context" do
      cred_id = SecureRandom.uuid

      post "/api/v1/onboarding/complete",
           params: { provider_credential_id: cred_id, provider_type: "vultr" }.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)
      account.reload
      expect(account.metadata["onboarding_completed_at"]).to be_present
      expect(account.metadata["onboarding_provider_credential_id"]).to eq(cred_id)
      expect(account.metadata["onboarding_provider_type"]).to eq("vultr")
    end

    it "does not blow up when the wizard sends the skip path (no body)" do
      post "/api/v1/onboarding/complete",
           params: {}.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      account.reload
      expect(account.metadata["onboarding_completed_at"]).to be_present
      expect(account.metadata).not_to have_key("onboarding_provider_credential_id")
    end
  end
end
