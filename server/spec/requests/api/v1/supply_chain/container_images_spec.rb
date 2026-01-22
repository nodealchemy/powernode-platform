# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::SupplyChain::ContainerImages", type: :request do
  # Stub audit logging to prevent validation errors for supply_chain actions
  before do
    allow_any_instance_of(Api::V1::SupplyChain::ContainerImagesController).to receive(:log_audit_event)
  end

  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  let(:read_user) { create(:user, account: account, permissions: ["supply_chain.read"]) }
  let(:write_user) { create(:user, account: account, permissions: ["supply_chain.read", "supply_chain.write"]) }
  let(:other_account_user) { create(:user, account: other_account, permissions: ["supply_chain.read", "supply_chain.write"]) }
  let(:no_permission_user) { create(:user, account: account, permissions: []) }

  let(:read_headers) { auth_headers_for(read_user) }
  let(:write_headers) { auth_headers_for(write_user) }
  let(:other_account_headers) { auth_headers_for(other_account_user) }
  let(:no_permission_headers) { auth_headers_for(no_permission_user) }

  describe "GET /api/v1/supply_chain/container_images" do
    let!(:image1) { create(:supply_chain_container_image, account: account, status: "verified", registry: "gcr.io", is_deployed: true) }
    let!(:image2) { create(:supply_chain_container_image, account: account, status: "unverified", registry: "docker.io", is_deployed: false) }
    let!(:quarantined_image) { create(:supply_chain_container_image, :quarantined, account: account, registry: "gcr.io") }
    let!(:other_account_image) { create(:supply_chain_container_image, account: other_account) }

    context "with supply_chain.read permission" do
      it "returns list of container images for current account" do
        get "/api/v1/supply_chain/container_images", headers: read_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data["container_images"]).to be_an(Array)
        expect(data["container_images"].length).to eq(3)
        expect(data["container_images"].none? { |i| i["id"] == other_account_image.id }).to be true
        expect(data["meta"]).to include("total" => 3)
      end

      it "filters by status" do
        get "/api/v1/supply_chain/container_images?status=verified", headers: read_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data["container_images"].length).to eq(1)
        expect(data["container_images"].first["status"]).to eq("verified")
      end

      it "filters by registry" do
        get "/api/v1/supply_chain/container_images?registry=gcr.io", headers: read_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data["container_images"].length).to eq(2)
        expect(data["container_images"].all? { |i| i["registry"] == "gcr.io" }).to be true
      end

      it "filters by deployed status" do
        get "/api/v1/supply_chain/container_images?deployed=true", headers: read_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data["container_images"].length).to eq(1)
        expect(data["container_images"].first["is_deployed"]).to be true
      end

      it "supports pagination" do
        get "/api/v1/supply_chain/container_images?page=1&per_page=2", headers: read_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data["container_images"].length).to eq(2)
        expect(data["meta"]).to include("page" => 1, "per_page" => 2, "total" => 3)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/container_images", headers: no_permission_headers, as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/container_images", as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "GET /api/v1/supply_chain/container_images/:id" do
    let!(:container_image) { create(:supply_chain_container_image, account: account) }
    let!(:other_account_image) { create(:supply_chain_container_image, account: other_account) }

    context "with supply_chain.read permission" do
      it "returns container image details" do
        get "/api/v1/supply_chain/container_images/#{container_image.id}", headers: read_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data["container_image"]).to include(
          "id" => container_image.id,
          "registry" => container_image.registry,
          "repository" => container_image.repository,
          "tag" => container_image.tag,
          "digest" => container_image.digest,
          "status" => container_image.status
        )
        expect(data["container_image"]).to have_key("layers")
        expect(data["container_image"]).to have_key("sbom_available")
      end

      it "returns not found for non-existent container image" do
        get "/api/v1/supply_chain/container_images/#{SecureRandom.uuid}", headers: read_headers, as: :json

        expect_error_response("Container image not found", 404)
      end
    end

    context "account isolation" do
      it "returns not found for container image from different account" do
        get "/api/v1/supply_chain/container_images/#{other_account_image.id}", headers: read_headers, as: :json

        expect_error_response("Container image not found", 404)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/container_images/#{container_image.id}", headers: no_permission_headers, as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/container_images/#{container_image.id}", as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "POST /api/v1/supply_chain/container_images" do
    let(:valid_params) do
      {
        container_image: {
          registry: "gcr.io",
          repository: "my-project/my-app",
          tag: "v1.0.0",
          digest: "sha256:#{SecureRandom.hex(32)}",
          is_deployed: true,
          deployment_contexts: ["production"]
        }
      }
    end

    context "with supply_chain.write permission" do
      it "creates a new container image" do
        expect {
          post "/api/v1/supply_chain/container_images", params: valid_params, headers: write_headers, as: :json
        }.to change { account.supply_chain_container_images.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data["container_image"]).to include(
          "registry" => "gcr.io",
          "repository" => "my-project/my-app",
          "tag" => "v1.0.0",
          "is_deployed" => true
        )
        expect(data["message"]).to eq("Container image created successfully")
      end

      it "associates container image with current account" do
        post "/api/v1/supply_chain/container_images", params: valid_params, headers: write_headers, as: :json

        container_image = SupplyChain::ContainerImage.last
        expect(container_image.account_id).to eq(account.id)
      end

      it "returns validation errors for invalid params" do
        invalid_params = valid_params.deep_merge(container_image: { registry: nil })

        post "/api/v1/supply_chain/container_images", params: invalid_params, headers: write_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        json = json_response
        expect(json["success"]).to be false
      end
    end

    context "with only supply_chain.read permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/container_images", params: valid_params, headers: read_headers, as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        post "/api/v1/supply_chain/container_images", params: valid_params, as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "PATCH /api/v1/supply_chain/container_images/:id" do
    let!(:container_image) { create(:supply_chain_container_image, account: account, is_deployed: false) }
    let!(:other_account_image) { create(:supply_chain_container_image, account: other_account) }

    let(:update_params) do
      {
        container_image: {
          is_deployed: true,
          deployment_contexts: ["staging", "production"]
        }
      }
    end

    context "with supply_chain.write permission" do
      it "updates the container image" do
        patch "/api/v1/supply_chain/container_images/#{container_image.id}",
              params: update_params,
              headers: write_headers,
              as: :json

        expect_success_response
        data = json_response_data
        expect(data["container_image"]["is_deployed"]).to be true
        expect(data["message"]).to eq("Container image updated successfully")
      end

      it "persists the changes" do
        patch "/api/v1/supply_chain/container_images/#{container_image.id}",
              params: update_params,
              headers: write_headers,
              as: :json

        expect(container_image.reload.is_deployed).to be true
      end

      it "returns validation errors for invalid params" do
        invalid_params = { container_image: { registry: "" } }

        patch "/api/v1/supply_chain/container_images/#{container_image.id}",
              params: invalid_params,
              headers: write_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "account isolation" do
      it "returns not found for container image from different account" do
        patch "/api/v1/supply_chain/container_images/#{other_account_image.id}",
              params: update_params,
              headers: write_headers,
              as: :json

        expect_error_response("Container image not found", 404)
      end
    end

    context "with only supply_chain.read permission" do
      it "returns forbidden error" do
        patch "/api/v1/supply_chain/container_images/#{container_image.id}",
              params: update_params,
              headers: read_headers,
              as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        patch "/api/v1/supply_chain/container_images/#{container_image.id}",
              params: update_params,
              as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "DELETE /api/v1/supply_chain/container_images/:id" do
    let!(:container_image) { create(:supply_chain_container_image, account: account) }
    let!(:other_account_image) { create(:supply_chain_container_image, account: other_account) }

    context "with supply_chain.write permission" do
      it "deletes the container image" do
        expect {
          delete "/api/v1/supply_chain/container_images/#{container_image.id}", headers: write_headers, as: :json
        }.to change { account.supply_chain_container_images.count }.by(-1)

        expect_success_response
        data = json_response_data
        expect(data["message"]).to eq("Container image deleted successfully")
      end
    end

    context "account isolation" do
      it "returns not found for container image from different account" do
        delete "/api/v1/supply_chain/container_images/#{other_account_image.id}", headers: write_headers, as: :json

        expect_error_response("Container image not found", 404)
      end
    end

    context "with only supply_chain.read permission" do
      it "returns forbidden error" do
        delete "/api/v1/supply_chain/container_images/#{container_image.id}", headers: read_headers, as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        delete "/api/v1/supply_chain/container_images/#{container_image.id}", as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "POST /api/v1/supply_chain/container_images/:id/scan" do
    let!(:container_image) { create(:supply_chain_container_image, account: account) }
    let!(:other_account_image) { create(:supply_chain_container_image, account: other_account) }

    before do
      # Mock the ContainerScanService to prevent actual scanning
      allow_any_instance_of(SupplyChain::ContainerScanService).to receive(:scan!).and_return(
        double(
          id: SecureRandom.uuid,
          critical_count: 2,
          high_count: 5,
          medium_count: 10,
          low_count: 3,
          total_vulnerabilities: 20
        )
      )
    end

    context "with supply_chain.write permission" do
      it "triggers a container scan" do
        post "/api/v1/supply_chain/container_images/#{container_image.id}/scan",
             headers: write_headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data["container_image_id"]).to eq(container_image.id)
        expect(data["scan_id"]).to be_present
        expect(data["vulnerability_counts"]).to include(
          "critical" => 2,
          "high" => 5,
          "medium" => 10,
          "low" => 3,
          "total" => 20
        )
        expect(data["message"]).to eq("Container scan completed")
      end

      it "accepts scanner parameter" do
        post "/api/v1/supply_chain/container_images/#{container_image.id}/scan",
             params: { scanner: "grype" },
             headers: write_headers,
             as: :json

        expect_success_response
      end
    end

    context "account isolation" do
      it "returns not found for container image from different account" do
        post "/api/v1/supply_chain/container_images/#{other_account_image.id}/scan",
             headers: write_headers,
             as: :json

        expect_error_response("Container image not found", 404)
      end
    end

    context "with only supply_chain.read permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/container_images/#{container_image.id}/scan",
             headers: read_headers,
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        post "/api/v1/supply_chain/container_images/#{container_image.id}/scan", as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "POST /api/v1/supply_chain/container_images/:id/evaluate_policies" do
    let!(:container_image) { create(:supply_chain_container_image, account: account) }
    let!(:other_account_image) { create(:supply_chain_container_image, account: other_account) }

    before do
      # Mock the ContainerScanService policy evaluation
      allow_any_instance_of(SupplyChain::ContainerScanService).to receive(:evaluate_policies).and_return({
        passed: true,
        policy_results: [
          { policy_id: "policy-1", name: "No Critical Vulnerabilities", passed: true },
          { policy_id: "policy-2", name: "Signature Required", passed: true }
        ]
      })
    end

    context "with supply_chain.write permission" do
      it "evaluates policies for the container image" do
        post "/api/v1/supply_chain/container_images/#{container_image.id}/evaluate_policies",
             headers: write_headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data["container_image_id"]).to eq(container_image.id)
        expect(data["passed"]).to be true
        expect(data["policy_results"]).to be_an(Array)
        expect(data["message"]).to eq("All policies passed")
      end

      it "returns failure message when policies fail" do
        allow_any_instance_of(SupplyChain::ContainerScanService).to receive(:evaluate_policies).and_return({
          passed: false,
          policy_results: [
            { policy_id: "policy-1", name: "No Critical Vulnerabilities", passed: false, reason: "Found 5 critical vulnerabilities" }
          ]
        })

        post "/api/v1/supply_chain/container_images/#{container_image.id}/evaluate_policies",
             headers: write_headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data["passed"]).to be false
        expect(data["message"]).to eq("Policy violations detected")
      end
    end

    context "account isolation" do
      it "returns not found for container image from different account" do
        post "/api/v1/supply_chain/container_images/#{other_account_image.id}/evaluate_policies",
             headers: write_headers,
             as: :json

        expect_error_response("Container image not found", 404)
      end
    end

    context "with only supply_chain.read permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/container_images/#{container_image.id}/evaluate_policies",
             headers: read_headers,
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        post "/api/v1/supply_chain/container_images/#{container_image.id}/evaluate_policies", as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "GET /api/v1/supply_chain/container_images/:id/vulnerabilities" do
    let!(:container_image) { create(:supply_chain_container_image, account: account) }
    let!(:other_account_image) { create(:supply_chain_container_image, account: other_account) }

    context "with supply_chain.read permission" do
      context "when container image has vulnerability scans" do
        let!(:vulnerability_scan) do
          SupplyChain::VulnerabilityScan.create!(
            container_image: container_image,
            account: account,
            scanner_name: "trivy",
            status: "completed",
            critical_count: 3,
            high_count: 7,
            medium_count: 12,
            low_count: 5,
            unknown_count: 0,
            vulnerabilities: [
              { "id" => "CVE-2024-1234", "severity" => "critical", "package" => "openssl" },
              { "id" => "CVE-2024-5678", "severity" => "high", "package" => "curl" }
            ],
            started_at: 1.hour.ago,
            completed_at: Time.current
          )
        end

        it "returns vulnerabilities from latest scan" do
          get "/api/v1/supply_chain/container_images/#{container_image.id}/vulnerabilities",
              headers: read_headers,
              as: :json

          expect_success_response
          data = json_response_data
          expect(data["scan_id"]).to eq(vulnerability_scan.id)
          expect(data["vulnerability_counts"]).to include(
            "critical" => 3,
            "high" => 7,
            "medium" => 12,
            "low" => 5
          )
          expect(data["vulnerabilities"]).to be_an(Array)
          expect(data["vulnerabilities"].length).to eq(2)
        end
      end

      context "when container image has no scans" do
        it "returns empty vulnerabilities with message" do
          get "/api/v1/supply_chain/container_images/#{container_image.id}/vulnerabilities",
              headers: read_headers,
              as: :json

          expect_success_response
          data = json_response_data
          expect(data["vulnerabilities"]).to eq([])
          expect(data["message"]).to eq("No scans available. Run a scan first.")
        end
      end
    end

    context "account isolation" do
      it "returns not found for container image from different account" do
        get "/api/v1/supply_chain/container_images/#{other_account_image.id}/vulnerabilities",
            headers: read_headers,
            as: :json

        expect_error_response("Container image not found", 404)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/container_images/#{container_image.id}/vulnerabilities",
            headers: no_permission_headers,
            as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/container_images/#{container_image.id}/vulnerabilities", as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "GET /api/v1/supply_chain/container_images/:id/sbom" do
    let!(:container_image) { create(:supply_chain_container_image, account: account) }
    let!(:other_account_image) { create(:supply_chain_container_image, account: other_account) }

    context "with supply_chain.read permission" do
      context "when container image has SBOM" do
        let!(:sbom_record) do
          create(:supply_chain_sbom,
                 account: account,
                 document: {
                   bomFormat: "CycloneDX",
                   specVersion: "1.5",
                   components: [
                     { name: "openssl", version: "1.1.1" },
                     { name: "curl", version: "7.81.0" }
                   ]
                 })
        end

        before do
          container_image.update!(sbom: sbom_record)
        end

        it "returns the SBOM data" do
          get "/api/v1/supply_chain/container_images/#{container_image.id}/sbom",
              headers: read_headers,
              as: :json

          expect_success_response
          data = json_response_data
          expect(data["sbom"]).to be_present
          # The SBOM is an association, so it returns the object with all its attributes
          expect(data["sbom"]).to be_a(Hash)
        end
      end

      context "when container image has no SBOM" do
        it "returns null sbom with message" do
          get "/api/v1/supply_chain/container_images/#{container_image.id}/sbom",
              headers: read_headers,
              as: :json

          expect_success_response
          data = json_response_data
          expect(data["sbom"]).to be_nil
          expect(data["message"]).to eq("No SBOM available for this image")
        end
      end
    end

    context "account isolation" do
      it "returns not found for container image from different account" do
        get "/api/v1/supply_chain/container_images/#{other_account_image.id}/sbom",
            headers: read_headers,
            as: :json

        expect_error_response("Container image not found", 404)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/container_images/#{container_image.id}/sbom",
            headers: no_permission_headers,
            as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/container_images/#{container_image.id}/sbom", as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "POST /api/v1/supply_chain/container_images/:id/quarantine" do
    let!(:container_image) { create(:supply_chain_container_image, account: account, status: "unverified") }
    let!(:other_account_image) { create(:supply_chain_container_image, account: other_account) }

    before do
      # Mock the quarantine! method
      allow_any_instance_of(SupplyChain::ContainerImage).to receive(:quarantine!).and_call_original
    end

    context "with supply_chain.write permission" do
      it "quarantines the container image" do
        post "/api/v1/supply_chain/container_images/#{container_image.id}/quarantine",
             params: { reason: "Critical vulnerabilities detected" },
             headers: write_headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data["container_image"]["status"]).to eq("quarantined")
        expect(data["message"]).to eq("Container image quarantined")
      end

      it "accepts optional reason parameter" do
        post "/api/v1/supply_chain/container_images/#{container_image.id}/quarantine",
             params: { reason: "Security policy violation" },
             headers: write_headers,
             as: :json

        expect_success_response
        container_image.reload
        expect(container_image.metadata["quarantine_reason"]).to eq("Security policy violation")
      end
    end

    context "account isolation" do
      it "returns not found for container image from different account" do
        post "/api/v1/supply_chain/container_images/#{other_account_image.id}/quarantine",
             headers: write_headers,
             as: :json

        expect_error_response("Container image not found", 404)
      end
    end

    context "with only supply_chain.read permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/container_images/#{container_image.id}/quarantine",
             headers: read_headers,
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        post "/api/v1/supply_chain/container_images/#{container_image.id}/quarantine", as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "POST /api/v1/supply_chain/container_images/:id/verify" do
    let!(:container_image) { create(:supply_chain_container_image, account: account, status: "unverified") }
    let!(:other_account_image) { create(:supply_chain_container_image, account: other_account) }

    before do
      # Mock the verify! method
      allow_any_instance_of(SupplyChain::ContainerImage).to receive(:verify!).and_call_original
    end

    context "with supply_chain.write permission" do
      it "verifies the container image" do
        post "/api/v1/supply_chain/container_images/#{container_image.id}/verify",
             headers: write_headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data["container_image"]["status"]).to eq("verified")
        expect(data["message"]).to eq("Container image verified")
      end
    end

    context "account isolation" do
      it "returns not found for container image from different account" do
        post "/api/v1/supply_chain/container_images/#{other_account_image.id}/verify",
             headers: write_headers,
             as: :json

        expect_error_response("Container image not found", 404)
      end
    end

    context "with only supply_chain.read permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/container_images/#{container_image.id}/verify",
             headers: read_headers,
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        post "/api/v1/supply_chain/container_images/#{container_image.id}/verify", as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "GET /api/v1/supply_chain/container_images/statistics" do
    let!(:verified_image) { create(:supply_chain_container_image, :verified, account: account, is_deployed: true, critical_vuln_count: 0) }
    let!(:quarantined_image) { create(:supply_chain_container_image, :quarantined, account: account, critical_vuln_count: 5) }
    let!(:clean_image) { create(:supply_chain_container_image, :clean, account: account, is_deployed: true, critical_vuln_count: 0) }
    let!(:other_account_image) { create(:supply_chain_container_image, account: other_account) }

    context "with supply_chain.read permission" do
      it "returns statistics for container images" do
        get "/api/v1/supply_chain/container_images/statistics", headers: read_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data["total"]).to eq(3)
        expect(data["by_status"]).to be_a(Hash)
        expect(data["by_registry"]).to be_a(Hash)
        expect(data["deployed_count"]).to eq(2)
        expect(data["with_critical_vulns"]).to eq(1)
        expect(data["vulnerability_totals"]).to include(
          "critical",
          "high",
          "medium",
          "low"
        )
      end

      it "only includes statistics for current account" do
        get "/api/v1/supply_chain/container_images/statistics", headers: read_headers, as: :json

        expect_success_response
        data = json_response_data
        # Should only count images from current account, not other_account
        expect(data["total"]).to eq(3)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/container_images/statistics", headers: no_permission_headers, as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/container_images/statistics", as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end
end
