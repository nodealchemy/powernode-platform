# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::SupplyChain::ScanInstances", type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  # User with supply_chain.read permission only
  let(:supply_chain_reader) do
    create(:user, account: account, permissions: [ "supply_chain.read" ])
  end

  # User with both supply_chain.read and supply_chain.write permissions
  let(:supply_chain_writer) do
    create(:user, account: account, permissions: [ "supply_chain.read", "supply_chain.write" ])
  end

  # User without supply_chain permissions
  let(:regular_user) do
    create(:user, account: account, permissions: [])
  end

  before(:each) do
    Rails.cache.clear
  end

  describe "GET /api/v1/supply_chain/scan_instances" do
    context "with supply_chain.read permission" do
      let!(:scan_templates) do
        [
          create(:supply_chain_scan_template),
          create(:supply_chain_scan_template),
          create(:supply_chain_scan_template)
        ]
      end
      let!(:scan_instances) do
        [
          create(:supply_chain_scan_instance, account: account, scan_template: scan_templates[0], status: "active", name: "Active Instance 1"),
          create(:supply_chain_scan_instance, account: account, scan_template: scan_templates[1], status: "active", name: "Active Instance 2"),
          create(:supply_chain_scan_instance, account: account, scan_template: scan_templates[2], status: "paused", name: "Paused Instance")
        ]
      end

      let!(:other_instance) do
        create(:supply_chain_scan_instance, account: other_account, scan_template: scan_templates[0])
      end

      it "returns scan instances for the current account" do
        get "/api/v1/supply_chain/scan_instances", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["scan_instances"].length).to eq(3)
        expect(data["scan_instances"].map { |i| i["id"] }).to match_array(scan_instances.map(&:id))
        expect(data["scan_instances"].map { |i| i["id"] }).not_to include(other_instance.id)
      end

      it "returns scan instances ordered by created_at desc" do
        get "/api/v1/supply_chain/scan_instances", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]

        created_ats = data["scan_instances"].map { |i| Time.parse(i["created_at"]) }
        expect(created_ats).to eq(created_ats.sort.reverse)
      end

      it "returns scan instance data with correct structure" do
        get "/api/v1/supply_chain/scan_instances", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        instance_data = json_response["data"]["scan_instances"].first

        expect(instance_data).to include(
          "id",
          "name",
          "description",
          "scan_template_id",
          "scan_template_name",
          "schedule_cron",
          "execution_count",
          "created_at"
        )
      end

      it "filters by active_only=true" do
        get "/api/v1/supply_chain/scan_instances?active_only=true", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["scan_instances"].length).to eq(2)
        expect(data["scan_instances"].map { |i| i["id"] }).to match_array([ scan_instances[0].id, scan_instances[1].id ])
      end

      it "returns all instances when active_only is not specified" do
        get "/api/v1/supply_chain/scan_instances", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["scan_instances"].length).to eq(3)
      end
    end

    context "pagination" do
      before do
        30.times do
          scan_template = create(:supply_chain_scan_template)
          create(:supply_chain_scan_instance, account: account, scan_template: scan_template)
        end
      end

      it "returns paginated results with default per_page of 20" do
        get "/api/v1/supply_chain/scan_instances", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["scan_instances"].length).to eq(20)
        expect(json_response["meta"]["total_count"]).to eq(30)
        expect(json_response["meta"]["current_page"]).to eq(1)
        expect(json_response["meta"]["per_page"]).to eq(20)
        expect(json_response["meta"]["total_pages"]).to eq(2)
      end

      it "respects page parameter" do
        get "/api/v1/supply_chain/scan_instances?page=2", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["scan_instances"].length).to eq(10)
        expect(json_response["meta"]["current_page"]).to eq(2)
      end

      it "respects per_page parameter" do
        get "/api/v1/supply_chain/scan_instances?per_page=10", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["scan_instances"].length).to eq(10)
        expect(json_response["meta"]["per_page"]).to eq(10)
        expect(json_response["meta"]["total_pages"]).to eq(3)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/scan_instances", headers: auth_headers_for(regular_user), as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/scan_instances", as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "GET /api/v1/supply_chain/scan_instances/:id" do
    let(:scan_template) { create(:supply_chain_scan_template) }
    let!(:scan_instance) { create(:supply_chain_scan_instance, account: account, scan_template: scan_template, name: "Test Instance") }

    context "with supply_chain.read permission" do
      it "returns the scan instance details" do
        get "/api/v1/supply_chain/scan_instances/#{scan_instance.id}", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["scan_instance"]

        expect(data["id"]).to eq(scan_instance.id)
        expect(data["name"]).to eq(scan_instance.name)
        expect(data["scan_template_id"]).to eq(scan_template.id)
      end

      it "includes detailed information" do
        get "/api/v1/supply_chain/scan_instances/#{scan_instance.id}", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["scan_instance"]

        expect(data).to include(
          "configuration",
          "recent_executions",
          "metadata"
        )
      end
    end

    context "with scan instance from another account" do
      let(:other_instance) { create(:supply_chain_scan_instance, account: other_account, scan_template: scan_template) }

      it "returns not found error" do
        get "/api/v1/supply_chain/scan_instances/#{other_instance.id}", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_error_response("Scan instance not found", 404)
      end
    end

    context "with non-existent scan instance" do
      it "returns not found error" do
        get "/api/v1/supply_chain/scan_instances/non-existent-id", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_error_response("Scan instance not found", 404)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/scan_instances/#{scan_instance.id}", headers: auth_headers_for(regular_user), as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/scan_instances" do
    let(:scan_template) { create(:supply_chain_scan_template) }

    context "with supply_chain.write permission" do
      let(:valid_params) do
        {
          scan_instance: {
            name: "New Scan Instance",
            description: "Test scan instance",
            scan_template_id: scan_template.id,
            schedule_cron: "0 0 * * *",
            configuration: { key: "value" },
            metadata: { info: "test" }
          }
        }
      end

      it "creates a new scan instance" do
        expect {
          post "/api/v1/supply_chain/scan_instances",
               params: valid_params,
               headers: auth_headers_for(supply_chain_writer),
               as: :json
        }.to change(SupplyChain::ScanInstance, :count).by(1)

        expect(response).to have_http_status(:created)
        expect_success_response
        expect(json_response["data"]["scan_instance"]["name"]).to eq("New Scan Instance")
      end

      it "associates the scan instance with the current user" do
        post "/api/v1/supply_chain/scan_instances",
             params: valid_params,
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        instance = SupplyChain::ScanInstance.last
        expect(instance.installed_by).to eq(supply_chain_writer)
      end

      it "associates the scan instance with the current account" do
        post "/api/v1/supply_chain/scan_instances",
             params: valid_params,
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        instance = SupplyChain::ScanInstance.last
        expect(instance.account).to eq(account)
      end

      it "returns error with missing required fields" do
        post "/api/v1/supply_chain/scan_instances",
             params: { scan_instance: { description: "Missing name" } },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["error"]).to include("Name can't be blank")
      end

      it "returns error with invalid scan_template_id" do
        invalid_params = valid_params.deep_dup
        invalid_params[:scan_instance][:scan_template_id] = "non-existent-id"

        post "/api/v1/supply_chain/scan_instances",
             params: invalid_params,
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error for user with only supply_chain.read" do
        post "/api/v1/supply_chain/scan_instances",
             params: { scan_instance: { name: "Test Instance" } },
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end

      it "returns forbidden error for regular user" do
        post "/api/v1/supply_chain/scan_instances",
             params: { scan_instance: { name: "Test Instance" } },
             headers: auth_headers_for(regular_user),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "PATCH /api/v1/supply_chain/scan_instances/:id" do
    let(:scan_template) { create(:supply_chain_scan_template) }
    let(:scan_instance) { create(:supply_chain_scan_instance, account: account, scan_template: scan_template, name: "Original Name") }

    context "with supply_chain.write permission" do
      it "updates the scan instance name" do
        patch "/api/v1/supply_chain/scan_instances/#{scan_instance.id}",
              params: { scan_instance: { name: "Updated Name" } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_success_response
        expect(json_response["data"]["scan_instance"]["name"]).to eq("Updated Name")

        scan_instance.reload
        expect(scan_instance.name).to eq("Updated Name")
      end

      it "updates the description" do
        patch "/api/v1/supply_chain/scan_instances/#{scan_instance.id}",
              params: { scan_instance: { description: "Updated Description" } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_success_response
        expect(json_response["data"]["scan_instance"]["description"]).to eq("Updated Description")
      end

      it "updates the schedule_cron" do
        patch "/api/v1/supply_chain/scan_instances/#{scan_instance.id}",
              params: { scan_instance: { schedule_cron: "0 2 * * *" } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_success_response
        expect(json_response["data"]["scan_instance"]["schedule_cron"]).to eq("0 2 * * *")
      end

      it "updates the configuration" do
        patch "/api/v1/supply_chain/scan_instances/#{scan_instance.id}",
              params: { scan_instance: { configuration: { new_key: "new_value" } } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_success_response
        scan_instance.reload
        expect(scan_instance.configuration["new_key"]).to eq("new_value")
      end

      it "returns error with invalid data" do
        patch "/api/v1/supply_chain/scan_instances/#{scan_instance.id}",
              params: { scan_instance: { name: "" } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_error_response("Name can't be blank", 422)
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        patch "/api/v1/supply_chain/scan_instances/#{scan_instance.id}",
              params: { scan_instance: { name: "Updated Name" } },
              headers: auth_headers_for(supply_chain_reader),
              as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end

    context "with scan instance from another account" do
      let(:other_instance) { create(:supply_chain_scan_instance, account: other_account, scan_template: scan_template) }

      it "returns not found error" do
        patch "/api/v1/supply_chain/scan_instances/#{other_instance.id}",
              params: { scan_instance: { name: "Hacked" } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_error_response("Scan instance not found", 404)
      end
    end
  end

  describe "DELETE /api/v1/supply_chain/scan_instances/:id" do
    let(:scan_template) { create(:supply_chain_scan_template) }
    let!(:scan_instance) { create(:supply_chain_scan_instance, account: account, scan_template: scan_template) }

    context "with supply_chain.write permission" do
      it "deletes the scan instance" do
        expect {
          delete "/api/v1/supply_chain/scan_instances/#{scan_instance.id}",
                 headers: auth_headers_for(supply_chain_writer),
                 as: :json
        }.to change(SupplyChain::ScanInstance, :count).by(-1)

        expect_success_response
        expect(json_response["data"]["message"]).to eq("Scan instance deleted")
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        delete "/api/v1/supply_chain/scan_instances/#{scan_instance.id}",
               headers: auth_headers_for(supply_chain_reader),
               as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end

    context "with scan instance from another account" do
      let(:other_instance) { create(:supply_chain_scan_instance, account: other_account, scan_template: scan_template) }

      it "returns not found error" do
        delete "/api/v1/supply_chain/scan_instances/#{other_instance.id}",
               headers: auth_headers_for(supply_chain_writer),
               as: :json

        expect_error_response("Scan instance not found", 404)
      end
    end
  end

  describe "POST /api/v1/supply_chain/scan_instances/:id/execute" do
    let(:scan_template) { create(:supply_chain_scan_template) }
    let(:scan_instance) { create(:supply_chain_scan_instance, account: account, scan_template: scan_template) }

    context "with supply_chain.write permission" do
      let(:valid_execute_params) do
        {
          target_type: "SupplyChain::Sbom",
          target_id: SecureRandom.uuid
        }
      end

      it "returns error when target_type is missing" do
        post "/api/v1/supply_chain/scan_instances/#{scan_instance.id}/execute",
             params: { target_id: SecureRandom.uuid },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_error_response("target_type and target_id are required", 422)
      end

      it "returns error when target_id is missing" do
        post "/api/v1/supply_chain/scan_instances/#{scan_instance.id}/execute",
             params: { target_type: "SupplyChain::Sbom" },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_error_response("target_type and target_id are required", 422)
      end

      it "returns error when both target_type and target_id are missing" do
        post "/api/v1/supply_chain/scan_instances/#{scan_instance.id}/execute",
             params: {},
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_error_response("target_type and target_id are required", 422)
      end

      it "creates a scan execution with valid parameters" do
        expect {
          post "/api/v1/supply_chain/scan_instances/#{scan_instance.id}/execute",
               params: valid_execute_params,
               headers: auth_headers_for(supply_chain_writer),
               as: :json
        }.to change(SupplyChain::ScanExecution, :count).by(1)

        expect_success_response
        expect(json_response["data"]["scan_execution"]).to be_present
      end

      it "enqueues ScanExecutionJob" do
        expect(::SupplyChain::ScanExecutionJob).to receive(:perform_later)

        post "/api/v1/supply_chain/scan_instances/#{scan_instance.id}/execute",
             params: valid_execute_params,
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
      end

      it "creates execution with correct attributes" do
        post "/api/v1/supply_chain/scan_instances/#{scan_instance.id}/execute",
             params: valid_execute_params,
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        execution = SupplyChain::ScanExecution.last

        expect(execution.scan_instance).to eq(scan_instance)
        expect(execution.account).to eq(account)
        expect(execution.input_data["target_type"]).to eq("SupplyChain::Sbom")
        expect(execution.input_data["target_id"]).to eq(valid_execute_params[:target_id])
        expect(execution.triggered_by).to eq(supply_chain_writer)
        expect(execution.status).to eq("pending")
        expect(execution.trigger_type).to eq("manual")
      end

      it "returns scan_execution data in response" do
        post "/api/v1/supply_chain/scan_instances/#{scan_instance.id}/execute",
             params: valid_execute_params,
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        execution_data = json_response["data"]["scan_execution"]

        expect(execution_data).to include(
          "id",
          "execution_id",
          "status",
          "trigger_type",
          "target_type",
          "target_id",
          "started_at",
          "completed_at",
          "created_at"
        )
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/scan_instances/#{scan_instance.id}/execute",
             params: { target_type: "SupplyChain::Sbom", target_id: SecureRandom.uuid },
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end

    context "with scan instance from another account" do
      let(:other_instance) { create(:supply_chain_scan_instance, account: other_account, scan_template: scan_template) }

      it "returns not found error" do
        post "/api/v1/supply_chain/scan_instances/#{other_instance.id}/execute",
             params: { target_type: "SupplyChain::Sbom", target_id: SecureRandom.uuid },
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_error_response("Scan instance not found", 404)
      end
    end
  end

  describe "GET /api/v1/supply_chain/scan_instances/:id/executions" do
    let(:scan_template) { create(:supply_chain_scan_template) }
    let(:scan_instance) { create(:supply_chain_scan_instance, account: account, scan_template: scan_template) }
    let!(:executions) do
      [
        create(:supply_chain_scan_execution, scan_instance: scan_instance, account: account, status: "completed"),
        create(:supply_chain_scan_execution, scan_instance: scan_instance, account: account, status: "failed"),
        create(:supply_chain_scan_execution, scan_instance: scan_instance, account: account, status: "pending")
      ]
    end

    context "with supply_chain.read permission" do
      it "returns executions for the scan instance" do
        get "/api/v1/supply_chain/scan_instances/#{scan_instance.id}/executions",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["scan_executions"].length).to eq(3)
        expect(data["scan_executions"].map { |e| e["id"] }).to match_array(executions.map(&:id))
      end

      it "returns executions ordered by created_at desc" do
        get "/api/v1/supply_chain/scan_instances/#{scan_instance.id}/executions",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]

        created_ats = data["scan_executions"].map { |e| Time.parse(e["created_at"]) }
        expect(created_ats).to eq(created_ats.sort.reverse)
      end

      it "filters by status" do
        get "/api/v1/supply_chain/scan_instances/#{scan_instance.id}/executions?status=completed",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["scan_executions"].length).to eq(1)
        expect(data["scan_executions"].first["status"]).to eq("completed")
      end

      it "filters by failed status" do
        get "/api/v1/supply_chain/scan_instances/#{scan_instance.id}/executions?status=failed",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["scan_executions"].length).to eq(1)
        expect(data["scan_executions"].first["status"]).to eq("failed")
      end

      it "includes pagination metadata" do
        get "/api/v1/supply_chain/scan_instances/#{scan_instance.id}/executions",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response

        expect(json_response["meta"]).to include(
          "total_count",
          "current_page",
          "per_page"
        )
      end

      it "returns execution data with correct structure" do
        get "/api/v1/supply_chain/scan_instances/#{scan_instance.id}/executions",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        execution_data = json_response["data"]["scan_executions"].first

        expect(execution_data).to include(
          "id",
          "execution_id",
          "status",
          "trigger_type",
          "started_at",
          "completed_at",
          "duration_ms",
          "error_message",
          "created_at"
        )
      end
    end

    context "with pagination" do
      before do
        30.times do
          create(:supply_chain_scan_execution, scan_instance: scan_instance, account: account)
        end
      end

      it "returns paginated results" do
        get "/api/v1/supply_chain/scan_instances/#{scan_instance.id}/executions",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["scan_executions"].length).to eq(20)
        expect(json_response["meta"]["total_count"]).to eq(33) # 30 + 3 from let! block
      end

      it "respects page parameter" do
        get "/api/v1/supply_chain/scan_instances/#{scan_instance.id}/executions?page=2",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response

        expect(json_response["meta"]["current_page"]).to eq(2)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/scan_instances/#{scan_instance.id}/executions",
            headers: auth_headers_for(regular_user),
            as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end

    context "with scan instance from another account" do
      let(:other_instance) { create(:supply_chain_scan_instance, account: other_account, scan_template: scan_template) }

      it "returns not found error" do
        get "/api/v1/supply_chain/scan_instances/#{other_instance.id}/executions",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_error_response("Scan instance not found", 404)
      end
    end
  end

  describe "account isolation" do
    let(:scan_template) { create(:supply_chain_scan_template) }
    let!(:account_instance) { create(:supply_chain_scan_instance, account: account, scan_template: scan_template) }
    let!(:other_instance) { create(:supply_chain_scan_instance, account: other_account, scan_template: scan_template) }

    it "only returns scan instances for the authenticated user account" do
      get "/api/v1/supply_chain/scan_instances", headers: auth_headers_for(supply_chain_reader), as: :json

      expect_success_response
      instance_ids = json_response["data"]["scan_instances"].map { |i| i["id"] }

      expect(instance_ids).to include(account_instance.id)
      expect(instance_ids).not_to include(other_instance.id)
    end

    it "prevents accessing another account scan instance directly" do
      get "/api/v1/supply_chain/scan_instances/#{other_instance.id}", headers: auth_headers_for(supply_chain_reader), as: :json

      expect_error_response("Scan instance not found", 404)
    end

    it "prevents modifying another account scan instance" do
      patch "/api/v1/supply_chain/scan_instances/#{other_instance.id}",
            params: { scan_instance: { name: "Hacked" } },
            headers: auth_headers_for(supply_chain_writer),
            as: :json

      expect_error_response("Scan instance not found", 404)
    end

    it "prevents deleting another account scan instance" do
      delete "/api/v1/supply_chain/scan_instances/#{other_instance.id}",
             headers: auth_headers_for(supply_chain_writer),
             as: :json

      expect_error_response("Scan instance not found", 404)
    end

    it "prevents executing scan on another account scan instance" do
      post "/api/v1/supply_chain/scan_instances/#{other_instance.id}/execute",
           params: { target_type: "SupplyChain::Sbom", target_id: SecureRandom.uuid },
           headers: auth_headers_for(supply_chain_writer),
           as: :json

      expect_error_response("Scan instance not found", 404)
    end

    it "prevents viewing executions of another account scan instance" do
      get "/api/v1/supply_chain/scan_instances/#{other_instance.id}/executions",
          headers: auth_headers_for(supply_chain_reader),
          as: :json

      expect_error_response("Scan instance not found", 404)
    end
  end
end
