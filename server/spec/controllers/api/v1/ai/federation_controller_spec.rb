# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::FederationController", type: :request do
  let(:account) { create(:account) }
  let(:base_path) { "/api/v1/ai/federation" }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai.federation.read', account: account) }
  let(:create_user) { user_with_permissions('ai.federation.create', account: account) }
  let(:verify_user) { user_with_permissions('ai.federation.verify', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let(:partner) { create(:federation_partner, account: account) }

  # =========================================================================
  # INDEX (ai.federation.read)
  # =========================================================================
  describe "GET /api/v1/ai/federation/partners" do
    let(:path) { "#{base_path}/partners" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.federation.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.federation.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # SHOW (ai.federation.read)
  # =========================================================================
  describe "GET /api/v1/ai/federation/partners/:id" do
    let(:path) { "#{base_path}/partners/#{partner.id}" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.federation.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.federation.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # CREATE (ai.federation.create)
  # =========================================================================
  describe "POST /api/v1/ai/federation/partners" do
    let(:path) { "#{base_path}/partners" }
    let(:valid_params) do
      {
        partner: {
          organization_name: "Test Partner Org",
          organization_id: "org-test-#{SecureRandom.hex(4)}",
          endpoint_url: "https://partner.example.com/a2a"
        }
      }
    end

    it 'returns 401 when unauthenticated' do
      post path, params: valid_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.federation.create permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.federation.create permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(create_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # VERIFY (ai.federation.verify)
  # =========================================================================
  describe "POST /api/v1/ai/federation/partners/:id/verify" do
    let(:path) { "#{base_path}/partners/#{partner.id}/verify" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.federation.verify permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.federation.verify permission' do
      post path, headers: auth_headers_for(verify_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end
end
