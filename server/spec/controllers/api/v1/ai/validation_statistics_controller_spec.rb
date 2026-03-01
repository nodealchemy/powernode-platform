# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::ValidationStatisticsController", type: :request do
  let(:account) { create(:account) }
  let(:read_user) { user_with_permissions('ai.workflows.read', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # =========================================================================
  # SHOW (GET /api/v1/ai/validation_statistics)
  # =========================================================================
  describe "GET /api/v1/ai/validation_statistics" do
    let(:path) { "/api/v1/ai/validation_statistics" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.workflows.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['statistics']).to be_a(Hash)
      expect(json_response_data['time_range']).to be_a(Hash)
    end

    it 'supports time_range parameter' do
      get path, params: { time_range: '7d' }, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response_data['time_range']['period']).to eq('7d')
    end
  end

  # =========================================================================
  # COMMON ISSUES (GET /api/v1/ai/validation_statistics/common_issues)
  # =========================================================================
  describe "GET /api/v1/ai/validation_statistics/common_issues" do
    let(:path) { "/api/v1/ai/validation_statistics/common_issues" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.workflows.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['common_issues']).to be_an(Array)
    end
  end

  # =========================================================================
  # HEALTH DISTRIBUTION (GET /api/v1/ai/validation_statistics/health_distribution)
  # =========================================================================
  describe "GET /api/v1/ai/validation_statistics/health_distribution" do
    let(:path) { "/api/v1/ai/validation_statistics/health_distribution" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.workflows.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.workflows.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['distribution']).to be_a(Hash)
    end
  end
end
