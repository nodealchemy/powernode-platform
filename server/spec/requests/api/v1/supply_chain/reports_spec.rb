# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::SupplyChain::Reports", type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

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

  before(:each) do
    Rails.cache.clear
  end

  describe "GET /api/v1/supply_chain/reports" do
    context "with supply_chain.read permission" do
      let!(:reports) do
        [
          create(:supply_chain_report, account: account, report_type: "sbom_export", status: "completed", format: "json"),
          create(:supply_chain_report, account: account, report_type: "vulnerability", status: "pending", format: "pdf"),
          create(:supply_chain_report, account: account, report_type: "attribution", status: "failed", format: "csv")
        ]
      end

      let!(:other_report) do
        create(:supply_chain_report, account: other_account, status: "completed")
      end

      it "returns reports for the current account" do
        get "/api/v1/supply_chain/reports", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["reports"]

        expect(data.length).to eq(3)
        expect(data.map { |r| r["id"] }).to match_array(reports.map(&:id))
        expect(data.map { |r| r["id"] }).not_to include(other_report.id)
      end

      it "returns reports ordered by created_at desc" do
        get "/api/v1/supply_chain/reports", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["reports"]

        created_ats = data.map { |r| Time.parse(r["created_at"]) }
        expect(created_ats).to eq(created_ats.sort.reverse)
      end

      it "returns report data with correct structure" do
        get "/api/v1/supply_chain/reports", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        report_data = json_response["data"]["reports"].first

        expect(report_data).to include(
          "id",
          "name",
          "report_type",
          "format",
          "status",
          "created_at"
        )
      end

      it "filters by report type" do
        get "/api/v1/supply_chain/reports?type=sbom_export", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["reports"]

        expect(data.length).to eq(1)
        expect(data.first["report_type"]).to eq("sbom_export")
      end

      it "filters by status" do
        get "/api/v1/supply_chain/reports?status=completed", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["reports"]

        expect(data.length).to eq(1)
        expect(data.first["status"]).to eq("completed")
      end

      it "filters by format" do
        get "/api/v1/supply_chain/reports?format=pdf", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["reports"]

        expect(data.length).to eq(1)
        expect(data.first["format"]).to eq("pdf")
      end

      it "applies multiple filters" do
        create(:supply_chain_report, account: account, report_type: "sbom_export", status: "completed", format: "pdf")

        get "/api/v1/supply_chain/reports?type=sbom_export&status=completed&format=pdf",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]["reports"]

        expect(data.length).to eq(1)
        expect(data.first["report_type"]).to eq("sbom_export")
        expect(data.first["status"]).to eq("completed")
        expect(data.first["format"]).to eq("pdf")
      end
    end

    context "pagination" do
      before do
        30.times do
          create(:supply_chain_report, account: account)
        end
      end

      it "returns paginated results with default per_page of 20" do
        get "/api/v1/supply_chain/reports", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        expect(json_response["data"]["reports"].length).to eq(20)
        expect(json_response["meta"]["total_count"]).to eq(30)
        expect(json_response["meta"]["current_page"]).to eq(1)
        expect(json_response["meta"]["per_page"]).to eq(20)
      end

      it "respects page parameter" do
        get "/api/v1/supply_chain/reports?page=2", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        expect(json_response["data"]["reports"].length).to eq(10)
        expect(json_response["meta"]["current_page"]).to eq(2)
      end

      it "respects per_page parameter" do
        get "/api/v1/supply_chain/reports?per_page=10", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        expect(json_response["data"]["reports"].length).to eq(10)
        expect(json_response["meta"]["per_page"]).to eq(10)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/reports", headers: auth_headers_for(regular_user), as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/reports", as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "GET /api/v1/supply_chain/reports/:id" do
    let!(:report) { create(:supply_chain_report, account: account, created_by: supply_chain_writer) }

    context "with supply_chain.read permission" do
      it "returns the report details" do
        get "/api/v1/supply_chain/reports/#{report.id}", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["report"]

        expect(data["id"]).to eq(report.id)
        expect(data["name"]).to eq(report.name)
        expect(data["report_type"]).to eq(report.report_type)
        expect(data["format"]).to eq(report.format)
        expect(data["status"]).to eq(report.status)
      end

      it "includes detailed fields" do
        get "/api/v1/supply_chain/reports/#{report.id}", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["report"]

        expect(data).to have_key("parameters")
        expect(data).to have_key("error_message")
        expect(data).to have_key("created_by")
      end

      it "includes created_by user information" do
        get "/api/v1/supply_chain/reports/#{report.id}", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["report"]

        expect(data["created_by"]).to include(
          "id" => supply_chain_writer.id,
          "email" => supply_chain_writer.email
        )
      end
    end

    context "with report from another account" do
      let(:other_report) { create(:supply_chain_report, account: other_account) }

      it "returns not found error" do
        get "/api/v1/supply_chain/reports/#{other_report.id}", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_error_response("Report not found", 404)
      end
    end

    context "with non-existent report" do
      it "returns not found error" do
        get "/api/v1/supply_chain/reports/non-existent-id", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_error_response("Report not found", 404)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/reports/#{report.id}", headers: auth_headers_for(regular_user), as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/reports" do
    context "with supply_chain.write permission" do
      let(:valid_params) do
        {
          report: {
            name: "Test Report",
            report_type: "sbom_export",
            format: "json",
            parameters: { sbom_id: "test-sbom-id" }
          }
        }
      end

      it "creates a new report" do
        expect {
          post "/api/v1/supply_chain/reports",
               params: valid_params,
               headers: auth_headers_for(supply_chain_writer),
               as: :json
        }.to change(SupplyChain::Report, :count).by(1)

        expect(response).to have_http_status(:created)
        expect_success_response
        expect(json_response["data"]["report"]["name"]).to eq("Test Report")
        expect(json_response["data"]["message"]).to eq("Report generation started")
      end

      it "associates report with current account" do
        post "/api/v1/supply_chain/reports",
             params: valid_params,
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        report = SupplyChain::Report.last
        expect(report.account_id).to eq(account.id)
      end

      it "associates report with current user as generated_by" do
        post "/api/v1/supply_chain/reports",
             params: valid_params,
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        report = SupplyChain::Report.last
        expect(report.created_by_id).to eq(supply_chain_writer.id)
      end

      it "enqueues report generation job" do
        allow(WorkerJobService).to receive(:enqueue_job)

        post "/api/v1/supply_chain/reports",
             params: valid_params,
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
      end

      it "returns error with invalid params" do
        post "/api/v1/supply_chain/reports",
             params: { report: { name: "" } },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error for user with only supply_chain.read" do
        post "/api/v1/supply_chain/reports",
             params: { report: { name: "Test" } },
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end

      it "returns forbidden error for regular user" do
        post "/api/v1/supply_chain/reports",
             params: { report: { name: "Test" } },
             headers: auth_headers_for(regular_user),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "PATCH /api/v1/supply_chain/reports/:id" do
    let(:report) { create(:supply_chain_report, account: account, name: "Original Name") }

    context "with supply_chain.write permission" do
      it "updates the report" do
        patch "/api/v1/supply_chain/reports/#{report.id}",
              params: { report: { name: "Updated Name" } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_success_response
        expect(json_response["data"]["report"]["name"]).to eq("Updated Name")
        expect(json_response["data"]["message"]).to eq("Report updated successfully")

        report.reload
        expect(report.name).to eq("Updated Name")
      end

      it "updates report parameters" do
        patch "/api/v1/supply_chain/reports/#{report.id}",
              params: { report: { parameters: { custom_field: "value" } } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_success_response
        report.reload
        expect(report.parameters["custom_field"]).to eq("value")
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        patch "/api/v1/supply_chain/reports/#{report.id}",
              params: { report: { name: "Updated Name" } },
              headers: auth_headers_for(supply_chain_reader),
              as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "DELETE /api/v1/supply_chain/reports/:id" do
    let!(:report) { create(:supply_chain_report, account: account) }

    context "with supply_chain.write permission" do
      it "deletes the report" do
        expect {
          delete "/api/v1/supply_chain/reports/#{report.id}",
                 headers: auth_headers_for(supply_chain_writer),
                 as: :json
        }.to change(SupplyChain::Report, :count).by(-1)

        expect_success_response
        expect(json_response["data"]["message"]).to eq("Report deleted successfully")
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        delete "/api/v1/supply_chain/reports/#{report.id}",
               headers: auth_headers_for(supply_chain_reader),
               as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "GET /api/v1/supply_chain/reports/:id/download" do
    context "with completed report" do
      let(:report) do
        create(:supply_chain_report, account: account, status: "completed", file_path: "/tmp/report.pdf")
      end

      it "returns download information" do
        get "/api/v1/supply_chain/reports/#{report.id}/download",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["report_id"]).to eq(report.id)
        expect(data["filename"]).to be_present
        expect(data["content_type"]).to be_present
        expect(data["download_url"]).to be_present
        expect(data["expires_at"]).to be_present
      end
    end

    context "with pending report" do
      let(:report) { create(:supply_chain_report, account: account, status: "pending", file_path: nil) }

      it "returns error" do
        get "/api/v1/supply_chain/reports/#{report.id}/download",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_error_response("Report not ready for download", 422)
      end
    end

    context "with completed report but no file" do
      let(:report) { create(:supply_chain_report, account: account, status: "completed", file_path: nil) }

      it "returns error" do
        get "/api/v1/supply_chain/reports/#{report.id}/download",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_error_response("Report not ready for download", 422)
      end
    end

    context "without supply_chain.read permission" do
      let(:report) { create(:supply_chain_report, account: account, status: "completed", file_path: "/tmp/report.pdf") }

      it "returns forbidden error" do
        get "/api/v1/supply_chain/reports/#{report.id}/download",
            headers: auth_headers_for(regular_user),
            as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/reports/:id/regenerate" do
    let(:report) { create(:supply_chain_report, account: account, status: "failed", metadata: { "error" => "Original error" }) }

    context "with supply_chain.write permission" do
      it "resets report status to pending" do
        post "/api/v1/supply_chain/reports/#{report.id}/regenerate",
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        report.reload
        expect(report.status).to eq("pending")
      end

      it "clears error message" do
        post "/api/v1/supply_chain/reports/#{report.id}/regenerate",
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        report.reload
        expect(report.metadata["error"]).to be_nil
      end

      it "enqueues report generation job" do
        allow(WorkerJobService).to receive(:enqueue_job)

        post "/api/v1/supply_chain/reports/#{report.id}/regenerate",
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        expect(json_response["data"]["message"]).to eq("Report regeneration started")
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/reports/#{report.id}/regenerate",
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/reports/generate_sbom" do
    let!(:sbom) { create(:supply_chain_sbom, account: account, name: "Test SBOM") }

    context "with supply_chain.write permission" do
      it "creates a new SBOM report" do
        expect {
          post "/api/v1/supply_chain/reports/generate_sbom",
               params: { sbom_id: sbom.id, format: "json" },
               headers: auth_headers_for(supply_chain_writer),
               as: :json
        }.to change(SupplyChain::Report, :count).by(1)

        expect(response).to have_http_status(:created)
        expect_success_response
      end

      it "creates report with correct parameters" do
        post "/api/v1/supply_chain/reports/generate_sbom",
             params: { sbom_id: sbom.id, format: "json", include_vulnerabilities: true },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        report = SupplyChain::Report.last
        expect(report.report_type).to eq("sbom_export")
        expect(report.format).to eq("json")
        expect(report.parameters["sbom_id"]).to eq(sbom.id)
        expect(report.parameters["include_vulnerabilities"]).to be true
      end

      it "uses custom name if provided" do
        post "/api/v1/supply_chain/reports/generate_sbom",
             params: { sbom_id: sbom.id, name: "Custom SBOM Report" },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        expect(json_response["data"]["report"]["name"]).to eq("Custom SBOM Report")
      end

      it "generates default name if not provided" do
        post "/api/v1/supply_chain/reports/generate_sbom",
             params: { sbom_id: sbom.id },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        expect(json_response["data"]["report"]["name"]).to include("SBOM Report")
        expect(json_response["data"]["report"]["name"]).to include(sbom.name)
      end

      it "returns error for non-existent SBOM" do
        post "/api/v1/supply_chain/reports/generate_sbom",
             params: { sbom_id: "non-existent" },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_error_response("SBOM not found", 404)
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/reports/generate_sbom",
             params: { sbom_id: sbom.id },
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/reports/generate_attribution" do
    let!(:sbom) { create(:supply_chain_sbom, account: account) }

    context "with supply_chain.write permission" do
      it "creates a new attribution report" do
        expect {
          post "/api/v1/supply_chain/reports/generate_attribution",
               params: { sbom_id: sbom.id },
               headers: auth_headers_for(supply_chain_writer),
               as: :json
        }.to change(SupplyChain::Report, :count).by(1)

        expect(response).to have_http_status(:created)
        expect_success_response
      end

      it "creates report with correct parameters" do
        post "/api/v1/supply_chain/reports/generate_attribution",
             params: { sbom_ids: [sbom.id], include_license_text: false },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        report = SupplyChain::Report.last
        expect(report.report_type).to eq("attribution")
        expect(report.format).to eq("html")
        expect(report.parameters["sbom_ids"]).to eq([sbom.id])
        expect(report.parameters["include_license_text"]).to be false
      end

      it "defaults to include_license_text true" do
        post "/api/v1/supply_chain/reports/generate_attribution",
             params: { sbom_id: sbom.id },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        report = SupplyChain::Report.last
        expect(report.parameters["include_license_text"]).to be true
      end

      it "supports custom format" do
        post "/api/v1/supply_chain/reports/generate_attribution",
             params: { sbom_id: sbom.id, format: "html" },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        report = SupplyChain::Report.last
        expect(report.format).to eq("html")
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/reports/generate_attribution",
             params: { sbom_id: sbom.id },
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/reports/generate_compliance" do
    context "with supply_chain.write permission" do
      it "creates a new compliance report" do
        expect {
          post "/api/v1/supply_chain/reports/generate_compliance",
               params: { framework: "ntia" },
               headers: auth_headers_for(supply_chain_writer),
               as: :json
        }.to change(SupplyChain::Report, :count).by(1)

        expect(response).to have_http_status(:created)
        expect_success_response
      end

      it "creates report with correct parameters" do
        post "/api/v1/supply_chain/reports/generate_compliance",
             params: {
               framework: "soc2",
               sbom_ids: ["sbom-1", "sbom-2"],
               start_date: "2024-01-01",
               end_date: "2024-12-31"
             },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        report = SupplyChain::Report.last
        expect(report.report_type).to eq("compliance")
        expect(report.format).to eq("pdf")
        expect(report.parameters["framework"]).to eq("soc2")
        expect(report.parameters["sbom_ids"]).to eq(["sbom-1", "sbom-2"])
        expect(report.parameters["date_range"]["start_date"]).to eq("2024-01-01")
        expect(report.parameters["date_range"]["end_date"]).to eq("2024-12-31")
      end

      it "defaults to ntia framework" do
        post "/api/v1/supply_chain/reports/generate_compliance",
             params: {},
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        report = SupplyChain::Report.last
        expect(report.parameters["framework"]).to eq("ntia")
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/reports/generate_compliance",
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/reports/generate_vulnerability" do
    context "with supply_chain.write permission" do
      it "creates a new vulnerability report" do
        expect {
          post "/api/v1/supply_chain/reports/generate_vulnerability",
               headers: auth_headers_for(supply_chain_writer),
               as: :json
        }.to change(SupplyChain::Report, :count).by(1)

        expect(response).to have_http_status(:created)
        expect_success_response
      end

      it "creates report with correct parameters" do
        post "/api/v1/supply_chain/reports/generate_vulnerability",
             params: {
               sbom_ids: ["sbom-1"],
               container_image_ids: ["image-1"],
               severity_filter: "critical",
               include_remediation: false
             },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        report = SupplyChain::Report.last
        expect(report.report_type).to eq("vulnerability")
        expect(report.format).to eq("pdf")
        expect(report.parameters["sbom_ids"]).to eq(["sbom-1"])
        expect(report.parameters["container_image_ids"]).to eq(["image-1"])
        expect(report.parameters["severity_filter"]).to eq("critical")
        expect(report.parameters["include_remediation"]).to be false
      end

      it "defaults to include_remediation true" do
        post "/api/v1/supply_chain/reports/generate_vulnerability",
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        report = SupplyChain::Report.last
        expect(report.parameters["include_remediation"]).to be true
      end

      it "supports custom format" do
        post "/api/v1/supply_chain/reports/generate_vulnerability",
             params: { format: "csv" },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        report = SupplyChain::Report.last
        expect(report.format).to eq("csv")
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/reports/generate_vulnerability",
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/reports/generate_vendor_risk" do
    context "with supply_chain.write permission" do
      it "creates a new vendor risk report" do
        expect {
          post "/api/v1/supply_chain/reports/generate_vendor_risk",
               headers: auth_headers_for(supply_chain_writer),
               as: :json
        }.to change(SupplyChain::Report, :count).by(1)

        expect(response).to have_http_status(:created)
        expect_success_response
      end

      it "creates report with correct parameters" do
        post "/api/v1/supply_chain/reports/generate_vendor_risk",
             params: {
               vendor_ids: ["vendor-1", "vendor-2"],
               include_assessments: false,
               include_questionnaires: true
             },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        report = SupplyChain::Report.last
        expect(report.report_type).to eq("vendor_risk")
        expect(report.format).to eq("pdf")
        expect(report.parameters["vendor_ids"]).to eq(["vendor-1", "vendor-2"])
        expect(report.parameters["include_assessments"]).to be false
        expect(report.parameters["include_questionnaires"]).to be true
      end

      it "defaults to include_assessments true" do
        post "/api/v1/supply_chain/reports/generate_vendor_risk",
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        report = SupplyChain::Report.last
        expect(report.parameters["include_assessments"]).to be true
      end

      it "defaults to include_questionnaires false" do
        post "/api/v1/supply_chain/reports/generate_vendor_risk",
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        report = SupplyChain::Report.last
        expect(report.parameters["include_questionnaires"]).to be false
      end

      it "supports custom format" do
        post "/api/v1/supply_chain/reports/generate_vendor_risk",
             params: { format: "csv" },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        report = SupplyChain::Report.last
        expect(report.format).to eq("csv")
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/reports/generate_vendor_risk",
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "account isolation" do
    let!(:account_report) { create(:supply_chain_report, account: account) }
    let!(:other_report) { create(:supply_chain_report, account: other_account) }

    it "only returns reports for the authenticated user account" do
      get "/api/v1/supply_chain/reports", headers: auth_headers_for(supply_chain_reader), as: :json

      expect_success_response
      report_ids = json_response["data"]["reports"].map { |r| r["id"] }

      expect(report_ids).to include(account_report.id)
      expect(report_ids).not_to include(other_report.id)
    end

    it "prevents accessing another account report directly" do
      get "/api/v1/supply_chain/reports/#{other_report.id}", headers: auth_headers_for(supply_chain_reader), as: :json

      expect_error_response("Report not found", 404)
    end

    it "prevents modifying another account report" do
      patch "/api/v1/supply_chain/reports/#{other_report.id}",
            params: { report: { name: "Hacked" } },
            headers: auth_headers_for(supply_chain_writer),
            as: :json

      expect_error_response("Report not found", 404)
    end

    it "prevents deleting another account report" do
      delete "/api/v1/supply_chain/reports/#{other_report.id}",
             headers: auth_headers_for(supply_chain_writer),
             as: :json

      expect_error_response("Report not found", 404)
    end

    it "prevents downloading another account report" do
      other_report.update!(status: "completed", file_path: "/tmp/report.pdf")

      get "/api/v1/supply_chain/reports/#{other_report.id}/download",
          headers: auth_headers_for(supply_chain_reader),
          as: :json

      expect_error_response("Report not found", 404)
    end

    it "prevents regenerating another account report" do
      post "/api/v1/supply_chain/reports/#{other_report.id}/regenerate",
           headers: auth_headers_for(supply_chain_writer),
           as: :json

      expect_error_response("Report not found", 404)
    end
  end
end
