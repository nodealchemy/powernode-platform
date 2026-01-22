# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::SupplyChain::LicenseViolations", type: :request do
  let(:account) { create(:account) }

  # User with supply_chain.read permission only
  let(:supply_chain_reader) do
    create(:user, account: account, permissions: ["supply_chain.read"])
  end

  # User with both supply_chain.read and supply_chain.write permissions
  let(:supply_chain_writer) do
    create(:user, account: account, permissions: ["supply_chain.read", "supply_chain.write"])
  end

  # User with supply_chain.admin permission
  let(:supply_chain_admin) do
    create(:user, account: account, permissions: ["supply_chain.read", "supply_chain.write", "supply_chain.admin"])
  end

  # User without supply_chain permissions
  let(:regular_user) do
    create(:user, account: account, permissions: [])
  end

  # Another account for isolation tests
  let(:other_account) { create(:account) }

  before(:each) do
    Rails.cache.clear
  end

  describe "GET /api/v1/supply_chain/license_violations" do
    let!(:sbom) { create(:supply_chain_sbom, account: account) }
    let!(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }
    let!(:policy) { create(:supply_chain_license_policy, account: account) }
    let!(:license) { create(:supply_chain_license, :copyleft) }

    context "with supply_chain.read permission" do
      let!(:violations) do
        [
          create(:supply_chain_license_violation,
                 account: account,
                 sbom: sbom,
                 sbom_component: component,
                 license_policy: policy,
                 license: license,
                 status: "open",
                 severity: "high",
                 violation_type: "denied"),
          create(:supply_chain_license_violation,
                 account: account,
                 sbom: sbom,
                 sbom_component: component,
                 license_policy: policy,
                 license: license,
                 status: "resolved",
                 severity: "medium",
                 violation_type: "copyleft"),
          create(:supply_chain_license_violation,
                 account: account,
                 sbom: sbom,
                 sbom_component: component,
                 license_policy: policy,
                 license: license,
                 status: "open",
                 severity: "critical",
                 violation_type: "incompatible")
        ]
      end

      let!(:other_violation) do
        other_sbom = create(:supply_chain_sbom, account: other_account)
        other_component = create(:supply_chain_sbom_component, sbom: other_sbom, account: other_account)
        other_policy = create(:supply_chain_license_policy, account: other_account)
        create(:supply_chain_license_violation,
               account: other_account,
               sbom: other_sbom,
               sbom_component: other_component,
               license_policy: other_policy,
               license: license,
               status: "open")
      end

      it "returns violations for the current account" do
        get "/api/v1/supply_chain/license_violations", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["license_violations"]

        expect(data.length).to eq(3)
        expect(data.map { |v| v["id"] }).to match_array(violations.map(&:id))
        expect(data.map { |v| v["id"] }).not_to include(other_violation.id)
      end

      it "returns violations ordered by created_at desc" do
        get "/api/v1/supply_chain/license_violations", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["license_violations"]

        created_ats = data.map { |v| Time.parse(v["created_at"]) }
        expect(created_ats).to eq(created_ats.sort.reverse)
      end

      it "returns violation data with correct structure" do
        get "/api/v1/supply_chain/license_violations", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        violation_data = json_response["data"]["license_violations"].first

        expect(violation_data).to include(
          "id",
          "status",
          "severity",
          "violation_type",
          "component_name",
          "component_version",
          "license_spdx_id",
          "license_name",
          "policy_name",
          "created_at"
        )
      end

      it "filters by status" do
        get "/api/v1/supply_chain/license_violations?status=open",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]["license_violations"]

        expect(data.length).to eq(2)
        expect(data.all? { |v| v["status"] == "open" }).to be true
      end

      it "filters by severity" do
        get "/api/v1/supply_chain/license_violations?severity=high",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]["license_violations"]

        expect(data.length).to eq(1)
        expect(data.first["severity"]).to eq("high")
      end

      it "filters by violation_type" do
        get "/api/v1/supply_chain/license_violations?violation_type=denied",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]["license_violations"]

        expect(data.length).to eq(1)
        expect(data.first["violation_type"]).to eq("denied")
      end

      it "filters by policy_id" do
        get "/api/v1/supply_chain/license_violations?policy_id=#{policy.id}",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]["license_violations"]

        expect(data.length).to eq(3)
      end

      it "applies multiple filters simultaneously" do
        get "/api/v1/supply_chain/license_violations?status=open&severity=high",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]["license_violations"]

        expect(data.length).to eq(1)
        expect(data.first["status"]).to eq("open")
        expect(data.first["severity"]).to eq("high")
      end
    end

    context "pagination" do
      before do
        30.times do
          create(:supply_chain_license_violation,
                 account: account,
                 sbom: sbom,
                 sbom_component: component,
                 license_policy: policy,
                 license: license)
        end
      end

      it "returns paginated results with default per_page of 20" do
        get "/api/v1/supply_chain/license_violations", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        expect(json_response["data"]["license_violations"].length).to eq(20)
        expect(json_response["meta"]["total_count"]).to eq(30)
        expect(json_response["meta"]["current_page"]).to eq(1)
        expect(json_response["meta"]["per_page"]).to eq(20)
        expect(json_response["meta"]["total_pages"]).to eq(2)
      end

      it "respects page parameter" do
        get "/api/v1/supply_chain/license_violations?page=2",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        expect(json_response["data"]["license_violations"].length).to eq(10)
        expect(json_response["meta"]["current_page"]).to eq(2)
      end

      it "respects per_page parameter" do
        get "/api/v1/supply_chain/license_violations?per_page=10",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        expect(json_response["data"]["license_violations"].length).to eq(10)
        expect(json_response["meta"]["per_page"]).to eq(10)
        expect(json_response["meta"]["total_pages"]).to eq(3)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/license_violations", headers: auth_headers_for(regular_user), as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/license_violations", as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "GET /api/v1/supply_chain/license_violations/:id" do
    let(:sbom) { create(:supply_chain_sbom, account: account) }
    let(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }
    let(:policy) { create(:supply_chain_license_policy, account: account) }
    let(:license) { create(:supply_chain_license, :copyleft) }
    let!(:violation) do
      create(:supply_chain_license_violation,
             account: account,
             sbom: sbom,
             sbom_component: component,
             license_policy: policy,
             license: license,
             description: "Test violation description",
             metadata: { "recommendation" => "Upgrade to MIT license" })
    end

    context "with supply_chain.read permission" do
      it "returns the violation details" do
        get "/api/v1/supply_chain/license_violations/#{violation.id}",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]["license_violation"]

        expect(data["id"]).to eq(violation.id)
        expect(data["status"]).to eq(violation.status)
        expect(data["severity"]).to eq(violation.severity)
        expect(data["violation_type"]).to eq(violation.violation_type)
      end

      it "includes detailed fields in show response" do
        get "/api/v1/supply_chain/license_violations/#{violation.id}",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]["license_violation"]

        expect(data).to include(
          "description",
          "recommendation",
          "notes",
          "resolved_at",
          "resolved_by_id",
          "exception_justification",
          "exception_expires_at",
          "exception_approved_by_id",
          "ai_remediation",
          "metadata"
        )
      end
    end

    context "with violation from another account" do
      let(:other_sbom) { create(:supply_chain_sbom, account: other_account) }
      let(:other_component) { create(:supply_chain_sbom_component, sbom: other_sbom, account: other_account) }
      let(:other_policy) { create(:supply_chain_license_policy, account: other_account) }
      let(:other_violation) do
        create(:supply_chain_license_violation,
               account: other_account,
               sbom: other_sbom,
               sbom_component: other_component,
               license_policy: other_policy,
               license: license)
      end

      it "returns not found error" do
        get "/api/v1/supply_chain/license_violations/#{other_violation.id}",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_error_response("License violation not found", 404)
      end
    end

    context "with non-existent violation" do
      it "returns not found error" do
        get "/api/v1/supply_chain/license_violations/non-existent-id",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_error_response("License violation not found", 404)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/license_violations/#{violation.id}",
            headers: auth_headers_for(regular_user),
            as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "PATCH /api/v1/supply_chain/license_violations/:id" do
    let(:sbom) { create(:supply_chain_sbom, account: account) }
    let(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }
    let(:policy) { create(:supply_chain_license_policy, account: account) }
    let(:license) { create(:supply_chain_license, :copyleft) }
    let(:violation) do
      create(:supply_chain_license_violation,
             account: account,
             sbom: sbom,
             sbom_component: component,
             license_policy: policy,
             license: license,
             notes: "Original notes")
    end

    context "with supply_chain.write permission" do
      it "updates the violation notes" do
        patch "/api/v1/supply_chain/license_violations/#{violation.id}",
              params: { license_violation: { notes: "Updated notes" } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_success_response
        expect(json_response["data"]["license_violation"]["notes"]).to eq("Updated notes")

        violation.reload
        expect(violation.notes).to eq("Updated notes")
      end

      it "updates the violation metadata" do
        patch "/api/v1/supply_chain/license_violations/#{violation.id}",
              params: { license_violation: { metadata: { custom_field: "custom_value" } } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_success_response
        violation.reload
        expect(violation.metadata["custom_field"]).to eq("custom_value")
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        patch "/api/v1/supply_chain/license_violations/#{violation.id}",
              params: { license_violation: { notes: "Updated notes" } },
              headers: auth_headers_for(supply_chain_reader),
              as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /api/v1/supply_chain/license_violations/:id/resolve" do
    let(:sbom) { create(:supply_chain_sbom, account: account) }
    let(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }
    let(:policy) { create(:supply_chain_license_policy, account: account) }
    let(:license) { create(:supply_chain_license, :copyleft) }
    let(:violation) do
      create(:supply_chain_license_violation,
             account: account,
             sbom: sbom,
             sbom_component: component,
             license_policy: policy,
             license: license,
             status: "open")
    end

    context "with supply_chain.write permission" do
      it "resolves the violation" do
        post "/api/v1/supply_chain/license_violations/#{violation.id}/resolve",
             params: { resolution: "fixed", notes: "Switched to MIT license" },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        data = json_response["data"]["license_violation"]
        expect(data["status"]).to eq("resolved")
        expect(json_response["data"]["message"]).to eq("Violation resolved")

        violation.reload
        expect(violation.status).to eq("resolved")
        expect(violation.metadata["resolution_reason"]).to eq("fixed")
      end

      it "resolves without notes" do
        post "/api/v1/supply_chain/license_violations/#{violation.id}/resolve",
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        data = json_response["data"]["license_violation"]
        expect(data["status"]).to eq("resolved")
      end

      it "handles resolution errors" do
        allow_any_instance_of(SupplyChain::LicenseViolation).to receive(:resolve!).and_raise(
          StandardError.new("Cannot resolve")
        )

        post "/api/v1/supply_chain/license_violations/#{violation.id}/resolve",
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_error_response("Failed to resolve: Cannot resolve", 422)
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/license_violations/#{violation.id}/resolve",
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /api/v1/supply_chain/license_violations/:id/request_exception" do
    let(:sbom) { create(:supply_chain_sbom, account: account) }
    let(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }
    let(:policy) { create(:supply_chain_license_policy, account: account) }
    let(:license) { create(:supply_chain_license, :copyleft) }
    let(:violation) do
      create(:supply_chain_license_violation,
             account: account,
             sbom: sbom,
             sbom_component: component,
             license_policy: policy,
             license: license,
             status: "open")
    end

    context "with supply_chain.write permission" do
      it "requests an exception with valid justification" do
        post "/api/v1/supply_chain/license_violations/#{violation.id}/request_exception",
             params: {
               justification: "Required for legacy system compatibility",
               expires_at: 90.days.from_now.iso8601
             },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        data = json_response["data"]["license_violation"]
        expect(json_response["data"]["message"]).to eq("Exception requested")

        violation.reload
        expect(violation.exception_requested).to be true
        expect(violation.exception_status).to eq("pending")
        expect(violation.exception_reason).to eq("Required for legacy system compatibility")
      end

      it "requires justification parameter" do
        post "/api/v1/supply_chain/license_violations/#{violation.id}/request_exception",
             params: {},
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_error_response("Justification is required for exception request", 422)
      end

      it "rejects empty justification" do
        post "/api/v1/supply_chain/license_violations/#{violation.id}/request_exception",
             params: { justification: "" },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_error_response("Justification is required for exception request", 422)
      end

      it "rejects blank justification" do
        post "/api/v1/supply_chain/license_violations/#{violation.id}/request_exception",
             params: { justification: "   " },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_error_response("Justification is required for exception request", 422)
      end

      it "handles exception request errors" do
        allow_any_instance_of(SupplyChain::LicenseViolation).to receive(:request_exception!).and_raise(
          StandardError.new("Cannot request exception")
        )

        post "/api/v1/supply_chain/license_violations/#{violation.id}/request_exception",
             params: { justification: "Valid reason" },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_error_response("Failed to request exception: Cannot request exception", 422)
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/license_violations/#{violation.id}/request_exception",
             params: { justification: "Valid reason" },
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /api/v1/supply_chain/license_violations/:id/approve_exception" do
    let(:sbom) { create(:supply_chain_sbom, account: account) }
    let(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }
    let(:policy) { create(:supply_chain_license_policy, account: account) }
    let(:license) { create(:supply_chain_license, :copyleft) }
    let(:violation) do
      create(:supply_chain_license_violation, :with_exception,
             account: account,
             sbom: sbom,
             sbom_component: component,
             license_policy: policy,
             license: license,
             status: "open")
    end

    context "with supply_chain.admin permission" do
      it "approves the exception" do
        post "/api/v1/supply_chain/license_violations/#{violation.id}/approve_exception",
             params: {
               notes: "Approved by security team",
               expires_at: 180.days.from_now.iso8601
             },
             headers: auth_headers_for(supply_chain_admin),
             as: :json

        expect_success_response
        data = json_response["data"]["license_violation"]
        expect(json_response["data"]["message"]).to eq("Exception approved")

        violation.reload
        expect(violation.status).to eq("exception_granted")
        expect(violation.exception_status).to eq("approved")
        expect(violation.exception_approved_by_id).to eq(supply_chain_admin.id)
      end

      it "approves without custom expiry date" do
        violation.update!(exception_expires_at: 60.days.from_now)

        post "/api/v1/supply_chain/license_violations/#{violation.id}/approve_exception",
             headers: auth_headers_for(supply_chain_admin),
             as: :json

        expect_success_response
        violation.reload
        expect(violation.status).to eq("exception_granted")
      end

      it "handles approval errors" do
        allow_any_instance_of(SupplyChain::LicenseViolation).to receive(:approve_exception!).and_raise(
          StandardError.new("Cannot approve")
        )

        post "/api/v1/supply_chain/license_violations/#{violation.id}/approve_exception",
             headers: auth_headers_for(supply_chain_admin),
             as: :json

        expect_error_response("Failed to approve exception: Cannot approve", 422)
      end
    end

    context "without supply_chain.admin permission" do
      it "returns forbidden error for writer" do
        post "/api/v1/supply_chain/license_violations/#{violation.id}/approve_exception",
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect(response).to have_http_status(:forbidden)
      end

      it "returns forbidden error for reader" do
        post "/api/v1/supply_chain/license_violations/#{violation.id}/approve_exception",
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /api/v1/supply_chain/license_violations/:id/reject_exception" do
    let(:sbom) { create(:supply_chain_sbom, account: account) }
    let(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }
    let(:policy) { create(:supply_chain_license_policy, account: account) }
    let(:license) { create(:supply_chain_license, :copyleft) }
    let(:violation) do
      create(:supply_chain_license_violation, :with_exception,
             account: account,
             sbom: sbom,
             sbom_component: component,
             license_policy: policy,
             license: license,
             status: "open")
    end

    context "with supply_chain.admin permission" do
      it "rejects the exception" do
        post "/api/v1/supply_chain/license_violations/#{violation.id}/reject_exception",
             params: { reason: "Does not meet security requirements" },
             headers: auth_headers_for(supply_chain_admin),
             as: :json

        expect_success_response
        data = json_response["data"]["license_violation"]
        expect(json_response["data"]["message"]).to eq("Exception rejected")

        violation.reload
        expect(violation.exception_status).to eq("rejected")
        expect(violation.exception_approved_by_id).to eq(supply_chain_admin.id)
        expect(violation.metadata["rejection_reason"]).to eq("Does not meet security requirements")
      end

      it "rejects without reason" do
        post "/api/v1/supply_chain/license_violations/#{violation.id}/reject_exception",
             headers: auth_headers_for(supply_chain_admin),
             as: :json

        expect_success_response
        violation.reload
        expect(violation.exception_status).to eq("rejected")
      end

      it "handles rejection errors" do
        allow_any_instance_of(SupplyChain::LicenseViolation).to receive(:reject_exception!).and_raise(
          StandardError.new("Cannot reject")
        )

        post "/api/v1/supply_chain/license_violations/#{violation.id}/reject_exception",
             headers: auth_headers_for(supply_chain_admin),
             as: :json

        expect_error_response("Failed to reject exception: Cannot reject", 422)
      end
    end

    context "without supply_chain.admin permission" do
      it "returns forbidden error for writer" do
        post "/api/v1/supply_chain/license_violations/#{violation.id}/reject_exception",
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect(response).to have_http_status(:forbidden)
      end

      it "returns forbidden error for reader" do
        post "/api/v1/supply_chain/license_violations/#{violation.id}/reject_exception",
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /api/v1/supply_chain/license_violations/statistics" do
    let(:sbom) { create(:supply_chain_sbom, account: account) }
    let(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }
    let(:policy) { create(:supply_chain_license_policy, account: account) }
    let(:license) { create(:supply_chain_license, :copyleft) }

    context "with supply_chain.read permission" do
      before do
        create(:supply_chain_license_violation,
               account: account,
               sbom: sbom,
               sbom_component: component,
               license_policy: policy,
               license: license,
               status: "open",
               severity: "critical",
               violation_type: "denied")
        create(:supply_chain_license_violation,
               account: account,
               sbom: sbom,
               sbom_component: component,
               license_policy: policy,
               license: license,
               status: "open",
               severity: "high",
               violation_type: "copyleft")
        create(:supply_chain_license_violation,
               account: account,
               sbom: sbom,
               sbom_component: component,
               license_policy: policy,
               license: license,
               status: "resolved",
               severity: "medium",
               violation_type: "incompatible")
        create(:supply_chain_license_violation, :with_exception,
               account: account,
               sbom: sbom,
               sbom_component: component,
               license_policy: policy,
               license: license,
               status: "open",
               severity: "low",
               violation_type: "unknown")
      end

      it "returns statistics for the account" do
        get "/api/v1/supply_chain/license_violations/statistics",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["total"]).to eq(4)
        expect(data["open_count"]).to eq(3)
        expect(data["exception_pending"]).to eq(1)
      end

      it "returns breakdown by status" do
        get "/api/v1/supply_chain/license_violations/statistics",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        by_status = json_response["data"]["by_status"]

        expect(by_status["open"]).to eq(3)
        expect(by_status["resolved"]).to eq(1)
      end

      it "returns breakdown by severity" do
        get "/api/v1/supply_chain/license_violations/statistics",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        by_severity = json_response["data"]["by_severity"]

        expect(by_severity["critical"]).to eq(1)
        expect(by_severity["high"]).to eq(1)
        expect(by_severity["medium"]).to eq(1)
        expect(by_severity["low"]).to eq(1)
      end

      it "returns breakdown by type" do
        get "/api/v1/supply_chain/license_violations/statistics",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        by_type = json_response["data"]["by_type"]

        expect(by_type["denied"]).to eq(1)
        expect(by_type["copyleft"]).to eq(1)
        expect(by_type["incompatible"]).to eq(1)
        expect(by_type["unknown"]).to eq(1)
      end
    end

    context "with no violations" do
      it "returns zero statistics" do
        get "/api/v1/supply_chain/license_violations/statistics",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response

        expect(json_response["data"]["total"]).to eq(0)
        expect(json_response["data"]["open_count"]).to eq(0)
        expect(json_response["data"]["exception_pending"]).to eq(0)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/license_violations/statistics",
            headers: auth_headers_for(regular_user),
            as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "account isolation" do
    let(:sbom) { create(:supply_chain_sbom, account: account) }
    let(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }
    let(:policy) { create(:supply_chain_license_policy, account: account) }
    let(:license) { create(:supply_chain_license, :copyleft) }
    let!(:account_violation) do
      create(:supply_chain_license_violation,
             account: account,
             sbom: sbom,
             sbom_component: component,
             license_policy: policy,
             license: license)
    end

    let(:other_sbom) { create(:supply_chain_sbom, account: other_account) }
    let(:other_component) { create(:supply_chain_sbom_component, sbom: other_sbom, account: other_account) }
    let(:other_policy) { create(:supply_chain_license_policy, account: other_account) }
    let!(:other_violation) do
      create(:supply_chain_license_violation,
             account: other_account,
             sbom: other_sbom,
             sbom_component: other_component,
             license_policy: other_policy,
             license: license)
    end

    it "only returns violations for the authenticated user account" do
      get "/api/v1/supply_chain/license_violations",
          headers: auth_headers_for(supply_chain_reader),
          as: :json

      expect_success_response
      violation_ids = json_response["data"]["license_violations"].map { |v| v["id"] }

      expect(violation_ids).to include(account_violation.id)
      expect(violation_ids).not_to include(other_violation.id)
    end

    it "prevents accessing another account violation directly" do
      get "/api/v1/supply_chain/license_violations/#{other_violation.id}",
          headers: auth_headers_for(supply_chain_reader),
          as: :json

      expect_error_response("License violation not found", 404)
    end

    it "prevents modifying another account violation" do
      patch "/api/v1/supply_chain/license_violations/#{other_violation.id}",
            params: { license_violation: { notes: "Hacked" } },
            headers: auth_headers_for(supply_chain_writer),
            as: :json

      expect_error_response("License violation not found", 404)
    end

    it "prevents resolving another account violation" do
      post "/api/v1/supply_chain/license_violations/#{other_violation.id}/resolve",
           headers: auth_headers_for(supply_chain_writer),
           as: :json

      expect_error_response("License violation not found", 404)
    end

    it "prevents requesting exception for another account violation" do
      post "/api/v1/supply_chain/license_violations/#{other_violation.id}/request_exception",
           params: { justification: "Valid reason" },
           headers: auth_headers_for(supply_chain_writer),
           as: :json

      expect_error_response("License violation not found", 404)
    end

    it "prevents approving exception for another account violation" do
      post "/api/v1/supply_chain/license_violations/#{other_violation.id}/approve_exception",
           headers: auth_headers_for(supply_chain_admin),
           as: :json

      expect_error_response("License violation not found", 404)
    end

    it "prevents rejecting exception for another account violation" do
      post "/api/v1/supply_chain/license_violations/#{other_violation.id}/reject_exception",
           headers: auth_headers_for(supply_chain_admin),
           as: :json

      expect_error_response("License violation not found", 404)
    end
  end

  describe "response format consistency" do
    let(:sbom) { create(:supply_chain_sbom, account: account) }
    let(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }
    let(:policy) { create(:supply_chain_license_policy, account: account) }
    let(:license) { create(:supply_chain_license, :copyleft) }
    let(:violation) do
      create(:supply_chain_license_violation,
             account: account,
             sbom: sbom,
             sbom_component: component,
             license_policy: policy,
             license: license)
    end

    it "returns consistent success response format for index" do
      get "/api/v1/supply_chain/license_violations",
          headers: auth_headers_for(supply_chain_reader),
          as: :json

      json = json_response
      expect(json).to have_key("success")
      expect(json["data"]).to have_key("license_violations")
      expect(json).to have_key("meta")
      expect(json["success"]).to be true
    end

    it "returns consistent success response format for show" do
      get "/api/v1/supply_chain/license_violations/#{violation.id}",
          headers: auth_headers_for(supply_chain_reader),
          as: :json

      json = json_response
      expect(json).to have_key("success")
      expect(json["data"]).to have_key("license_violation")
      expect(json["success"]).to be true
    end

    it "returns consistent success response format for statistics" do
      get "/api/v1/supply_chain/license_violations/statistics",
          headers: auth_headers_for(supply_chain_reader),
          as: :json

      json = json_response
      expect(json).to have_key("success")
      expect(json["data"]).to have_key("total")
      expect(json["success"]).to be true
    end

    it "returns consistent error response format for not found" do
      get "/api/v1/supply_chain/license_violations/non-existent-id",
          headers: auth_headers_for(supply_chain_reader),
          as: :json

      json = json_response
      expect(json).to have_key("success")
      expect(json).to have_key("error")
      expect(json["success"]).to be false
    end
  end
end
