# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::SupplyChain::QuestionnaireResponses", type: :request do
  let!(:account) { create(:account) }
  let!(:other_account) { create(:account) }
  let!(:read_user) { create(:user, account: account, permissions: ["supply_chain.read"]) }
  let!(:write_user) { create(:user, account: account, permissions: ["supply_chain.read", "supply_chain.write"]) }
  let!(:other_user) { create(:user, account: other_account, permissions: ["supply_chain.read", "supply_chain.write"]) }

  before(:each) do
    Rails.cache.clear
  end

  describe "GET /api/v1/supply_chain/questionnaire_responses" do
    let(:vendor) { create(:supply_chain_vendor, account: account) }
    let(:template) { create(:supply_chain_questionnaire_template) }
    let(:headers) { auth_headers_for(read_user) }

    context "with no filters" do
      before do
        create_list(:supply_chain_questionnaire_response, 3, vendor: vendor, template: template, account: account)
        other_vendor = create(:supply_chain_vendor, account: other_account)
        create(:supply_chain_questionnaire_response, vendor: other_vendor, template: template, account: other_account)
      end

      it "returns paginated questionnaire responses for current account" do
        get "/api/v1/supply_chain/questionnaire_responses", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["questionnaire_responses"].length).to eq(3)
        expect(json_response["meta"]["total_count"]).to eq(3)
        expect(json_response["meta"]["current_page"]).to eq(1)
      end

      it "orders responses by created_at descending" do
        # Create responses with specific timestamps
        response1 = create(:supply_chain_questionnaire_response, vendor: vendor, template: template, account: account, created_at: 3.days.ago)
        response2 = create(:supply_chain_questionnaire_response, vendor: vendor, template: template, account: account, created_at: 2.days.ago)
        response3 = create(:supply_chain_questionnaire_response, vendor: vendor, template: template, account: account, created_at: 1.day.ago)

        get "/api/v1/supply_chain/questionnaire_responses", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        response_ids = response_data["questionnaire_responses"].map { |r| r["id"] }
        # Verify these 3 responses are in the correct order relative to each other
        # (other responses from before block may also be present)
        response1_index = response_ids.index(response1.id)
        response2_index = response_ids.index(response2.id)
        response3_index = response_ids.index(response3.id)

        expect(response3_index).to be < response2_index
        expect(response2_index).to be < response1_index
      end
    end

    context "with pagination" do
      before do
        create_list(:supply_chain_questionnaire_response, 25, vendor: vendor, template: template, account: account)
      end

      it "respects per_page parameter" do
        get "/api/v1/supply_chain/questionnaire_responses?per_page=10", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["questionnaire_responses"].length).to eq(10)
        expect(json_response["meta"]["total_count"]).to eq(25)
        expect(json_response["meta"]["per_page"]).to eq(10)
      end

      it "respects page parameter" do
        get "/api/v1/supply_chain/questionnaire_responses?page=2&per_page=10", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["questionnaire_responses"].length).to eq(10)
        expect(json_response["meta"]["current_page"]).to eq(2)
      end

      it "defaults to 20 per page" do
        get "/api/v1/supply_chain/questionnaire_responses", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["questionnaire_responses"].length).to eq(20)
        expect(json_response["meta"]["per_page"]).to eq(20)
      end
    end

    context "with status filter" do
      before do
        create(:supply_chain_questionnaire_response, vendor: vendor, template: template, account: account, status: "pending")
        create(:supply_chain_questionnaire_response, vendor: vendor, template: template, account: account, status: "submitted")
        create(:supply_chain_questionnaire_response, vendor: vendor, template: template, account: account, status: "submitted")
      end

      it "filters by status" do
        get "/api/v1/supply_chain/questionnaire_responses?status=submitted", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["questionnaire_responses"].length).to eq(2)
        expect(response_data["questionnaire_responses"].all? { |r| r["status"] == "submitted" }).to be true
      end
    end

    context "with vendor_id filter" do
      let(:vendor2) { create(:supply_chain_vendor, account: account) }

      before do
        create_list(:supply_chain_questionnaire_response, 2, vendor: vendor, template: template, account: account)
        create(:supply_chain_questionnaire_response, vendor: vendor2, template: template, account: account)
      end

      it "filters by vendor_id" do
        get "/api/v1/supply_chain/questionnaire_responses?vendor_id=#{vendor.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["questionnaire_responses"].length).to eq(2)
        expect(response_data["questionnaire_responses"].all? { |r| r["vendor_id"] == vendor.id }).to be true
      end
    end

    context "with combined filters" do
      let(:vendor2) { create(:supply_chain_vendor, account: account) }

      before do
        create(:supply_chain_questionnaire_response, vendor: vendor, template: template, account: account, status: "pending")
        create(:supply_chain_questionnaire_response, vendor: vendor, template: template, account: account, status: "submitted")
        create(:supply_chain_questionnaire_response, vendor: vendor2, template: template, account: account, status: "submitted")
      end

      it "applies multiple filters" do
        get "/api/v1/supply_chain/questionnaire_responses?status=submitted&vendor_id=#{vendor.id}",
            headers: headers,
            as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["questionnaire_responses"].length).to eq(1)
        response = response_data["questionnaire_responses"].first
        expect(response["status"]).to eq("submitted")
        expect(response["vendor_id"]).to eq(vendor.id)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/questionnaire_responses", as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without required permission" do
      let(:user_without_permission) { create(:user, account: account, permissions: []) }
      let(:headers) { auth_headers_for(user_without_permission) }

      it "returns forbidden error" do
        get "/api/v1/supply_chain/questionnaire_responses", headers: headers, as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "GET /api/v1/supply_chain/questionnaire_responses/:id" do
    let(:vendor) { create(:supply_chain_vendor, account: account) }
    let(:template) { create(:supply_chain_questionnaire_template) }
    let(:questionnaire_response) { create(:supply_chain_questionnaire_response, vendor: vendor, template: template, account: account) }
    let(:headers) { auth_headers_for(read_user) }

    context "with valid questionnaire response" do
      it "returns questionnaire response details" do
        get "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["questionnaire_response"]).to include(
          "id" => questionnaire_response.id,
          "vendor_id" => vendor.id,
          "template_id" => template.id,
          "status" => questionnaire_response.status
        )
      end

      it "includes detailed fields" do
        get "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["questionnaire_response"]).to have_key("responses")
        expect(response_data["questionnaire_response"]).to have_key("section_scores")
        expect(response_data["questionnaire_response"]).to have_key("reviewer_notes")
        expect(response_data["questionnaire_response"]).to have_key("feedback")
      end
    end

    context "with questionnaire response from another account" do
      let(:other_vendor) { create(:supply_chain_vendor, account: other_account) }
      let(:other_response) { create(:supply_chain_questionnaire_response, vendor: other_vendor, template: template, account: other_account) }

      it "returns not found error" do
        get "/api/v1/supply_chain/questionnaire_responses/#{other_response.id}", headers: headers, as: :json

        expect_error_response("Questionnaire response not found", 404)
      end
    end

    context "with non-existent questionnaire response" do
      it "returns not found error" do
        get "/api/v1/supply_chain/questionnaire_responses/nonexistent-id", headers: headers, as: :json

        expect_error_response("Questionnaire response not found", 404)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}", as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without required permission" do
      let(:user_without_permission) { create(:user, account: account, permissions: []) }
      let(:headers) { auth_headers_for(user_without_permission) }

      it "returns forbidden error" do
        get "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}", headers: headers, as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "GET /api/v1/supply_chain/questionnaire_responses/token/:token" do
    let(:vendor) { create(:supply_chain_vendor, account: account) }
    let(:template) { create(:supply_chain_questionnaire_template) }
    let(:questionnaire_response) { create(:supply_chain_questionnaire_response, vendor: vendor, template: template, account: account) }

    context "with valid token" do
      it "returns questionnaire response without authentication" do
        get "/api/v1/supply_chain/questionnaire_responses/token/#{questionnaire_response.access_token}", as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["questionnaire_response"]).to include(
          "id" => questionnaire_response.id,
          "status" => questionnaire_response.status
        )
        expect(response_data["template"]).to be_present
      end

      it "includes template information" do
        get "/api/v1/supply_chain/questionnaire_responses/token/#{questionnaire_response.access_token}", as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["template"]).to include(
          "name" => template.name,
          "description" => template.description,
          "sections" => template.sections,
          "questions" => template.questions
        )
      end

      it "includes vendor response information" do
        get "/api/v1/supply_chain/questionnaire_responses/token/#{questionnaire_response.access_token}", as: :json

        expect_success_response
        response_data = json_response["data"]

        vendor_response = response_data["questionnaire_response"]
        expect(vendor_response).to have_key("template_name")
        expect(vendor_response).to have_key("due_at")
        expect(vendor_response).to have_key("responses")
        expect(vendor_response).to have_key("feedback")
      end
    end

    context "with expired token" do
      let(:expired_response) { create(:supply_chain_questionnaire_response, :expired, vendor: vendor, template: template, account: account) }

      it "returns gone error" do
        get "/api/v1/supply_chain/questionnaire_responses/token/#{expired_response.access_token}", as: :json

        expect(response).to have_http_status(:gone)
        expect(json_response["success"]).to be false
        expect(json_response["error"]).to eq("This questionnaire link has expired")
      end
    end

    context "with invalid token" do
      it "returns not found error" do
        get "/api/v1/supply_chain/questionnaire_responses/token/invalid-token", as: :json

        expect_error_response("Invalid questionnaire link", 404)
      end
    end
  end

  describe "POST /api/v1/supply_chain/questionnaire_responses/token/:token/submit" do
    let(:vendor) { create(:supply_chain_vendor, account: account) }
    let(:template) do
      create(:supply_chain_questionnaire_template,
             sections: [{ id: "section1", name: "General", weight: 1.0, order: 0 }],
             questions: [{ id: "q1", section_id: "section1", text: "Question?", type: "yes_no", required: true }])
    end
    let(:questionnaire_response) { create(:supply_chain_questionnaire_response, vendor: vendor, template: template, account: account) }
    let(:submit_params) do
      {
        responses: {
          "q1" => { answer: "yes", answered_at: Time.current.iso8601 }
        }
      }
    end

    context "with valid submission" do
      before do
        allow_any_instance_of(SupplyChain::QuestionnaireResponse).to receive(:calculate_scores!)
        allow(SupplyChainChannel).to receive(:broadcast_questionnaire_submitted)
      end

      it "submits questionnaire without authentication" do
        post "/api/v1/supply_chain/questionnaire_responses/token/#{questionnaire_response.access_token}/submit",
             params: submit_params,
             as: :json

        expect_success_response
        # Message is not included in response when data is present (per render_success behavior)
        expect(json_response["data"]).to have_key("overall_score")
      end

      it "updates status to submitted" do
        post "/api/v1/supply_chain/questionnaire_responses/token/#{questionnaire_response.access_token}/submit",
             params: submit_params,
             as: :json

        expect_success_response

        questionnaire_response.reload
        expect(questionnaire_response.status).to eq("submitted")
        expect(questionnaire_response.submitted_at).to be_present
      end

      it "calculates scores" do
        expect_any_instance_of(SupplyChain::QuestionnaireResponse).to receive(:calculate_scores!)

        post "/api/v1/supply_chain/questionnaire_responses/token/#{questionnaire_response.access_token}/submit",
             params: submit_params,
             as: :json

        expect_success_response
      end

      it "returns overall score" do
        allow_any_instance_of(SupplyChain::QuestionnaireResponse).to receive(:calculate_scores!) do |response|
          response.overall_score = 85.5
        end

        post "/api/v1/supply_chain/questionnaire_responses/token/#{questionnaire_response.access_token}/submit",
             params: submit_params,
             as: :json

        expect_success_response
        response_data = json_response["data"]

        # JSON may serialize as string, so compare as float
        expect(response_data["overall_score"].to_f).to eq(85.5)
      end

      it "broadcasts submission notification" do
        expect(SupplyChainChannel).to receive(:broadcast_questionnaire_submitted).with(kind_of(SupplyChain::QuestionnaireResponse))

        post "/api/v1/supply_chain/questionnaire_responses/token/#{questionnaire_response.access_token}/submit",
             params: submit_params,
             as: :json
      end
    end

    context "with already submitted questionnaire" do
      let(:submitted_response) { create(:supply_chain_questionnaire_response, :submitted, vendor: vendor, template: template, account: account) }

      it "returns unprocessable entity error" do
        post "/api/v1/supply_chain/questionnaire_responses/token/#{submitted_response.access_token}/submit",
             params: submit_params,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
        expect(json_response["error"]).to eq("Questionnaire already submitted")
      end
    end

    context "with expired token" do
      let(:expired_response) { create(:supply_chain_questionnaire_response, :expired, vendor: vendor, template: template, account: account) }

      it "returns gone error" do
        post "/api/v1/supply_chain/questionnaire_responses/token/#{expired_response.access_token}/submit",
             params: submit_params,
             as: :json

        expect(response).to have_http_status(:gone)
        expect(json_response["success"]).to be false
        expect(json_response["error"]).to eq("This questionnaire link has expired")
      end
    end

    context "with invalid token" do
      it "returns not found error" do
        post "/api/v1/supply_chain/questionnaire_responses/token/invalid-token/submit",
             params: submit_params,
             as: :json

        expect_error_response("Invalid questionnaire link", 404)
      end
    end

    context "with validation errors" do
      let(:mock_errors) { instance_double(ActiveModel::Errors, full_messages: ["Validation error"], clear: nil, empty?: false, any?: true) }

      it "returns unprocessable entity with error message" do
        # Create response BEFORE setting up the mock
        response_record = questionnaire_response

        allow_any_instance_of(SupplyChain::QuestionnaireResponse).to receive(:save).and_return(false)
        allow_any_instance_of(SupplyChain::QuestionnaireResponse).to receive(:errors).and_return(mock_errors)

        post "/api/v1/supply_chain/questionnaire_responses/token/#{response_record.access_token}/submit",
             params: submit_params,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
        expect(json_response["error"]).to eq("Validation error")
      end
    end
  end

  describe "PATCH /api/v1/supply_chain/questionnaire_responses/:id" do
    let(:vendor) { create(:supply_chain_vendor, account: account) }
    let(:template) { create(:supply_chain_questionnaire_template) }
    let(:questionnaire_response) { create(:supply_chain_questionnaire_response, vendor: vendor, template: template, account: account) }
    let(:headers) { auth_headers_for(write_user) }

    context "with valid parameters" do
      let(:update_params) do
        {
          questionnaire_response: {
            review_notes: "Updated notes",
            metadata: { key: "value" }
          }
        }
      end

      it "updates the questionnaire response" do
        patch "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}",
              params: update_params,
              headers: headers,
              as: :json

        expect_success_response
        response_data = json_response["data"]

        expect(response_data["questionnaire_response"]).to be_present
      end
    end

    context "with invalid parameters" do
      let(:mock_errors) { instance_double(ActiveModel::Errors, full_messages: ["Update failed"], clear: nil, empty?: false, any?: true) }

      it "returns unprocessable entity error" do
        # Create response BEFORE setting up the mock
        response_record = questionnaire_response

        allow_any_instance_of(SupplyChain::QuestionnaireResponse).to receive(:update).and_return(false)
        allow_any_instance_of(SupplyChain::QuestionnaireResponse).to receive(:errors).and_return(mock_errors)

        patch "/api/v1/supply_chain/questionnaire_responses/#{response_record.id}",
              params: { questionnaire_response: { review_notes: "" } },
              headers: headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
      end
    end

    context "with questionnaire response from another account" do
      let(:other_vendor) { create(:supply_chain_vendor, account: other_account) }
      let(:other_response) { create(:supply_chain_questionnaire_response, vendor: other_vendor, template: template, account: other_account) }

      it "returns not found error" do
        patch "/api/v1/supply_chain/questionnaire_responses/#{other_response.id}",
              params: { questionnaire_response: { review_notes: "Hacked" } },
              headers: headers,
              as: :json

        expect_error_response("Questionnaire response not found", 404)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        patch "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}",
              params: { questionnaire_response: { review_notes: "No auth" } },
              as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without write permission" do
      let(:headers) { auth_headers_for(read_user) }

      it "returns forbidden error" do
        patch "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}",
              params: { questionnaire_response: { review_notes: "Unauthorized" } },
              headers: headers,
              as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/questionnaire_responses/:id/approve" do
    let(:vendor) { create(:supply_chain_vendor, account: account) }
    let(:template) { create(:supply_chain_questionnaire_template) }
    let(:questionnaire_response) { create(:supply_chain_questionnaire_response, :submitted, vendor: vendor, template: template, account: account) }
    let(:headers) { auth_headers_for(write_user) }

    context "with valid request" do
      before do
        allow_any_instance_of(SupplyChain::QuestionnaireResponse).to receive(:approve!)
        allow_any_instance_of(SupplyChain::Vendor).to receive(:update_risk_from_questionnaire)
      end

      it "approves the questionnaire response" do
        expect_any_instance_of(SupplyChain::QuestionnaireResponse).to receive(:approve!).with(
          approved_by: write_user,
          notes: nil
        )

        post "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}/approve",
             headers: headers,
             as: :json

        expect_success_response
      end

      it "approves with notes" do
        expect_any_instance_of(SupplyChain::QuestionnaireResponse).to receive(:approve!).with(
          approved_by: write_user,
          notes: "Looks good"
        )

        post "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}/approve",
             params: { notes: "Looks good" },
             headers: headers,
             as: :json

        expect_success_response
      end

      it "updates vendor risk assessment" do
        expect_any_instance_of(SupplyChain::Vendor).to receive(:update_risk_from_questionnaire).with(
          kind_of(SupplyChain::QuestionnaireResponse)
        )

        post "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}/approve",
             headers: headers,
             as: :json

        expect_success_response
      end

      it "returns success with questionnaire response" do
        post "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}/approve",
             headers: headers,
             as: :json

        expect_success_response
        response_data = json_response["data"]

        # Message is not included when data is present (per render_success behavior)
        expect(response_data["questionnaire_response"]).to be_present
      end
    end

    context "when approval fails" do
      before do
        allow_any_instance_of(SupplyChain::QuestionnaireResponse).to receive(:approve!).and_raise(StandardError, "Cannot approve")
      end

      it "returns unprocessable entity error" do
        post "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}/approve",
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
        expect(json_response["error"]).to eq("Failed to approve: Cannot approve")
      end
    end

    context "with questionnaire response from another account" do
      let(:other_vendor) { create(:supply_chain_vendor, account: other_account) }
      let(:other_response) { create(:supply_chain_questionnaire_response, :submitted, vendor: other_vendor, template: template, account: other_account) }

      it "returns not found error" do
        post "/api/v1/supply_chain/questionnaire_responses/#{other_response.id}/approve",
             headers: headers,
             as: :json

        expect_error_response("Questionnaire response not found", 404)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        post "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}/approve",
             as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without write permission" do
      let(:headers) { auth_headers_for(read_user) }

      it "returns forbidden error" do
        post "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}/approve",
             headers: headers,
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/questionnaire_responses/:id/reject" do
    let(:vendor) { create(:supply_chain_vendor, account: account) }
    let(:template) { create(:supply_chain_questionnaire_template) }
    let(:questionnaire_response) { create(:supply_chain_questionnaire_response, :submitted, vendor: vendor, template: template, account: account) }
    let(:headers) { auth_headers_for(write_user) }

    context "with valid request" do
      before do
        allow_any_instance_of(SupplyChain::QuestionnaireResponse).to receive(:reject!)
      end

      it "rejects the questionnaire response" do
        expect_any_instance_of(SupplyChain::QuestionnaireResponse).to receive(:reject!).with(
          rejected_by: write_user,
          reason: "Incomplete answers"
        )

        post "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}/reject",
             params: { reason: "Incomplete answers" },
             headers: headers,
             as: :json

        expect_success_response
      end

      it "returns success with questionnaire response" do
        post "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}/reject",
             params: { reason: "Incomplete answers" },
             headers: headers,
             as: :json

        expect_success_response
        response_data = json_response["data"]

        # Message is not included when data is present (per render_success behavior)
        expect(response_data["questionnaire_response"]).to be_present
      end
    end

    context "without reason" do
      it "returns unprocessable entity error" do
        post "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}/reject",
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
        expect(json_response["error"]).to eq("Rejection reason is required")
      end

      it "returns error with blank reason" do
        post "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}/reject",
             params: { reason: "" },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
        expect(json_response["error"]).to eq("Rejection reason is required")
      end
    end

    context "when rejection fails" do
      before do
        allow_any_instance_of(SupplyChain::QuestionnaireResponse).to receive(:reject!).and_raise(StandardError, "Cannot reject")
      end

      it "returns unprocessable entity error" do
        post "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}/reject",
             params: { reason: "Test reason" },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
        expect(json_response["error"]).to eq("Failed to reject: Cannot reject")
      end
    end

    context "with questionnaire response from another account" do
      let(:other_vendor) { create(:supply_chain_vendor, account: other_account) }
      let(:other_response) { create(:supply_chain_questionnaire_response, :submitted, vendor: other_vendor, template: template, account: other_account) }

      it "returns not found error" do
        post "/api/v1/supply_chain/questionnaire_responses/#{other_response.id}/reject",
             params: { reason: "Test" },
             headers: headers,
             as: :json

        expect_error_response("Questionnaire response not found", 404)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        post "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}/reject",
             params: { reason: "Test" },
             as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without write permission" do
      let(:headers) { auth_headers_for(read_user) }

      it "returns forbidden error" do
        post "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}/reject",
             params: { reason: "Test" },
             headers: headers,
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/questionnaire_responses/:id/request_changes" do
    let(:vendor) { create(:supply_chain_vendor, account: account) }
    let(:template) { create(:supply_chain_questionnaire_template) }
    let(:questionnaire_response) { create(:supply_chain_questionnaire_response, :submitted, vendor: vendor, template: template, account: account) }
    let(:headers) { auth_headers_for(write_user) }

    context "with valid request" do
      before do
        allow_any_instance_of(SupplyChain::QuestionnaireResponse).to receive(:request_changes!)
      end

      it "requests changes to the questionnaire response" do
        expect_any_instance_of(SupplyChain::QuestionnaireResponse).to receive(:request_changes!).with(
          requested_by: write_user,
          feedback: "Please provide more details on question 3"
        )

        post "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}/request_changes",
             params: { feedback: "Please provide more details on question 3" },
             headers: headers,
             as: :json

        expect_success_response
      end

      it "returns success with questionnaire response" do
        post "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}/request_changes",
             params: { feedback: "Please provide more details" },
             headers: headers,
             as: :json

        expect_success_response
        response_data = json_response["data"]

        # Message is not included when data is present (per render_success behavior)
        expect(response_data["questionnaire_response"]).to be_present
      end
    end

    context "without feedback" do
      it "returns unprocessable entity error" do
        post "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}/request_changes",
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
        expect(json_response["error"]).to eq("Feedback is required")
      end

      it "returns error with blank feedback" do
        post "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}/request_changes",
             params: { feedback: "" },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
        expect(json_response["error"]).to eq("Feedback is required")
      end
    end

    context "when request_changes fails" do
      before do
        allow_any_instance_of(SupplyChain::QuestionnaireResponse).to receive(:request_changes!).and_raise(StandardError, "Cannot request changes")
      end

      it "returns unprocessable entity error" do
        post "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}/request_changes",
             params: { feedback: "Test feedback" },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
        expect(json_response["error"]).to eq("Failed to request changes: Cannot request changes")
      end
    end

    context "with questionnaire response from another account" do
      let(:other_vendor) { create(:supply_chain_vendor, account: other_account) }
      let(:other_response) { create(:supply_chain_questionnaire_response, :submitted, vendor: other_vendor, template: template, account: other_account) }

      it "returns not found error" do
        post "/api/v1/supply_chain/questionnaire_responses/#{other_response.id}/request_changes",
             params: { feedback: "Test" },
             headers: headers,
             as: :json

        expect_error_response("Questionnaire response not found", 404)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        post "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}/request_changes",
             params: { feedback: "Test" },
             as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without write permission" do
      let(:headers) { auth_headers_for(read_user) }

      it "returns forbidden error" do
        post "/api/v1/supply_chain/questionnaire_responses/#{questionnaire_response.id}/request_changes",
             params: { feedback: "Test" },
             headers: headers,
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "account isolation" do
    let(:vendor) { create(:supply_chain_vendor, account: account) }
    let(:other_vendor) { create(:supply_chain_vendor, account: other_account) }
    let(:template) { create(:supply_chain_questionnaire_template) }
    let(:questionnaire_response) { create(:supply_chain_questionnaire_response, vendor: vendor, template: template, account: account) }
    let(:other_response) { create(:supply_chain_questionnaire_response, vendor: other_vendor, template: template, account: other_account) }
    let(:headers) { auth_headers_for(write_user) }

    it "prevents access to questionnaire responses from other accounts in show" do
      get "/api/v1/supply_chain/questionnaire_responses/#{other_response.id}", headers: headers, as: :json

      expect_error_response("Questionnaire response not found", 404)
    end

    it "prevents access to questionnaire responses from other accounts in update" do
      patch "/api/v1/supply_chain/questionnaire_responses/#{other_response.id}",
            params: { questionnaire_response: { notes: "Hacked" } },
            headers: headers,
            as: :json

      expect_error_response("Questionnaire response not found", 404)
    end

    it "prevents access to questionnaire responses from other accounts in approve" do
      post "/api/v1/supply_chain/questionnaire_responses/#{other_response.id}/approve",
           headers: headers,
           as: :json

      expect_error_response("Questionnaire response not found", 404)
    end

    it "prevents access to questionnaire responses from other accounts in reject" do
      post "/api/v1/supply_chain/questionnaire_responses/#{other_response.id}/reject",
           params: { reason: "Test" },
           headers: headers,
           as: :json

      expect_error_response("Questionnaire response not found", 404)
    end

    it "prevents access to questionnaire responses from other accounts in request_changes" do
      post "/api/v1/supply_chain/questionnaire_responses/#{other_response.id}/request_changes",
           params: { feedback: "Test" },
           headers: headers,
           as: :json

      expect_error_response("Questionnaire response not found", 404)
    end

    it "only shows questionnaire responses from current account in index" do
      create_list(:supply_chain_questionnaire_response, 3, vendor: vendor, template: template, account: account)
      create_list(:supply_chain_questionnaire_response, 3, vendor: other_vendor, template: template, account: other_account)

      get "/api/v1/supply_chain/questionnaire_responses", headers: headers, as: :json

      expect_success_response
      response_data = json_response["data"]

      expect(response_data["questionnaire_responses"].length).to eq(3)
      # Verify all responses belong to the current account via vendor relationship
      response_data["questionnaire_responses"].each do |response|
        found_response = SupplyChain::QuestionnaireResponse.find(response["id"])
        expect(found_response.vendor.account_id).to eq(account.id)
      end
    end
  end
end
