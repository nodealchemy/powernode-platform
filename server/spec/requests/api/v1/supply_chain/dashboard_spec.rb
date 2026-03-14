# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::SupplyChain::Dashboard", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ "supply_chain.read" ]) }
  let(:user_without_permission) { create(:user, account: account, permissions: []) }
  let(:headers) { auth_headers_for(user) }

  before(:each) do
    Rails.cache.clear
  end

  describe "GET /api/v1/supply_chain/dashboard" do
    context "with valid authentication and permissions" do
      before do
        # Create test data for dashboard
        create_list(:supply_chain_sbom, 3, account: account, ntia_minimum_compliant: false, vulnerability_count: 0)
        create(:supply_chain_sbom, account: account, ntia_minimum_compliant: true, vulnerability_count: 5)
        create(:supply_chain_attestation, account: account, signature: "test_signature")
        create(:supply_chain_container_image, account: account, status: "verified")
        create(:supply_chain_container_image, account: account, status: "quarantined")
        create(:supply_chain_vendor, account: account, status: "active", risk_tier: "high")
      end

      it "returns success response" do
        get "/api/v1/supply_chain/dashboard", headers: headers, as: :json

        expect_success_response
      end

      it "returns overview data with correct structure" do
        get "/api/v1/supply_chain/dashboard", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data).to have_key("overview")
        overview = response_data["overview"]

        expect(overview).to include(
          "sboms" => hash_including(
            "total" => kind_of(Integer),
            "with_vulnerabilities" => kind_of(Integer),
            "ntia_compliant" => kind_of(Integer)
          ),
          "vulnerabilities" => hash_including(
            "total" => kind_of(Integer),
            "critical" => kind_of(Integer),
            "high" => kind_of(Integer),
            "open" => kind_of(Integer)
          ),
          "attestations" => hash_including(
            "total" => kind_of(Integer),
            "signed" => kind_of(Integer),
            "verified" => kind_of(Integer)
          ),
          "container_images" => hash_including(
            "total" => kind_of(Integer),
            "verified" => kind_of(Integer),
            "quarantined" => kind_of(Integer)
          ),
          "vendors" => hash_including(
            "total" => kind_of(Integer),
            "active" => kind_of(Integer),
            "high_risk" => kind_of(Integer)
          )
        )
      end

      it "returns recent_activity array" do
        get "/api/v1/supply_chain/dashboard", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data).to have_key("recent_activity")
        expect(response_data["recent_activity"]).to be_an(Array)
      end

      it "returns alerts array" do
        get "/api/v1/supply_chain/dashboard", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data).to have_key("alerts")
        expect(response_data["alerts"]).to be_an(Array)
      end

      it "returns quick_stats with correct structure" do
        get "/api/v1/supply_chain/dashboard", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data).to have_key("quick_stats")
        quick_stats = response_data["quick_stats"]

        expect(quick_stats).to include(
          "sboms_this_month" => kind_of(Integer),
          "scans_this_month" => kind_of(Integer),
          "attestations_this_month" => kind_of(Integer)
        )
      end

      it "includes correct SBOM counts" do
        get "/api/v1/supply_chain/dashboard", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data["overview"]["sboms"]["total"]).to eq(4)
        expect(response_data["overview"]["sboms"]["ntia_compliant"]).to eq(1)
        expect(response_data["overview"]["sboms"]["with_vulnerabilities"]).to eq(1)
      end

      it "includes correct container image counts" do
        get "/api/v1/supply_chain/dashboard", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data["overview"]["container_images"]["total"]).to eq(2)
        expect(response_data["overview"]["container_images"]["verified"]).to eq(1)
        expect(response_data["overview"]["container_images"]["quarantined"]).to eq(1)
      end

      it "includes correct vendor counts" do
        get "/api/v1/supply_chain/dashboard", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data["overview"]["vendors"]["total"]).to eq(1)
        expect(response_data["overview"]["vendors"]["active"]).to eq(1)
        expect(response_data["overview"]["vendors"]["high_risk"]).to eq(1)
      end

      it "includes correct attestation counts" do
        get "/api/v1/supply_chain/dashboard", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data["overview"]["attestations"]["total"]).to eq(1)
        expect(response_data["overview"]["attestations"]["signed"]).to eq(1)
      end
    end

    context "with empty data" do
      it "returns zero counts when no data exists" do
        get "/api/v1/supply_chain/dashboard", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data["overview"]["sboms"]["total"]).to eq(0)
        expect(response_data["overview"]["vulnerabilities"]["total"]).to eq(0)
        expect(response_data["overview"]["attestations"]["total"]).to eq(0)
        expect(response_data["overview"]["container_images"]["total"]).to eq(0)
        expect(response_data["overview"]["vendors"]["total"]).to eq(0)
      end
    end

    context "without supply_chain.read permission" do
      let(:headers) { auth_headers_for(user_without_permission) }

      it "returns forbidden error" do
        get "/api/v1/supply_chain/dashboard", headers: headers, as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/dashboard", as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "when user belongs to different account" do
      let(:other_account) { create(:account) }
      let(:other_user) { create(:user, account: other_account, permissions: [ "supply_chain.read" ]) }
      let(:other_headers) { auth_headers_for(other_user) }

      before do
        create_list(:supply_chain_sbom, 2, account: account)
        create_list(:supply_chain_sbom, 3, account: other_account)
      end

      it "returns only data for user's account" do
        get "/api/v1/supply_chain/dashboard", headers: other_headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data["overview"]["sboms"]["total"]).to eq(3)
      end
    end
  end

  describe "GET /api/v1/supply_chain/analytics" do
    context "with valid authentication and permissions" do
      before do
        create_list(:supply_chain_sbom, 2, account: account)
        create(:supply_chain_container_image, account: account)
        create(:supply_chain_vendor, account: account, status: "active")
      end

      it "returns success response" do
        get "/api/v1/supply_chain/analytics", headers: headers, as: :json

        expect_success_response
      end

      it "returns analytics data with all required metrics" do
        get "/api/v1/supply_chain/analytics", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data).to have_key("vulnerability_trends")
        expect(response_data).to have_key("sbom_metrics")
        expect(response_data).to have_key("container_metrics")
        expect(response_data).to have_key("vendor_risk_metrics")
        expect(response_data).to have_key("compliance_metrics")
      end

      it "returns sbom_metrics with correct structure" do
        get "/api/v1/supply_chain/analytics", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data["sbom_metrics"]).to include(
          "total" => kind_of(Integer),
          "by_format" => kind_of(Hash),
          "ntia_compliance_rate" => kind_of(Numeric)
        )
      end

      it "returns container_metrics with correct structure" do
        get "/api/v1/supply_chain/analytics", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data["container_metrics"]).to include(
          "total" => kind_of(Integer),
          "by_status" => kind_of(Hash),
          "deployed" => kind_of(Integer),
          "total_vulnerabilities" => hash_including(
            "critical" => kind_of(Integer),
            "high" => kind_of(Integer),
            "medium" => kind_of(Integer),
            "low" => kind_of(Integer)
          )
        )
      end

      it "returns vendor_risk_metrics with correct structure" do
        get "/api/v1/supply_chain/analytics", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data["vendor_risk_metrics"]).to include(
          "total_active" => kind_of(Integer),
          "by_risk_tier" => kind_of(Hash),
          "by_type" => kind_of(Hash),
          "assessments_completed" => kind_of(Integer)
        )
      end

      it "returns compliance_metrics with correct structure" do
        get "/api/v1/supply_chain/analytics", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data["compliance_metrics"]).to include(
          "license_violations" => kind_of(Integer),
          "policy_violations" => kind_of(Hash),
          "compliant_sboms" => kind_of(Integer),
          "signed_attestations" => kind_of(Integer)
        )
      end

      it "returns vulnerability_trends as hash" do
        get "/api/v1/supply_chain/analytics", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data["vulnerability_trends"]).to be_a(Hash)
      end
    end

    context "without supply_chain.read permission" do
      let(:headers) { auth_headers_for(user_without_permission) }

      it "returns forbidden error" do
        get "/api/v1/supply_chain/analytics", headers: headers, as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/analytics", as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "GET /api/v1/supply_chain/compliance_summary" do
    context "with valid authentication and permissions" do
      before do
        create(:supply_chain_sbom, account: account, ntia_minimum_compliant: true)
        create(:supply_chain_sbom, account: account, ntia_minimum_compliant: false)
        create(:supply_chain_attestation, account: account, slsa_level: "SLSA_LEVEL_2", signature: "test_sig")
        create(:supply_chain_vendor, account: account, status: "active")
      end

      it "returns success response" do
        get "/api/v1/supply_chain/compliance_summary", headers: headers, as: :json

        expect_success_response
      end

      it "returns compliance summary with all required sections" do
        get "/api/v1/supply_chain/compliance_summary", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data).to have_key("overall_status")
        expect(response_data).to have_key("ntia_compliance")
        expect(response_data).to have_key("slsa_compliance")
        expect(response_data).to have_key("license_compliance")
        expect(response_data).to have_key("vendor_compliance")
        expect(response_data).to have_key("recommendations")
      end

      it "returns overall_status with score and status" do
        get "/api/v1/supply_chain/compliance_summary", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data["overall_status"]).to include(
          "score" => kind_of(Numeric),
          "status" => be_in([ "good", "warning", "critical" ])
        )
      end

      it "returns ntia_compliance with correct structure" do
        get "/api/v1/supply_chain/compliance_summary", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data["ntia_compliance"]).to include(
          "compliant_count" => kind_of(Integer),
          "total_count" => kind_of(Integer),
          "compliance_rate" => kind_of(Numeric)
        )
      end

      it "returns slsa_compliance with correct structure" do
        get "/api/v1/supply_chain/compliance_summary", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data["slsa_compliance"]).to include(
          "total" => kind_of(Integer),
          "by_level" => kind_of(Hash),
          "signed_percentage" => kind_of(Numeric),
          "rekor_logged_percentage" => kind_of(Numeric)
        )
      end

      it "returns license_compliance with correct structure" do
        get "/api/v1/supply_chain/compliance_summary", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data["license_compliance"]).to include(
          "policies_active" => kind_of(Integer),
          "violations_open" => kind_of(Integer),
          "violations_by_type" => kind_of(Hash)
        )
      end

      it "returns vendor_compliance with correct structure" do
        get "/api/v1/supply_chain/compliance_summary", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data["vendor_compliance"]).to include(
          "total_active" => kind_of(Integer),
          "with_dpa" => kind_of(Integer),
          "pii_without_dpa" => kind_of(Integer),
          "with_baa" => kind_of(Integer),
          "phi_without_baa" => kind_of(Integer),
          "assessments_current" => kind_of(Integer)
        )
      end

      it "returns recommendations as array" do
        get "/api/v1/supply_chain/compliance_summary", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data["recommendations"]).to be_an(Array)
      end

      it "calculates correct NTIA compliance rate" do
        get "/api/v1/supply_chain/compliance_summary", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data["ntia_compliance"]["compliant_count"]).to eq(1)
        expect(response_data["ntia_compliance"]["total_count"]).to eq(2)
        expect(response_data["ntia_compliance"]["compliance_rate"]).to eq(50.0)
      end
    end

    context "with no data" do
      it "returns 100% compliance when no SBOMs exist" do
        get "/api/v1/supply_chain/compliance_summary", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data["ntia_compliance"]["compliance_rate"]).to eq(100)
      end

      it "returns overall status as good with 100 score" do
        get "/api/v1/supply_chain/compliance_summary", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        expect(response_data["overall_status"]["score"]).to eq(100)
        expect(response_data["overall_status"]["status"]).to eq("good")
      end
    end

    context "with recommendations generated" do
      before do
        # Create non-compliant SBOM
        create(:supply_chain_sbom, account: account, ntia_minimum_compliant: false)
        # Create unsigned attestation
        create(:supply_chain_attestation, account: account, signature: nil)
      end

      it "includes recommendations for non-compliant SBOMs" do
        get "/api/v1/supply_chain/compliance_summary", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        sbom_recommendations = response_data["recommendations"].select { |r| r["category"] == "sbom" }
        expect(sbom_recommendations).not_to be_empty
      end

      it "includes recommendations for unsigned attestations" do
        get "/api/v1/supply_chain/compliance_summary", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        attestation_recommendations = response_data["recommendations"].select { |r| r["category"] == "attestation" }
        expect(attestation_recommendations).not_to be_empty
      end

      it "recommendations have correct structure" do
        get "/api/v1/supply_chain/compliance_summary", headers: headers, as: :json

        expect_success_response
        response_data = json_response_data

        if response_data["recommendations"].any?
          recommendation = response_data["recommendations"].first
          expect(recommendation).to include(
            "priority" => be_in([ "critical", "high", "medium", "low" ]),
            "category" => kind_of(String),
            "recommendation" => kind_of(String),
            "action" => kind_of(String)
          )
        end
      end
    end

    context "without supply_chain.read permission" do
      let(:headers) { auth_headers_for(user_without_permission) }

      it "returns forbidden error" do
        get "/api/v1/supply_chain/compliance_summary", headers: headers, as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/compliance_summary", as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "permission enforcement" do
    context "when user has supply_chain.read permission" do
      it "allows access to dashboard" do
        get "/api/v1/supply_chain/dashboard", headers: headers, as: :json

        expect(response).to have_http_status(:success)
      end

      it "allows access to analytics" do
        get "/api/v1/supply_chain/analytics", headers: headers, as: :json

        expect(response).to have_http_status(:success)
      end

      it "allows access to compliance_summary" do
        get "/api/v1/supply_chain/compliance_summary", headers: headers, as: :json

        expect(response).to have_http_status(:success)
      end
    end

    context "when user lacks supply_chain.read permission" do
      let(:headers) { auth_headers_for(user_without_permission) }

      it "denies access to dashboard" do
        get "/api/v1/supply_chain/dashboard", headers: headers, as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end

      it "denies access to analytics" do
        get "/api/v1/supply_chain/analytics", headers: headers, as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end

      it "denies access to compliance_summary" do
        get "/api/v1/supply_chain/compliance_summary", headers: headers, as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "data isolation between accounts" do
    let(:other_account) { create(:account) }
    let(:other_user) { create(:user, account: other_account, permissions: [ "supply_chain.read" ]) }

    before do
      # Create data for main account
      create_list(:supply_chain_sbom, 3, account: account)
      create_list(:supply_chain_container_image, 2, account: account)

      # Create data for other account
      create_list(:supply_chain_sbom, 5, account: other_account)
      create_list(:supply_chain_container_image, 4, account: other_account)
    end

    it "returns only account-specific data in dashboard" do
      get "/api/v1/supply_chain/dashboard", headers: auth_headers_for(other_user), as: :json

      expect_success_response
      response_data = json_response_data

      expect(response_data["overview"]["sboms"]["total"]).to eq(5)
      expect(response_data["overview"]["container_images"]["total"]).to eq(4)
    end

    it "returns only account-specific data in analytics" do
      get "/api/v1/supply_chain/analytics", headers: auth_headers_for(other_user), as: :json

      expect_success_response
      response_data = json_response_data

      expect(response_data["sbom_metrics"]["total"]).to eq(5)
      expect(response_data["container_metrics"]["total"]).to eq(4)
    end

    it "returns only account-specific data in compliance_summary" do
      get "/api/v1/supply_chain/compliance_summary", headers: auth_headers_for(other_user), as: :json

      expect_success_response
      response_data = json_response_data

      expect(response_data["ntia_compliance"]["total_count"]).to eq(5)
    end
  end
end
