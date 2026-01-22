# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::SupplyChain::Vendors", type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:read_user) { create(:user, account: account, permissions: ["supply_chain.read"]) }
  let(:write_user) { create(:user, account: account, permissions: ["supply_chain.read", "supply_chain.write"]) }
  let(:other_user) { create(:user, account: other_account, permissions: ["supply_chain.read", "supply_chain.write"]) }

  before(:each) do
    Rails.cache.clear
  end

  describe "GET /api/v1/supply_chain/vendors" do
    let(:headers) { auth_headers_for(read_user) }

    context "with no filters" do
      before do
        create_list(:supply_chain_vendor, 3, account: account)
        create(:supply_chain_vendor, account: other_account) # Should not appear
      end

      it "returns paginated vendors for current account" do
        get "/api/v1/supply_chain/vendors", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["vendors"].length).to eq(3)
        expect(response_data["meta"]["total"]).to eq(3)
        expect(response_data["meta"]["page"]).to eq(1)
      end

      it "orders vendors by created_at descending" do
        # Create vendors with specific timestamps in the past (before the before block vendors)
        vendor1 = create(:supply_chain_vendor, account: account, name: "First Vendor", created_at: 10.days.ago)
        vendor2 = create(:supply_chain_vendor, account: account, name: "Second Vendor", created_at: 9.days.ago)
        vendor3 = create(:supply_chain_vendor, account: account, name: "Third Vendor", created_at: 8.days.ago)

        get "/api/v1/supply_chain/vendors", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        # The response should include all vendors ordered by created_at desc
        vendor_ids = response_data["vendors"].map { |v| v["id"] }
        # Verify our specific vendors are in the correct relative order
        idx1 = vendor_ids.index(vendor1.id)
        idx2 = vendor_ids.index(vendor2.id)
        idx3 = vendor_ids.index(vendor3.id)

        # vendor3 should come before vendor2, which should come before vendor1 (descending order)
        expect(idx3).to be < idx2
        expect(idx2).to be < idx1
      end
    end

    context "with pagination" do
      before do
        create_list(:supply_chain_vendor, 25, account: account)
      end

      it "respects per_page parameter" do
        get "/api/v1/supply_chain/vendors?per_page=10", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["vendors"].length).to eq(10)
        expect(response_data["meta"]["total"]).to eq(25)
        expect(response_data["meta"]["per_page"]).to eq(10)
      end

      it "respects page parameter" do
        get "/api/v1/supply_chain/vendors?page=2&per_page=10", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["vendors"].length).to eq(10)
        expect(response_data["meta"]["page"]).to eq(2)
      end

      it "defaults to 20 per page" do
        get "/api/v1/supply_chain/vendors", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["vendors"].length).to eq(20)
        expect(response_data["meta"]["per_page"]).to eq(20)
      end
    end

    context "with status filter" do
      before do
        create(:supply_chain_vendor, account: account, status: "active")
        create(:supply_chain_vendor, account: account, status: "active")
        create(:supply_chain_vendor, account: account, status: "inactive")
      end

      it "filters by status" do
        get "/api/v1/supply_chain/vendors?status=active", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["vendors"].length).to eq(2)
        expect(response_data["vendors"].all? { |v| v["status"] == "active" }).to be true
      end
    end

    context "with vendor type filter" do
      before do
        create(:supply_chain_vendor, account: account, vendor_type: "saas")
        create(:supply_chain_vendor, account: account, vendor_type: "api")
        create(:supply_chain_vendor, account: account, vendor_type: "saas")
      end

      it "filters by vendor type" do
        get "/api/v1/supply_chain/vendors?type=saas", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["vendors"].length).to eq(2)
        expect(response_data["vendors"].all? { |v| v["vendor_type"] == "saas" }).to be true
      end
    end

    context "with risk_tier filter" do
      before do
        create(:supply_chain_vendor, account: account, risk_tier: "critical")
        create(:supply_chain_vendor, account: account, risk_tier: "high")
        create(:supply_chain_vendor, account: account, risk_tier: "critical")
      end

      it "filters by risk tier" do
        get "/api/v1/supply_chain/vendors?risk_tier=critical", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["vendors"].length).to eq(2)
        expect(response_data["vendors"].all? { |v| v["risk_tier"] == "critical" }).to be true
      end
    end

    context "with combined filters" do
      before do
        create(:supply_chain_vendor, account: account, status: "active", vendor_type: "saas", risk_tier: "critical")
        create(:supply_chain_vendor, account: account, status: "active", vendor_type: "api", risk_tier: "high")
        create(:supply_chain_vendor, account: account, status: "inactive", vendor_type: "saas", risk_tier: "critical")
      end

      it "applies multiple filters" do
        get "/api/v1/supply_chain/vendors?status=active&type=saas&risk_tier=critical",
            headers: headers,
            as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["vendors"].length).to eq(1)
        vendor = response_data["vendors"].first
        expect(vendor["status"]).to eq("active")
        expect(vendor["vendor_type"]).to eq("saas")
        expect(vendor["risk_tier"]).to eq("critical")
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/vendors", as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without required permission" do
      let(:user_without_permission) { create(:user, account: account, permissions: []) }
      let(:headers) { auth_headers_for(user_without_permission) }

      it "returns forbidden error" do
        get "/api/v1/supply_chain/vendors", headers: headers, as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "GET /api/v1/supply_chain/vendors/:id" do
    let(:vendor) { create(:supply_chain_vendor, account: account) }
    let(:headers) { auth_headers_for(read_user) }

    context "with valid vendor" do
      it "returns vendor details" do
        get "/api/v1/supply_chain/vendors/#{vendor.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["vendor"]).to include(
          "id" => vendor.id,
          "name" => vendor.name,
          "slug" => vendor.slug,
          "vendor_type" => vendor.vendor_type,
          "status" => vendor.status,
          "risk_tier" => vendor.risk_tier
        )
        # risk_score may be serialized as string
        expect(response_data["vendor"]["risk_score"].to_f).to eq(vendor.risk_score.to_f)
      end

      it "includes detailed fields" do
        get "/api/v1/supply_chain/vendors/#{vendor.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["vendor"]).to have_key("description")
        expect(response_data["vendor"]).to have_key("website")
        expect(response_data["vendor"]).to have_key("primary_contact")
        expect(response_data["vendor"]).to have_key("assessment_count")
        expect(response_data["vendor"]).to have_key("metadata")
      end

      it "includes data handling flags" do
        vendor.update!(handles_pii: true, handles_phi: false, handles_pci: true)

        get "/api/v1/supply_chain/vendors/#{vendor.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["vendor"]["handles_pii"]).to be true
        expect(response_data["vendor"]["handles_phi"]).to be false
        expect(response_data["vendor"]["handles_pci"]).to be true
      end
    end

    context "with vendor from another account" do
      let(:other_vendor) { create(:supply_chain_vendor, account: other_account) }

      it "returns not found error" do
        get "/api/v1/supply_chain/vendors/#{other_vendor.id}", headers: headers, as: :json

        expect_error_response("Vendor not found", 404)
      end
    end

    context "with non-existent vendor" do
      it "returns not found error" do
        get "/api/v1/supply_chain/vendors/nonexistent-id", headers: headers, as: :json

        expect_error_response("Vendor not found", 404)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/vendors/#{vendor.id}", as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without required permission" do
      let(:user_without_permission) { create(:user, account: account, permissions: []) }
      let(:headers) { auth_headers_for(user_without_permission) }

      it "returns forbidden error" do
        get "/api/v1/supply_chain/vendors/#{vendor.id}", headers: headers, as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/vendors" do
    let(:headers) { auth_headers_for(write_user) }

    context "with valid parameters" do
      let(:valid_params) do
        {
          vendor: {
            name: "Test Vendor Corp",
            vendor_type: "saas",
            status: "active",
            description: "A test vendor description",
            website: "https://testvendor.com",
            contact_email: "john@testvendor.com",
            handles_pii: true,
            handles_phi: false,
            handles_pci: true,
            has_dpa: true,
            has_baa: false,
            contract_start_date: Date.current,
            contract_end_date: 1.year.from_now
          }
        }
      end

      it "creates a new vendor" do
        expect {
          post "/api/v1/supply_chain/vendors", params: valid_params, headers: headers, as: :json
        }.to change(SupplyChain::Vendor, :count).by(1)

        expect(response).to have_http_status(:created)
        expect_success_response
      end

      it "returns the created vendor" do
        post "/api/v1/supply_chain/vendors", params: valid_params, headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["vendor"]).to include(
          "name" => "Test Vendor Corp",
          "vendor_type" => "saas",
          "status" => "active"
        )
        expect(response_data["message"]).to eq("Vendor created successfully")
      end

      it "auto-generates slug from name" do
        post "/api/v1/supply_chain/vendors", params: valid_params, headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["vendor"]["slug"]).to eq("test-vendor-corp")
      end

      it "associates vendor with current account" do
        post "/api/v1/supply_chain/vendors", params: valid_params, headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        vendor = SupplyChain::Vendor.find(response_data["vendor"]["id"])
        expect(vendor.account_id).to eq(account.id)
      end
    end

    context "with minimal valid parameters" do
      let(:minimal_params) do
        {
          vendor: {
            name: "Minimal Vendor",
            vendor_type: "api",
            status: "active"
          }
        }
      end

      it "creates vendor with defaults" do
        expect {
          post "/api/v1/supply_chain/vendors", params: minimal_params, headers: headers, as: :json
        }.to change(SupplyChain::Vendor, :count).by(1)

        expect_success_response
      end
    end

    context "with invalid parameters" do
      it "returns validation error for missing name" do
        post "/api/v1/supply_chain/vendors",
             params: { vendor: { vendor_type: "saas", status: "active" } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
        expect(json_response["details"]["errors"]).to be_present
      end

      it "returns validation error for invalid vendor_type" do
        post "/api/v1/supply_chain/vendors",
             params: { vendor: { name: "Test", vendor_type: "invalid_type", status: "active" } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
      end

      it "returns validation error for invalid status" do
        post "/api/v1/supply_chain/vendors",
             params: { vendor: { name: "Test", vendor_type: "saas", status: "invalid_status" } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
      end

      it "returns validation error for invalid email format" do
        post "/api/v1/supply_chain/vendors",
             params: {
               vendor: {
                 name: "Test",
                 vendor_type: "saas",
                 status: "active",
                 contact_email: "invalid-email"
               }
             },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        post "/api/v1/supply_chain/vendors",
             params: { vendor: { name: "Test", vendor_type: "saas", status: "active" } },
             as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without write permission" do
      let(:headers) { auth_headers_for(read_user) }

      it "returns forbidden error" do
        post "/api/v1/supply_chain/vendors",
             params: { vendor: { name: "Test", vendor_type: "saas", status: "active" } },
             headers: headers,
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "PATCH /api/v1/supply_chain/vendors/:id" do
    let(:vendor) { create(:supply_chain_vendor, account: account, name: "Original Name") }
    let(:headers) { auth_headers_for(write_user) }

    context "with valid parameters" do
      let(:update_params) do
        {
          vendor: {
            name: "Updated Vendor Name",
            description: "Updated description",
            status: "inactive"
          }
        }
      end

      it "updates the vendor" do
        patch "/api/v1/supply_chain/vendors/#{vendor.id}",
              params: update_params,
              headers: headers,
              as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["vendor"]["name"]).to eq("Updated Vendor Name")
        expect(response_data["message"]).to eq("Vendor updated successfully")
      end

      it "persists changes to database" do
        patch "/api/v1/supply_chain/vendors/#{vendor.id}",
              params: update_params,
              headers: headers,
              as: :json

        vendor.reload
        expect(vendor.name).to eq("Updated Vendor Name")
        expect(vendor.description).to eq("Updated description")
        expect(vendor.status).to eq("inactive")
      end
    end

    context "with partial update" do
      it "updates only provided fields" do
        original_type = vendor.vendor_type

        patch "/api/v1/supply_chain/vendors/#{vendor.id}",
              params: { vendor: { description: "New description only" } },
              headers: headers,
              as: :json

        expect_success_response

        vendor.reload
        expect(vendor.description).to eq("New description only")
        expect(vendor.vendor_type).to eq(original_type)
      end
    end

    context "with invalid parameters" do
      it "returns validation error" do
        patch "/api/v1/supply_chain/vendors/#{vendor.id}",
              params: { vendor: { name: "" } },
              headers: headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
      end
    end

    context "with vendor from another account" do
      let(:other_vendor) { create(:supply_chain_vendor, account: other_account) }

      it "returns not found error" do
        patch "/api/v1/supply_chain/vendors/#{other_vendor.id}",
              params: { vendor: { name: "Hacked Name" } },
              headers: headers,
              as: :json

        expect_error_response("Vendor not found", 404)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        patch "/api/v1/supply_chain/vendors/#{vendor.id}",
              params: { vendor: { name: "No Auth" } },
              as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without write permission" do
      let(:headers) { auth_headers_for(read_user) }

      it "returns forbidden error" do
        patch "/api/v1/supply_chain/vendors/#{vendor.id}",
              params: { vendor: { name: "Unauthorized" } },
              headers: headers,
              as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "DELETE /api/v1/supply_chain/vendors/:id" do
    let!(:vendor) { create(:supply_chain_vendor, account: account) }
    let(:headers) { auth_headers_for(write_user) }

    context "with valid vendor" do
      it "deletes the vendor" do
        expect {
          delete "/api/v1/supply_chain/vendors/#{vendor.id}", headers: headers, as: :json
        }.to change(SupplyChain::Vendor, :count).by(-1)

        expect_success_response
      end

      it "returns success message" do
        delete "/api/v1/supply_chain/vendors/#{vendor.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["message"]).to eq("Vendor deleted successfully")
      end
    end

    context "with vendor from another account" do
      let!(:other_vendor) { create(:supply_chain_vendor, account: other_account) }

      it "returns not found error" do
        expect {
          delete "/api/v1/supply_chain/vendors/#{other_vendor.id}", headers: headers, as: :json
        }.not_to change(SupplyChain::Vendor, :count)

        expect_error_response("Vendor not found", 404)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        delete "/api/v1/supply_chain/vendors/#{vendor.id}", as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without write permission" do
      let(:headers) { auth_headers_for(read_user) }

      it "returns forbidden error" do
        delete "/api/v1/supply_chain/vendors/#{vendor.id}", headers: headers, as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/vendors/:id/assess" do
    let(:vendor) { create(:supply_chain_vendor, account: account) }
    let(:headers) { auth_headers_for(write_user) }

    context "with valid request" do
      it "creates a risk assessment" do
        expect {
          post "/api/v1/supply_chain/vendors/#{vendor.id}/assess", headers: headers, as: :json
        }.to change(SupplyChain::RiskAssessment, :count).by(1)

        expect_success_response
      end

      it "returns assessment details" do
        post "/api/v1/supply_chain/vendors/#{vendor.id}/assess", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["vendor_id"]).to eq(vendor.id)
        expect(response_data["assessment"]).to be_present
        expect(response_data["message"]).to eq("Risk assessment completed")
      end

      it "updates vendor risk profile" do
        post "/api/v1/supply_chain/vendors/#{vendor.id}/assess", headers: headers, as: :json

        expect_success_response

        vendor.reload
        expect(vendor.last_assessment_at).to be_present
        expect(vendor.next_assessment_due).to be_present
      end
    end

    context "with vendor from another account" do
      let(:other_vendor) { create(:supply_chain_vendor, account: other_account) }

      it "returns not found error" do
        post "/api/v1/supply_chain/vendors/#{other_vendor.id}/assess", headers: headers, as: :json

        expect_error_response("Vendor not found", 404)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        post "/api/v1/supply_chain/vendors/#{vendor.id}/assess", as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without write permission" do
      let(:headers) { auth_headers_for(read_user) }

      it "returns forbidden error" do
        post "/api/v1/supply_chain/vendors/#{vendor.id}/assess", headers: headers, as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/vendors/:id/reassess" do
    let(:vendor) { create(:supply_chain_vendor, account: account) }
    let(:headers) { auth_headers_for(write_user) }

    before do
      # Create initial assessment
      create(:supply_chain_risk_assessment, vendor: vendor, account: account)
      vendor.update!(last_assessment_at: 1.month.ago)
    end

    context "with valid request" do
      it "creates a new risk assessment" do
        expect {
          post "/api/v1/supply_chain/vendors/#{vendor.id}/reassess", headers: headers, as: :json
        }.to change(SupplyChain::RiskAssessment, :count).by(1)

        expect_success_response
      end

      it "returns assessment details" do
        post "/api/v1/supply_chain/vendors/#{vendor.id}/reassess", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["vendor_id"]).to eq(vendor.id)
        expect(response_data["assessment"]).to be_present
        expect(response_data["message"]).to eq("Periodic reassessment completed")
      end

      it "updates last assessment date" do
        old_date = vendor.last_assessment_at

        post "/api/v1/supply_chain/vendors/#{vendor.id}/reassess", headers: headers, as: :json

        expect_success_response

        vendor.reload
        expect(vendor.last_assessment_at).to be > old_date
      end
    end

    context "with vendor from another account" do
      let(:other_vendor) { create(:supply_chain_vendor, account: other_account) }

      it "returns not found error" do
        post "/api/v1/supply_chain/vendors/#{other_vendor.id}/reassess", headers: headers, as: :json

        expect_error_response("Vendor not found", 404)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        post "/api/v1/supply_chain/vendors/#{vendor.id}/reassess", as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without write permission" do
      let(:headers) { auth_headers_for(read_user) }

      it "returns forbidden error" do
        post "/api/v1/supply_chain/vendors/#{vendor.id}/reassess", headers: headers, as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "GET /api/v1/supply_chain/vendors/:id/risk_profile" do
    let(:vendor) { create(:supply_chain_vendor, account: account, handles_pii: true, handles_phi: false, handles_pci: true) }
    let(:headers) { auth_headers_for(read_user) }

    before do
      create(:supply_chain_risk_assessment, vendor: vendor, account: account, status: "completed")
    end

    context "with valid request" do
      it "returns risk profile" do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/risk_profile", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["vendor_id"]).to eq(vendor.id)
        expect(response_data["risk_tier"]).to eq(vendor.risk_tier)
        # risk_score may be serialized as string
        expect(response_data["risk_score"].to_f).to eq(vendor.risk_score.to_f)
      end

      it "includes inherent risk calculation" do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/risk_profile", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["inherent_risk"]).to be_present
      end

      it "includes latest assessment" do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/risk_profile", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["latest_assessment"]).to be_present
      end

      it "includes data handling information" do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/risk_profile", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["data_handling"]).to include(
          "handles_pii" => true,
          "handles_phi" => false,
          "handles_pci" => true
        )
      end

      it "includes certifications" do
        vendor.update!(certifications: [{ name: "SOC 2 Type II", verified: true }])

        get "/api/v1/supply_chain/vendors/#{vendor.id}/risk_profile", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["certifications"]).to be_an(Array)
      end
    end

    context "without completed assessment" do
      let(:vendor_no_assessment) { create(:supply_chain_vendor, account: account) }

      it "returns profile with null latest_assessment" do
        get "/api/v1/supply_chain/vendors/#{vendor_no_assessment.id}/risk_profile", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["latest_assessment"]).to be_nil
      end
    end

    context "with vendor from another account" do
      let(:other_vendor) { create(:supply_chain_vendor, account: other_account) }

      it "returns not found error" do
        get "/api/v1/supply_chain/vendors/#{other_vendor.id}/risk_profile", headers: headers, as: :json

        expect_error_response("Vendor not found", 404)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/risk_profile", as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without read permission" do
      let(:user_without_permission) { create(:user, account: account, permissions: []) }
      let(:headers) { auth_headers_for(user_without_permission) }

      it "returns forbidden error" do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/risk_profile", headers: headers, as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "GET /api/v1/supply_chain/vendors/:id/monitoring_events" do
    let(:vendor) { create(:supply_chain_vendor, account: account) }
    let(:headers) { auth_headers_for(read_user) }

    before do
      create_list(:supply_chain_vendor_monitoring_event, 5, vendor: vendor, account: account)
    end

    context "with no filters" do
      it "returns monitoring events" do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/monitoring_events", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["events"]).to be_an(Array)
        expect(response_data["events"].length).to eq(5)
      end

      it "includes metadata with counts" do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/monitoring_events", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["meta"]).to include(
          "total" => 5,
          "page" => 1
        )
        expect(response_data["meta"]).to have_key("unacknowledged_count")
      end
    end

    context "with type filter" do
      before do
        create(:supply_chain_vendor_monitoring_event,
               vendor: vendor,
               account: account,
               event_type: "security_incident")
      end

      it "filters by event type" do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/monitoring_events?type=security_incident",
            headers: headers,
            as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["events"].all? { |e| e["event_type"] == "security_incident" }).to be true
      end
    end

    context "with severity filter" do
      before do
        create(:supply_chain_vendor_monitoring_event,
               vendor: vendor,
               account: account,
               severity: "critical")
      end

      it "filters by severity" do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/monitoring_events?severity=critical",
            headers: headers,
            as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["events"].all? { |e| e["severity"] == "critical" }).to be true
      end
    end

    context "with unacknowledged filter" do
      before do
        vendor.monitoring_events.first.update!(is_acknowledged: true)
      end

      it "filters for unacknowledged events" do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/monitoring_events?unacknowledged=true",
            headers: headers,
            as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["events"].all? { |e| e["acknowledged"] == false }).to be true
      end
    end

    context "with pagination" do
      before do
        create_list(:supply_chain_vendor_monitoring_event, 20, vendor: vendor, account: account)
      end

      it "respects per_page parameter" do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/monitoring_events?per_page=10",
            headers: headers,
            as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["events"].length).to eq(10)
      end
    end

    context "with vendor from another account" do
      let(:other_vendor) { create(:supply_chain_vendor, account: other_account) }

      it "returns not found error" do
        get "/api/v1/supply_chain/vendors/#{other_vendor.id}/monitoring_events", headers: headers, as: :json

        expect_error_response("Vendor not found", 404)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/monitoring_events", as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without read permission" do
      let(:user_without_permission) { create(:user, account: account, permissions: []) }
      let(:headers) { auth_headers_for(user_without_permission) }

      it "returns forbidden error" do
        get "/api/v1/supply_chain/vendors/#{vendor.id}/monitoring_events", headers: headers, as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "GET /api/v1/supply_chain/vendors/statistics" do
    let(:headers) { auth_headers_for(read_user) }

    before do
      create(:supply_chain_vendor, account: account, status: "active", vendor_type: "saas", risk_tier: "critical")
      create(:supply_chain_vendor, account: account, status: "active", vendor_type: "api", risk_tier: "high")
      create(:supply_chain_vendor, account: account, status: "inactive", vendor_type: "saas", risk_tier: "low")
      create(:supply_chain_vendor, account: other_account) # Should not be counted
    end

    context "with valid request" do
      it "returns vendor statistics" do
        get "/api/v1/supply_chain/vendors/statistics", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["total"]).to eq(3)
      end

      it "includes breakdown by status" do
        get "/api/v1/supply_chain/vendors/statistics", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["by_status"]).to be_a(Hash)
        expect(response_data["by_status"]["active"]).to eq(2)
        expect(response_data["by_status"]["inactive"]).to eq(1)
      end

      it "includes breakdown by type" do
        get "/api/v1/supply_chain/vendors/statistics", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["by_type"]).to be_a(Hash)
        expect(response_data["by_type"]["saas"]).to eq(2)
        expect(response_data["by_type"]["api"]).to eq(1)
      end

      it "includes breakdown by risk tier" do
        get "/api/v1/supply_chain/vendors/statistics", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["by_risk_tier"]).to be_a(Hash)
        expect(response_data["by_risk_tier"]["critical"]).to eq(1)
        expect(response_data["by_risk_tier"]["high"]).to eq(1)
        expect(response_data["by_risk_tier"]["low"]).to eq(1)
      end

      it "includes average risk score" do
        get "/api/v1/supply_chain/vendors/statistics", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        # Average risk score can be a string or numeric depending on serialization
        expect(response_data["average_risk_score"]).to be_present
      end

      it "includes contract expiry count" do
        vendor = account.supply_chain_vendors.first
        vendor.update!(contract_end_date: 30.days.from_now)

        get "/api/v1/supply_chain/vendors/statistics", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["with_expiring_contracts"]).to eq(1)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/vendors/statistics", as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without read permission" do
      let(:user_without_permission) { create(:user, account: account, permissions: []) }
      let(:headers) { auth_headers_for(user_without_permission) }

      it "returns forbidden error" do
        get "/api/v1/supply_chain/vendors/statistics", headers: headers, as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "GET /api/v1/supply_chain/vendors/risk_dashboard" do
    let(:headers) { auth_headers_for(read_user) }

    before do
      create(:supply_chain_vendor, account: account, status: "active", risk_tier: "critical")
      create(:supply_chain_vendor, account: account, status: "active", risk_tier: "high")
      create(:supply_chain_vendor, account: account, status: "active", risk_tier: "medium")
      create(:supply_chain_vendor, account: account, status: "inactive", risk_tier: "critical")
      create(:supply_chain_vendor, account: other_account, status: "active", risk_tier: "critical") # Should not appear
    end

    context "with valid request" do
      it "returns risk dashboard data" do
        get "/api/v1/supply_chain/vendors/risk_dashboard", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["summary"]).to be_present
      end

      it "includes summary statistics" do
        get "/api/v1/supply_chain/vendors/risk_dashboard", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        summary = response_data["summary"]
        expect(summary["total_active"]).to eq(3)
        expect(summary["critical_count"]).to eq(1)
        expect(summary["high_risk_count"]).to eq(1)
        expect(summary).to have_key("assessments_overdue")
      end

      it "includes critical vendors list" do
        get "/api/v1/supply_chain/vendors/risk_dashboard", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["critical_vendors"]).to be_an(Array)
        expect(response_data["critical_vendors"].length).to eq(1)
      end

      it "includes recent events" do
        vendor = account.supply_chain_vendors.first
        create_list(:supply_chain_vendor_monitoring_event, 3, vendor: vendor, account: account)

        get "/api/v1/supply_chain/vendors/risk_dashboard", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["recent_events"]).to be_an(Array)
      end

      it "includes expiring contracts" do
        vendor = account.supply_chain_vendors.active.first
        vendor.update!(contract_end_date: 30.days.from_now)

        get "/api/v1/supply_chain/vendors/risk_dashboard", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["expiring_contracts"]).to be_an(Array)
        expect(response_data["expiring_contracts"].length).to eq(1)
      end

      it "limits critical vendors to 10" do
        create_list(:supply_chain_vendor, 15, account: account, status: "active", risk_tier: "critical")

        get "/api/v1/supply_chain/vendors/risk_dashboard", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["critical_vendors"].length).to eq(10)
      end

      it "limits recent events to 10" do
        vendor = account.supply_chain_vendors.first
        create_list(:supply_chain_vendor_monitoring_event, 15, vendor: vendor, account: account)

        get "/api/v1/supply_chain/vendors/risk_dashboard", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["recent_events"].length).to eq(10)
      end
    end

    context "with no active vendors" do
      before do
        account.supply_chain_vendors.update_all(status: "inactive")
      end

      it "returns empty lists" do
        get "/api/v1/supply_chain/vendors/risk_dashboard", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["summary"]["total_active"]).to eq(0)
        expect(response_data["critical_vendors"]).to eq([])
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/vendors/risk_dashboard", as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without read permission" do
      let(:user_without_permission) { create(:user, account: account, permissions: []) }
      let(:headers) { auth_headers_for(user_without_permission) }

      it "returns forbidden error" do
        get "/api/v1/supply_chain/vendors/risk_dashboard", headers: headers, as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "account isolation" do
    let(:vendor) { create(:supply_chain_vendor, account: account) }
    let!(:other_vendor) { create(:supply_chain_vendor, account: other_account) }
    let(:headers) { auth_headers_for(write_user) }

    it "prevents access to vendors from other accounts in show" do
      get "/api/v1/supply_chain/vendors/#{other_vendor.id}", headers: headers, as: :json

      expect_error_response("Vendor not found", 404)
    end

    it "prevents access to vendors from other accounts in update" do
      patch "/api/v1/supply_chain/vendors/#{other_vendor.id}",
            params: { vendor: { name: "Hacked" } },
            headers: headers,
            as: :json

      expect_error_response("Vendor not found", 404)
    end

    it "prevents access to vendors from other accounts in delete" do
      expect {
        delete "/api/v1/supply_chain/vendors/#{other_vendor.id}", headers: headers, as: :json
      }.not_to change(SupplyChain::Vendor, :count)

      expect_error_response("Vendor not found", 404)
    end

    it "only shows vendors from current account in index" do
      create_list(:supply_chain_vendor, 3, account: account)
      create_list(:supply_chain_vendor, 3, account: other_account)

      get "/api/v1/supply_chain/vendors", headers: headers, as: :json

      expect_success_response
      response_data = json_response["data"]

      expect(response_data["vendors"].length).to eq(3)
    end
  end
end
