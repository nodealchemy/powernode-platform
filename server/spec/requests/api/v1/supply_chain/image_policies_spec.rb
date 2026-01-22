# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::SupplyChain::ImagePolicies", type: :request do
  # Stub audit logging to prevent validation errors for supply_chain actions
  before do
    allow_any_instance_of(Api::V1::SupplyChain::ImagePoliciesController).to receive(:log_audit_event)
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

  describe "GET /api/v1/supply_chain/image_policies" do
    let!(:policy1) { create(:supply_chain_image_policy, :vulnerability_threshold, account: account, is_active: true, created_by: write_user) }
    let!(:policy2) { create(:supply_chain_image_policy, :signature_required, account: account, is_active: true, created_by: write_user) }
    let!(:inactive_policy) { create(:supply_chain_image_policy, :registry_allowlist, account: account, is_active: false, created_by: write_user) }
    let!(:other_account_policy) { create(:supply_chain_image_policy, account: other_account) }

    context "with supply_chain.read permission" do
      it "returns list of image policies for current account" do
        get "/api/v1/supply_chain/image_policies", headers: read_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data["image_policies"]).to be_an(Array)
        expect(data["image_policies"].length).to eq(3)
        expect(data["image_policies"].none? { |p| p["id"] == other_account_policy.id }).to be true
        expect(json_response["meta"]).to include("total_count" => 3)
      end

      it "filters by active_only" do
        get "/api/v1/supply_chain/image_policies?active_only=true", headers: read_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data["image_policies"].length).to eq(2)
        expect(data["image_policies"].all? { |p| p["is_active"] }).to be true
      end

      it "filters by policy_type" do
        get "/api/v1/supply_chain/image_policies?policy_type=vulnerability_threshold", headers: read_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data["image_policies"].length).to eq(1)
        expect(data["image_policies"].first["policy_type"]).to eq("vulnerability_threshold")
      end

      it "supports pagination" do
        get "/api/v1/supply_chain/image_policies?page=1&per_page=2", headers: read_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data["image_policies"].length).to eq(2)
        expect(json_response["meta"]).to include("current_page" => 1, "per_page" => 2, "total_count" => 3)
      end

      it "orders by created_at descending" do
        get "/api/v1/supply_chain/image_policies", headers: read_headers, as: :json

        expect_success_response
        data = json_response_data
        policies = data["image_policies"]
        expect(policies.first["id"]).to eq(inactive_policy.id)
        expect(policies.last["id"]).to eq(policy1.id)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/image_policies", headers: no_permission_headers, as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/image_policies", as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "GET /api/v1/supply_chain/image_policies/:id" do
    let!(:policy) { create(:supply_chain_image_policy, :vulnerability_threshold, account: account, created_by: write_user) }
    let!(:other_account_policy) { create(:supply_chain_image_policy, account: other_account) }

    context "with supply_chain.read permission" do
      it "returns image policy details" do
        get "/api/v1/supply_chain/image_policies/#{policy.id}", headers: read_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data["image_policy"]).to include(
          "id" => policy.id,
          "name" => policy.name,
          "description" => policy.description,
          "policy_type" => policy.policy_type,
          "enforcement_level" => policy.enforcement_level,
          "is_active" => policy.is_active,
          "require_signature" => policy.require_signature,
          "require_sbom" => policy.require_sbom
        )
        # Show action includes detailed fields
        expect(data["image_policy"]).to have_key("match_rules")
        expect(data["image_policy"]).to have_key("rules")
        expect(data["image_policy"]).to have_key("max_critical_vulns")
        expect(data["image_policy"]).to have_key("max_high_vulns")
        expect(data["image_policy"]).to have_key("metadata")
      end

      it "returns not found for non-existent policy" do
        get "/api/v1/supply_chain/image_policies/#{SecureRandom.uuid}", headers: read_headers, as: :json

        expect_error_response("Image policy not found", 404)
      end
    end

    context "account isolation" do
      it "returns not found for policy from different account" do
        get "/api/v1/supply_chain/image_policies/#{other_account_policy.id}", headers: read_headers, as: :json

        expect_error_response("Image policy not found", 404)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/image_policies/#{policy.id}", headers: no_permission_headers, as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/image_policies/#{policy.id}", as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "POST /api/v1/supply_chain/image_policies" do
    let(:valid_params) do
      {
        image_policy: {
          name: "Critical Vulnerability Policy",
          description: "Block images with critical vulnerabilities",
          policy_type: "vulnerability_threshold",
          enforcement_level: "block",
          is_active: true,
          max_critical_vulns: 0,
          max_high_vulns: 5,
          match_rules: { registries: ["gcr.io"] },
          rules: {},
          metadata: {}
        }
      }
    end

    context "with supply_chain.write permission" do
      it "creates a new image policy" do
        expect {
          post "/api/v1/supply_chain/image_policies", params: valid_params, headers: write_headers, as: :json
        }.to change { account.supply_chain_image_policies.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data["image_policy"]).to include(
          "name" => "Critical Vulnerability Policy",
          "policy_type" => "vulnerability_threshold",
          "enforcement_level" => "block",
          "is_active" => true
        )
      end

      it "associates policy with current account" do
        post "/api/v1/supply_chain/image_policies", params: valid_params, headers: write_headers, as: :json

        policy = SupplyChain::ImagePolicy.last
        expect(policy.account_id).to eq(account.id)
      end

      it "associates policy with current user" do
        post "/api/v1/supply_chain/image_policies", params: valid_params, headers: write_headers, as: :json

        policy = SupplyChain::ImagePolicy.last
        expect(policy.created_by_id).to eq(write_user.id)
      end

      it "creates signature_required policy" do
        params = {
          image_policy: {
            name: "Signature Required Policy",
            description: "Require all images to be signed",
            policy_type: "signature_required",
            enforcement_level: "block",
            is_active: true,
            require_signature: true,
            require_sbom: true
          }
        }

        post "/api/v1/supply_chain/image_policies", params: params, headers: write_headers, as: :json

        expect(response).to have_http_status(:created)
        policy = SupplyChain::ImagePolicy.last
        expect(policy.policy_type).to eq("signature_required")
        expect(policy.require_signature).to be true
        expect(policy.require_sbom).to be true
      end

      it "creates registry_allowlist policy" do
        params = {
          image_policy: {
            name: "Registry Allowlist",
            description: "Only allow trusted registries",
            policy_type: "registry_allowlist",
            enforcement_level: "block",
            is_active: true,
            rules: {
              allowed_registries: ["gcr.io", "docker.io"],
              denied_registries: ["quay.io"]
            }
          }
        }

        post "/api/v1/supply_chain/image_policies", params: params, headers: write_headers, as: :json

        expect(response).to have_http_status(:created)
        policy = SupplyChain::ImagePolicy.last
        expect(policy.policy_type).to eq("registry_allowlist")
        expect(policy.rules["allowed_registries"]).to include("gcr.io", "docker.io")
      end

      it "returns validation errors for invalid params" do
        invalid_params = valid_params.deep_merge(image_policy: { name: nil })

        post "/api/v1/supply_chain/image_policies", params: invalid_params, headers: write_headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json = json_response
        expect(json["success"]).to be false
        expect(json["error"]).to include("Name")
      end

      it "returns validation errors for invalid policy_type" do
        invalid_params = valid_params.deep_merge(image_policy: { policy_type: "invalid_type" })

        post "/api/v1/supply_chain/image_policies", params: invalid_params, headers: write_headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json = json_response
        expect(json["success"]).to be false
      end

      it "returns validation errors for invalid enforcement_level" do
        invalid_params = valid_params.deep_merge(image_policy: { enforcement_level: "invalid_level" })

        post "/api/v1/supply_chain/image_policies", params: invalid_params, headers: write_headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json = json_response
        expect(json["success"]).to be false
      end
    end

    context "with only supply_chain.read permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/image_policies", params: valid_params, headers: read_headers, as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        post "/api/v1/supply_chain/image_policies", params: valid_params, as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "PATCH /api/v1/supply_chain/image_policies/:id" do
    let!(:policy) { create(:supply_chain_image_policy, :vulnerability_threshold, account: account, is_active: true, created_by: write_user) }
    let!(:other_account_policy) { create(:supply_chain_image_policy, account: other_account) }

    let(:update_params) do
      {
        image_policy: {
          name: "Updated Policy Name",
          enforcement_level: "warn",
          is_active: false,
          max_critical_vulnerabilities: 2
        }
      }
    end

    context "with supply_chain.write permission" do
      it "updates the image policy" do
        patch "/api/v1/supply_chain/image_policies/#{policy.id}",
              params: update_params,
              headers: write_headers,
              as: :json

        expect_success_response
        data = json_response_data
        expect(data["image_policy"]["name"]).to eq("Updated Policy Name")
        expect(data["image_policy"]["enforcement_level"]).to eq("warn")
        expect(data["image_policy"]["is_active"]).to be false
      end

      it "persists the changes" do
        patch "/api/v1/supply_chain/image_policies/#{policy.id}",
              params: update_params,
              headers: write_headers,
              as: :json

        policy.reload
        expect(policy.name).to eq("Updated Policy Name")
        expect(policy.enforcement_level).to eq("warn")
        expect(policy.is_active).to be false
      end

      it "updates rules" do
        params = {
          image_policy: {
            rules: {
              allowed_registries: ["gcr.io", "ghcr.io"]
            }
          }
        }

        patch "/api/v1/supply_chain/image_policies/#{policy.id}",
              params: params,
              headers: write_headers,
              as: :json

        expect_success_response
        policy.reload
        expect(policy.rules["allowed_registries"]).to include("gcr.io", "ghcr.io")
      end

      it "returns validation errors for invalid params" do
        invalid_params = { image_policy: { enforcement_level: "invalid" } }

        patch "/api/v1/supply_chain/image_policies/#{policy.id}",
              params: invalid_params,
              headers: write_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json = json_response
        expect(json["success"]).to be false
      end
    end

    context "account isolation" do
      it "returns not found for policy from different account" do
        patch "/api/v1/supply_chain/image_policies/#{other_account_policy.id}",
              params: update_params,
              headers: write_headers,
              as: :json

        expect_error_response("Image policy not found", 404)
      end
    end

    context "with only supply_chain.read permission" do
      it "returns forbidden error" do
        patch "/api/v1/supply_chain/image_policies/#{policy.id}",
              params: update_params,
              headers: read_headers,
              as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        patch "/api/v1/supply_chain/image_policies/#{policy.id}",
              params: update_params,
              as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "DELETE /api/v1/supply_chain/image_policies/:id" do
    let!(:policy) { create(:supply_chain_image_policy, account: account, created_by: write_user) }
    let!(:other_account_policy) { create(:supply_chain_image_policy, account: other_account) }

    context "with supply_chain.write permission" do
      it "deletes the image policy" do
        expect {
          delete "/api/v1/supply_chain/image_policies/#{policy.id}", headers: write_headers, as: :json
        }.to change { account.supply_chain_image_policies.count }.by(-1)

        expect_success_response
        data = json_response_data
        expect(data["message"]).to eq("Image policy deleted")
      end

      it "removes the policy from database" do
        delete "/api/v1/supply_chain/image_policies/#{policy.id}", headers: write_headers, as: :json

        expect(SupplyChain::ImagePolicy.exists?(policy.id)).to be false
      end
    end

    context "account isolation" do
      it "returns not found for policy from different account" do
        delete "/api/v1/supply_chain/image_policies/#{other_account_policy.id}", headers: write_headers, as: :json

        expect_error_response("Image policy not found", 404)
      end
    end

    context "with only supply_chain.read permission" do
      it "returns forbidden error" do
        delete "/api/v1/supply_chain/image_policies/#{policy.id}", headers: read_headers, as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        delete "/api/v1/supply_chain/image_policies/#{policy.id}", as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "POST /api/v1/supply_chain/image_policies/:id/evaluate" do
    let!(:policy) { create(:supply_chain_image_policy, :vulnerability_threshold, account: account, created_by: write_user, max_critical_vulns: 0, max_high_vulns: 5) }
    let!(:compliant_image) { create(:supply_chain_container_image, :clean, account: account) }
    let!(:non_compliant_image) { create(:supply_chain_container_image, account: account, critical_vuln_count: 3, high_vuln_count: 10) }
    let!(:other_account_policy) { create(:supply_chain_image_policy, account: other_account) }
    let!(:other_account_image) { create(:supply_chain_container_image, account: other_account) }

    before do
      # Mock the SupplyChainChannel broadcast
      allow(SupplyChainChannel).to receive(:broadcast_policy_violation)
    end

    context "with supply_chain.write permission" do
      it "evaluates policy for compliant image" do
        post "/api/v1/supply_chain/image_policies/#{policy.id}/evaluate",
             params: { image_id: compliant_image.id },
             headers: write_headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data["policy_id"]).to eq(policy.id)
        expect(data["policy_name"]).to eq(policy.name)
        expect(data["image_id"]).to eq(compliant_image.id)
        expect(data["image_reference"]).to eq(compliant_image.full_reference)
        expect(data["compliant"]).to be true
        expect(data["enforcement_action"]).to be_present
        expect(data["violations"]).to eq([])
      end

      it "evaluates policy for non-compliant image" do
        post "/api/v1/supply_chain/image_policies/#{policy.id}/evaluate",
             params: { image_id: non_compliant_image.id },
             headers: write_headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data["policy_id"]).to eq(policy.id)
        expect(data["image_id"]).to eq(non_compliant_image.id)
        expect(data["compliant"]).to be false
        expect(data["violations"]).to be_an(Array)
        expect(data["violations"].length).to be > 0
      end

      it "broadcasts violations when policy is violated" do
        expect(SupplyChainChannel).to receive(:broadcast_policy_violation).with(
          account,
          hash_including(
            policy: policy,
            image: non_compliant_image,
            violations: kind_of(Array)
          )
        )

        post "/api/v1/supply_chain/image_policies/#{policy.id}/evaluate",
             params: { image_id: non_compliant_image.id },
             headers: write_headers,
             as: :json

        expect_success_response
      end

      it "does not broadcast when policy passes" do
        expect(SupplyChainChannel).not_to receive(:broadcast_policy_violation)

        post "/api/v1/supply_chain/image_policies/#{policy.id}/evaluate",
             params: { image_id: compliant_image.id },
             headers: write_headers,
             as: :json

        expect_success_response
      end

      it "returns error when image_id is missing" do
        post "/api/v1/supply_chain/image_policies/#{policy.id}/evaluate",
             headers: write_headers,
             as: :json

        expect(response).to have_http_status(:not_found)
      end

      it "returns error when image does not exist" do
        post "/api/v1/supply_chain/image_policies/#{policy.id}/evaluate",
             params: { image_id: SecureRandom.uuid },
             headers: write_headers,
             as: :json

        expect(response).to have_http_status(:not_found)
      end

      it "enforces account isolation for images" do
        post "/api/v1/supply_chain/image_policies/#{policy.id}/evaluate",
             params: { image_id: other_account_image.id },
             headers: write_headers,
             as: :json

        expect(response).to have_http_status(:not_found)
      end

      context "signature_required policy" do
        let!(:signature_policy) { create(:supply_chain_image_policy, :signature_required, account: account, created_by: write_user, require_signature: true) }

        it "detects missing signature" do
          allow(compliant_image).to receive(:signed?).and_return(false)
          allow_any_instance_of(SupplyChain::ContainerImage).to receive(:signed?).and_return(false)

          post "/api/v1/supply_chain/image_policies/#{signature_policy.id}/evaluate",
               params: { image_id: compliant_image.id },
               headers: write_headers,
               as: :json

          expect_success_response
          data = json_response_data
          expect(data["compliant"]).to be false
          expect(data["violations"].any? { |v| v["type"] == "signature_missing" }).to be true
        end
      end

      context "registry_allowlist policy" do
        let!(:allowlist_policy) do
          create(:supply_chain_image_policy, :registry_allowlist,
                 account: account,
                 created_by: write_user,
                 rules: { "allowed_registries" => ["gcr.io"] })
        end
        let!(:gcr_image) { create(:supply_chain_container_image, account: account, registry: "gcr.io") }
        let!(:docker_image) { create(:supply_chain_container_image, account: account, registry: "docker.io") }

        it "allows images from allowed registry" do
          post "/api/v1/supply_chain/image_policies/#{allowlist_policy.id}/evaluate",
               params: { image_id: gcr_image.id },
               headers: write_headers,
               as: :json

          expect_success_response
          data = json_response_data
          expect(data["compliant"]).to be true
        end

        it "blocks images from non-allowed registry" do
          post "/api/v1/supply_chain/image_policies/#{allowlist_policy.id}/evaluate",
               params: { image_id: docker_image.id },
               headers: write_headers,
               as: :json

          expect_success_response
          data = json_response_data
          expect(data["compliant"]).to be false
          expect(data["violations"].any? { |v| v["type"] == "registry_not_allowed" }).to be true
        end
      end
    end

    context "account isolation" do
      it "returns not found for policy from different account" do
        post "/api/v1/supply_chain/image_policies/#{other_account_policy.id}/evaluate",
             params: { image_id: compliant_image.id },
             headers: write_headers,
             as: :json

        expect_error_response("Image policy not found", 404)
      end
    end

    context "with only supply_chain.read permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/image_policies/#{policy.id}/evaluate",
             params: { image_id: compliant_image.id },
             headers: read_headers,
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        post "/api/v1/supply_chain/image_policies/#{policy.id}/evaluate",
             params: { image_id: compliant_image.id },
             as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end
end
