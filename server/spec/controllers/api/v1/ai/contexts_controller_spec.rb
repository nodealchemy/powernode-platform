# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::Ai::ContextsController", type: :request do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }

  # Users with specific permissions
  let(:read_user) { user_with_permissions('ai.context.read', account: account) }
  let(:create_user) { user_with_permissions('ai.context.read', 'ai.context.create', account: account) }
  let(:update_user) { user_with_permissions('ai.context.read', 'ai.context.update', account: account) }
  let(:delete_user) { user_with_permissions('ai.context.read', 'ai.context.delete', account: account) }
  let(:export_user) { user_with_permissions('ai.context.read', 'ai.context.export', account: account) }
  let(:import_user) { user_with_permissions('ai.context.read', 'ai.context.import', account: account) }
  let(:no_perms_user) { user_without_permissions(account: account) }

  # Test data
  let!(:context_record) { create(:ai_persistent_context, account: account, context_type: "agent_memory") }

  # Stub ContextPersistenceService to avoid deep dependencies
  before do
    # Stub list_contexts with a paginated response mock
    paginated_result = double('PaginatedResult',
      map: [],
      current_page: 1,
      total_pages: 1,
      total_count: 0,
      limit_value: 20
    )
    allow(Ai::ContextPersistenceService).to receive(:list_contexts).and_return(paginated_result)

    # Stub find_context to return our test context
    allow(Ai::ContextPersistenceService).to receive(:find_context).and_return(context_record)
    allow(context_record).to receive(:context_details).and_return({
      id: context_record.id,
      name: context_record.name,
      context_type: context_record.context_type,
      scope: context_record.scope
    })
    allow(context_record).to receive(:context_summary).and_return({
      id: context_record.id,
      name: context_record.name
    })
    allow(context_record).to receive(:unarchive!).and_return(true)

    # Stub context_entries for stats with proper chaining
    where_not_double = double('WhereNotResult', count: 2)
    where_double = double('WhereResult', not: where_not_double, count: 2)
    entries_double = double('Entries',
      count: 5,
      group: double(count: { "fact" => 3, "knowledge" => 2 }),
      sum: 1024,
      average: 0.65,
      where: where_double
    )
    allow(context_record).to receive(:context_entries).and_return(entries_double)

    # Stub create/update/archive/search/export/clone/import
    allow(Ai::ContextPersistenceService).to receive(:create_context).and_return(context_record)
    allow(Ai::ContextPersistenceService).to receive(:update_context).and_return(context_record)
    allow(Ai::ContextPersistenceService).to receive(:archive_context).and_return(true)
    allow(Ai::ContextPersistenceService).to receive(:search).and_return([])
    allow(Ai::ContextPersistenceService).to receive(:export_context).and_return('{"data": []}')
    allow(Ai::ContextPersistenceService).to receive(:clone_context).and_return(context_record)
    allow(Ai::ContextPersistenceService).to receive(:import_context).and_return(context_record)
  end

  # =========================================================================
  # INDEX (GET /api/v1/ai/contexts)
  # =========================================================================
  describe "GET /api/v1/ai/contexts" do
    let(:path) { "/api/v1/ai/contexts" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.context.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.context.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['contexts']).to be_an(Array)
    end
  end

  # =========================================================================
  # SHOW (GET /api/v1/ai/contexts/:id)
  # =========================================================================
  describe "GET /api/v1/ai/contexts/:id" do
    let(:path) { "/api/v1/ai/contexts/#{context_record.id}" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.context.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.context.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['context']).to be_a(Hash)
    end
  end

  # =========================================================================
  # CREATE (POST /api/v1/ai/contexts)
  # =========================================================================
  describe "POST /api/v1/ai/contexts" do
    let(:path) { "/api/v1/ai/contexts" }
    let(:valid_params) do
      { context: { name: "Test Context", context_type: "agent", scope: "account" } }
    end

    it 'returns 401 when unauthenticated' do
      post path, params: valid_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.context.create permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.context.create permission' do
      post path, params: valid_params.to_json, headers: auth_headers_for(create_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # UPDATE (PATCH /api/v1/ai/contexts/:id)
  # =========================================================================
  describe "PATCH /api/v1/ai/contexts/:id" do
    let(:path) { "/api/v1/ai/contexts/#{context_record.id}" }
    let(:update_params) do
      { context: { name: "Updated Context" } }
    end

    it 'returns 401 when unauthenticated' do
      patch path, params: update_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.context.update permission' do
      patch path, params: update_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.context.update permission' do
      patch path, params: update_params.to_json, headers: auth_headers_for(update_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # DESTROY (DELETE /api/v1/ai/contexts/:id)
  # =========================================================================
  describe "DELETE /api/v1/ai/contexts/:id" do
    let(:path) { "/api/v1/ai/contexts/#{context_record.id}" }

    it 'returns 401 when unauthenticated' do
      delete path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.context.delete permission' do
      delete path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.context.delete permission' do
      allow(context_record).to receive(:destroy!).and_return(true)
      delete path, headers: auth_headers_for(delete_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # SEARCH (POST /api/v1/ai/contexts/:id/search)
  # =========================================================================
  describe "POST /api/v1/ai/contexts/:id/search" do
    let(:path) { "/api/v1/ai/contexts/#{context_record.id}/search" }

    it 'returns 401 when unauthenticated' do
      post path, params: { q: "test" }.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.context.read permission' do
      post path, params: { q: "test" }.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.context.read permission' do
      post path, params: { q: "test" }.to_json, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['results']).to be_an(Array)
    end
  end

  # =========================================================================
  # ARCHIVE (POST /api/v1/ai/contexts/:id/archive)
  # =========================================================================
  describe "POST /api/v1/ai/contexts/:id/archive" do
    let(:path) { "/api/v1/ai/contexts/#{context_record.id}/archive" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.context.update permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.context.update permission' do
      post path, headers: auth_headers_for(update_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # UNARCHIVE (POST /api/v1/ai/contexts/:id/unarchive)
  # =========================================================================
  describe "POST /api/v1/ai/contexts/:id/unarchive" do
    let(:path) { "/api/v1/ai/contexts/#{context_record.id}/unarchive" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.context.update permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.context.update permission' do
      post path, headers: auth_headers_for(update_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # EXPORT (GET /api/v1/ai/contexts/:id/export)
  # =========================================================================
  describe "GET /api/v1/ai/contexts/:id/export" do
    let(:path) { "/api/v1/ai/contexts/#{context_record.id}/export" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.context.export permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.context.export permission' do
      get path, headers: auth_headers_for(export_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # CLONE (POST /api/v1/ai/contexts/:id/clone)
  # =========================================================================
  describe "POST /api/v1/ai/contexts/:id/clone" do
    let(:path) { "/api/v1/ai/contexts/#{context_record.id}/clone" }

    it 'returns 401 when unauthenticated' do
      post path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.context.create permission' do
      post path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.context.create permission' do
      post path, headers: auth_headers_for(create_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # IMPORT (POST /api/v1/ai/contexts/import)
  # =========================================================================
  describe "POST /api/v1/ai/contexts/import" do
    let(:path) { "/api/v1/ai/contexts/import" }
    let(:import_params) { { data: '{"name":"imported"}' } }

    it 'returns 401 when unauthenticated' do
      post path, params: import_params.to_json, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.context.import permission' do
      post path, params: import_params.to_json, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'does not return 403 when user has ai.context.import permission' do
      post path, params: import_params.to_json, headers: auth_headers_for(import_user)
      expect(response).not_to have_http_status(:forbidden)
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  # =========================================================================
  # STATS (GET /api/v1/ai/contexts/:id/stats)
  # =========================================================================
  describe "GET /api/v1/ai/contexts/:id/stats" do
    let(:path) { "/api/v1/ai/contexts/#{context_record.id}/stats" }

    it 'returns 401 when unauthenticated' do
      get path, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 when user lacks ai.context.read permission' do
      get path, headers: auth_headers_for(no_perms_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns success when user has ai.context.read permission' do
      get path, headers: auth_headers_for(read_user)
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to eq(true)
      expect(json_response_data['stats']).to be_a(Hash)
    end
  end
end
