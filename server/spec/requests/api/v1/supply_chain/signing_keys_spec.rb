# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::SupplyChain::SigningKeys", type: :request do
  let!(:account) { create(:account) }
  let!(:other_account) { create(:account) }

  # User with supply_chain.read permission only
  let!(:read_only_user) do
    create(:user, account: account, permissions: ["supply_chain.read"])
  end

  # User with both read and write permissions
  let!(:read_write_user) do
    create(:user, account: account, permissions: ["supply_chain.read", "supply_chain.write"])
  end

  # User without supply chain permissions
  let!(:regular_user) do
    create(:user, account: account, permissions: [])
  end

  before(:each) do
    Rails.cache.clear
  end

  describe "GET /api/v1/supply_chain/signing_keys" do
    context "with supply_chain.read permission" do
      let!(:signing_keys) do
        [
          create(:supply_chain_signing_key, account: account, status: "active", key_type: "cosign"),
          create(:supply_chain_signing_key, account: account, status: "rotated", key_type: "kms_reference", kms_provider: "aws_kms", kms_key_uri: "arn:aws:kms:us-east-1:123456789:key/test"),
          create(:supply_chain_signing_key, account: account, status: "revoked", key_type: "gpg")
        ]
      end

      let!(:other_account_key) do
        create(:supply_chain_signing_key, account: other_account)
      end

      it "returns signing keys for the current account" do
        get "/api/v1/supply_chain/signing_keys", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        data = json_response["data"]["signing_keys"]

        expect(data.length).to eq(3)
        expect(data.map { |k| k["id"] }).to match_array(signing_keys.map(&:id))
        expect(data.map { |k| k["id"] }).not_to include(other_account_key.id)
      end

      it "returns signing keys ordered by created_at desc" do
        get "/api/v1/supply_chain/signing_keys", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        data = json_response["data"]["signing_keys"]

        created_ats = data.map { |k| Time.parse(k["created_at"]) }
        expect(created_ats).to eq(created_ats.sort.reverse)
      end

      it "returns signing key data with correct structure" do
        get "/api/v1/supply_chain/signing_keys", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        key_data = json_response["data"]["signing_keys"].first

        expect(key_data).to include(
          "id",
          "key_id",
          "name",
          "description",
          "key_type",
          "fingerprint",
          "status",
          "kms_provider",
          "created_at",
          "expires_at",
          "rotated_at"
        )
      end

      it "filters by status" do
        get "/api/v1/supply_chain/signing_keys?status=active", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        data = json_response["data"]["signing_keys"]

        expect(data.length).to eq(1)
        expect(data.first["status"]).to eq("active")
      end

      it "filters by key_type" do
        get "/api/v1/supply_chain/signing_keys?key_type=cosign", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        data = json_response["data"]["signing_keys"]

        expect(data.length).to eq(1)
        expect(data.first["key_type"]).to eq("cosign")
      end

      it "applies multiple filters simultaneously" do
        get "/api/v1/supply_chain/signing_keys?status=active&key_type=cosign", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        data = json_response["data"]["signing_keys"]

        expect(data.length).to eq(1)
        expect(data.first["status"]).to eq("active")
        expect(data.first["key_type"]).to eq("cosign")
      end
    end

    context "pagination" do
      before do
        25.times do
          create(:supply_chain_signing_key, account: account)
        end
      end

      it "returns paginated results with default per_page of 20" do
        get "/api/v1/supply_chain/signing_keys", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        expect(json_response["data"]["signing_keys"].length).to eq(20)
        expect(json_response["meta"]["total_count"]).to eq(25)
        expect(json_response["meta"]["current_page"]).to eq(1)
        expect(json_response["meta"]["per_page"]).to eq(20)
      end

      it "respects page parameter" do
        get "/api/v1/supply_chain/signing_keys?page=2", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        expect(json_response["data"]["signing_keys"].length).to eq(5)
        expect(json_response["meta"]["current_page"]).to eq(2)
      end

      it "respects per_page parameter" do
        get "/api/v1/supply_chain/signing_keys?per_page=10", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        expect(json_response["data"]["signing_keys"].length).to eq(10)
        expect(json_response["meta"]["per_page"]).to eq(10)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/signing_keys", headers: auth_headers_for(regular_user), as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end

    context "without authentication" do
      it "returns unauthorized error" do
        get "/api/v1/supply_chain/signing_keys", as: :json

        expect_error_response("Access token required", 401)
      end
    end
  end

  describe "GET /api/v1/supply_chain/signing_keys/:id" do
    let!(:signing_key) { create(:supply_chain_signing_key, account: account) }
    let!(:attestation1) { create(:supply_chain_attestation, account: account, signing_key: signing_key) }
    let!(:attestation2) { create(:supply_chain_attestation, account: account, signing_key: signing_key) }

    context "with supply_chain.read permission" do
      it "returns the signing key with detailed information" do
        get "/api/v1/supply_chain/signing_keys/#{signing_key.id}", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        data = json_response["data"]["signing_key"]

        expect(data["id"]).to eq(signing_key.id)
        expect(data["key_id"]).to eq(signing_key.key_id)
        expect(data["name"]).to eq(signing_key.name)
        expect(data["key_type"]).to eq(signing_key.key_type)
        expect(data["status"]).to eq(signing_key.status)
      end

      it "includes public key in detailed view" do
        get "/api/v1/supply_chain/signing_keys/#{signing_key.id}", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        data = json_response["data"]["signing_key"]

        expect(data["public_key"]).to eq(signing_key.public_key)
      end

      it "includes attestation count in detailed view" do
        get "/api/v1/supply_chain/signing_keys/#{signing_key.id}", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        data = json_response["data"]["signing_key"]

        expect(data["attestation_count"]).to eq(2)
      end

      it "includes metadata in detailed view" do
        get "/api/v1/supply_chain/signing_keys/#{signing_key.id}", headers: auth_headers_for(read_only_user), as: :json

        expect_success_response
        data = json_response["data"]["signing_key"]

        expect(data).to have_key("metadata")
      end
    end

    context "with signing key from another account" do
      let(:other_key) { create(:supply_chain_signing_key, account: other_account) }

      it "returns not found error" do
        get "/api/v1/supply_chain/signing_keys/#{other_key.id}", headers: auth_headers_for(read_only_user), as: :json

        expect_error_response("Signing key not found", 404)
      end
    end

    context "with non-existent signing key" do
      it "returns not found error" do
        get "/api/v1/supply_chain/signing_keys/non-existent-id", headers: auth_headers_for(read_only_user), as: :json

        expect_error_response("Signing key not found", 404)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/signing_keys/#{signing_key.id}", headers: auth_headers_for(regular_user), as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/signing_keys" do
    context "with supply_chain.write permission" do
      let(:valid_params) do
        {
          signing_key: {
            name: "Production Signing Key",
            description: "Key for signing production artifacts",
            key_type: "cosign",
            public_key: "-----BEGIN PUBLIC KEY-----\nMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEtest123\n-----END PUBLIC KEY-----",
            expires_at: 1.year.from_now.iso8601
          }
        }
      end

      it "creates a new signing key with valid parameters" do
        expect do
          post "/api/v1/supply_chain/signing_keys",
               params: valid_params,
               headers: auth_headers_for(read_write_user),
               as: :json
        end.to change(SupplyChain::SigningKey, :count).by(1)

        expect(response).to have_http_status(:created)
        expect_success_response

        data = json_response["data"]["signing_key"]
        expect(data["name"]).to eq("Production Signing Key")
        expect(data["key_type"]).to eq("cosign")
        expect(data["fingerprint"]).to be_present
      end

      it "creates a KMS signing key with required fields" do
        kms_params = {
          signing_key: {
            name: "KMS Signing Key",
            key_type: "kms_reference",
            public_key: "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtest\n-----END PUBLIC KEY-----",
            kms_provider: "aws_kms",
            kms_key_uri: "arn:aws:kms:us-east-1:123456789:key/test-key-id"
          }
        }

        post "/api/v1/supply_chain/signing_keys",
             params: kms_params,
             headers: auth_headers_for(read_write_user),
             as: :json

        expect(response).to have_http_status(:created)
        expect_success_response

        data = json_response["data"]["signing_key"]
        expect(data["key_type"]).to eq("kms_reference")
        expect(data["kms_provider"]).to eq("aws_kms")
      end

      it "creates an OIDC identity key" do
        oidc_params = {
          signing_key: {
            name: "OIDC Signing Key",
            key_type: "oidc_identity",
            public_key: "-----BEGIN PUBLIC KEY-----\nMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEoidc123\n-----END PUBLIC KEY-----"
          }
        }

        post "/api/v1/supply_chain/signing_keys",
             params: oidc_params,
             headers: auth_headers_for(read_write_user),
             as: :json

        expect(response).to have_http_status(:created)
        expect_success_response
      end

      it "includes metadata in created key" do
        params_with_metadata = valid_params.deep_merge(
          signing_key: {
            metadata: {
              environment: "production",
              owner: "security-team"
            }
          }
        )

        post "/api/v1/supply_chain/signing_keys",
             params: params_with_metadata,
             headers: auth_headers_for(read_write_user),
             as: :json

        expect(response).to have_http_status(:created)
        expect_success_response

        created_key = SupplyChain::SigningKey.last
        expect(created_key.metadata["environment"]).to eq("production")
      end

      it "returns validation error with missing required fields" do
        invalid_params = {
          signing_key: {
            name: ""
          }
        }

        post "/api/v1/supply_chain/signing_keys",
             params: invalid_params,
             headers: auth_headers_for(read_write_user),
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
        expect(json_response["error"]).to be_present
      end

      it "returns validation error for KMS key without required fields" do
        invalid_kms_params = {
          signing_key: {
            name: "Invalid KMS Key",
            key_type: "kms_reference",
            public_key: "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAtest\n-----END PUBLIC KEY-----"
            # Missing kms_provider and kms_key_uri
          }
        }

        post "/api/v1/supply_chain/signing_keys",
             params: invalid_kms_params,
             headers: auth_headers_for(read_write_user),
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response["success"]).to be false
        expect(json_response["error"]).to be_present
      end
    end

    context "without supply_chain.write permission" do
      let(:valid_params) do
        {
          signing_key: {
            name: "Test Key",
            key_type: "cosign",
            public_key: "-----BEGIN PUBLIC KEY-----\nMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEtest\n-----END PUBLIC KEY-----"
          }
        }
      end

      it "returns forbidden error for read-only user" do
        post "/api/v1/supply_chain/signing_keys",
             params: valid_params,
             headers: auth_headers_for(read_only_user),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end

      it "returns forbidden error for regular user" do
        post "/api/v1/supply_chain/signing_keys",
             params: valid_params,
             headers: auth_headers_for(regular_user),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "PATCH /api/v1/supply_chain/signing_keys/:id" do
    let(:signing_key) { create(:supply_chain_signing_key, account: account, name: "Original Name") }

    context "with supply_chain.write permission" do
      it "updates the signing key name" do
        patch "/api/v1/supply_chain/signing_keys/#{signing_key.id}",
              params: { signing_key: { name: "Updated Name" } },
              headers: auth_headers_for(read_write_user),
              as: :json

        expect_success_response
        expect(json_response["data"]["signing_key"]["name"]).to eq("Updated Name")

        signing_key.reload
        expect(signing_key.name).to eq("Updated Name")
      end

      it "updates the description" do
        patch "/api/v1/supply_chain/signing_keys/#{signing_key.id}",
              params: { signing_key: { description: "Updated description" } },
              headers: auth_headers_for(read_write_user),
              as: :json

        expect_success_response
        expect(json_response["data"]["signing_key"]["description"]).to eq("Updated description")
      end

      it "updates the expires_at date" do
        new_expiry = 2.years.from_now
        patch "/api/v1/supply_chain/signing_keys/#{signing_key.id}",
              params: { signing_key: { expires_at: new_expiry.iso8601 } },
              headers: auth_headers_for(read_write_user),
              as: :json

        expect_success_response
        signing_key.reload
        expect(signing_key.expires_at).to be_within(1.second).of(new_expiry)
      end

      it "updates metadata" do
        patch "/api/v1/supply_chain/signing_keys/#{signing_key.id}",
              params: { signing_key: { metadata: { updated: true } } },
              headers: auth_headers_for(read_write_user),
              as: :json

        expect_success_response
        signing_key.reload
        expect(signing_key.metadata["updated"]).to be true
      end

      it "does not allow updating key_type" do
        patch "/api/v1/supply_chain/signing_keys/#{signing_key.id}",
              params: { signing_key: { key_type: "gpg" } },
              headers: auth_headers_for(read_write_user),
              as: :json

        expect_success_response
        signing_key.reload
        expect(signing_key.key_type).not_to eq("gpg")
      end

      it "returns validation error with invalid parameters" do
        patch "/api/v1/supply_chain/signing_keys/#{signing_key.id}",
              params: { signing_key: { name: "" } },
              headers: auth_headers_for(read_write_user),
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "with signing key from another account" do
      let(:other_key) { create(:supply_chain_signing_key, account: other_account) }

      it "returns not found error" do
        patch "/api/v1/supply_chain/signing_keys/#{other_key.id}",
              params: { signing_key: { name: "Hacked" } },
              headers: auth_headers_for(read_write_user),
              as: :json

        expect_error_response("Signing key not found", 404)
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        patch "/api/v1/supply_chain/signing_keys/#{signing_key.id}",
              params: { signing_key: { name: "New Name" } },
              headers: auth_headers_for(read_only_user),
              as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "DELETE /api/v1/supply_chain/signing_keys/:id" do
    context "with supply_chain.write permission" do
      it "deletes a signing key without attestations" do
        signing_key = create(:supply_chain_signing_key, account: account)

        expect do
          delete "/api/v1/supply_chain/signing_keys/#{signing_key.id}",
                 headers: auth_headers_for(read_write_user),
                 as: :json
        end.to change(SupplyChain::SigningKey, :count).by(-1)

        expect_success_response
        expect(json_response["data"]["message"]).to eq("Signing key deleted")
      end

      it "prevents deletion of a signing key with existing attestations" do
        signing_key = create(:supply_chain_signing_key, account: account)
        create(:supply_chain_attestation, account: account, signing_key: signing_key)

        expect do
          delete "/api/v1/supply_chain/signing_keys/#{signing_key.id}",
                 headers: auth_headers_for(read_write_user),
                 as: :json
        end.not_to change(SupplyChain::SigningKey, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect_error_response("Cannot delete signing key with existing attestations", 422)
      end

      it "allows deletion after attestations are removed" do
        signing_key = create(:supply_chain_signing_key, account: account)
        attestation = create(:supply_chain_attestation, account: account, signing_key: signing_key)
        attestation.destroy

        expect do
          delete "/api/v1/supply_chain/signing_keys/#{signing_key.id}",
                 headers: auth_headers_for(read_write_user),
                 as: :json
        end.to change(SupplyChain::SigningKey, :count).by(-1)

        expect_success_response
      end
    end

    context "with signing key from another account" do
      let(:other_key) { create(:supply_chain_signing_key, account: other_account) }

      it "returns not found error" do
        delete "/api/v1/supply_chain/signing_keys/#{other_key.id}",
               headers: auth_headers_for(read_write_user),
               as: :json

        expect_error_response("Signing key not found", 404)
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        signing_key = create(:supply_chain_signing_key, account: account)

        delete "/api/v1/supply_chain/signing_keys/#{signing_key.id}",
               headers: auth_headers_for(read_only_user),
               as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/signing_keys/:id/rotate" do
    let(:signing_key) { create(:supply_chain_signing_key, account: account, status: "active") }

    context "with supply_chain.write permission" do
      it "rotates the signing key successfully" do
        # Mock the rotate! method to return a new key
        new_key = create(:supply_chain_signing_key, account: account, status: "active")
        allow_any_instance_of(SupplyChain::SigningKey).to receive(:rotate!).and_return(new_key)

        post "/api/v1/supply_chain/signing_keys/#{signing_key.id}/rotate",
             headers: auth_headers_for(read_write_user),
             as: :json

        expect_success_response
        data = json_response["data"]

        expect(data).to have_key("old_key")
        expect(data).to have_key("new_key")
      end

      it "returns old key with rotated status" do
        new_key = create(:supply_chain_signing_key, account: account, status: "active")
        allow_any_instance_of(SupplyChain::SigningKey).to receive(:rotate!).and_return(new_key)

        post "/api/v1/supply_chain/signing_keys/#{signing_key.id}/rotate",
             headers: auth_headers_for(read_write_user),
             as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["old_key"]).to be_present
        expect(data["new_key"]).to be_present
        expect(data["new_key"]["id"]).not_to eq(data["old_key"]["id"])
      end

      it "handles rotation errors gracefully" do
        allow_any_instance_of(SupplyChain::SigningKey).to receive(:rotate!).and_raise(StandardError.new("Rotation failed"))

        post "/api/v1/supply_chain/signing_keys/#{signing_key.id}/rotate",
             headers: auth_headers_for(read_write_user),
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect_error_response("Failed to rotate key: Rotation failed", 422)
      end
    end

    context "with signing key from another account" do
      let(:other_key) { create(:supply_chain_signing_key, account: other_account) }

      it "returns not found error" do
        post "/api/v1/supply_chain/signing_keys/#{other_key.id}/rotate",
             headers: auth_headers_for(read_write_user),
             as: :json

        expect_error_response("Signing key not found", 404)
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/signing_keys/#{signing_key.id}/rotate",
             headers: auth_headers_for(read_only_user),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "POST /api/v1/supply_chain/signing_keys/:id/revoke" do
    let(:signing_key) { create(:supply_chain_signing_key, account: account, status: "active") }

    context "with supply_chain.write permission" do
      it "revokes the signing key successfully" do
        post "/api/v1/supply_chain/signing_keys/#{signing_key.id}/revoke",
             headers: auth_headers_for(read_write_user),
             as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["signing_key"]).to be_present

        signing_key.reload
        expect(signing_key.status).to eq("revoked")
      end

      it "revokes with a custom reason" do
        post "/api/v1/supply_chain/signing_keys/#{signing_key.id}/revoke",
             params: { reason: "Security incident" },
             headers: auth_headers_for(read_write_user),
             as: :json

        expect_success_response
        signing_key.reload
        expect(signing_key.status).to eq("revoked")
      end

      it "uses default reason when none provided" do
        post "/api/v1/supply_chain/signing_keys/#{signing_key.id}/revoke",
             headers: auth_headers_for(read_write_user),
             as: :json

        expect_success_response
        signing_key.reload
        expect(signing_key.status).to eq("revoked")
      end

      it "handles revocation errors gracefully" do
        allow_any_instance_of(SupplyChain::SigningKey).to receive(:revoke!).and_raise(StandardError.new("Revocation failed"))

        post "/api/v1/supply_chain/signing_keys/#{signing_key.id}/revoke",
             headers: auth_headers_for(read_write_user),
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect_error_response("Failed to revoke key: Revocation failed", 422)
      end
    end

    context "with signing key from another account" do
      let(:other_key) { create(:supply_chain_signing_key, account: other_account) }

      it "returns not found error" do
        post "/api/v1/supply_chain/signing_keys/#{other_key.id}/revoke",
             headers: auth_headers_for(read_write_user),
             as: :json

        expect_error_response("Signing key not found", 404)
      end
    end

    context "without supply_chain.write permission" do
      it "returns forbidden error" do
        post "/api/v1/supply_chain/signing_keys/#{signing_key.id}/revoke",
             headers: auth_headers_for(read_only_user),
             as: :json

        expect_error_response("Insufficient permissions to manage supply chain data", 403)
      end
    end
  end

  describe "GET /api/v1/supply_chain/signing_keys/:id/public_key" do
    let(:signing_key) { create(:supply_chain_signing_key, account: account) }

    context "with supply_chain.read permission" do
      it "returns the public key details" do
        get "/api/v1/supply_chain/signing_keys/#{signing_key.id}/public_key",
            headers: auth_headers_for(read_only_user),
            as: :json

        expect_success_response
        data = json_response["data"]

        expect(data["key_id"]).to eq(signing_key.key_id)
        expect(data["public_key"]).to eq(signing_key.public_key)
        expect(data["key_type"]).to eq(signing_key.key_type)
        expect(data["fingerprint"]).to eq(signing_key.fingerprint)
      end

      it "does not include private key information" do
        get "/api/v1/supply_chain/signing_keys/#{signing_key.id}/public_key",
            headers: auth_headers_for(read_only_user),
            as: :json

        expect_success_response
        data = json_response["data"]

        expect(data).not_to have_key("private_key")
        expect(data).not_to have_key("encrypted_private_key")
      end
    end

    context "with signing key from another account" do
      let(:other_key) { create(:supply_chain_signing_key, account: other_account) }

      it "returns not found error" do
        get "/api/v1/supply_chain/signing_keys/#{other_key.id}/public_key",
            headers: auth_headers_for(read_only_user),
            as: :json

        expect_error_response("Signing key not found", 404)
      end
    end

    context "without supply_chain.read permission" do
      it "returns forbidden error" do
        get "/api/v1/supply_chain/signing_keys/#{signing_key.id}/public_key",
            headers: auth_headers_for(regular_user),
            as: :json

        expect_error_response("Insufficient permissions to view supply chain data", 403)
      end
    end
  end

  describe "account isolation" do
    let!(:account_key) { create(:supply_chain_signing_key, account: account) }
    let!(:other_key) { create(:supply_chain_signing_key, account: other_account) }

    it "only returns signing keys for the authenticated user account" do
      get "/api/v1/supply_chain/signing_keys", headers: auth_headers_for(read_only_user), as: :json

      expect_success_response
      key_ids = json_response["data"]["signing_keys"].map { |k| k["id"] }

      expect(key_ids).to include(account_key.id)
      expect(key_ids).not_to include(other_key.id)
    end

    it "prevents accessing another account signing key directly" do
      get "/api/v1/supply_chain/signing_keys/#{other_key.id}", headers: auth_headers_for(read_only_user), as: :json

      expect_error_response("Signing key not found", 404)
    end

    it "prevents modifying another account signing key" do
      patch "/api/v1/supply_chain/signing_keys/#{other_key.id}",
            params: { signing_key: { name: "Hacked" } },
            headers: auth_headers_for(read_write_user),
            as: :json

      expect_error_response("Signing key not found", 404)
    end

    it "prevents deleting another account signing key" do
      delete "/api/v1/supply_chain/signing_keys/#{other_key.id}",
             headers: auth_headers_for(read_write_user),
             as: :json

      expect_error_response("Signing key not found", 404)
    end

    it "prevents rotating another account signing key" do
      post "/api/v1/supply_chain/signing_keys/#{other_key.id}/rotate",
           headers: auth_headers_for(read_write_user),
           as: :json

      expect_error_response("Signing key not found", 404)
    end

    it "prevents revoking another account signing key" do
      post "/api/v1/supply_chain/signing_keys/#{other_key.id}/revoke",
           headers: auth_headers_for(read_write_user),
           as: :json

      expect_error_response("Signing key not found", 404)
    end

    it "prevents accessing another account public key" do
      get "/api/v1/supply_chain/signing_keys/#{other_key.id}/public_key",
          headers: auth_headers_for(read_only_user),
          as: :json

      expect_error_response("Signing key not found", 404)
    end
  end

  describe "permission enforcement" do
    let!(:signing_key) { create(:supply_chain_signing_key, account: account) }

    it "allows read-only user to view signing keys" do
      get "/api/v1/supply_chain/signing_keys", headers: auth_headers_for(read_only_user), as: :json
      expect_success_response
    end

    it "allows read-only user to view signing key details" do
      get "/api/v1/supply_chain/signing_keys/#{signing_key.id}", headers: auth_headers_for(read_only_user), as: :json
      expect_success_response
    end

    it "allows read-only user to view public key" do
      get "/api/v1/supply_chain/signing_keys/#{signing_key.id}/public_key", headers: auth_headers_for(read_only_user), as: :json
      expect_success_response
    end

    it "prevents read-only user from creating signing keys" do
      post "/api/v1/supply_chain/signing_keys",
           params: { signing_key: { name: "Test" } },
           headers: auth_headers_for(read_only_user),
           as: :json
      expect_error_response("Insufficient permissions to manage supply chain data", 403)
    end

    it "prevents read-only user from updating signing keys" do
      patch "/api/v1/supply_chain/signing_keys/#{signing_key.id}",
            params: { signing_key: { name: "New Name" } },
            headers: auth_headers_for(read_only_user),
            as: :json
      expect_error_response("Insufficient permissions to manage supply chain data", 403)
    end

    it "prevents read-only user from deleting signing keys" do
      delete "/api/v1/supply_chain/signing_keys/#{signing_key.id}",
             headers: auth_headers_for(read_only_user),
             as: :json
      expect_error_response("Insufficient permissions to manage supply chain data", 403)
    end

    it "prevents read-only user from rotating signing keys" do
      post "/api/v1/supply_chain/signing_keys/#{signing_key.id}/rotate",
           headers: auth_headers_for(read_only_user),
           as: :json
      expect_error_response("Insufficient permissions to manage supply chain data", 403)
    end

    it "prevents read-only user from revoking signing keys" do
      post "/api/v1/supply_chain/signing_keys/#{signing_key.id}/revoke",
           headers: auth_headers_for(read_only_user),
           as: :json
      expect_error_response("Insufficient permissions to manage supply chain data", 403)
    end
  end
end
