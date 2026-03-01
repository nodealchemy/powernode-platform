# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::SandboxTestingController", type: :request do
  let(:account) { create(:account) }

  # Users with specific permissions
  let(:test_user) { user_with_permissions('ai.sandboxes.test', account: account) }
  let(:benchmark_user) { user_with_permissions('ai.sandboxes.benchmark', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let(:sandbox) { create(:ai_sandbox, account: account) }
  let(:base_path) { "/api/v1/ai/sandboxes/#{sandbox.id}" }

  # =========================================================================
  # RUNS (ai.sandboxes.test)
  # =========================================================================
  describe "GET /api/v1/ai/sandboxes/:sandbox_id/runs" do
    let(:path) { "#{base_path}/runs" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.sandboxes.test permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.sandboxes.test permission' do
      get path, headers: auth_headers_for(test_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # SHOW_RUN (ai.sandboxes.test)
  # =========================================================================
  describe "GET /api/v1/ai/sandboxes/:sandbox_id/runs/:run_id" do
    let(:test_run) { create(:ai_test_run, sandbox: sandbox, account: account) }
    let(:path) { "#{base_path}/runs/#{test_run.id}" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.sandboxes.test permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.sandboxes.test permission' do
      get path, headers: auth_headers_for(test_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # CREATE_RUN (ai.sandboxes.test)
  # =========================================================================
  describe "POST /api/v1/ai/sandboxes/:sandbox_id/runs" do
    let(:path) { "#{base_path}/runs" }
    let(:valid_params) do
      { run_type: "manual", scenario_ids: [] }
    end

    it 'returns 401 when unauthenticated' do
      post path, params: valid_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.sandboxes.test permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.sandboxes.test permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(test_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # BENCHMARKS (ai.sandboxes.benchmark)
  # =========================================================================
  describe "GET /api/v1/ai/sandboxes/:sandbox_id/benchmarks" do
    let(:path) { "#{base_path}/benchmarks" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.sandboxes.benchmark permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.sandboxes.benchmark permission' do
      get path, headers: auth_headers_for(benchmark_user)
      expect(response).to have_http_status(:success)
    end
  end

  # =========================================================================
  # CREATE_BENCHMARK (ai.sandboxes.benchmark)
  # =========================================================================
  describe "POST /api/v1/ai/sandboxes/:sandbox_id/benchmarks" do
    let(:path) { "#{base_path}/benchmarks" }
    let(:valid_params) do
      { name: "Test Benchmark", description: "A test benchmark" }
    end

    it 'returns 401 when unauthenticated' do
      post path, params: valid_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.sandboxes.benchmark permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.sandboxes.benchmark permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(benchmark_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end
end
