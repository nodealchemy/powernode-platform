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

    def post_with_sbom(l, sbom)
      post "/api/v1/internal/ai/campaign_lands/#{l.id}/security_findings",
           params: { findings: [], scanners: ["worker_diff_secret_scan"], sbom: sbom },
           headers: service_headers, as: :json
    end

    it "stores an optional SBOM under metadata.security_gate.sbom (inventory metadata)" do
      l = land(status: "staged_ci", staged_sha: "abc")
      sbom = { format: "CycloneDX", spec_version: "1.5", generated: true, component_count: 2,
               document: { "bomFormat" => "CycloneDX",
                           "components" => [ { "name" => "rack" }, { "name" => "nokogiri" } ] } }

      post_with_sbom(l, sbom)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]["blocked"]).to be false
      stored = l.reload.metadata.dig("security_gate", "sbom")
      expect(stored["format"]).to eq("CycloneDX")
      expect(stored["component_count"]).to eq(2)
      expect(stored.dig("document", "components").map { |c| c["name"] }).to contain_exactly("rack", "nokogiri")
    end

    it "stores no SBOM (back-compat) when the param is omitted, leaving findings/scanners intact" do
      l = land(status: "staged_ci", staged_sha: "abc")

      post_findings(l, [])

      expect(response).to have_http_status(:ok)
      gate = l.reload.metadata["security_gate"]
      expect(gate).to have_key("worker_scan")
      expect(gate).not_to have_key("sbom")
      expect(gate.dig("worker_scan", "scanners")).to include("worker_diff_secret_scan")
    end

    it "caps an oversized SBOM to a truncated summary without bloating the row or failing the land" do
      l = land(status: "staged_ci", staged_sha: "abc")
      huge = "x" * (300 * 1024)
      sbom = { format: "CycloneDX", spec_version: "1.5", generated: true, component_count: 1,
               document: { "blob" => huge } }

      post_with_sbom(l, sbom)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]["blocked"]).to be false
      stored = l.reload.metadata.dig("security_gate", "sbom")
      expect(stored["truncated"]).to be true
      expect(stored["component_count"]).to eq(1)
      expect(stored.to_json).not_to include(huge)
      # The findings/scanners path is unchanged by a (capped) SBOM.
      expect(l.metadata.dig("security_gate", "worker_scan", "scanners")).to include("worker_diff_secret_scan")
    end
  end
end
