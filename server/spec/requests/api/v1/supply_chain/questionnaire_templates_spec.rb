# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::SupplyChain::QuestionnaireTemplates", type: :request do
  let!(:account) { create(:account) }
  let!(:other_account) { create(:account) }
  let!(:read_user) { create(:user, account: account, permissions: [ "supply_chain.read" ]) }
  let!(:write_user) { create(:user, account: account, permissions: [ "supply_chain.read", "supply_chain.write" ]) }
  let!(:other_user) { create(:user, account: other_account, permissions: [ "supply_chain.read", "supply_chain.write" ]) }

  before(:each) do
    Rails.cache.clear
  end

  describe "GET /api/v1/supply_chain/questionnaire_templates" do
    let(:headers) { auth_headers_for(read_user) }

    context "with no filters" do
      before do
        read_user # Ensure read_user and account are created first
        create_list(:supply_chain_questionnaire_template, 3, account: account, is_system: false)
        create(:supply_chain_questionnaire_template, account: other_account) # Should not appear
      end

      it "returns paginated templates for current account" do
        get "/api/v1/supply_chain/questionnaire_templates", headers: headers, as: :json

        expect_success_response
        expect(json_response["data"]["questionnaire_templates"].length).to eq(3)
        expect(json_response["meta"]["total_count"]).to eq(3)
        expect(json_response["meta"]["current_page"]).to eq(1)
      end

      it "orders templates by created_at descending" do
        template1 = create(:supply_chain_questionnaire_template, account: account, name: "First Template", created_at: 3.days.ago)
        template2 = create(:supply_chain_questionnaire_template, account: account, name: "Second Template", created_at: 2.days.ago)
        template3 = create(:supply_chain_questionnaire_template, account: account, name: "Third Template", created_at: 1.day.ago)

        get "/api/v1/supply_chain/questionnaire_templates", headers: headers, as: :json

        expect_success_response
        template_ids = json_response["data"]["questionnaire_templates"].map { |t| t["id"] }
        # Check that these 3 templates appear in the right order (newest first)
        expect(template_ids.index(template3.id)).to be < template_ids.index(template2.id)
        expect(template_ids.index(template2.id)).to be < template_ids.index(template1.id)
      end
    end

    context "with system templates" do
      before do
        read_user # Ensure read_user and account are created first
        create(:supply_chain_questionnaire_template, account: account, is_system: false)
        create(:supply_chain_questionnaire_template, account: nil, is_system: true)
        create(:supply_chain_questionnaire_template, account: nil, is_system: true)
      end

      it "includes system templates for all accounts" do
        get "/api/v1/supply_chain/questionnaire_templates", headers: headers, as: :json

        expect_success_response
        expect(json_response["data"]["questionnaire_templates"].length).to eq(3)
      end
    end

    context "with pagination" do
      before do
        read_user # Ensure read_user and account are created first
        create_list(:supply_chain_questionnaire_template, 25, account: account)
      end

      it "respects per_page parameter" do
        get "/api/v1/supply_chain/questionnaire_templates?per_page=10", headers: headers, as: :json

        expect_success_response
        expect(json_response["data"]["questionnaire_templates"].length).to eq(10)
        expect(json_response["meta"]["total_count"]).to eq(25)
        expect(json_response["meta"]["per_page"]).to eq(10)
      end

      it "respects page parameter" do
        get "/api/v1/supply_chain/questionnaire_templates?page=2&per_page=10", headers: headers, as: :json

        expect_success_response
        expect(json_response["data"]["questionnaire_templates"].length).to eq(10)
        expect(json_response["meta"]["current_page"]).to eq(2)
      end

      it "defaults to 20 per page" do
        get "/api/v1/supply_chain/questionnaire_templates", headers: headers, as: :json

        expect_success_response
        expect(json_response["data"]["questionnaire_templates"].length).to eq(20)
        expect(json_response["meta"]["per_page"]).to eq(20)
      end
    end

    context "with active_only filter" do
      before do
        read_user # Ensure read_user and account are created first
        create(:supply_chain_questionnaire_template, account: account, is_active: true)
        create(:supply_chain_questionnaire_template, account: account, is_active: true)
        create(:supply_chain_questionnaire_template, account: account, is_active: false)
      end

      it "filters by active status" do
        get "/api/v1/supply_chain/questionnaire_templates?active_only=true", headers: headers, as: :json

        expect_success_response
        expect(json_response["data"]["questionnaire_templates"].length).to eq(2)
        expect(json_response["data"]["questionnaire_templates"].all? { |t| t["is_active"] == true }).to be true
      end
    end

    context "with system_only filter" do
      before do
        read_user # Ensure read_user and account are created first
        create(:supply_chain_questionnaire_template, account: account, is_system: false)
        create(:supply_chain_questionnaire_template, account: nil, is_system: true)
        create(:supply_chain_questionnaire_template, account: nil, is_system: true)
      end

      it "filters by system templates" do
        get "/api/v1/supply_chain/questionnaire_templates?system_only=true", headers: headers, as: :json

        expect_success_response
        expect(json_response["data"]["questionnaire_templates"].length).to eq(2)
        expect(json_response["data"]["questionnaire_templates"].all? { |t| t["is_system"] == true }).to be true
      end
    end

    context "with type filter" do
      before do
        read_user # Ensure read_user and account are created first
        create(:supply_chain_questionnaire_template, account: account, template_type: "soc2")
        create(:supply_chain_questionnaire_template, account: account, template_type: "iso27001")
        create(:supply_chain_questionnaire_template, account: account, template_type: "soc2")
      end

      it "filters by template type" do
        get "/api/v1/supply_chain/questionnaire_templates?type=soc2", headers: headers, as: :json

        expect_success_response
        expect(json_response["data"]["questionnaire_templates"].length).to eq(2)
        expect(json_response["data"]["questionnaire_templates"].all? { |t| t["template_type"] == "soc2" }).to be true
      end
    end

    context "with combined filters" do
      before do
        read_user # Ensure read_user and account are created first
        create(:supply_chain_questionnaire_template, account: account, is_active: true, template_type: "soc2")
        create(:supply_chain_questionnaire_template, account: account, is_active: false, template_type: "soc2")
        create(:supply_chain_questionnaire_template, account: account, is_active: true, template_type: "iso27001")
      end

      it "applies multiple filters" do
        get "/api/v1/supply_chain/questionnaire_templates?active_only=true&type=soc2", headers: headers, as: :json

        expect_success_response
        expect(json_response["data"]["questionnaire_templates"].length).to eq(1)
        template = json_response["data"]["questionnaire_templates"].first
        expect(template["is_active"]).to be true
        expect(template["template_type"]).to eq("soc2")
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/questionnaire_templates", as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without required permission" do
      let(:user_without_permission) { create(:user, account: account, permissions: []) }
      let(:headers) { auth_headers_for(user_without_permission) }

      it "returns forbidden error" do
        get "/api/v1/supply_chain/questionnaire_templates", headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /api/v1/supply_chain/questionnaire_templates/:id" do
    let(:template) { create(:supply_chain_questionnaire_template, account: account) }
    let(:headers) { auth_headers_for(read_user) }

    context "with valid template" do
      it "returns template details" do
        get "/api/v1/supply_chain/questionnaire_templates/#{template.id}", headers: headers, as: :json

        expect_success_response
        expect(json_response["data"]["questionnaire_template"]).to include(
          "id" => template.id,
          "name" => template.name,
          "description" => template.description,
          "template_type" => template.template_type,
          "version" => template.version,
          "is_system" => template.is_system,
          "is_active" => template.is_active
        )
      end

      it "includes detailed fields" do
        get "/api/v1/supply_chain/questionnaire_templates/#{template.id}", headers: headers, as: :json

        expect_success_response
        expect(json_response["data"]["questionnaire_template"]).to have_key("sections")
        expect(json_response["data"]["questionnaire_template"]).to have_key("questions")
        expect(json_response["data"]["questionnaire_template"]).to have_key("response_count")
        expect(json_response["data"]["questionnaire_template"]).to have_key("metadata")
      end

      it "includes section and question counts" do
        get "/api/v1/supply_chain/questionnaire_templates/#{template.id}", headers: headers, as: :json

        expect_success_response
        expect(json_response["data"]["questionnaire_template"]).to have_key("section_count")
        expect(json_response["data"]["questionnaire_template"]).to have_key("question_count")
      end
    end

    context "with system template" do
      let(:system_template) { create(:supply_chain_questionnaire_template, account: nil, is_system: true) }

      it "allows viewing system templates" do
        get "/api/v1/supply_chain/questionnaire_templates/#{system_template.id}", headers: headers, as: :json

        expect_success_response
        expect(json_response["data"]["questionnaire_template"]["is_system"]).to be true
      end
    end

    context "with template from another account" do
      let(:other_template) { create(:supply_chain_questionnaire_template, account: other_account) }

      it "returns not found error" do
        get "/api/v1/supply_chain/questionnaire_templates/#{other_template.id}", headers: headers, as: :json

        expect_error_response("Questionnaire template not found", 404)
      end
    end

    context "with non-existent template" do
      it "returns not found error" do
        get "/api/v1/supply_chain/questionnaire_templates/nonexistent-id", headers: headers, as: :json

        expect_error_response("Questionnaire template not found", 404)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/questionnaire_templates/#{template.id}", as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without required permission" do
      let(:user_without_permission) { create(:user, account: account, permissions: []) }
      let(:headers) { auth_headers_for(user_without_permission) }

      it "returns forbidden error" do
        get "/api/v1/supply_chain/questionnaire_templates/#{template.id}", headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /api/v1/supply_chain/questionnaire_templates" do
    let(:headers) { auth_headers_for(write_user) }

    context "with valid parameters" do
      let(:valid_params) do
        {
          questionnaire_template: {
            name: "Custom Security Assessment",
            description: "A custom security questionnaire",
            template_type: "custom",
            version: "1.0",
            is_active: true,
            sections: [
              { id: "sec1", name: "General Security", description: "General questions", weight: 1.0, order: 0 }
            ],
            questions: [
              { id: "q1", section_id: "sec1", text: "Do you have a security policy?", type: "yes_no", required: true, weight: 1.0, order: 0 }
            ],
            metadata: { custom_field: "value" }
          }
        }
      end

      it "creates a new template" do
        expect {
          post "/api/v1/supply_chain/questionnaire_templates", params: valid_params, headers: headers, as: :json
        }.to change(SupplyChain::QuestionnaireTemplate, :count).by(1)

        expect(response).to have_http_status(:created)
        expect_success_response
      end

      it "returns the created template" do
        post "/api/v1/supply_chain/questionnaire_templates", params: valid_params, headers: headers, as: :json

        expect_success_response
        expect(json_response["data"]["questionnaire_template"]).to include(
          "name" => "Custom Security Assessment",
          "template_type" => "custom",
          "version" => "1.0"
        )
      end

      it "associates template with current account" do
        post "/api/v1/supply_chain/questionnaire_templates", params: valid_params, headers: headers, as: :json

        expect_success_response
        template = SupplyChain::QuestionnaireTemplate.find(json_response["data"]["questionnaire_template"]["id"])
        expect(template.account_id).to eq(account.id)
      end

      it "sets created_by to current user" do
        post "/api/v1/supply_chain/questionnaire_templates", params: valid_params, headers: headers, as: :json

        expect_success_response
        template = SupplyChain::QuestionnaireTemplate.find(json_response["data"]["questionnaire_template"]["id"])
        expect(template.created_by_id).to eq(write_user.id)
      end

      it "sets is_system to false" do
        post "/api/v1/supply_chain/questionnaire_templates", params: valid_params, headers: headers, as: :json

        expect_success_response
        expect(json_response["data"]["questionnaire_template"]["is_system"]).to be false
      end
    end

    context "with minimal valid parameters" do
      let(:minimal_params) do
        {
          questionnaire_template: {
            name: "Minimal Template",
            template_type: "custom",
            version: "1.0"
          }
        }
      end

      it "creates template with defaults" do
        expect {
          post "/api/v1/supply_chain/questionnaire_templates", params: minimal_params, headers: headers, as: :json
        }.to change(SupplyChain::QuestionnaireTemplate, :count).by(1)

        expect_success_response
      end
    end

    context "with invalid parameters" do
      it "returns validation error for missing name" do
        post "/api/v1/supply_chain/questionnaire_templates",
             params: { questionnaire_template: { template_type: "custom", version: "1.0" } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
        expect(json_response["error"]).to be_present
      end

      it "returns validation error for invalid template_type" do
        post "/api/v1/supply_chain/questionnaire_templates",
             params: { questionnaire_template: { name: "Test", template_type: "invalid_type", version: "1.0" } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
      end

      # Note: version has a database default of "1.0", so this validation never fails
    end

    context "without authentication" do
      it "returns unauthorized error" do
        post "/api/v1/supply_chain/questionnaire_templates",
             params: { questionnaire_template: { name: "Test", template_type: "custom", version: "1.0" } },
             as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without write permission" do
      let(:headers) { auth_headers_for(read_user) }

      it "returns forbidden error" do
        post "/api/v1/supply_chain/questionnaire_templates",
             params: { questionnaire_template: { name: "Test", template_type: "custom", version: "1.0" } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PATCH /api/v1/supply_chain/questionnaire_templates/:id" do
    let(:template) { create(:supply_chain_questionnaire_template, account: account, name: "Original Name", is_system: false) }
    let(:headers) { auth_headers_for(write_user) }

    context "with valid parameters" do
      let(:update_params) do
        {
          questionnaire_template: {
            name: "Updated Template Name",
            description: "Updated description",
            is_active: false
          }
        }
      end

      it "updates the template" do
        patch "/api/v1/supply_chain/questionnaire_templates/#{template.id}",
              params: update_params,
              headers: headers,
              as: :json

        expect_success_response
        expect(json_response["data"]["questionnaire_template"]["name"]).to eq("Updated Template Name")
      end

      it "persists changes to database" do
        patch "/api/v1/supply_chain/questionnaire_templates/#{template.id}",
              params: update_params,
              headers: headers,
              as: :json

        template.reload
        expect(template.name).to eq("Updated Template Name")
        expect(template.description).to eq("Updated description")
        expect(template.is_active).to be false
      end
    end

    context "with partial update" do
      it "updates only provided fields" do
        original_type = template.template_type

        patch "/api/v1/supply_chain/questionnaire_templates/#{template.id}",
              params: { questionnaire_template: { description: "New description only" } },
              headers: headers,
              as: :json

        expect_success_response

        template.reload
        expect(template.description).to eq("New description only")
        expect(template.template_type).to eq(original_type)
      end
    end

    context "with system template" do
      let(:system_template) { create(:supply_chain_questionnaire_template, account: nil, is_system: true) }

      it "returns forbidden error" do
        patch "/api/v1/supply_chain/questionnaire_templates/#{system_template.id}",
              params: { questionnaire_template: { name: "Cannot Update" } },
              headers: headers,
              as: :json

        expect(response).to have_http_status(:forbidden)
        expect(json_response["success"]).to be false
        expect(json_response["error"]).to eq("Cannot modify system templates")
      end

      it "does not modify system template" do
        original_name = system_template.name

        patch "/api/v1/supply_chain/questionnaire_templates/#{system_template.id}",
              params: { questionnaire_template: { name: "Hacked Name" } },
              headers: headers,
              as: :json

        system_template.reload
        expect(system_template.name).to eq(original_name)
      end
    end

    context "with invalid parameters" do
      it "returns validation error" do
        patch "/api/v1/supply_chain/questionnaire_templates/#{template.id}",
              params: { questionnaire_template: { name: "" } },
              headers: headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
      end
    end

    context "with template from another account" do
      let(:other_template) { create(:supply_chain_questionnaire_template, account: other_account) }

      it "returns not found error" do
        patch "/api/v1/supply_chain/questionnaire_templates/#{other_template.id}",
              params: { questionnaire_template: { name: "Hacked Name" } },
              headers: headers,
              as: :json

        expect_error_response("Questionnaire template not found", 404)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        patch "/api/v1/supply_chain/questionnaire_templates/#{template.id}",
              params: { questionnaire_template: { name: "No Auth" } },
              as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without write permission" do
      let(:headers) { auth_headers_for(read_user) }

      it "returns forbidden error" do
        patch "/api/v1/supply_chain/questionnaire_templates/#{template.id}",
              params: { questionnaire_template: { name: "Unauthorized" } },
              headers: headers,
              as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "DELETE /api/v1/supply_chain/questionnaire_templates/:id" do
    let!(:template) { create(:supply_chain_questionnaire_template, account: account, is_system: false) }
    let(:headers) { auth_headers_for(write_user) }

    context "with valid template" do
      it "deletes the template" do
        expect {
          delete "/api/v1/supply_chain/questionnaire_templates/#{template.id}", headers: headers, as: :json
        }.to change(SupplyChain::QuestionnaireTemplate, :count).by(-1)

        expect_success_response
      end

      it "returns success message" do
        delete "/api/v1/supply_chain/questionnaire_templates/#{template.id}", headers: headers, as: :json

        expect_success_response
        expect(json_response["data"]["message"]).to eq("Questionnaire template deleted")
      end
    end

    context "with system template" do
      let!(:system_template) { create(:supply_chain_questionnaire_template, account: nil, is_system: true) }

      it "returns forbidden error" do
        expect {
          delete "/api/v1/supply_chain/questionnaire_templates/#{system_template.id}", headers: headers, as: :json
        }.not_to change(SupplyChain::QuestionnaireTemplate, :count)

        expect(response).to have_http_status(:forbidden)
        expect(json_response["success"]).to be false
        expect(json_response["error"]).to eq("Cannot delete system templates")
      end
    end

    context "with template having responses" do
      let!(:vendor) { create(:supply_chain_vendor, account: account) }
      let!(:questionnaire_response) { create(:supply_chain_questionnaire_response, template: template, vendor: vendor, account: account) }

      it "returns unprocessable entity error" do
        expect {
          delete "/api/v1/supply_chain/questionnaire_templates/#{template.id}", headers: headers, as: :json
        }.not_to change(SupplyChain::QuestionnaireTemplate, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
        expect(json_response["error"]).to eq("Cannot delete template with existing responses")
      end
    end

    context "with template from another account" do
      let!(:other_template) { create(:supply_chain_questionnaire_template, account: other_account) }

      it "returns not found error" do
        expect {
          delete "/api/v1/supply_chain/questionnaire_templates/#{other_template.id}", headers: headers, as: :json
        }.not_to change(SupplyChain::QuestionnaireTemplate, :count)

        expect_error_response("Questionnaire template not found", 404)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        delete "/api/v1/supply_chain/questionnaire_templates/#{template.id}", as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without write permission" do
      let(:headers) { auth_headers_for(read_user) }

      it "returns forbidden error" do
        delete "/api/v1/supply_chain/questionnaire_templates/#{template.id}", headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /api/v1/supply_chain/questionnaire_templates/:id/duplicate" do
    let!(:template) { create(:supply_chain_questionnaire_template, account: account, name: "Original Template") }
    let(:headers) { auth_headers_for(write_user) }

    context "with valid request" do
      it "creates a duplicate template" do
        expect {
          post "/api/v1/supply_chain/questionnaire_templates/#{template.id}/duplicate", headers: headers, as: :json
        }.to change(SupplyChain::QuestionnaireTemplate, :count).by(1)

        expect_success_response
      end

      it "returns the duplicated template" do
        post "/api/v1/supply_chain/questionnaire_templates/#{template.id}/duplicate", headers: headers, as: :json

        expect_success_response
        expect(json_response["data"]["questionnaire_template"]["name"]).to eq("Original Template (Copy)")
      end

      it "duplicates with custom name" do
        post "/api/v1/supply_chain/questionnaire_templates/#{template.id}/duplicate",
             params: { name: "Custom Copy Name" },
             headers: headers,
             as: :json

        expect_success_response
        expect(json_response["data"]["questionnaire_template"]["name"]).to eq("Custom Copy Name")
      end

      it "sets is_system to false on duplicate" do
        system_template = create(:supply_chain_questionnaire_template, account: nil, is_system: true, name: "System Template")

        post "/api/v1/supply_chain/questionnaire_templates/#{system_template.id}/duplicate",
             headers: headers,
             as: :json

        expect_success_response
        expect(json_response["data"]["questionnaire_template"]["is_system"]).to be false
      end

      it "associates duplicate with current account" do
        post "/api/v1/supply_chain/questionnaire_templates/#{template.id}/duplicate", headers: headers, as: :json

        expect_success_response
        new_template = SupplyChain::QuestionnaireTemplate.find(json_response["data"]["questionnaire_template"]["id"])
        expect(new_template.account_id).to eq(account.id)
      end

      it "copies sections and questions" do
        template.update!(
          sections: [ { id: "sec1", name: "Security", weight: 1.0, order: 0 } ],
          questions: [ { id: "q1", section_id: "sec1", text: "Question?", type: "yes_no", required: true } ]
        )

        post "/api/v1/supply_chain/questionnaire_templates/#{template.id}/duplicate", headers: headers, as: :json

        expect_success_response
        new_template = SupplyChain::QuestionnaireTemplate.find(json_response["data"]["questionnaire_template"]["id"])
        expect(new_template.sections).to eq(template.sections)
        expect(new_template.questions).to eq(template.questions)
      end
    end

    context "with system template" do
      let!(:system_template) { create(:supply_chain_questionnaire_template, account: nil, is_system: true, name: "System Template") }

      it "allows duplicating system templates" do
        expect {
          post "/api/v1/supply_chain/questionnaire_templates/#{system_template.id}/duplicate", headers: headers, as: :json
        }.to change(SupplyChain::QuestionnaireTemplate, :count).by(1)

        expect_success_response
      end
    end

    context "with template from another account" do
      let!(:other_template) { create(:supply_chain_questionnaire_template, account: other_account) }

      it "returns not found error" do
        expect {
          post "/api/v1/supply_chain/questionnaire_templates/#{other_template.id}/duplicate", headers: headers, as: :json
        }.not_to change(SupplyChain::QuestionnaireTemplate, :count)

        expect_error_response("Questionnaire template not found", 404)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        post "/api/v1/supply_chain/questionnaire_templates/#{template.id}/duplicate", as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without write permission" do
      let(:headers) { auth_headers_for(read_user) }

      it "returns forbidden error" do
        post "/api/v1/supply_chain/questionnaire_templates/#{template.id}/duplicate", headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /api/v1/supply_chain/questionnaire_templates/:id/send_to_vendor" do
    let!(:template) { create(:supply_chain_questionnaire_template, account: account) }
    let!(:vendor) { create(:supply_chain_vendor, account: account) }
    let(:headers) { auth_headers_for(write_user) }

    context "with valid request" do
      let(:params) do
        {
          vendor_id: vendor.id,
          due_at: 30.days.from_now
        }
      end

      it "creates a questionnaire response" do
        expect {
          post "/api/v1/supply_chain/questionnaire_templates/#{template.id}/send_to_vendor",
               params: params,
               headers: headers,
               as: :json
        }.to change(SupplyChain::QuestionnaireResponse, :count).by(1)

        expect_success_response
      end

      it "returns the created response" do
        post "/api/v1/supply_chain/questionnaire_templates/#{template.id}/send_to_vendor",
             params: params,
             headers: headers,
             as: :json

        expect_success_response
        expect(json_response["data"]["questionnaire_response"]).to include(
          "vendor_id" => vendor.id,
          "template_id" => template.id,
          "status" => "pending"
        )
      end

      it "sets sent_at to current time" do
        post "/api/v1/supply_chain/questionnaire_templates/#{template.id}/send_to_vendor",
             params: params,
             headers: headers,
             as: :json

        expect_success_response
        questionnaire_response = SupplyChain::QuestionnaireResponse.find(json_response["data"]["questionnaire_response"]["id"])
        expect(questionnaire_response.sent_at).to be_within(1.second).of(Time.current)
      end

      it "sets requested_by to current user" do
        post "/api/v1/supply_chain/questionnaire_templates/#{template.id}/send_to_vendor",
             params: params,
             headers: headers,
             as: :json

        expect_success_response
        questionnaire_response = SupplyChain::QuestionnaireResponse.find(json_response["data"]["questionnaire_response"]["id"])
        expect(questionnaire_response.requested_by_id).to eq(write_user.id)
      end

      it "generates access token" do
        post "/api/v1/supply_chain/questionnaire_templates/#{template.id}/send_to_vendor",
             params: params,
             headers: headers,
             as: :json

        expect_success_response
        questionnaire_response = SupplyChain::QuestionnaireResponse.find(json_response["data"]["questionnaire_response"]["id"])
        expect(questionnaire_response.access_token).to be_present
        expect(questionnaire_response.access_token.length).to be >= 32
      end

      it "includes access_url in response" do
        post "/api/v1/supply_chain/questionnaire_templates/#{template.id}/send_to_vendor",
             params: params,
             headers: headers,
             as: :json

        expect_success_response
        expect(json_response["data"]["questionnaire_response"]["access_url"]).to be_present
        expect(json_response["data"]["questionnaire_response"]["access_url"]).to include("/vendor-questionnaire/")
      end

      it "uses custom due_at when provided" do
        custom_due_at = 60.days.from_now

        post "/api/v1/supply_chain/questionnaire_templates/#{template.id}/send_to_vendor",
             params: { vendor_id: vendor.id, due_at: custom_due_at },
             headers: headers,
             as: :json

        expect_success_response
        questionnaire_response = SupplyChain::QuestionnaireResponse.find(json_response["data"]["questionnaire_response"]["id"])
        expect(questionnaire_response.expires_at).to be_within(1.second).of(custom_due_at)
      end

      it "defaults due_at to 30 days when not provided" do
        post "/api/v1/supply_chain/questionnaire_templates/#{template.id}/send_to_vendor",
             params: { vendor_id: vendor.id },
             headers: headers,
             as: :json

        expect_success_response
        questionnaire_response = SupplyChain::QuestionnaireResponse.find(json_response["data"]["questionnaire_response"]["id"])
        expect(questionnaire_response.expires_at).to be_within(1.hour).of(30.days.from_now)
      end
    end

    context "without vendor_id" do
      it "returns error" do
        post "/api/v1/supply_chain/questionnaire_templates/#{template.id}/send_to_vendor",
             params: {},
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
        expect(json_response["error"]).to include("Failed to send questionnaire")
      end
    end

    context "with vendor from another account" do
      let(:other_vendor) { create(:supply_chain_vendor, account: other_account) }

      it "returns error" do
        post "/api/v1/supply_chain/questionnaire_templates/#{template.id}/send_to_vendor",
             params: { vendor_id: other_vendor.id },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
      end
    end

    context "with template from another account" do
      let(:other_template) { create(:supply_chain_questionnaire_template, account: other_account) }

      it "returns not found error" do
        post "/api/v1/supply_chain/questionnaire_templates/#{other_template.id}/send_to_vendor",
             params: { vendor_id: vendor.id },
             headers: headers,
             as: :json

        expect_error_response("Questionnaire template not found", 404)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        post "/api/v1/supply_chain/questionnaire_templates/#{template.id}/send_to_vendor",
             params: { vendor_id: vendor.id },
             as: :json

        expect_error_response("Access token required", 401)
      end
    end

    context "without write permission" do
      let(:headers) { auth_headers_for(read_user) }

      it "returns forbidden error" do
        post "/api/v1/supply_chain/questionnaire_templates/#{template.id}/send_to_vendor",
             params: { vendor_id: vendor.id },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "account isolation" do
    # Use lazy let for template since most tests don't need it
    let(:template) { create(:supply_chain_questionnaire_template, account: account, is_system: false) }
    let!(:other_template) { create(:supply_chain_questionnaire_template, account: other_account, is_system: false) }
    let(:headers) { auth_headers_for(write_user) }

    it "prevents access to templates from other accounts in show" do
      get "/api/v1/supply_chain/questionnaire_templates/#{other_template.id}", headers: headers, as: :json

      expect_error_response("Questionnaire template not found", 404)
    end

    it "prevents access to templates from other accounts in update" do
      patch "/api/v1/supply_chain/questionnaire_templates/#{other_template.id}",
            params: { questionnaire_template: { name: "Hacked" } },
            headers: headers,
            as: :json

      expect_error_response("Questionnaire template not found", 404)
    end

    it "prevents access to templates from other accounts in delete" do
      expect {
        delete "/api/v1/supply_chain/questionnaire_templates/#{other_template.id}", headers: headers, as: :json
      }.not_to change(SupplyChain::QuestionnaireTemplate, :count)

      expect_error_response("Questionnaire template not found", 404)
    end

    it "only shows templates from current account and system templates in index" do
      create_list(:supply_chain_questionnaire_template, 3, account: account, is_system: false)
      create_list(:supply_chain_questionnaire_template, 3, account: other_account, is_system: false)
      create_list(:supply_chain_questionnaire_template, 2, account: nil, is_system: true)

      get "/api/v1/supply_chain/questionnaire_templates", headers: headers, as: :json

      expect_success_response
      expect(json_response["data"]["questionnaire_templates"].length).to eq(5) # 3 account + 2 system
    end
  end
end
