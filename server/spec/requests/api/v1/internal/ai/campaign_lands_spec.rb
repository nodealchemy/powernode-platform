# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Internal::Ai::CampaignLands", type: :request do
  include_context "internal api auth"

  let(:campaign) { create(:ai_campaign, account: internal_account) }

  def land(status:, **attrs)
    Ai::CampaignLand.create!({
      campaign: campaign, account: internal_account, status: status,
      source_branch: "campaign/#{campaign.id}", target_branch: "develop"
    }.merge(attrs))
  end

  describe "POST process_queue" do
    it "picks a queued land and transitions it to staging" do
      l = land(status: "queued", queued_at: 1.minute.ago)

      post "/api/v1/internal/ai/campaign_lands/process_queue", headers: service_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      data = body["data"] || body
      ids = data["lands"].map { |x| x["id"] }
      expect(ids).to include(l.id)
      expect(l.reload.status).to eq("staging")
    end

    it "requires worker auth" do
      post "/api/v1/internal/ai/campaign_lands/process_queue"
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    end
  end

  describe "GET show" do
    it "returns the land summary" do
      l = land(status: "queued")
      get "/api/v1/internal/ai/campaign_lands/#{l.id}", headers: service_headers
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data.dig("land", "id")).to eq(l.id)
    end
  end

  describe "GET ci_status" do
    it "reports the CI gate status for the staged sha" do
      l = land(status: "staged_ci", staged_sha: "abc")
      allow(Ai::Land::CiGate).to receive(:status_for).with(sha: "abc").and_return(:success)

      get "/api/v1/internal/ai/campaign_lands/#{l.id}/ci_status", params: { gate: "staged" }, headers: service_headers

      data = JSON.parse(response.body)["data"]
      expect(data["ci_status"]).to eq("success")
    end
  end

  describe "POST verify" do
    it "lands when develop CI is green" do
      l = land(status: "verifying", merged_sha: "merged")
      allow(Ai::Land::CiGate).to receive(:status_for).with(sha: "merged").and_return(:success)
      allow_any_instance_of(Ai::Land::LandService).to receive(:cleanup!)

      post "/api/v1/internal/ai/campaign_lands/#{l.id}/verify", headers: service_headers

      expect(l.reload.status).to eq("landed")
    end

    it "rolls back when develop CI is red" do
      l = land(status: "verifying", merged_sha: "merged")
      allow(Ai::Land::CiGate).to receive(:status_for).with(sha: "merged").and_return(:failure)
      rollback_called = false
      allow_any_instance_of(Ai::Land::LandService).to receive(:rollback!) { rollback_called = true; l }

      post "/api/v1/internal/ai/campaign_lands/#{l.id}/verify", headers: service_headers

      expect(rollback_called).to be(true)
    end
  end

  describe "POST stage (delegates to LandService)" do
    it "invokes the land service" do
      l = land(status: "staging")
      svc = instance_double(Ai::Land::LandService, stage!: l)
      allow(Ai::Land::LandService).to receive(:new).and_return(svc)

      post "/api/v1/internal/ai/campaign_lands/#{l.id}/stage", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(svc).to have_received(:stage!)
    end
  end

  describe "POST security_findings (worker deep-scan park-back)" do
    def post_findings(l, findings)
      post "/api/v1/internal/ai/campaign_lands/#{l.id}/security_findings",
           params: { findings: findings, scanners: ["worker_diff_secret_scan"] },
           headers: service_headers, as: :json
    end

    it "parks the land and records worker findings when a finding is blocking" do
      l = land(status: "staged_ci", staged_sha: "abc")

      post_findings(l, [{ scanner: "worker_diff_secret_scan", severity: "critical",
                          detail: "potential secret detected (token)" }])

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["blocked"]).to be true
      expect(data["land_status"]).to eq("parked")

      worker_scan = l.reload.metadata.dig("security_gate", "worker_scan")
      expect(worker_scan["blocked"]).to be true
      expect(worker_scan["scanners"]).to include("worker_diff_secret_scan")
      expect(worker_scan["findings"].first["detail"]).to eq("potential secret detected (token)")
    end

    it "records the clean scan WITHOUT parking when no finding is blocking" do
      l = land(status: "staged_ci", staged_sha: "abc")

      post_findings(l, [])

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["blocked"]).to be false
      expect(l.reload.status).to eq("staged_ci")
      expect(l.metadata.dig("security_gate", "worker_scan", "blocked")).to be false
    end

    it "preserves an existing server-side security_gate record when merging the worker scan" do
      l = land(status: "staged_ci", metadata: { "security_gate" => { "scanned_content" => false } })

      post_findings(l, [])

      gate = l.reload.metadata["security_gate"]
      expect(gate["scanned_content"]).to be false
      expect(gate).to have_key("worker_scan")
    end

    it "requires worker auth" do
      l = land(status: "staged_ci")
      post "/api/v1/internal/ai/campaign_lands/#{l.id}/security_findings"
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    end
  end
end
