# frozen_string_literal: true

require "rails_helper"

# Regression guard for the Authentication concern (sub-part (a) of the auth
# hardenings): worker JWTs are long-lived (30d), so the worker AND its account
# must be re-validated as active on every request — otherwise a suspended
# account's worker (or a revoked worker) keeps operating until token expiry.
RSpec.describe "Worker token re-validation (Authentication)", type: :request do
  let(:account) { create(:account) }
  let(:worker) { create(:worker, account: account) }

  # A worker-accessible endpoint that runs through authenticate_request.
  let(:path) { "/api/v1/ai/learning/promote_learning" }
  let(:body) { { learning_id: SecureRandom.uuid }.to_json }

  def worker_headers(w)
    payload = {
      sub: w.id,
      account_id: w.account_id,
      type: "worker",
      permissions: w.permission_names,
      version: Security::JwtService::CURRENT_TOKEN_VERSION
    }
    { "Authorization" => "Bearer #{Security::JwtService.encode(payload)}", "Content-Type" => "application/json" }
  end

  before do
    # Suppress after_commit callbacks that would enqueue real worker jobs.
    allow(WorkerJobService).to receive(:enqueue_ai_promote_learning)
  end

  context "when the worker's account is suspended" do
    it "rejects the request with 401" do
      account.update_column(:status, "suspended")

      post path, params: body, headers: worker_headers(worker)

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to match(/suspended/i)
    end
  end

  context "when the worker itself is suspended" do
    it "rejects the request with 401" do
      suspended_worker = create(:worker, :suspended, account: account)

      post path, params: body, headers: worker_headers(suspended_worker)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "when the worker and account are both active" do
    it "passes authentication (not 401)" do
      post path, params: body, headers: worker_headers(worker)

      expect(response).not_to have_http_status(:unauthorized)
    end
  end
end
