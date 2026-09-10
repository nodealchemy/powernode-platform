# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A2 — the worker→server door.
RSpec.describe "Api::V1::Internal platform status sweep", type: :request do
  let(:account) { create(:account) }
  let(:system_worker) { create(:worker, :system_worker, account: account) }
  let(:worker_headers) do
    { "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{system_worker.node_instance_id}")) }
  end

  def post_sweep(params = {}, headers: worker_headers)
    post "/api/v1/internal/platform/status_sweep",
         params: params.to_json,
         headers: headers.merge("Content-Type" => "application/json")
  end

  describe "authentication" do
    it "refuses a request with no worker mTLS identity" do
      post_sweep({}, headers: {})

      expect(response).to have_http_status(:unauthorized)
    end

    it "accepts the worker's mTLS identity — the other arm" do
      system_worker

      post_sweep

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /api/v1/internal/platform/status_sweep" do
    it "runs the runner for the named account and reports its summary" do
      system_worker
      allow(Platform::Status::SweepRunner).to receive(:run!).and_call_original

      post_sweep({ account_id: account.id })

      expect(Platform::Status::SweepRunner).to have_received(:run!).with(account).once
      body = JSON.parse(response.body)["data"]
      expect(body["accounts_swept"]).to eq(1)
      expect(body["summaries"].first["account_id"]).to eq(account.id)
    end

    it "sweeps every account when none is named" do
      system_worker
      other = create(:account)

      post_sweep

      ids = JSON.parse(response.body)["data"]["summaries"].map { |s| s["account_id"] }
      expect(ids).to include(account.id, other.id)
    end

    it "surfaces a skipped account with its reason rather than hiding it as a success" do
      system_worker
      account.suspend_ai!

      post_sweep({ account_id: account.id })

      summary = JSON.parse(response.body)["data"]["summaries"].first
      expect(summary["skipped"]).to be(true)
      expect(summary["reason"]).to eq("kill_switch")
    end

    it "reports one account's failure without losing the others" do
      system_worker
      other = create(:account)
      allow(Platform::Status::SweepRunner).to receive(:run!) do |acct|
        raise "sweep exploded" if acct.id == account.id

        { skipped: false, transitions: [], events_written: 0, reaped: 0, kinds: {} }
      end

      post_sweep

      expect(response).to have_http_status(:ok)
      summaries = JSON.parse(response.body)["data"]["summaries"].index_by { |s| s["account_id"] }
      expect(summaries[account.id]["error"]).to include("sweep exploded")
      expect(summaries[other.id]["skipped"]).to be(false)
    end

    it "reports truncated: false on a sweep that finished inside its ceiling" do
      system_worker

      post_sweep

      expect(JSON.parse(response.body)["data"]["truncated"]).to be(false)
    end
  end
end
