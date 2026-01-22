# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::SupplyChain::Attestations", type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  # User with supply_chain.read permission only
  let(:read_only_user) do
    create(:user, account: account, permissions: ["supply_chain.read"])
  end

  # User with both read and write permissions
  let(:read_write_user) do
    create(:user, account: account, permissions: ["supply_chain.read", "supply_chain.write"])
  end

  # User without supply chain permissions
  let(:regular_user) do
    create(:user, account: account, permissions: [])
  end

  before(:each) do
    Rails.cache.clear
  end

  describe "GET /api/v1/supply_chain/attestations" do
    context "with supply_chain.read permission" do
      let!(:attestations) do
        [
          create(:supply_chain_attestation, account: account, attestation_type: "slsa_provenance", slsa_level: 1, verification_status: "unverified"),
          create(:supply_chain_attestation, account: account, attestation_type: "slsa_provenance", slsa_level: 2, verification_status: "verified"),
          create(:supply_chain_attestation, account: account, attestation_type: "slsa_provenance", slsa_level: 3, verification_status: "unverified")
        ]
      end

      let!(:other_account_attestation) do
        create(:supply_chain_attestation, account: other_account)
      end

      it "returns attestations for the current account" do
        get "/api/v1/supply_chain/attestations", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        data = json_response["data"]["attestations"]

        expect(data.length).to eq(3)
        expect(data.map { |a| a["id"] }).to match_array(attestations.map(&:id))
        expect(data.map { |a| a["id"] }).not_to include(other_account_attestation.id)
      end

      it "returns attestations ordered by created_at desc" do
        get "/api/v1/supply_chain/attestations", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        data = json_response["data"]["attestations"]

        created_ats = data.map { |a| Time.parse(a["created_at"]) }
        expect(created_ats).to eq(created_ats.sort.reverse)
      end

      it "returns attestation data with correct structure" do
        get "/api/v1/supply_chain/attestations", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        attestation_data = json_response["data"]["attestations"].first

        expect(attestation_data).to include(
          "id",
          "attestation_id",
          "attestation_type",
          "slsa_level",
          "subject_name",
          "subject_digest",
          "signed",
          "verified",
          "rekor_logged",
          "created_at"
        )
      end

      it "filters by type" do
        get "/api/v1/supply_chain/attestations?type=slsa_provenance", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        data = json_response["data"]["attestations"]

        expect(data.length).to eq(3)
        expect(data.all? { |a| a["attestation_type"] == "slsa_provenance" }).to be true
      end

      it "filters by slsa_level" do
        get "/api/v1/supply_chain/attestations?slsa_level=2", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        data = json_response["data"]["attestations"]

        expect(data.length).to eq(1)
        expect(data.first["slsa_level"]).to eq(2)
      end

      it "filters by status" do
        get "/api/v1/supply_chain/attestations?status=verified", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        data = json_response["data"]["attestations"]

        expect(data.length).to eq(1)
        expect(data.first["verification_status"]).to eq("verified")
      end

      it "applies multiple filters simultaneously" do
        get "/api/v1/supply_chain/attestations?slsa_level=1&status=unverified", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        data = json_response["data"]["attestations"]

        expect(data.length).to eq(1)
        expect(data.first["slsa_level"]).to eq(1)
        expect(data.first["verification_status"]).to eq("unverified")
      end
    end

    context "pagination" do
      before do
        25.times do
          create(:supply_chain_attestation, account: account)
        end
      end

      it "returns paginated results with default per_page of 20" do
        get "/api/v1/supply_chain/attestations", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        expect(json_response["data"]["attestations"].length).to eq(20)
        expect(json_response["data"]["meta"]["total"]).to eq(25)
        expect(json_response["data"]["meta"]["page"]).to eq(1)
        expect(json_response["data"]["meta"]["per_page"]).to eq(20)
      end

      it "respects page parameter" do
        get "/api/v1/supply_chain/attestations?page=2", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        expect(json_response["data"]["attestations"].length).to eq(5)
        expect(json_response["data"]["meta"]["page"]).to eq(2)
      end

      it "respects per_page parameter" do
        get "/api/v1/supply_chain/attestations?per_page=10", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        expect(json_response["data"]["attestations"].length).to eq(10)
        expect(json_response["data"]["meta"]["per_page"]).to eq(10)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/attestations", headers: auth_headers_for(regular_user), as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/attestations", as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "GET /api/v1/supply_chain/attestations/:id" do
    let!(:signing_key) { create(:supply_chain_signing_key, account: account) }
    let!(:attestation) { create(:supply_chain_attestation, :signed, account: account, signing_key: signing_key) }

    context "with supply_chain.read permission" do
      it "returns the attestation with detailed information" do
        get "/api/v1/supply_chain/attestations/#{attestation.id}", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        data = json_response["data"]["attestation"]

        expect(data["id"]).to eq(attestation.id)
        expect(data["attestation_id"]).to eq(attestation.attestation_id)
        expect(data["predicate"]).to be_present
        expect(data["predicate_type"]).to be_present
        expect(data["signature"]).to eq("[PRESENT]")
        expect(data["signature_algorithm"]).to be_present
      end

      it "includes signing key information when present" do
        get "/api/v1/supply_chain/attestations/#{attestation.id}", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        data = json_response["data"]["attestation"]

        expect(data["signing_key"]).to include(
          "id" => signing_key.id,
          "key_id" => signing_key.key_id,
          "key_type" => signing_key.key_type
        )
      end

      it "includes verification information" do
        get "/api/v1/supply_chain/attestations/#{attestation.id}", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        data = json_response["data"]["attestation"]

        expect(data["verification_status"]).to be_present
        expect(data).to have_key("verification_results")
      end
    end

    context "with attestation from another account" do
      let(:other_attestation) { create(:supply_chain_attestation, account: other_account) }

      it "returns not found error" do
        get "/api/v1/supply_chain/attestations/#{other_attestation.id}", headers: auth_headers_for(read_only_user), as: :json

        expect_error_response("Attestation not found", 404)
      end
    end

    context "with non-existent attestation" do
      it "returns not found error" do
        get "/api/v1/supply_chain/attestations/non-existent-id", headers: auth_headers_for(read_only_user), as: :json

        expect_error_response("Attestation not found", 404)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/attestations/#{attestation.id}", headers: auth_headers_for(regular_user), as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/attestations" do
    context "with supply_chain.write permission" do
      let(:valid_params) do
        {
          subject_name: "app:test-application",
          subject_digest: "sha256:#{SecureRandom.hex(32)}",
          builder_id: "https://github.com/actions/runner",
          materials: [{ uri: "git+https://github.com/example/repo" }],
          source_repository: "https://github.com/example/repo",
          source_commit: SecureRandom.hex(20),
          source_branch: "main"
        }
      end

      it "creates an attestation with valid parameters" do
        expect do
          post "/api/v1/supply_chain/attestations",
               params: valid_params,
               headers: auth_headers_for(read_write_user),
               as: :json
        end.to change(SupplyChain::Attestation, :count).by(1)

        expect(response).to have_http_status(:created)
        expect_success_response

        data = json_response["data"]["attestation"]
        expect(data["subject_name"]).to eq(valid_params[:subject_name])
        # The generator strips the algorithm prefix from subject_digest
        expected_digest = valid_params[:subject_digest].split(":").last
        expect(data["subject_digest"]).to eq(expected_digest)
        expect(json_response["data"]["message"]).to eq("Attestation created successfully")
      end

      it "creates a signed attestation when sign parameter is true" do
        create(:supply_chain_signing_key, account: account, status: "active")

        post "/api/v1/supply_chain/attestations",
             params: valid_params.merge(sign: true),
             headers: auth_headers_for(read_write_user),
             as: :json

        expect(response).to have_http_status(:created)
        expect_success_response
      end

      it "returns error with invalid parameters" do
        invalid_params = { subject_name: "" }

        post "/api/v1/supply_chain/attestations",
             params: invalid_params,
             headers: auth_headers_for(read_write_user),
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
        expect(json_response["error"]).to include("Failed to create attestation")
      end
    end

    context "without supply_chain.write permission" do
      let(:valid_params) do
        {
          subject_name: "app:test-application",
          subject_digest: "sha256:#{SecureRandom.hex(32)}",
          builder_id: "https://github.com/actions/runner"
        }
      end

      it "returns forbidden error for read-only user" do
        post "/api/v1/supply_chain/attestations",
             params: valid_params,
             headers: auth_headers_for(read_only_user),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end

      it "returns forbidden error for regular user" do
        post "/api/v1/supply_chain/attestations",
             params: valid_params,
             headers: auth_headers_for(regular_user),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "PATCH /api/v1/supply_chain/attestations/:id" do
    let!(:attestation) { create(:supply_chain_attestation, account: account) }

    context "with supply_chain.write permission" do
      it "updates the attestation with valid parameters" do
        new_subject_name = "app:updated-application"

        patch "/api/v1/supply_chain/attestations/#{attestation.id}",
              params: { attestation: { subject_name: new_subject_name } },
              headers: auth_headers_for(read_write_user),
              as: :json

        expect_success_response
        expect(json_response["data"]["attestation"]["subject_name"]).to eq(new_subject_name)
        expect(json_response["data"]["message"]).to eq("Attestation updated successfully")

        attestation.reload
        expect(attestation.subject_name).to eq(new_subject_name)
      end

      it "returns validation error with invalid parameters" do
        patch "/api/v1/supply_chain/attestations/#{attestation.id}",
              params: { attestation: { subject_name: "" } },
              headers: auth_headers_for(read_write_user),
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with attestation from another account" do
      let(:other_attestation) { create(:supply_chain_attestation, account: other_account) }

      it "returns not found error" do
        patch "/api/v1/supply_chain/attestations/#{other_attestation.id}",
              params: { attestation: { subject_name: "new-name" } },
              headers: auth_headers_for(read_write_user),
              as: :json

        expect_error_response("Attestation not found", 404)
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        patch "/api/v1/supply_chain/attestations/#{attestation.id}",
              params: { attestation: { subject_name: "new-name" } },
              headers: auth_headers_for(read_only_user),
              as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "DELETE /api/v1/supply_chain/attestations/:id" do
    let!(:attestation) { create(:supply_chain_attestation, account: account) }

    context "with supply_chain.write permission" do
      it "deletes the attestation" do
        expect do
          delete "/api/v1/supply_chain/attestations/#{attestation.id}",
                 headers: auth_headers_for(read_write_user),
                 as: :json
        end.to change(SupplyChain::Attestation, :count).by(-1)

        expect_success_response
        expect(json_response["data"]["message"]).to eq("Attestation deleted successfully")
      end
    end

    context "with attestation from another account" do
      let(:other_attestation) { create(:supply_chain_attestation, account: other_account) }

      it "returns not found error" do
        delete "/api/v1/supply_chain/attestations/#{other_attestation.id}",
               headers: auth_headers_for(read_write_user),
               as: :json

        expect_error_response("Attestation not found", 404)
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        delete "/api/v1/supply_chain/attestations/#{attestation.id}",
               headers: auth_headers_for(read_only_user),
               as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/attestations/:id/verify" do
    let!(:attestation) { create(:supply_chain_attestation, :signed, account: account) }

    context "with supply_chain.write permission" do
      it "verifies the attestation and returns verification results" do
        post "/api/v1/supply_chain/attestations/#{attestation.id}/verify",
             headers: auth_headers_for(read_write_user),
             as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["attestation_id"]).to eq(attestation.id)
        expect(data).to have_key("verified")
        expect(data).to have_key("verification_details")
        expect(data["message"]).to be_present
      end

      it "returns verification failure when verification fails" do
        allow_any_instance_of(SupplyChain::Attestation).to receive(:verify!).and_return({
          verified: false,
          details: { reason: "Invalid signature" }
        })

        post "/api/v1/supply_chain/attestations/#{attestation.id}/verify",
             headers: auth_headers_for(read_write_user),
             as: :json

        expect_success_response
        expect(json_response["data"]["verified"]).to be false
        expect(json_response["data"]["message"]).to eq("Attestation verification failed")
      end
    end

    context "with attestation from another account" do
      let(:other_attestation) { create(:supply_chain_attestation, :signed, account: other_account) }

      it "returns not found error" do
        post "/api/v1/supply_chain/attestations/#{other_attestation.id}/verify",
             headers: auth_headers_for(read_write_user),
             as: :json

        expect_error_response("Attestation not found", 404)
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/attestations/#{attestation.id}/verify",
             headers: auth_headers_for(read_only_user),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/attestations/:id/sign" do
    let!(:attestation) { create(:supply_chain_attestation, account: account) }
    let!(:signing_key) { create(:supply_chain_signing_key, account: account, status: "active") }

    context "with supply_chain.write permission" do
      it "signs the attestation with the default signing key" do
        post "/api/v1/supply_chain/attestations/#{attestation.id}/sign",
             headers: auth_headers_for(read_write_user),
             as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["message"]).to eq("Attestation signed successfully")
        expect(data["attestation"]).to be_present
      end

      it "signs the attestation with a specified signing key" do
        specific_key = create(:supply_chain_signing_key, account: account, status: "active")

        post "/api/v1/supply_chain/attestations/#{attestation.id}/sign",
             params: { signing_key_id: specific_key.id },
             headers: auth_headers_for(read_write_user),
             as: :json

        expect_success_response
        expect(json_response["data"]["message"]).to eq("Attestation signed successfully")
      end

      it "returns error when no signing key is available" do
        signing_key.update!(status: "revoked")

        post "/api/v1/supply_chain/attestations/#{attestation.id}/sign",
             headers: auth_headers_for(read_write_user),
             as: :json

        expect_error_response("Signing failed: No signing key available", 422)
      end

      it "returns error when specified signing key is not found" do
        post "/api/v1/supply_chain/attestations/#{attestation.id}/sign",
             params: { signing_key_id: "non-existent-id" },
             headers: auth_headers_for(read_write_user),
             as: :json

        expect_error_response("Signing key not found", 404)
      end
    end

    context "with attestation from another account" do
      let(:other_attestation) { create(:supply_chain_attestation, account: other_account) }

      it "returns not found error" do
        post "/api/v1/supply_chain/attestations/#{other_attestation.id}/sign",
             headers: auth_headers_for(read_write_user),
             as: :json

        expect_error_response("Attestation not found", 404)
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/attestations/#{attestation.id}/sign",
             headers: auth_headers_for(read_only_user),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/attestations/:id/record_to_rekor" do
    let!(:attestation) { create(:supply_chain_attestation, :signed, account: account) }

    context "with supply_chain.write permission" do
      it "records the signed attestation to Rekor" do
        post "/api/v1/supply_chain/attestations/#{attestation.id}/record_to_rekor",
             headers: auth_headers_for(read_write_user),
             as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["message"]).to eq("Recorded to Rekor transparency log")
        expect(data["rekor_log_id"]).to be_present
        expect(data["rekor_log_url"]).to be_present
        expect(data["attestation"]).to be_present
      end
    end

    context "when attestation is not signed" do
      let(:unsigned_attestation) { create(:supply_chain_attestation, account: account) }

      it "returns error" do
        post "/api/v1/supply_chain/attestations/#{unsigned_attestation.id}/record_to_rekor",
             headers: auth_headers_for(read_write_user),
             as: :json

        expect_error_response("Failed to record to Rekor: Attestation must be signed first", 422)
      end
    end

    context "with attestation from another account" do
      let(:other_attestation) { create(:supply_chain_attestation, :signed, account: other_account) }

      it "returns not found error" do
        post "/api/v1/supply_chain/attestations/#{other_attestation.id}/record_to_rekor",
             headers: auth_headers_for(read_write_user),
             as: :json

        expect_error_response("Attestation not found", 404)
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/attestations/#{attestation.id}/record_to_rekor",
             headers: auth_headers_for(read_only_user),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "GET /api/v1/supply_chain/attestations/:id/verification_logs" do
    let!(:attestation) { create(:supply_chain_attestation, account: account) }
    let!(:verification_logs) do
      [
        create(:supply_chain_verification_log, :passed, attestation: attestation, account: account),
        create(:supply_chain_verification_log, :failed, attestation: attestation, account: account),
        create(:supply_chain_verification_log, :passed, attestation: attestation, account: account)
      ]
    end

    context "with supply_chain.read permission" do
      it "returns verification logs for the attestation" do
        get "/api/v1/supply_chain/attestations/#{attestation.id}/verification_logs",
            headers: auth_headers_for(read_only_user),
            as: :json

        expect_success_response
        data = json_response["data"]["logs"]

        expect(data.length).to eq(3)
        expect(data.map { |l| l["id"] }).to match_array(verification_logs.map(&:id))
      end

      it "returns logs ordered by created_at desc" do
        get "/api/v1/supply_chain/attestations/#{attestation.id}/verification_logs",
            headers: auth_headers_for(read_only_user),
            as: :json

        expect_success_response
        data = json_response["data"]["logs"]

        created_ats = data.map { |l| Time.parse(l["created_at"]) }
        expect(created_ats).to eq(created_ats.sort.reverse)
      end

      it "returns log data with correct structure" do
        get "/api/v1/supply_chain/attestations/#{attestation.id}/verification_logs",
            headers: auth_headers_for(read_only_user),
            as: :json

        expect_success_response
        log_data = json_response["data"]["logs"].first

        expect(log_data).to include(
          "id",
          "verification_type",
          "result",
          "verifier_identity",
          "verification_details",
          "created_at"
        )
      end

      it "supports pagination" do
        15.times do
          create(:supply_chain_verification_log, attestation: attestation, account: account)
        end

        get "/api/v1/supply_chain/attestations/#{attestation.id}/verification_logs?per_page=10",
            headers: auth_headers_for(read_only_user),
            as: :json

        expect_success_response
        expect(json_response["data"]["logs"].length).to eq(10)
        expect(json_response["data"]["meta"]["total"]).to eq(18)
      end
    end

    context "with attestation from another account" do
      let(:other_attestation) { create(:supply_chain_attestation, account: other_account) }

      it "returns not found error" do
        get "/api/v1/supply_chain/attestations/#{other_attestation.id}/verification_logs",
            headers: auth_headers_for(read_only_user),
            as: :json

        expect_error_response("Attestation not found", 404)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/attestations/#{attestation.id}/verification_logs",
            headers: auth_headers_for(regular_user),
            as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "GET /api/v1/supply_chain/attestations/statistics" do
    context "with supply_chain.read permission" do
      before do
        create(:supply_chain_attestation, :signed, account: account, attestation_type: "slsa_provenance", slsa_level: 1, verification_status: "verified")
        create(:supply_chain_attestation, :signed, account: account, attestation_type: "slsa_provenance", slsa_level: 2, verification_status: "unverified")
        create(:supply_chain_attestation, :signed, :logged_to_rekor, account: account, attestation_type: "slsa_provenance", slsa_level: 3, verification_status: "verified")
        create(:supply_chain_attestation, account: account, attestation_type: "slsa_provenance", slsa_level: 1, verification_status: "failed")
      end

      it "returns total attestation count" do
        get "/api/v1/supply_chain/attestations/statistics",
            headers: auth_headers_for(read_only_user),
            as: :json

        expect_success_response
        expect(json_response["data"]["total"]).to eq(4)
      end

      it "returns breakdown by type" do
        get "/api/v1/supply_chain/attestations/statistics",
            headers: auth_headers_for(read_only_user),
            as: :json

        expect_success_response
        by_type = json_response["data"]["by_type"]

        expect(by_type).to be_a(Hash)
        expect(by_type["slsa_provenance"]).to eq(4)
      end

      it "returns breakdown by SLSA level" do
        get "/api/v1/supply_chain/attestations/statistics",
            headers: auth_headers_for(read_only_user),
            as: :json

        expect_success_response
        by_slsa_level = json_response["data"]["by_slsa_level"]

        expect(by_slsa_level).to be_a(Hash)
        expect(by_slsa_level["1"]).to eq(2)
        expect(by_slsa_level["2"]).to eq(1)
        expect(by_slsa_level["3"]).to eq(1)
      end

      it "returns breakdown by status" do
        get "/api/v1/supply_chain/attestations/statistics",
            headers: auth_headers_for(read_only_user),
            as: :json

        expect_success_response
        by_status = json_response["data"]["by_status"]

        expect(by_status).to be_a(Hash)
        expect(by_status["verified"]).to eq(2)
        expect(by_status["unverified"]).to eq(1)
        expect(by_status["failed"]).to eq(1)
      end

      it "returns signed attestations count" do
        get "/api/v1/supply_chain/attestations/statistics",
            headers: auth_headers_for(read_only_user),
            as: :json

        expect_success_response
        expect(json_response["data"]["signed_count"]).to eq(3)
      end

      it "returns Rekor logged attestations count" do
        get "/api/v1/supply_chain/attestations/statistics",
            headers: auth_headers_for(read_only_user),
            as: :json

        expect_success_response
        expect(json_response["data"]["rekor_logged_count"]).to eq(1)
      end

      it "only includes statistics for the current account" do
        create(:supply_chain_attestation, account: other_account)

        get "/api/v1/supply_chain/attestations/statistics",
            headers: auth_headers_for(read_only_user),
            as: :json

        expect_success_response
        expect(json_response["data"]["total"]).to eq(4)
      end
    end

    context "with no attestations" do
      it "returns zero statistics" do
        get "/api/v1/supply_chain/attestations/statistics",
            headers: auth_headers_for(read_only_user),
            as: :json

        expect_success_response
        expect(json_response["data"]["total"]).to eq(0)
        expect(json_response["data"]["signed_count"]).to eq(0)
        expect(json_response["data"]["rekor_logged_count"]).to eq(0)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/attestations/statistics",
            headers: auth_headers_for(regular_user),
            as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "account isolation" do
    let!(:account_attestation) { create(:supply_chain_attestation, account: account) }
    let!(:other_attestation) { create(:supply_chain_attestation, account: other_account) }

    it "only returns attestations for the authenticated user account" do
      get "/api/v1/supply_chain/attestations", headers: auth_headers_for(read_only_user), as: :json

      expect_success_response
      attestation_ids = json_response["data"]["attestations"].map { |a| a["id"] }

      expect(attestation_ids).to include(account_attestation.id)
      expect(attestation_ids).not_to include(other_attestation.id)
    end

    it "prevents accessing another account attestation directly" do
      get "/api/v1/supply_chain/attestations/#{other_attestation.id}", headers: auth_headers_for(read_only_user), as: :json

      expect_error_response("Attestation not found", 404)
    end

    it "prevents modifying another account attestation" do
      patch "/api/v1/supply_chain/attestations/#{other_attestation.id}",
            params: { attestation: { subject_name: "new-name" } },
            headers: auth_headers_for(read_write_user),
            as: :json

      expect_error_response("Attestation not found", 404)
    end

    it "prevents deleting another account attestation" do
      delete "/api/v1/supply_chain/attestations/#{other_attestation.id}",
             headers: auth_headers_for(read_write_user),
             as: :json

      expect_error_response("Attestation not found", 404)
    end

    it "prevents signing another account attestation" do
      post "/api/v1/supply_chain/attestations/#{other_attestation.id}/sign",
           headers: auth_headers_for(read_write_user),
           as: :json

      expect_error_response("Attestation not found", 404)
    end
  end

  describe "permission enforcement" do
    let!(:attestation) { create(:supply_chain_attestation, account: account) }

    it "allows read-only user to view attestations" do
      get "/api/v1/supply_chain/attestations", headers: auth_headers_for(read_only_user), as: :json
      expect_success_response
    end

    it "allows read-only user to view attestation details" do
      get "/api/v1/supply_chain/attestations/#{attestation.id}", headers: auth_headers_for(read_only_user), as: :json
      expect_success_response
    end

    it "allows read-only user to view verification logs" do
      get "/api/v1/supply_chain/attestations/#{attestation.id}/verification_logs", headers: auth_headers_for(read_only_user), as: :json
      expect_success_response
    end

    it "allows read-only user to view statistics" do
      get "/api/v1/supply_chain/attestations/statistics", headers: auth_headers_for(read_only_user), as: :json
      expect_success_response
    end

    it "prevents read-only user from creating attestations" do
      post "/api/v1/supply_chain/attestations",
           params: { subject_name: "test" },
           headers: auth_headers_for(read_only_user),
           as: :json
      expect_error_response("Insufficient permissions to manage supply chain data", 403)
    end

    it "prevents read-only user from updating attestations" do
      patch "/api/v1/supply_chain/attestations/#{attestation.id}",
            params: { attestation: { subject_name: "new" } },
            headers: auth_headers_for(read_only_user),
            as: :json
      expect_error_response("Insufficient permissions to manage supply chain data", 403)
    end

    it "prevents read-only user from deleting attestations" do
      delete "/api/v1/supply_chain/attestations/#{attestation.id}",
             headers: auth_headers_for(read_only_user),
             as: :json
      expect_error_response("Insufficient permissions to manage supply chain data", 403)
    end

    it "prevents read-only user from verifying attestations" do
      post "/api/v1/supply_chain/attestations/#{attestation.id}/verify",
           headers: auth_headers_for(read_only_user),
           as: :json
      expect_error_response("Insufficient permissions to manage supply chain data", 403)
    end

    it "prevents read-only user from signing attestations" do
      post "/api/v1/supply_chain/attestations/#{attestation.id}/sign",
           headers: auth_headers_for(read_only_user),
           as: :json
      expect_error_response("Insufficient permissions to manage supply chain data", 403)
    end

    it "prevents read-only user from recording to Rekor" do
      post "/api/v1/supply_chain/attestations/#{attestation.id}/record_to_rekor",
           headers: auth_headers_for(read_only_user),
           as: :json
      expect_error_response("Insufficient permissions to manage supply chain data", 403)
    end
  end
end
