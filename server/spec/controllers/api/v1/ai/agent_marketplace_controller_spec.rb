# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::AgentMarketplaceController", type: :request do
  let(:account) { create(:account) }
  let(:base_path) { "/api/v1/ai/agent_marketplace" }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai.marketplace.read', account: account) }
  let(:manage_user) { user_with_permissions('ai.marketplace.manage', account: account) }
  let(:review_user) { user_with_permissions('ai.marketplace.review', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Use a random UUID for template_id in paths — permission checks fire before record lookup
  let(:fake_template_id) { SecureRandom.uuid }

  # =========================================================================
  # TEMPLATES (ai.marketplace.read)
  # =========================================================================
  describe "GET /api/v1/ai/agent_marketplace/templates" do
    let(:path) { "#{base_path}/templates" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.marketplace.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.marketplace.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # FEATURED (ai.marketplace.read)
  # =========================================================================
  describe "GET /api/v1/ai/agent_marketplace/templates/featured" do
    let(:path) { "#{base_path}/templates/featured" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.marketplace.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.marketplace.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # CATEGORIES (ai.marketplace.read)
  # =========================================================================
  describe "GET /api/v1/ai/agent_marketplace/categories" do
    let(:path) { "#{base_path}/categories" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.marketplace.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.marketplace.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # INSTALL (ai.marketplace.manage)
  # =========================================================================
  describe "POST /api/v1/ai/agent_marketplace/templates/:template_id/install" do
    let(:path) { "#{base_path}/templates/#{fake_template_id}/install" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.marketplace.manage permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.marketplace.manage permission' do
      post path, headers: auth_headers_for(manage_user)
      # May return 404 (template not found) but permission check passes
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # UNINSTALL (ai.marketplace.manage)
  # =========================================================================
  describe "DELETE /api/v1/ai/agent_marketplace/installations/:id" do
    let(:path) { "#{base_path}/installations/#{SecureRandom.uuid}" }

    it 'returns 401 when unauthenticated' do
      delete path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.marketplace.manage permission' do
      delete path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.marketplace.manage permission' do
      delete path, headers: auth_headers_for(manage_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # CREATE REVIEW (ai.marketplace.review)
  # =========================================================================
  describe "POST /api/v1/ai/agent_marketplace/templates/:template_id/reviews" do
    let(:path) { "#{base_path}/templates/#{fake_template_id}/reviews" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.marketplace.review permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.marketplace.review permission' do
      post path,
           params: { rating: 5, title: "Great", content: "Works well" }.to_json,
           headers: auth_headers_for(review_user)
      # May return 404 (template not found) but permission check passes
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end
end
