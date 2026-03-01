# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::SkillsController", type: :request do
  let(:account) { create(:account) }
  let(:base_path) { "/api/v1/ai/skills" }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai.skills.read', account: account) }
  let(:create_user) { user_with_permissions('ai.skills.create', account: account) }
  let(:update_user) { user_with_permissions('ai.skills.update', account: account) }
  let(:delete_user) { user_with_permissions('ai.skills.delete', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let(:skill) { create(:ai_skill, account: account, category: "productivity") }

  # =========================================================================
  # INDEX (ai.skills.read)
  # =========================================================================
  describe "GET /api/v1/ai/skills" do
    let(:path) { base_path }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.skills.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.skills.read permission' do
      skill # create
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # SHOW (ai.skills.read)
  # =========================================================================
  describe "GET /api/v1/ai/skills/:id" do
    let(:path) { "#{base_path}/#{skill.id}" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.skills.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.skills.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # CREATE (ai.skills.create)
  # =========================================================================
  describe "POST /api/v1/ai/skills" do
    let(:path) { base_path }
    let(:valid_params) do
      {
        skill: {
          name: "Test Skill",
          description: "A test skill",
          category: "productivity",
          version: "1.0.0"
        }
      }
    end

    it 'returns 401 when unauthenticated' do
      post path, params: valid_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.skills.create permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.skills.create permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(create_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # UPDATE (ai.skills.update)
  # =========================================================================
  describe "PATCH /api/v1/ai/skills/:id" do
    let(:path) { "#{base_path}/#{skill.id}" }
    let(:update_params) { { skill: { name: "Updated Skill Name" } } }

    it 'returns 401 when unauthenticated' do
      patch path, params: update_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.skills.update permission' do
      patch path, params: update_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.skills.update permission' do
      patch path, params: update_params.to_json, headers: auth_headers_for(update_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # DESTROY (ai.skills.delete)
  # =========================================================================
  describe "DELETE /api/v1/ai/skills/:id" do
    let(:path) { "#{base_path}/#{skill.id}" }

    it 'returns 401 when unauthenticated' do
      delete path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.skills.delete permission' do
      delete path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.skills.delete permission' do
      delete path, headers: auth_headers_for(delete_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # ACTIVATE (ai.skills.update)
  # =========================================================================
  describe "POST /api/v1/ai/skills/:id/activate" do
    let(:disabled_skill) { create(:ai_skill, :disabled, account: account, category: "productivity") }
    let(:path) { "#{base_path}/#{disabled_skill.id}/activate" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.skills.update permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.skills.update permission' do
      post path, headers: auth_headers_for(update_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # DEACTIVATE (ai.skills.update)
  # =========================================================================
  describe "POST /api/v1/ai/skills/:id/deactivate" do
    let(:path) { "#{base_path}/#{skill.id}/deactivate" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.skills.update permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.skills.update permission' do
      post path, headers: auth_headers_for(update_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # AGENTS (ai.skills.read)
  # =========================================================================
  describe "GET /api/v1/ai/skills/:id/agents" do
    let(:path) { "#{base_path}/#{skill.id}/agents" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.skills.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.skills.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # CATEGORIES (ai.skills.read)
  # =========================================================================
  describe "GET /api/v1/ai/skills/categories" do
    let(:path) { "#{base_path}/categories" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.skills.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success with categories when user has ai.skills.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
    end
  end
end
