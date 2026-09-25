# frozen_string_literal: true

require "rails_helper"

# The Control → Policies → Compliance tab toggles a compliance policy on and
# off and lists the account's security events (the audit client has called
# both since it was written; neither existed). A toggle is a policy change, so
# it is gated on ai.governance.manage and leaves an audit entry; the list is a
# read, gated on ai.governance.read, account-scoped and paginated.
RSpec.describe "AI governance: policy toggle and security events", type: :request do
  let(:account)       { create(:account) }
  let(:other_account) { create(:account) }
  let(:manager)       { user_with_permissions("ai.governance.read", "ai.governance.manage", account: account) }
  let(:reader)        { user_with_permissions("ai.governance.read", account: account) }
  let(:outsider)      { user_with_permissions("ai.agents.read", account: account) }

  def headers(user)
    auth_headers_for(user).merge("Content-Type" => "application/json")
  end

  describe "PUT /api/v1/ai/governance/policies/:id/toggle" do
    let!(:policy) { create(:ai_compliance_policy, account: account, status: "active") }

    def toggle(target, user = manager)
      put "/api/v1/ai/governance/policies/#{target.id}/toggle", headers: headers(user)
    end

    it "disables an active policy and enables it again" do
      toggle(policy)
      expect(response).to have_http_status(:ok)
      expect(json_response_data.dig("policy", "status")).to eq("disabled")
      expect(policy.reload.status).to eq("disabled")

      toggle(policy)
      expect(json_response_data.dig("policy", "status")).to eq("active")
      expect(policy.reload.status).to eq("active")
    end

    it "activates a draft policy" do
      draft = create(:ai_compliance_policy, account: account, status: "draft")
      toggle(draft)

      expect(response).to have_http_status(:ok)
      expect(draft.reload.status).to eq("active")
    end

    it "records the change in the audit log, attributed to the caller" do
      expect { toggle(policy) }.to change {
        AuditLog.where(resource_type: "Ai::CompliancePolicy", resource_id: policy.id).count
      }.by(1)

      entry = AuditLog.where(resource_type: "Ai::CompliancePolicy", resource_id: policy.id).last
      expect(entry).to have_attributes(action: "update", account_id: account.id, user_id: manager.id)
      expect(entry.old_values).to include("status" => "active")
      expect(entry.new_values).to include("status" => "disabled")
    end

    it "refuses an archived policy, and a required one being switched off" do
      archived = create(:ai_compliance_policy, account: account, status: "archived")
      required = create(:ai_compliance_policy, account: account, status: "active", is_required: true)

      toggle(archived)
      expect(response).to have_http_status(:unprocessable_content)
      toggle(required)
      expect(response).to have_http_status(:unprocessable_content)

      expect([ archived.reload.status, required.reload.status ]).to eq(%w[archived active])
    end

    it "is forbidden without ai.governance.manage, and changes nothing" do
      expect { toggle(policy, reader) }.not_to change { AuditLog.count }
      expect(response).to have_http_status(:forbidden)
      expect(policy.reload.status).to eq("active")
    end

    it "cannot reach another account's policy" do
      foreign = create(:ai_compliance_policy, account: other_account, status: "active")
      toggle(foreign)

      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.status).to eq("active")
    end
  end

  describe "GET /api/v1/ai/governance/security_events" do
    let!(:failed_login) do
      create(:audit_log, account: account, user: reader, action: "login_failed", resource_type: "User",
                         severity: "high", risk_level: "medium", source: "web")
    end
    let!(:not_security) { create(:audit_log, account: account, user: reader, action: "update") }
    let!(:foreign_event) { create(:audit_log, account: other_account, action: "login_failed") }

    it "lists only the caller's account's security events, in the SecurityEvent shape" do
      get "/api/v1/ai/governance/security_events", headers: headers(reader)

      expect(response).to have_http_status(:ok)
      events = json_response_data["events"]
      expect(events.map { |e| e["id"] }).to eq([ failed_login.id ])
      expect(events.first.keys).to include("id", "action", "resource_type", "severity", "risk_level", "source",
                                           "ip_address", "created_at")
      expect(events.first).to include("action" => "login_failed", "severity" => "high", "risk_level" => "medium")
    end

    it "is paginated, with a capped page size" do
      create_list(:audit_log, 3, account: account, action: "login_failed")

      get "/api/v1/ai/governance/security_events", params: { per_page: 2 }, headers: auth_headers_for(reader)
      expect(json_response_data["events"].length).to eq(2)
      expect(json_response_data["pagination"]).to include("total_count" => 4, "per_page" => 2)

      get "/api/v1/ai/governance/security_events", params: { per_page: 10_000 }, headers: auth_headers_for(reader)
      expect(json_response_data["pagination"]["per_page"]).to eq(100)
    end

    it "is forbidden without ai.governance.read" do
      get "/api/v1/ai/governance/security_events", headers: headers(outsider)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
