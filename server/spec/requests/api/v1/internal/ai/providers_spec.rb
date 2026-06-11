# frozen_string_literal: true

require "rails_helper"

# C1 (operator decision 2026-06-11): provider model sync is pull-based. The
# worker's short-interval AiProviderPendingSyncJob POSTs sync_pending to pick
# up providers flagged by their create/update callbacks; the existing
# sync_all endpoint stays as the daily full-sweep backstop.
RSpec.describe "Api::V1::Internal::Ai::Providers", type: :request do
  let(:account) { create(:account) }
  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    { "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end

  describe "POST /api/v1/internal/ai/providers/sync_pending" do
    it "delegates to sync_pending_providers and returns its results" do
      allow(::Ai::ProviderManagementService).to receive(:sync_pending_providers)
        .and_return({ synced: 2, failed: 1, errors: [ { provider_id: "x", name: "Broken" } ] })

      post "/api/v1/internal/ai/providers/sync_pending", headers: internal_headers, as: :json

      expect_success_response
      results = json_response_data["results"]
      expect(results["synced"]).to eq(2)
      expect(results["failed"]).to eq(1)
    end

    it "returns unauthorized without an mTLS worker identity" do
      post "/api/v1/internal/ai/providers/sync_pending", as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
