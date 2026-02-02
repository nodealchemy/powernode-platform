# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::SupplyChain::CveMonitors", type: :request do
  let(:account) { create(:account) }

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

  # Another account for isolation tests
  let(:other_account) { create(:account) }

  before(:each) do
    Rails.cache.clear
  end

  describe "GET /api/v1/supply_chain/cve_monitors" do
    context "with supply_chain.read permission" do
      let!(:monitors) do
        [
          create(:supply_chain_cve_monitor, account: account, is_active: true, scope_type: "account_wide"),
          create(:supply_chain_cve_monitor, :image_scope, account: account, is_active: false),
          create(:supply_chain_cve_monitor, :repository_scope, account: account, is_active: true)
        ]
      end

      let!(:other_monitor) do
        create(:supply_chain_cve_monitor, account: other_account)
      end

      it "returns cve monitors for the current account" do
        get "/api/v1/supply_chain/cve_monitors", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["cve_monitors"]

        expect(data.length).to eq(3)
        expect(data.map { |m| m["id"] }).to match_array(monitors.map(&:id))
        expect(data.map { |m| m["id"] }).not_to include(other_monitor.id)
      end

      it "returns monitors ordered by created_at desc" do
        get "/api/v1/supply_chain/cve_monitors", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["cve_monitors"]

        created_ats = data.map { |m| Time.parse(m["created_at"]) }
        expect(created_ats).to eq(created_ats.sort.reverse)
      end

      it "returns monitor data with correct structure" do
        get "/api/v1/supply_chain/cve_monitors", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        monitor_data = json_response["data"]["cve_monitors"].first

        expect(monitor_data).to include(
          "id",
          "name",
          "description",
          "scope_type",
          "scope_id",
          "min_severity",
          "is_active",
          "schedule_cron",
          "last_run_at",
          "next_run_at",
          "created_at"
        )
      end

      it "filters by active_only=true" do
        get "/api/v1/supply_chain/cve_monitors?active_only=true", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["cve_monitors"]

        expect(data.length).to eq(2)
        expect(data.all? { |m| m["is_active"] == true }).to be true
      end

      it "filters by scope_type" do
        get "/api/v1/supply_chain/cve_monitors?scope_type=account_wide", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["cve_monitors"]

        expect(data.length).to eq(1)
        expect(data.first["scope_type"]).to eq("account_wide")
      end
    end

    context "pagination" do
      before do
        30.times do
          create(:supply_chain_cve_monitor, account: account)
        end
      end

      it "returns paginated results with default per_page of 20" do
        get "/api/v1/supply_chain/cve_monitors", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        expect(json_response["data"]["cve_monitors"].length).to eq(20)
        expect(json_response["meta"]["total_count"]).to eq(30)
        expect(json_response["meta"]["current_page"]).to eq(1)
        expect(json_response["meta"]["per_page"]).to eq(20)
        expect(json_response["meta"]["total_pages"]).to eq(2)
      end

      it "respects page parameter" do
        get "/api/v1/supply_chain/cve_monitors?page=2", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        expect(json_response["data"]["cve_monitors"].length).to eq(10)
        expect(json_response["meta"]["current_page"]).to eq(2)
      end

      it "respects per_page parameter" do
        get "/api/v1/supply_chain/cve_monitors?per_page=10", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        expect(json_response["data"]["cve_monitors"].length).to eq(10)
        expect(json_response["meta"]["per_page"]).to eq(10)
        expect(json_response["meta"]["total_pages"]).to eq(3)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/cve_monitors", headers: auth_headers_for(regular_user), as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/cve_monitors", as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "GET /api/v1/supply_chain/cve_monitors/:id" do
    let!(:monitor) { create(:supply_chain_cve_monitor, account: account) }

    context "with supply_chain.read permission" do
      it "returns the monitor details" do
        get "/api/v1/supply_chain/cve_monitors/#{monitor.id}", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["cve_monitor"]

        expect(data["id"]).to eq(monitor.id)
        expect(data["name"]).to eq(monitor.name)
        expect(data["description"]).to eq(monitor.description)
        expect(data["scope_type"]).to eq(monitor.scope_type)
        expect(data["min_severity"]).to eq(monitor.min_severity)
      end

      it "includes detailed fields" do
        get "/api/v1/supply_chain/cve_monitors/#{monitor.id}", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["cve_monitor"]

        expect(data).to include(
          "notification_channels",
          "filters",
          "alert_count",
          "metadata"
        )
      end
    end

    context "with monitor from another account" do
      let(:other_monitor) { create(:supply_chain_cve_monitor, account: other_account) }

      it "returns not found error" do
        get "/api/v1/supply_chain/cve_monitors/#{other_monitor.id}", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_error_response("CVE monitor not found", 404)
      end
    end

    context "with non-existent monitor" do
      it "returns not found error" do
        get "/api/v1/supply_chain/cve_monitors/non-existent-id", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_error_response("CVE monitor not found", 404)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/cve_monitors/#{monitor.id}", headers: auth_headers_for(regular_user), as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /api/v1/supply_chain/cve_monitors" do
    context "with supply_chain.write permission" do
      let(:valid_params) do
        {
          cve_monitor: {
            name: "Critical CVE Monitor",
            description: "Monitor critical vulnerabilities",
            scope_type: "account_wide",
            min_severity: "critical",
            is_active: true,
            schedule_cron: "0 0 * * *",
            notification_channels: [],
            filters: {},
            metadata: {}
          }
        }
      end

      it "creates a new cve monitor" do
        expect {
          post "/api/v1/supply_chain/cve_monitors",
               params: valid_params,
               headers: auth_headers_for(supply_chain_writer),
               as: :json
        }.to change(SupplyChain::CveMonitor, :count).by(1)

        expect(response).to have_http_status(:created)
        expect_success_response
        expect(json_response["data"]["cve_monitor"]["name"]).to eq("Critical CVE Monitor")
      end

      it "sets the created_by to current user" do
        post "/api/v1/supply_chain/cve_monitors",
             params: valid_params,
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        monitor = SupplyChain::CveMonitor.last
        expect(monitor.created_by_id).to eq(supply_chain_writer.id)
      end

      it "creates monitor with image scope" do
        image_id = SecureRandom.uuid
        params = valid_params.deep_merge(cve_monitor: { scope_type: "image", scope_id: image_id })

        post "/api/v1/supply_chain/cve_monitors",
             params: params,
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        expect(json_response["data"]["cve_monitor"]["scope_type"]).to eq("image")
        expect(json_response["data"]["cve_monitor"]["scope_id"]).to eq(image_id)
      end

      it "creates monitor with repository scope" do
        repo_id = SecureRandom.uuid
        params = valid_params.deep_merge(cve_monitor: { scope_type: "repository", scope_id: repo_id })

        post "/api/v1/supply_chain/cve_monitors",
             params: params,
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        expect(json_response["data"]["cve_monitor"]["scope_type"]).to eq("repository")
        expect(json_response["data"]["cve_monitor"]["scope_id"]).to eq(repo_id)
      end

      it "returns error with missing name" do
        params = valid_params.deep_merge(cve_monitor: { name: nil })

        post "/api/v1/supply_chain/cve_monitors",
             params: params,
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["error"]).to include("Name can't be blank")
      end

      it "returns error with invalid scope_type" do
        params = valid_params.deep_merge(cve_monitor: { scope_type: "invalid" })

        post "/api/v1/supply_chain/cve_monitors",
             params: params,
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["error"]).to include("Scope type is not included in the list")
      end

      it "returns error with invalid min_severity" do
        params = valid_params.deep_merge(cve_monitor: { min_severity: "extreme" })

        post "/api/v1/supply_chain/cve_monitors",
             params: params,
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["error"]).to include("Min severity is not included in the list")
      end

      it "returns error when scope_id is missing for image scope" do
        params = valid_params.deep_merge(cve_monitor: { scope_type: "image", scope_id: nil })

        post "/api/v1/supply_chain/cve_monitors",
             params: params,
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["error"]).to include("Scope is required for image scope")
      end

      it "returns error when scope_id is missing for repository scope" do
        params = valid_params.deep_merge(cve_monitor: { scope_type: "repository", scope_id: nil })

        post "/api/v1/supply_chain/cve_monitors",
             params: params,
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["error"]).to include("Scope is required for repository scope")
      end

      it "returns error with duplicate name in same account" do
        create(:supply_chain_cve_monitor, account: account, name: "Duplicate Monitor")
        params = valid_params.deep_merge(cve_monitor: { name: "Duplicate Monitor" })

        post "/api/v1/supply_chain/cve_monitors",
             params: params,
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["error"]).to include("Name has already been taken")
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error for user with only supply_chain.read" do
        post "/api/v1/supply_chain/cve_monitors",
             params: { cve_monitor: { name: "Test Monitor" } },
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect(response).to have_http_status(:forbidden)
      end

      it "returns forbidden error for regular user" do
        post "/api/v1/supply_chain/cve_monitors",
             params: { cve_monitor: { name: "Test Monitor" } },
             headers: auth_headers_for(regular_user),
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PATCH /api/v1/supply_chain/cve_monitors/:id" do
    let(:monitor) { create(:supply_chain_cve_monitor, account: account, name: "Original Name", is_active: true) }

    context "with supply_chain.write permission" do
      it "updates the monitor name" do
        patch "/api/v1/supply_chain/cve_monitors/#{monitor.id}",
              params: { cve_monitor: { name: "Updated Name" } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_success_response
        expect(json_response["data"]["cve_monitor"]["name"]).to eq("Updated Name")

        monitor.reload
        expect(monitor.name).to eq("Updated Name")
      end

      it "updates the description" do
        patch "/api/v1/supply_chain/cve_monitors/#{monitor.id}",
              params: { cve_monitor: { description: "Updated description" } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_success_response
        expect(json_response["data"]["cve_monitor"]["description"]).to eq("Updated description")
      end

      it "updates the min_severity" do
        patch "/api/v1/supply_chain/cve_monitors/#{monitor.id}",
              params: { cve_monitor: { min_severity: "high" } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_success_response
        expect(json_response["data"]["cve_monitor"]["min_severity"]).to eq("high")
      end

      it "updates the is_active status" do
        patch "/api/v1/supply_chain/cve_monitors/#{monitor.id}",
              params: { cve_monitor: { is_active: false } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_success_response
        expect(json_response["data"]["cve_monitor"]["is_active"]).to be false
      end

      it "updates the schedule_cron" do
        patch "/api/v1/supply_chain/cve_monitors/#{monitor.id}",
              params: { cve_monitor: { schedule_cron: "0 */6 * * *" } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_success_response
        expect(json_response["data"]["cve_monitor"]["schedule_cron"]).to eq("0 */6 * * *")
      end

      it "updates notification channels" do
        new_channels = [ { "type" => "email", "config" => { "address" => "test@example.com" } } ]

        patch "/api/v1/supply_chain/cve_monitors/#{monitor.id}",
              params: { cve_monitor: { notification_channels: new_channels } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_success_response
        monitor.reload
        expect(monitor.notification_channels).to eq(new_channels)
      end

      it "returns error with invalid min_severity" do
        patch "/api/v1/supply_chain/cve_monitors/#{monitor.id}",
              params: { cve_monitor: { min_severity: "extreme" } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["error"]).to include("Min severity is not included in the list")
      end

      it "returns error with duplicate name" do
        create(:supply_chain_cve_monitor, account: account, name: "Existing Monitor")

        patch "/api/v1/supply_chain/cve_monitors/#{monitor.id}",
              params: { cve_monitor: { name: "Existing Monitor" } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["error"]).to include("Name has already been taken")
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        patch "/api/v1/supply_chain/cve_monitors/#{monitor.id}",
              params: { cve_monitor: { name: "Updated Name" } },
              headers: auth_headers_for(supply_chain_reader),
              as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "with monitor from another account" do
      let(:other_monitor) { create(:supply_chain_cve_monitor, account: other_account) }

      it "returns not found error" do
        patch "/api/v1/supply_chain/cve_monitors/#{other_monitor.id}",
              params: { cve_monitor: { name: "Hacked" } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "DELETE /api/v1/supply_chain/cve_monitors/:id" do
    let!(:monitor) { create(:supply_chain_cve_monitor, account: account) }

    context "with supply_chain.write permission" do
      it "deletes the monitor" do
        expect {
          delete "/api/v1/supply_chain/cve_monitors/#{monitor.id}",
                 headers: auth_headers_for(supply_chain_writer),
                 as: :json
        }.to change(SupplyChain::CveMonitor, :count).by(-1)

        expect_success_response
        expect(json_response["data"]["message"]).to eq("CVE monitor deleted")
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        delete "/api/v1/supply_chain/cve_monitors/#{monitor.id}",
               headers: auth_headers_for(supply_chain_reader),
               as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "with monitor from another account" do
      let(:other_monitor) { create(:supply_chain_cve_monitor, account: other_account) }

      it "returns not found error" do
        delete "/api/v1/supply_chain/cve_monitors/#{other_monitor.id}",
               headers: auth_headers_for(supply_chain_writer),
               as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/v1/supply_chain/cve_monitors/:id/run" do
    let(:monitor) { create(:supply_chain_cve_monitor, account: account) }

    context "with supply_chain.write permission" do
      it "enqueues the CVE monitoring job" do
        expect {
          post "/api/v1/supply_chain/cve_monitors/#{monitor.id}/run",
               headers: auth_headers_for(supply_chain_writer),
               as: :json
        }.to have_enqueued_job(SupplyChain::CveMonitoringJob).with(monitor.id)

        expect_success_response
        expect(json_response["data"]["message"]).to eq("CVE monitoring job queued")
        expect(json_response["data"]["cve_monitor"]["id"]).to eq(monitor.id)
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/cve_monitors/#{monitor.id}/run",
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "with monitor from another account" do
      let(:other_monitor) { create(:supply_chain_cve_monitor, account: other_account) }

      it "returns not found error" do
        post "/api/v1/supply_chain/cve_monitors/#{other_monitor.id}/run",
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /api/v1/supply_chain/cve_monitors/:id/alerts" do
    let(:monitor) { create(:supply_chain_cve_monitor, account: account) }

    context "with supply_chain.read permission" do
      it "returns recent alerts for the monitor" do
        # Mock recent_alerts method to return sample alerts
        allow_any_instance_of(SupplyChain::CveMonitor).to receive(:recent_alerts).and_return([
          {
            id: SecureRandom.uuid,
            cve_id: "CVE-2024-1234",
            severity: "critical",
            alert_type: "new_vulnerability",
            component_name: "express",
            component_version: "4.17.1",
            created_at: 1.day.ago
          },
          {
            id: SecureRandom.uuid,
            cve_id: "CVE-2024-5678",
            severity: "high",
            alert_type: "severity_upgrade",
            component_name: "lodash",
            component_version: "4.17.20",
            created_at: 2.days.ago
          }
        ])

        get "/api/v1/supply_chain/cve_monitors/#{monitor.id}/alerts",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        data = json_response["data"]["alerts"]

        expect(data.length).to eq(2)
        expect(data.first["cve_id"]).to eq("CVE-2024-1234")
        expect(data.first["severity"]).to eq("critical")
        expect(data.first["component_name"]).to eq("express")
      end

      it "respects limit parameter" do
        alerts = Array.new(100) do |i|
          {
            id: SecureRandom.uuid,
            cve_id: "CVE-2024-#{1000 + i}",
            severity: "high",
            alert_type: "new_vulnerability",
            component_name: "package-#{i}",
            component_version: "1.0.0",
            created_at: i.days.ago
          }
        end

        allow_any_instance_of(SupplyChain::CveMonitor).to receive(:recent_alerts).with(limit: "25").and_return(alerts.first(25))

        get "/api/v1/supply_chain/cve_monitors/#{monitor.id}/alerts?limit=25",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        expect(json_response["data"]["alerts"].length).to eq(25)
      end

      it "includes cve_monitor_id in response" do
        allow_any_instance_of(SupplyChain::CveMonitor).to receive(:recent_alerts).and_return([])

        get "/api/v1/supply_chain/cve_monitors/#{monitor.id}/alerts",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        expect(json_response["data"]["cve_monitor_id"]).to eq(monitor.id)
      end

      it "returns empty array when no alerts" do
        allow_any_instance_of(SupplyChain::CveMonitor).to receive(:recent_alerts).and_return([])

        get "/api/v1/supply_chain/cve_monitors/#{monitor.id}/alerts",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect_success_response
        expect(json_response["data"]["alerts"]).to eq([])
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/cve_monitors/#{monitor.id}/alerts",
            headers: auth_headers_for(regular_user),
            as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "with monitor from another account" do
      let(:other_monitor) { create(:supply_chain_cve_monitor, account: other_account) }

      it "returns not found error" do
        get "/api/v1/supply_chain/cve_monitors/#{other_monitor.id}/alerts",
            headers: auth_headers_for(supply_chain_reader),
            as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/v1/supply_chain/cve_monitors/run_all" do
    context "with supply_chain.write permission" do
      let!(:active_monitors) do
        [
          create(:supply_chain_cve_monitor, account: account, is_active: true),
          create(:supply_chain_cve_monitor, account: account, is_active: true),
          create(:supply_chain_cve_monitor, account: account, is_active: true)
        ]
      end

      let!(:inactive_monitor) do
        create(:supply_chain_cve_monitor, account: account, is_active: false)
      end

      let!(:other_account_monitor) do
        create(:supply_chain_cve_monitor, account: other_account, is_active: true)
      end

      it "enqueues jobs for all active monitors in the account" do
        active_monitors.each do |monitor|
          expect(SupplyChain::CveMonitoringJob).to receive(:perform_later).with(monitor.id)
        end

        # Ensure inactive and other account monitors are not queued
        expect(SupplyChain::CveMonitoringJob).not_to receive(:perform_later).with(inactive_monitor.id)
        expect(SupplyChain::CveMonitoringJob).not_to receive(:perform_later).with(other_account_monitor.id)

        post "/api/v1/supply_chain/cve_monitors/run_all",
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        expect(json_response["data"]["message"]).to eq("CVE monitoring jobs queued")
        expect(json_response["data"]["monitors_queued"]).to eq(3)
      end

      it "returns zero monitors_queued when no active monitors" do
        active_monitors.each(&:destroy)

        post "/api/v1/supply_chain/cve_monitors/run_all",
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        expect(json_response["data"]["monitors_queued"]).to eq(0)
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error for supply_chain.read user" do
        post "/api/v1/supply_chain/cve_monitors/run_all",
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect(response).to have_http_status(:forbidden)
      end

      it "returns forbidden error for regular user" do
        post "/api/v1/supply_chain/cve_monitors/run_all",
             headers: auth_headers_for(regular_user),
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "account isolation" do
    let!(:account_monitor) { create(:supply_chain_cve_monitor, account: account) }
    let!(:other_monitor) { create(:supply_chain_cve_monitor, account: other_account) }

    it "only returns monitors for the authenticated user account" do
      get "/api/v1/supply_chain/cve_monitors", headers: auth_headers_for(supply_chain_reader), as: :json

      expect_success_response
      monitor_ids = json_response["data"]["cve_monitors"].map { |m| m["id"] }

      expect(monitor_ids).to include(account_monitor.id)
      expect(monitor_ids).not_to include(other_monitor.id)
    end

    it "prevents accessing another account monitor directly" do
      get "/api/v1/supply_chain/cve_monitors/#{other_monitor.id}", headers: auth_headers_for(supply_chain_reader), as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "prevents modifying another account monitor" do
      patch "/api/v1/supply_chain/cve_monitors/#{other_monitor.id}",
            params: { cve_monitor: { name: "Hacked" } },
            headers: auth_headers_for(supply_chain_writer),
            as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "prevents deleting another account monitor" do
      delete "/api/v1/supply_chain/cve_monitors/#{other_monitor.id}",
             headers: auth_headers_for(supply_chain_writer),
             as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "prevents running another account monitor" do
      post "/api/v1/supply_chain/cve_monitors/#{other_monitor.id}/run",
           headers: auth_headers_for(supply_chain_writer),
           as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "prevents viewing alerts from another account monitor" do
      get "/api/v1/supply_chain/cve_monitors/#{other_monitor.id}/alerts",
          headers: auth_headers_for(supply_chain_reader),
          as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
