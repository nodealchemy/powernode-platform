# frozen_string_literal: true

require "rails_helper"

# IMP-0213523480d1 — the stranded-dispatch reconciler rides the approval-expiry
# sweep's existing worker→server door (AiApprovalExpiryJob, hourly) rather than
# a cron of its own. The reconciler is covered by
# spec/services/ai/approvals/stranded_dispatch_reconciler_spec.rb; what matters
# here is that the sweep REACHES it and reports what it did.
RSpec.describe "Api::V1::Internal::Ai::Autonomy approval-request sweep", type: :request do
  let(:account)       { create(:account) }
  let(:system_worker) { create(:worker, :system_worker, account: account) }
  let(:worker_headers) do
    { "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{system_worker.node_instance_id}")) }
  end

  describe "POST /api/v1/internal/ai/approval_requests/expire_overdue" do
    it "reports zero reconciled dispatches when nothing is stranded" do
      post "/api/v1/internal/ai/approval_requests/expire_overdue", headers: worker_headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["expired_count"]).to eq(0)
      expect(data["stranded_failed_count"]).to eq(0)
      expect(data["stranded_redispatched_count"]).to eq(0)
    end

    it "runs the stranded-dispatch reconciler for each account and sums its counts" do
      reconciler = instance_double(Ai::Approvals::StrandedDispatchReconciler, call: { failed: 2, redispatched: 1 })
      allow(Ai::Approvals::StrandedDispatchReconciler).to receive(:new).and_return(reconciler)

      post "/api/v1/internal/ai/approval_requests/expire_overdue", headers: worker_headers

      expect(Ai::Approvals::StrandedDispatchReconciler).to have_received(:new).with(account: account)
      data = JSON.parse(response.body)["data"]
      expect(data["stranded_failed_count"]).to be >= 2
      expect(data["stranded_redispatched_count"]).to be >= 1
    end
  end
end
