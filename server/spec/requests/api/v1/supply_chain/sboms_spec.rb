# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::SupplyChain::Sboms", type: :request do
  let(:account) { create(:account) }

  # User with supply_chain.read permission only
  let(:supply_chain_reader) do
    create(:user, account: account, permissions: ["supply_chain.read"])
  end

  # User with both supply_chain.read and supply_chain.write permissions
  let(:supply_chain_writer) do
    create(:user, account: account, permissions: ["supply_chain.read", "supply_chain.write"])
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

  describe "GET /api/v1/supply_chain/sboms" do
    context "with supply_chain.read permission" do
      let!(:sboms) do
        [
          create(:supply_chain_sbom, account: account, status: "completed", format: "cyclonedx_1_5"),
          create(:supply_chain_sbom, account: account, status: "generating", format: "spdx_2_3"),
          create(:supply_chain_sbom, account: account, status: "failed", format: "cyclonedx_1_5")
        ]
      end

      let!(:other_sbom) do
        create(:supply_chain_sbom, account: other_account, status: "completed")
      end

      it "returns sboms for the current account" do
        get "/api/v1/supply_chain/sboms", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["sboms"]

        expect(data.length).to eq(3)
        expect(data.map { |s| s["id"] }).to match_array(sboms.map(&:id))
        expect(data.map { |s| s["id"] }).not_to include(other_sbom.id)
      end

      it "returns sboms ordered by created_at desc" do
        get "/api/v1/supply_chain/sboms", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["sboms"]

        created_ats = data.map { |s| Time.parse(s["created_at"]) }
        expect(created_ats).to eq(created_ats.sort.reverse)
      end

      it "returns sbom data with correct structure" do
        get "/api/v1/supply_chain/sboms", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        sbom_data = json_response["data"]["sboms"].first

        expect(sbom_data).to include(
          "id",
          "sbom_id",
          "name",
          "version",
          "format",
          "component_count",
          "vulnerability_count",
          "risk_score",
          "ntia_minimum_compliant",
          "status",
          "created_at",
          "updated_at"
        )
      end

      it "filters by status" do
        get "/api/v1/supply_chain/sboms?status=completed", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["sboms"]

        expect(data.length).to eq(1)
        expect(data.first["status"]).to eq("completed")
      end

      it "filters by format" do
        get "/api/v1/supply_chain/sboms?format=cyclonedx_1_5", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["sboms"]

        expect(data.length).to eq(2)
        expect(data.all? { |s| s["format"] == "cyclonedx_1_5" }).to be true
      end
    end

    context "pagination" do
      before do
        30.times do
          create(:supply_chain_sbom, account: account)
        end
      end

      it "returns paginated results with default per_page of 20" do
        get "/api/v1/supply_chain/sboms", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        expect(json_response["data"]["sboms"].length).to eq(20)
        expect(json_response["data"]["meta"]["total"]).to eq(30)
        expect(json_response["data"]["meta"]["page"]).to eq(1)
        expect(json_response["data"]["meta"]["per_page"]).to eq(20)
        expect(json_response["data"]["meta"]["total_pages"]).to eq(2)
      end

      it "respects page parameter" do
        get "/api/v1/supply_chain/sboms?page=2", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        expect(json_response["data"]["sboms"].length).to eq(10)
        expect(json_response["data"]["meta"]["page"]).to eq(2)
      end

      it "respects per_page parameter" do
        get "/api/v1/supply_chain/sboms?per_page=10", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        expect(json_response["data"]["sboms"].length).to eq(10)
        expect(json_response["data"]["meta"]["per_page"]).to eq(10)
        expect(json_response["data"]["meta"]["total_pages"]).to eq(3)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/sboms", headers: auth_headers_for(regular_user), as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/sboms", as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "GET /api/v1/supply_chain/sboms/:id" do
    let!(:sbom) { create(:supply_chain_sbom, account: account) }

    context "with supply_chain.read permission" do
      it "returns the sbom details" do
        get "/api/v1/supply_chain/sboms/#{sbom.id}", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["sbom"]

        expect(data["id"]).to eq(sbom.id)
        expect(data["sbom_id"]).to eq(sbom.sbom_id)
        expect(data["name"]).to eq(sbom.name)
        expect(data["format"]).to eq(sbom.format)
        expect(data["status"]).to eq(sbom.status)
      end
    end

    context "with sbom from another account" do
      let(:other_sbom) { create(:supply_chain_sbom, account: other_account) }

      it "returns not found error" do
        get "/api/v1/supply_chain/sboms/#{other_sbom.id}", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_error_response("SBOM not found", 404)
      end
    end

    context "with non-existent sbom" do
      it "returns not found error" do
        get "/api/v1/supply_chain/sboms/non-existent-id", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_error_response("SBOM not found", 404)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/sboms/#{sbom.id}", headers: auth_headers_for(regular_user), as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/sboms" do
    context "with supply_chain.write permission" do
      let(:valid_params) do
        {
          name: "Test Application SBOM",
          version: "1.0.0",
          source_path: "/tmp/test-app",
          ecosystems: ["npm"],
          format: "cyclonedx_1_5"
        }
      end

      it "creates a new sbom" do
        # Use a block so SBOM is created when generate is called, not when stub is set up
        allow_any_instance_of(SupplyChain::SbomGenerationService).to receive(:generate) do
          create(:supply_chain_sbom, account: account, name: "Test Application SBOM")
        end

        expect {
          post "/api/v1/supply_chain/sboms",
               params: valid_params,
               headers: auth_headers_for(supply_chain_writer),
               as: :json
        }.to change(SupplyChain::Sbom, :count).by(1)

        expect(response).to have_http_status(:created)
        expect_success_response
        expect(json_response["data"]["sbom"]["name"]).to eq("Test Application SBOM")
      end

      it "returns error with invalid params" do
        allow_any_instance_of(SupplyChain::SbomGenerationService).to receive(:generate).and_raise(
          StandardError.new("Invalid source path")
        )

        post "/api/v1/supply_chain/sboms",
             params: { name: "" },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_error_response("Failed to generate SBOM: Invalid source path", 422)
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error for user with only supply_chain.read" do
        post "/api/v1/supply_chain/sboms",
             params: { name: "Test SBOM" },
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end

      it "returns forbidden error for regular user" do
        post "/api/v1/supply_chain/sboms",
             params: { name: "Test SBOM" },
             headers: auth_headers_for(regular_user),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "PATCH /api/v1/supply_chain/sboms/:id" do
    let(:sbom) { create(:supply_chain_sbom, account: account, name: "Original Name") }

    context "with supply_chain.write permission" do
      it "updates the sbom" do
        patch "/api/v1/supply_chain/sboms/#{sbom.id}",
              params: { sbom: { name: "Updated Name" } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_success_response
        expect(json_response["data"]["sbom"]["name"]).to eq("Updated Name")

        sbom.reload
        expect(sbom.name).to eq("Updated Name")
      end

      it "updates the version" do
        patch "/api/v1/supply_chain/sboms/#{sbom.id}",
              params: { sbom: { version: "2.0.0" } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_success_response
        expect(json_response["data"]["sbom"]["version"]).to eq("2.0.0")
      end

      it "updates the status" do
        patch "/api/v1/supply_chain/sboms/#{sbom.id}",
              params: { sbom: { status: "archived" } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_success_response
        expect(json_response["data"]["sbom"]["status"]).to eq("archived")
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        patch "/api/v1/supply_chain/sboms/#{sbom.id}",
              params: { sbom: { name: "Updated Name" } },
              headers: auth_headers_for(supply_chain_reader),
              as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "DELETE /api/v1/supply_chain/sboms/:id" do
    let!(:sbom) { create(:supply_chain_sbom, account: account) }

    context "with supply_chain.write permission" do
      it "deletes the sbom" do
        expect {
          delete "/api/v1/supply_chain/sboms/#{sbom.id}",
                 headers: auth_headers_for(supply_chain_writer),
                 as: :json
        }.to change(SupplyChain::Sbom, :count).by(-1)

        expect_success_response
        expect(json_response["data"]["message"]).to eq("SBOM deleted successfully")
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        delete "/api/v1/supply_chain/sboms/#{sbom.id}",
               headers: auth_headers_for(supply_chain_reader),
               as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "GET /api/v1/supply_chain/sboms/:id/components" do
    let(:sbom) { create(:supply_chain_sbom, account: account) }
    let!(:components) do
      [
        create(:supply_chain_sbom_component, sbom: sbom, account: account, dependency_type: "direct", ecosystem: "npm", has_known_vulnerabilities: true),
        create(:supply_chain_sbom_component, sbom: sbom, account: account, dependency_type: "transitive", ecosystem: "npm", has_known_vulnerabilities: false),
        create(:supply_chain_sbom_component, sbom: sbom, account: account, dependency_type: "dev", ecosystem: "gem", has_known_vulnerabilities: false)
      ]
    end

    context "with supply_chain.read permission" do
      it "returns components for the sbom" do
        get "/api/v1/supply_chain/sboms/#{sbom.id}/components",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]["components"]

        expect(data.length).to eq(3)
        expect(data.map { |c| c["id"] }).to match_array(components.map(&:id))
      end

      it "filters by dependency type" do
        get "/api/v1/supply_chain/sboms/#{sbom.id}/components?type=direct",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]["components"]

        expect(data.length).to eq(1)
        expect(data.first["dependency_type"]).to eq("direct")
      end

      it "filters by ecosystem" do
        get "/api/v1/supply_chain/sboms/#{sbom.id}/components?ecosystem=npm",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]["components"]

        expect(data.length).to eq(2)
        expect(data.all? { |c| c["ecosystem"] == "npm" }).to be true
      end

      it "filters by vulnerable components" do
        get "/api/v1/supply_chain/sboms/#{sbom.id}/components?vulnerable=true",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]["components"]

        expect(data.length).to eq(1)
        expect(data.first["has_known_vulnerabilities"]).to be true
      end

      it "includes pagination metadata" do
        get "/api/v1/supply_chain/sboms/#{sbom.id}/components",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        expect(json_response["data"]["meta"]).to include(
          "total",
          "page",
          "per_page"
        )
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/sboms/#{sbom.id}/components",
            headers: auth_headers_for(regular_user),
            as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "GET /api/v1/supply_chain/sboms/:id/vulnerabilities" do
    let(:sbom) { create(:supply_chain_sbom, account: account) }
    let(:component1) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }
    let(:component2) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }
    let!(:vulnerabilities) do
      [
        create(:supply_chain_sbom_vulnerability, sbom: sbom, component: component1, account: account, severity: "critical", remediation_status: "open", cvss_score: 9.8),
        create(:supply_chain_sbom_vulnerability, sbom: sbom, component: component1, account: account, severity: "high", remediation_status: "in_progress", cvss_score: 7.5),
        create(:supply_chain_sbom_vulnerability, sbom: sbom, component: component2, account: account, severity: "medium", remediation_status: "fixed", cvss_score: 5.3)
      ]
    end

    context "with supply_chain.read permission" do
      it "returns vulnerabilities for the sbom" do
        get "/api/v1/supply_chain/sboms/#{sbom.id}/vulnerabilities",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]["vulnerabilities"]

        expect(data.length).to eq(3)
        expect(data.map { |v| v["id"] }).to match_array(vulnerabilities.map(&:id))
      end

      it "returns vulnerabilities ordered by cvss_score desc" do
        get "/api/v1/supply_chain/sboms/#{sbom.id}/vulnerabilities",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]["vulnerabilities"]

        cvss_scores = data.map { |v| v["cvss_score"] }
        expect(cvss_scores).to eq(cvss_scores.sort.reverse)
      end

      it "filters by severity" do
        get "/api/v1/supply_chain/sboms/#{sbom.id}/vulnerabilities?severity=critical",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]["vulnerabilities"]

        expect(data.length).to eq(1)
        expect(data.first["severity"]).to eq("critical")
      end

      it "filters by remediation status" do
        get "/api/v1/supply_chain/sboms/#{sbom.id}/vulnerabilities?status=fixed",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]["vulnerabilities"]

        expect(data.length).to eq(1)
        expect(data.first["remediation_status"]).to eq("fixed")
      end

      it "includes vulnerability breakdown by severity in metadata" do
        get "/api/v1/supply_chain/sboms/#{sbom.id}/vulnerabilities",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        meta = json_response["data"]["meta"]

        expect(meta["by_severity"]).to include(
          "critical" => 1,
          "high" => 1,
          "medium" => 1,
          "low" => 0
        )
      end

      it "includes component information" do
        get "/api/v1/supply_chain/sboms/#{sbom.id}/vulnerabilities",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        vuln = json_response["data"]["vulnerabilities"].first

        expect(vuln["component"]).to include(
          "id",
          "name",
          "version"
        )
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/sboms/#{sbom.id}/vulnerabilities",
            headers: auth_headers_for(regular_user),
            as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/sboms/:id/export" do
    let(:sbom) { create(:supply_chain_sbom, account: account, name: "Test SBOM") }

    context "with supply_chain.write permission" do
      before do
        allow_any_instance_of(SupplyChain::Sbom).to receive(:export).with(format: anything).and_return(
          { "bomFormat" => "CycloneDX", "specVersion" => "1.5" }
        )
      end

      it "exports the sbom in json format" do
        post "/api/v1/supply_chain/sboms/#{sbom.id}/export",
             params: { export_format: "json" },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["format"]).to eq("json")
        expect(data["document"]).to be_present
        expect(data["filename"]).to include(".json")
      end

      it "exports the sbom in xml format" do
        post "/api/v1/supply_chain/sboms/#{sbom.id}/export",
             params: { export_format: "xml" },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        expect(json_response["data"]["format"]).to eq("xml")
        expect(json_response["data"]["filename"]).to include(".xml")
      end

      it "defaults to json format when not specified" do
        post "/api/v1/supply_chain/sboms/#{sbom.id}/export",
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        expect(json_response["data"]["format"]).to eq("json")
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/sboms/#{sbom.id}/export",
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "GET /api/v1/supply_chain/sboms/:id/compliance_status" do
    let(:sbom) { create(:supply_chain_sbom, account: account, ntia_minimum_compliant: true, risk_score: 45) }
    let(:component) { create(:supply_chain_sbom_component, sbom: sbom, account: account) }
    let!(:critical_vuln) do
      create(:supply_chain_sbom_vulnerability, sbom: sbom, component: component, account: account, severity: "critical")
    end
    let!(:high_vuln) do
      create(:supply_chain_sbom_vulnerability, sbom: sbom, component: component, account: account, severity: "high")
    end

    context "with supply_chain.read permission" do
      before do
        allow_any_instance_of(SupplyChain::Sbom).to receive(:ntia_compliance_details).and_return(
          { "has_component_name" => true, "has_supplier" => true }
        )
      end

      it "returns compliance status for the sbom" do
        get "/api/v1/supply_chain/sboms/#{sbom.id}/compliance_status",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["sbom_id"]).to eq(sbom.id)
        expect(data["ntia_compliant"]).to be true
        expect(data["risk_score"].to_f).to eq(45.0)
      end

      it "includes NTIA compliance details" do
        get "/api/v1/supply_chain/sboms/#{sbom.id}/compliance_status",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        expect(json_response["data"]["ntia_compliance_details"]).to include(
          "has_component_name" => true,
          "has_supplier" => true
        )
      end

      it "includes vulnerability summary by severity" do
        get "/api/v1/supply_chain/sboms/#{sbom.id}/compliance_status",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        summary = json_response["data"]["vulnerability_summary"]

        expect(summary["total"]).to eq(sbom.vulnerability_count)
        expect(summary["critical"]).to eq(1)
        expect(summary["high"]).to eq(1)
        expect(summary["medium"]).to eq(0)
        expect(summary["low"]).to eq(0)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/sboms/#{sbom.id}/compliance_status",
            headers: auth_headers_for(regular_user),
            as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/sboms/:id/correlate_vulnerabilities" do
    let(:sbom) { create(:supply_chain_sbom, account: account) }

    context "with supply_chain.write permission" do
      it "correlates vulnerabilities for the sbom" do
        allow_any_instance_of(SupplyChain::VulnerabilityCorrelationService).to receive(:correlate!).and_return(5)

        post "/api/v1/supply_chain/sboms/#{sbom.id}/correlate_vulnerabilities",
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["sbom_id"]).to eq(sbom.id)
        expect(data["vulnerabilities_found"]).to eq(5)
        expect(data["message"]).to eq("Vulnerability correlation completed")
      end

      it "returns error when correlation fails" do
        allow_any_instance_of(SupplyChain::VulnerabilityCorrelationService).to receive(:correlate!).and_raise(
          StandardError.new("API unavailable")
        )

        post "/api/v1/supply_chain/sboms/#{sbom.id}/correlate_vulnerabilities",
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_error_response("Correlation failed: API unavailable", 422)
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/sboms/#{sbom.id}/correlate_vulnerabilities",
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/sboms/:id/calculate_risk" do
    let(:sbom) { create(:supply_chain_sbom, account: account) }

    context "with supply_chain.write permission" do
      it "calculates risk for the sbom" do
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!).and_return(
          {
            overall_score: 67,
            vulnerability_risk: 45,
            dependency_risk: 30,
            license_risk: 15
          }
        )

        post "/api/v1/supply_chain/sboms/#{sbom.id}/calculate_risk",
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["sbom_id"]).to eq(sbom.id)
        expect(data["risk_score"]).to eq(67)
        expect(data["risk_breakdown"]).to include(
          "overall_score" => 67,
          "vulnerability_risk" => 45,
          "dependency_risk" => 30,
          "license_risk" => 15
        )
        expect(data["message"]).to eq("Risk calculation completed")
      end

      it "returns error when calculation fails" do
        allow_any_instance_of(SupplyChain::RiskCalculationService).to receive(:calculate!).and_raise(
          StandardError.new("Insufficient data")
        )

        post "/api/v1/supply_chain/sboms/#{sbom.id}/calculate_risk",
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_error_response("Risk calculation failed: Insufficient data", 422)
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/sboms/#{sbom.id}/calculate_risk",
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "GET /api/v1/supply_chain/sboms/statistics" do
    context "with supply_chain.read permission" do
      before do
        # Create SBOMs and then set counts using update_column to bypass the update_counters callback
        # which overwrites component_count based on document contents
        sbom1 = create(:supply_chain_sbom, account: account, status: "completed", format: "cyclonedx_1_5", risk_score: 45, ntia_minimum_compliant: true)
        sbom1.update_columns(component_count: 100, vulnerability_count: 5)

        sbom2 = create(:supply_chain_sbom, account: account, status: "completed", format: "spdx_2_3", risk_score: 30, ntia_minimum_compliant: true)
        sbom2.update_columns(component_count: 75, vulnerability_count: 3)

        sbom3 = create(:supply_chain_sbom, account: account, status: "generating", format: "cyclonedx_1_5", risk_score: 65, ntia_minimum_compliant: false)
        sbom3.update_columns(component_count: 50, vulnerability_count: 10)
      end

      it "returns statistics for the account" do
        get "/api/v1/supply_chain/sboms/statistics",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["total_sboms"]).to eq(3)
        expect(data["total_components"]).to eq(225)
        expect(data["total_vulnerabilities"]).to eq(18)
        expect(data["ntia_compliant_count"]).to eq(2)
      end

      it "returns average risk score" do
        get "/api/v1/supply_chain/sboms/statistics",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        # JSON serializes decimals as strings, so convert and check
        avg_score = json_response["data"]["average_risk_score"]
        expect(avg_score).to be_present
        expect(avg_score.to_f).to be_a(Float)
      end

      it "returns breakdown by format" do
        get "/api/v1/supply_chain/sboms/statistics",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        by_format = json_response["data"]["by_format"]

        expect(by_format["cyclonedx_1_5"]).to eq(2)
        expect(by_format["spdx_2_3"]).to eq(1)
      end

      it "returns breakdown by status" do
        get "/api/v1/supply_chain/sboms/statistics",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        by_status = json_response["data"]["by_status"]

        expect(by_status["completed"]).to eq(2)
        expect(by_status["generating"]).to eq(1)
      end
    end

    context "with no sboms" do
      it "returns zero statistics" do
        get "/api/v1/supply_chain/sboms/statistics",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response

        expect(json_response["data"]["total_sboms"]).to eq(0)
        expect(json_response["data"]["total_components"]).to eq(0)
        expect(json_response["data"]["total_vulnerabilities"]).to eq(0)
        expect(json_response["data"]["ntia_compliant_count"]).to eq(0)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/sboms/statistics",
            headers: auth_headers_for(regular_user),
            as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "account isolation" do
    let!(:account_sbom) { create(:supply_chain_sbom, account: account) }
    let!(:other_sbom) { create(:supply_chain_sbom, account: other_account) }

    it "only returns sboms for the authenticated user account" do
      get "/api/v1/supply_chain/sboms", headers: auth_headers_for(supply_chain_reader), as: :json

      expect_success_response
      sbom_ids = json_response["data"]["sboms"].map { |s| s["id"] }

      expect(sbom_ids).to include(account_sbom.id)
      expect(sbom_ids).not_to include(other_sbom.id)
    end

    it "prevents accessing another account sbom directly" do
      get "/api/v1/supply_chain/sboms/#{other_sbom.id}", headers: auth_headers_for(supply_chain_reader), as: :json

      expect_error_response("SBOM not found", 404)
    end

    it "prevents modifying another account sbom" do
      patch "/api/v1/supply_chain/sboms/#{other_sbom.id}",
            params: { sbom: { name: "Hacked" } },
            headers: auth_headers_for(supply_chain_writer),
            as: :json

      expect_error_response("SBOM not found", 404)
    end

    it "prevents deleting another account sbom" do
      delete "/api/v1/supply_chain/sboms/#{other_sbom.id}",
             headers: auth_headers_for(supply_chain_writer),
             as: :json

      expect_error_response("SBOM not found", 404)
    end
  end
end
