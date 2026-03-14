# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::SupplyChain::LicensePolicies", type: :request do
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

  describe "GET /api/v1/supply_chain/license_policies" do
    context "with supply_chain.read permission" do
      let!(:policies) do
        [
          create(:supply_chain_license_policy, account: account, name: "Policy 1", policy_type: "allowlist", is_active: true),
          create(:supply_chain_license_policy, account: account, name: "Policy 2", policy_type: "denylist", is_active: true),
          create(:supply_chain_license_policy, account: account, name: "Policy 3", policy_type: "hybrid", is_active: false)
        ]
      end

      let!(:other_policy) do
        create(:supply_chain_license_policy, account: other_account, name: "Other Policy")
      end

      it "returns license policies for the current account" do
        get "/api/v1/supply_chain/license_policies", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["license_policies"]

        expect(data.length).to eq(3)
        expect(data.map { |p| p["id"] }).to match_array(policies.map(&:id))
        expect(data.map { |p| p["id"] }).not_to include(other_policy.id)
      end

      it "returns policies ordered by created_at desc" do
        get "/api/v1/supply_chain/license_policies", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["license_policies"]

        created_ats = data.map { |p| Time.parse(p["created_at"]) }
        expect(created_ats).to eq(created_ats.sort.reverse)
      end

      it "returns policy data with correct structure" do
        get "/api/v1/supply_chain/license_policies", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        policy_data = json_response["data"]["license_policies"].first

        expect(policy_data).to include(
          "id",
          "name",
          "description",
          "policy_type",
          "enforcement_level",
          "is_active",
          "is_default",
          "priority",
          "block_copyleft",
          "block_strong_copyleft",
          "block_unknown",
          "created_at",
          "updated_at"
        )
      end

      it "filters by active_only" do
        get "/api/v1/supply_chain/license_policies?active_only=true", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["license_policies"]

        expect(data.length).to eq(2)
        expect(data.all? { |p| p["is_active"] == true }).to be true
      end

      it "filters by policy_type" do
        get "/api/v1/supply_chain/license_policies?policy_type=allowlist", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["license_policies"]

        expect(data.length).to eq(1)
        expect(data.first["policy_type"]).to eq("allowlist")
      end
    end

    context "pagination" do
      before do
        30.times do |n|
          create(:supply_chain_license_policy, account: account, name: "Policy #{n}")
        end
      end

      it "returns paginated results with default per_page of 20" do
        get "/api/v1/supply_chain/license_policies", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        expect(json_response["data"]["license_policies"].length).to eq(20)
        expect(json_response["meta"]["total_count"]).to eq(30)
        expect(json_response["meta"]["current_page"]).to eq(1)
        expect(json_response["meta"]["per_page"]).to eq(20)
        expect(json_response["meta"]["total_pages"]).to eq(2)
      end

      it "respects page parameter" do
        get "/api/v1/supply_chain/license_policies?page=2", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        expect(json_response["data"]["license_policies"].length).to eq(10)
        expect(json_response["meta"]["current_page"]).to eq(2)
      end

      it "respects per_page parameter" do
        get "/api/v1/supply_chain/license_policies?per_page=10", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        expect(json_response["data"]["license_policies"].length).to eq(10)
        expect(json_response["meta"]["per_page"]).to eq(10)
        expect(json_response["meta"]["total_pages"]).to eq(3)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/license_policies", headers: auth_headers_for(regular_user), as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/license_policies", as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "GET /api/v1/supply_chain/license_policies/:id" do
    let!(:policy) do
      create(:supply_chain_license_policy,
             account: account,
             name: "Test Policy",
             policy_type: "allowlist",
             allowed_licenses: [ "MIT", "Apache-2.0" ],
             denied_licenses: [],
             is_active: true)
    end

    context "with supply_chain.read permission" do
      it "returns the license policy details" do
        get "/api/v1/supply_chain/license_policies/#{policy.id}", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["license_policy"]

        expect(data["id"]).to eq(policy.id)
        expect(data["name"]).to eq(policy.name)
        expect(data["policy_type"]).to eq(policy.policy_type)
        expect(data["is_active"]).to eq(policy.is_active)
      end

      it "includes detailed information" do
        get "/api/v1/supply_chain/license_policies/#{policy.id}", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_success_response
        data = json_response["data"]["license_policy"]

        expect(data).to include(
          "allowed_licenses",
          "denied_licenses",
          "exception_packages",
          "violation_count",
          "metadata"
        )
        expect(data["allowed_licenses"]).to eq([ "MIT", "Apache-2.0" ])
      end
    end

    context "with license policy from another account" do
      let(:other_policy) { create(:supply_chain_license_policy, account: other_account) }

      it "returns not found error" do
        get "/api/v1/supply_chain/license_policies/#{other_policy.id}", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_error_response("License policy not found", 404)
      end
    end

    context "with non-existent license policy" do
      it "returns not found error" do
        get "/api/v1/supply_chain/license_policies/non-existent-id", headers: auth_headers_for(supply_chain_reader), as: :json

        expect_error_response("License policy not found", 404)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/license_policies/#{policy.id}", headers: auth_headers_for(regular_user), as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/license_policies" do
    context "with supply_chain.write permission" do
      let(:valid_params) do
        {
          license_policy: {
            name: "New License Policy",
            description: "A test license policy",
            policy_type: "allowlist",
            enforcement_level: "warn",
            is_active: true,
            allowed_licenses: [ "MIT", "Apache-2.0", "BSD-3-Clause" ],
            denied_licenses: [],
            block_copyleft: false,
            block_strong_copyleft: true
          }
        }
      end

      it "creates a new license policy" do
        expect {
          post "/api/v1/supply_chain/license_policies",
               params: valid_params,
               headers: auth_headers_for(supply_chain_writer),
               as: :json
        }.to change(SupplyChain::LicensePolicy, :count).by(1)

        expect(response).to have_http_status(:created)
        expect_success_response
        expect(json_response["data"]["license_policy"]["name"]).to eq("New License Policy")
        expect(json_response["data"]["license_policy"]["policy_type"]).to eq("allowlist")
      end

      it "associates the policy with the current account" do
        post "/api/v1/supply_chain/license_policies",
             params: valid_params,
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        policy = SupplyChain::LicensePolicy.last
        expect(policy.account_id).to eq(account.id)
      end

      it "associates the policy with the current user as creator" do
        post "/api/v1/supply_chain/license_policies",
             params: valid_params,
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_success_response
        policy = SupplyChain::LicensePolicy.last
        expect(policy.created_by_id).to eq(supply_chain_writer.id)
      end

      it "returns error with invalid params" do
        invalid_params = {
          license_policy: {
            name: "",
            policy_type: "invalid_type"
          }
        }

        post "/api/v1/supply_chain/license_policies",
             params: invalid_params,
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_error_response("Name can't be blank, Policy type is not included in the list", 422)
      end

      it "returns error when name is not unique for account" do
        create(:supply_chain_license_policy, account: account, name: "Duplicate Policy")

        duplicate_params = {
          license_policy: {
            name: "Duplicate Policy",
            policy_type: "allowlist",
            enforcement_level: "warn"
          }
        }

        post "/api/v1/supply_chain/license_policies",
             params: duplicate_params,
             headers: auth_headers_for(supply_chain_writer),
             as: :json

        expect_error_response("Name has already been taken", 422)
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error for user with only supply_chain.read" do
        post "/api/v1/supply_chain/license_policies",
             params: { license_policy: { name: "Test Policy" } },
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end

      it "returns forbidden error for regular user" do
        post "/api/v1/supply_chain/license_policies",
             params: { license_policy: { name: "Test Policy" } },
             headers: auth_headers_for(regular_user),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "PATCH /api/v1/supply_chain/license_policies/:id" do
    let(:policy) do
      create(:supply_chain_license_policy,
             account: account,
             name: "Original Policy",
             policy_type: "allowlist",
             enforcement_level: "warn")
    end

    context "with supply_chain.write permission" do
      it "updates the license policy" do
        patch "/api/v1/supply_chain/license_policies/#{policy.id}",
              params: { license_policy: { name: "Updated Policy" } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_success_response
        expect(json_response["data"]["license_policy"]["name"]).to eq("Updated Policy")

        policy.reload
        expect(policy.name).to eq("Updated Policy")
      end

      it "updates the enforcement level" do
        patch "/api/v1/supply_chain/license_policies/#{policy.id}",
              params: { license_policy: { enforcement_level: "block" } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_success_response
        expect(json_response["data"]["license_policy"]["enforcement_level"]).to eq("block")
      end

      it "updates allowed licenses" do
        patch "/api/v1/supply_chain/license_policies/#{policy.id}",
              params: { license_policy: { allowed_licenses: [ "MIT", "Apache-2.0", "BSD-3-Clause" ] } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_success_response
        policy.reload
        expect(policy.allowed_licenses).to match_array([ "MIT", "Apache-2.0", "BSD-3-Clause" ])
      end

      it "updates block_copyleft settings" do
        patch "/api/v1/supply_chain/license_policies/#{policy.id}",
              params: { license_policy: { block_copyleft: true, block_strong_copyleft: true } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_success_response
        policy.reload
        expect(policy.block_copyleft).to be true
        expect(policy.block_strong_copyleft).to be true
      end

      it "returns error with invalid params" do
        patch "/api/v1/supply_chain/license_policies/#{policy.id}",
              params: { license_policy: { enforcement_level: "invalid" } },
              headers: auth_headers_for(supply_chain_writer),
              as: :json

        expect_error_response("Enforcement level is not included in the list", 422)
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        patch "/api/v1/supply_chain/license_policies/#{policy.id}",
              params: { license_policy: { name: "Updated Policy" } },
              headers: auth_headers_for(supply_chain_reader),
              as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "DELETE /api/v1/supply_chain/license_policies/:id" do
    let!(:policy) { create(:supply_chain_license_policy, account: account) }

    context "with supply_chain.write permission" do
      it "deletes the license policy" do
        expect {
          delete "/api/v1/supply_chain/license_policies/#{policy.id}",
                 headers: auth_headers_for(supply_chain_writer),
                 as: :json
        }.to change(SupplyChain::LicensePolicy, :count).by(-1)

        expect_success_response
        expect(json_response["data"]["message"]).to eq("License policy deleted")
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        delete "/api/v1/supply_chain/license_policies/#{policy.id}",
               headers: auth_headers_for(supply_chain_reader),
               as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/license_policies/:id/evaluate" do
    let(:policy) do
      create(:supply_chain_license_policy,
             account: account,
             name: "Test Policy",
             policy_type: "denylist",
             enforcement_level: "block",
             denied_licenses: [ "GPL-3.0-only", "AGPL-3.0-only" ],
             block_strong_copyleft: true)
    end

    let!(:sbom1) do
      create(:supply_chain_sbom, account: account, name: "SBOM 1", component_count: 10)
    end

    let!(:sbom2) do
      create(:supply_chain_sbom, account: account, name: "SBOM 2", component_count: 5)
    end

    let!(:other_sbom) do
      create(:supply_chain_sbom, account: other_account, name: "Other SBOM")
    end

    context "with supply_chain.read permission" do
      it "evaluates the policy against multiple SBOMs" do
        # Mock the evaluate method to return violations
        allow_any_instance_of(SupplyChain::LicensePolicy).to receive(:evaluate).and_return([
          {
            license_spdx_id: "GPL-3.0-only",
            component_name: "some-package",
            violation_type: "denied",
            severity: "high"
          }
        ])

        post "/api/v1/supply_chain/license_policies/#{policy.id}/evaluate",
             params: { sbom_ids: [ sbom1.id, sbom2.id ] },
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["policy_id"]).to eq(policy.id)
        expect(data["policy_name"]).to eq(policy.name)
        expect(data["results"]).to be_an(Array)
        expect(data["results"].length).to eq(2)
      end

      it "returns compliant result when no violations found" do
        # Mock evaluate to return empty violations
        allow_any_instance_of(SupplyChain::LicensePolicy).to receive(:evaluate).and_return([])

        post "/api/v1/supply_chain/license_policies/#{policy.id}/evaluate",
             params: { sbom_ids: [ sbom1.id ] },
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect_success_response
        data = json_response["data"]

        result = data["results"].first
        expect(result["sbom_id"]).to eq(sbom1.id)
        expect(result["sbom_name"]).to eq(sbom1.name)
        expect(result["compliant"]).to be true
        expect(result["violation_count"]).to eq(0)
        expect(result["violations"]).to eq([])
      end

      it "returns violation results with correct structure" do
        violations = [
          {
            license_spdx_id: "GPL-3.0-only",
            component_name: "package-a",
            violation_type: "denied",
            severity: "high"
          },
          {
            license_spdx_id: "AGPL-3.0-only",
            component_name: "package-b",
            violation_type: "strong_copyleft",
            severity: "critical"
          }
        ]
        allow_any_instance_of(SupplyChain::LicensePolicy).to receive(:evaluate).and_return(violations)

        post "/api/v1/supply_chain/license_policies/#{policy.id}/evaluate",
             params: { sbom_ids: [ sbom1.id ] },
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect_success_response
        data = json_response["data"]

        result = data["results"].first
        expect(result["compliant"]).to be false
        expect(result["violation_count"]).to eq(2)
        expect(result["violations"].length).to eq(2)

        violation = result["violations"].first
        expect(violation).to include(
          "license_spdx_id",
          "component_name",
          "violation_type",
          "severity"
        )
      end

      it "calculates total violations across all SBOMs" do
        # First SBOM has 2 violations
        violations_sbom1 = [
          { license_spdx_id: "GPL-3.0-only", component_name: "pkg1", violation_type: "denied", severity: "high" },
          { license_spdx_id: "AGPL-3.0-only", component_name: "pkg2", violation_type: "denied", severity: "high" }
        ]
        # Second SBOM has 1 violation
        violations_sbom2 = [
          { license_spdx_id: "GPL-3.0-only", component_name: "pkg3", violation_type: "denied", severity: "high" }
        ]

        allow_any_instance_of(SupplyChain::LicensePolicy).to receive(:evaluate).and_return(violations_sbom1, violations_sbom2)

        post "/api/v1/supply_chain/license_policies/#{policy.id}/evaluate",
             params: { sbom_ids: [ sbom1.id, sbom2.id ] },
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect_success_response
        expect(json_response["data"]["total_violations"]).to eq(3)
      end

      it "handles empty sbom_ids parameter" do
        post "/api/v1/supply_chain/license_policies/#{policy.id}/evaluate",
             params: { sbom_ids: [] },
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect_success_response
        expect(json_response["data"]["results"]).to eq([])
        expect(json_response["data"]["total_violations"]).to eq(0)
      end

      it "ignores SBOMs from other accounts" do
        allow_any_instance_of(SupplyChain::LicensePolicy).to receive(:evaluate).and_return([])

        post "/api/v1/supply_chain/license_policies/#{policy.id}/evaluate",
             params: { sbom_ids: [ sbom1.id, other_sbom.id ] },
             headers: auth_headers_for(supply_chain_reader),
             as: :json

        expect_success_response
        data = json_response["data"]

        # Should only evaluate sbom1, not other_sbom
        expect(data["results"].length).to eq(1)
        expect(data["results"].first["sbom_id"]).to eq(sbom1.id)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/license_policies/#{policy.id}/evaluate",
             params: { sbom_ids: [ sbom1.id ] },
             headers: auth_headers_for(regular_user),
             as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "account isolation" do
    let!(:account_policy) { create(:supply_chain_license_policy, account: account, name: "Account Policy") }
    let!(:other_policy) { create(:supply_chain_license_policy, account: other_account, name: "Other Policy") }

    it "only returns policies for the authenticated user account" do
      get "/api/v1/supply_chain/license_policies", headers: auth_headers_for(supply_chain_reader), as: :json

      expect_success_response
      policy_ids = json_response["data"]["license_policies"].map { |p| p["id"] }

      expect(policy_ids).to include(account_policy.id)
      expect(policy_ids).not_to include(other_policy.id)
    end

    it "prevents accessing another account policy directly" do
      get "/api/v1/supply_chain/license_policies/#{other_policy.id}", headers: auth_headers_for(supply_chain_reader), as: :json

      expect_error_response("License policy not found", 404)
    end

    it "prevents modifying another account policy" do
      patch "/api/v1/supply_chain/license_policies/#{other_policy.id}",
            params: { license_policy: { name: "Hacked" } },
            headers: auth_headers_for(supply_chain_writer),
            as: :json

      expect_error_response("License policy not found", 404)
    end

    it "prevents deleting another account policy" do
      delete "/api/v1/supply_chain/license_policies/#{other_policy.id}",
             headers: auth_headers_for(supply_chain_writer),
             as: :json

      expect_error_response("License policy not found", 404)
    end
  end
end
