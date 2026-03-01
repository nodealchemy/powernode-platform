# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Ai::Security::Quarantine", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ["ai.security.manage"]) }
  let(:headers) { auth_headers_for(user) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }

  describe "GET /api/v1/ai/security/quarantine" do
    before do
      create_list(:ai_quarantine_record, 3, account: account)
    end

    it "returns list of quarantine records" do
      get "/api/v1/ai/security/quarantine", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data["items"]).to be_an(Array)
      expect(data["items"].length).to eq(3)
    end

    it "filters by agent_id" do
      record = create(:ai_quarantine_record, account: account, agent_id: agent.id)

      get "/api/v1/ai/security/quarantine",
          headers: headers,
          params: { agent_id: agent.id }

      expect_success_response
      data = json_response_data
      ids = data["items"].map { |r| r["id"] }
      expect(ids).to include(record.id)
    end

    it "filters by status" do
      get "/api/v1/ai/security/quarantine",
          headers: headers,
          params: { status: "active" }

      expect_success_response
      data = json_response_data
      statuses = data["items"].map { |r| r["status"] }
      expect(statuses).to all(eq("active"))
    end

    it "filters by severity" do
      create(:ai_quarantine_record, :critical, account: account)

      get "/api/v1/ai/security/quarantine",
          headers: headers,
          params: { severity: "critical" }

      expect_success_response
      data = json_response_data
      severities = data["items"].map { |r| r["severity"] }
      expect(severities).to all(eq("critical"))
    end

    it "returns 403 without permission" do
      no_perm_user = create(:user, account: account, permissions: [])
      get "/api/v1/ai/security/quarantine",
          headers: auth_headers_for(no_perm_user),
          as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/ai/security/quarantine/:id" do
    let!(:record) { create(:ai_quarantine_record, account: account) }

    it "returns the quarantine record" do
      get "/api/v1/ai/security/quarantine/#{record.id}",
          headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data["id"]).to eq(record.id)
      expect(data["severity"]).to eq(record.severity)
    end

    it "returns 404 for non-existent record" do
      get "/api/v1/ai/security/quarantine/#{SecureRandom.uuid}",
          headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/ai/security/quarantine" do
    it "quarantines an agent" do
      post "/api/v1/ai/security/quarantine",
           headers: headers,
           params: {
             agent_id: agent.id,
             severity: "medium",
             reason: "Suspicious activity detected"
           },
           as: :json

      expect(response).to have_http_status(:created)
      data = json_response_data
      expect(data["agent_id"]).to eq(agent.id)
      expect(data["severity"]).to eq("medium")
      expect(data["status"]).to eq("active")
    end

    it "returns 404 for non-existent agent" do
      post "/api/v1/ai/security/quarantine",
           headers: headers,
           params: {
             agent_id: SecureRandom.uuid,
             severity: "low",
             reason: "Test"
           },
           as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/ai/security/quarantine/:id/escalate" do
    let(:quarantine_service) { Ai::Security::QuarantineService.new(account: account) }
    let!(:record) { quarantine_service.quarantine!(agent: agent, severity: "low", reason: "Initial") }

    it "escalates the quarantine to a higher severity" do
      post "/api/v1/ai/security/quarantine/#{record.id}/escalate",
           headers: headers,
           params: { new_severity: "high" },
           as: :json

      expect_success_response
      data = json_response_data
      expect(data["severity"]).to eq("high")
      expect(data["escalated_from_id"]).to eq(record.id)
    end

    it "returns error when escalating to same severity" do
      post "/api/v1/ai/security/quarantine/#{record.id}/escalate",
           headers: headers,
           params: { new_severity: "low" },
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /api/v1/ai/security/quarantine/:id/restore" do
    let(:quarantine_service) { Ai::Security::QuarantineService.new(account: account) }
    let!(:record) { quarantine_service.quarantine!(agent: agent, severity: "medium", reason: "Test") }

    it "restores the quarantined agent" do
      post "/api/v1/ai/security/quarantine/#{record.id}/restore",
           headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data["status"]).to eq("restored")
      expect(data["approved_by_id"]).to eq(user.id)
    end
  end

  describe "GET /api/v1/ai/security/quarantine/report" do
    before do
      create_list(:ai_security_audit_trail, 3, account: account)
      create(:ai_quarantine_record, account: account, agent_id: agent.id)
    end

    it "returns a security report" do
      get "/api/v1/ai/security/quarantine/report",
          headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data["total_events"]).to be >= 3
      expect(data["active_quarantines"]).to be >= 1
      expect(data["recommendations"]).to be_an(Array)
    end

    it "accepts custom period_days" do
      get "/api/v1/ai/security/quarantine/report",
          headers: headers,
          params: { period_days: 7 }

      expect_success_response
      data = json_response_data
      expect(data["period_days"]).to eq(7)
    end
  end

  describe "GET /api/v1/ai/security/quarantine/compliance" do
    before do
      create(:ai_security_audit_trail, account: account, asi_reference: "ASI01")
      create(:ai_security_audit_trail, account: account, asi_reference: "ASI03")
    end

    it "returns the compliance matrix" do
      get "/api/v1/ai/security/quarantine/compliance",
          headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data["matrix"]).to be_an(Array)
      expect(data["matrix"].length).to eq(10)
    end

    it "includes ASI references ASI01 through ASI10" do
      get "/api/v1/ai/security/quarantine/compliance",
          headers: headers, as: :json

      data = json_response_data
      refs = data["matrix"].map { |m| m["asi_reference"] }
      expect(refs).to include("ASI01", "ASI05", "ASI10")
    end
  end
end
