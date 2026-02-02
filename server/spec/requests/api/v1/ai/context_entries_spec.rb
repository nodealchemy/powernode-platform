# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::ContextEntries', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'ai.context.read', 'ai.context.create', 'ai.context.update', 'ai.context.delete' ]) }
  let(:read_only_user) { create(:user, account: account, permissions: [ 'ai.context.read' ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }
  let(:headers) { auth_headers_for(user) }

  # Helper to create persistent context
  let(:create_context) do
    ->(attrs = {}) {
      Ai::PersistentContext.create!({
        account: account,
        name: "Test Context #{SecureRandom.hex(4)}",
        context_type: 'shared_context',
        scope: 'account',
        version: 1,
        context_data: {},
        created_by_user: user
      }.merge(attrs))
    }
  end

  # Helper to create context entry
  let(:create_entry) do
    ->(ctx, attrs = {}) {
      ctx.context_entries.create!({
        entry_key: "test_key_#{SecureRandom.hex(4)}",
        entry_type: 'memory',
        content: { data: 'test value' },
        content_text: 'test value',
        importance_score: 0.8,
        version: 1
      }.merge(attrs))
    }
  end

  let(:persistent_context) { create_context.call }

  describe 'GET /api/v1/ai/contexts/:context_id/entries' do
    let(:headers) { auth_headers_for(user) }

    before do
      3.times { create_entry.call(persistent_context) }
    end

    context 'with ai.context.read permission' do
      it 'returns list of context entries' do
        get "/api/v1/ai/contexts/#{persistent_context.id}/entries", headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to have_key('entries')
        expect(data).to have_key('pagination')
      end

      it 'includes pagination metadata' do
        get "/api/v1/ai/contexts/#{persistent_context.id}/entries", headers: headers

        data = json_response_data
        expect(data['pagination']).to include('current_page', 'total_count', 'total_pages')
      end

      it 'accepts filter parameters via query string' do
        create_entry.call(persistent_context, entry_type: 'fact', importance_score: 0.9)

        get "/api/v1/ai/contexts/#{persistent_context.id}/entries?type=fact&high_importance=true", headers: headers

        expect_success_response
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        get "/api/v1/ai/contexts/#{persistent_context.id}/entries",
            headers: auth_headers_for(regular_user)

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/ai/contexts/#{persistent_context.id}/entries"

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/ai/contexts/:context_id/entries/:id' do
    let(:entry) { create_entry.call(persistent_context, entry_key: 'show_test_key') }

    context 'with permission' do
      it 'returns entry details' do
        get "/api/v1/ai/contexts/#{persistent_context.id}/entries/#{entry.id}",
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to have_key('entry')
        expect(data['entry']['entry_key']).to eq('show_test_key')
      end

      it 'can find entry by key' do
        get "/api/v1/ai/contexts/#{persistent_context.id}/entries/#{entry.entry_key}",
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['entry']['id']).to eq(entry.id)
      end
    end

    context 'when entry not found' do
      it 'returns not found error' do
        get "/api/v1/ai/contexts/#{persistent_context.id}/entries/nonexistent",
            headers: headers

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/ai/contexts/:context_id/entries' do
    context 'with ai.context.create permission' do
      let(:valid_params) do
        {
          entry: {
            key: 'new_key',
            type: 'memory',
            content_text: 'New value',
            content: { data: 'new value' }
          }
        }
      end

      it 'creates a new entry' do
        expect {
          post "/api/v1/ai/contexts/#{persistent_context.id}/entries",
               params: valid_params,
               headers: headers,
               as: :json
        }.to change { persistent_context.context_entries.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data).to have_key('entry')
      end
    end

    context 'with validation error' do
      it 'returns validation error for invalid data' do
        post "/api/v1/ai/contexts/#{persistent_context.id}/entries",
             params: { entry: { key: '', type: 'memory' } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        post "/api/v1/ai/contexts/#{persistent_context.id}/entries",
             params: { entry: { key: 'test', type: 'memory', content: {} } },
             headers: auth_headers_for(read_only_user),
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PATCH /api/v1/ai/contexts/:context_id/entries/:id' do
    let(:entry) { create_entry.call(persistent_context) }

    context 'with ai.context.update permission' do
      it 'updates the entry' do
        patch "/api/v1/ai/contexts/#{persistent_context.id}/entries/#{entry.id}?create_version=false",
              params: {
                entry: {
                  content_text: 'Updated value',
                  content: { data: 'updated value' }
                }
              },
              headers: headers,
              as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('entry')
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        patch "/api/v1/ai/contexts/#{persistent_context.id}/entries/#{entry.id}",
              params: { entry: { content_text: 'Updated' } },
              headers: auth_headers_for(read_only_user),
              as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'DELETE /api/v1/ai/contexts/:context_id/entries/:id' do
    let!(:entry) { create_entry.call(persistent_context) }

    context 'with ai.context.delete permission' do
      it 'deletes the entry' do
        delete "/api/v1/ai/contexts/#{persistent_context.id}/entries/#{entry.id}",
               headers: headers

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('Entry deleted')
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        delete "/api/v1/ai/contexts/#{persistent_context.id}/entries/#{entry.id}",
               headers: auth_headers_for(read_only_user)

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/ai/contexts/:context_id/entries/:id/archive' do
    let(:entry) { create_entry.call(persistent_context) }

    context 'with permission' do
      it 'archives the entry' do
        post "/api/v1/ai/contexts/#{persistent_context.id}/entries/#{entry.id}/archive",
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to have_key('entry')

        entry.reload
        expect(entry.archived_at).not_to be_nil
      end
    end
  end

  describe 'POST /api/v1/ai/contexts/:context_id/entries/:id/unarchive' do
    let(:entry) { create_entry.call(persistent_context, archived_at: Time.current) }

    context 'with permission' do
      it 'unarchives the entry' do
        post "/api/v1/ai/contexts/#{persistent_context.id}/entries/#{entry.id}/unarchive",
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to have_key('entry')

        entry.reload
        expect(entry.archived_at).to be_nil
      end
    end
  end

  describe 'POST /api/v1/ai/contexts/:context_id/entries/:id/boost' do
    let(:entry) { create_entry.call(persistent_context, importance_score: 0.5) }

    context 'with permission' do
      it 'boosts entry importance' do
        post "/api/v1/ai/contexts/#{persistent_context.id}/entries/#{entry.id}/boost?amount=0.1",
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to have_key('entry')

        entry.reload
        expect(entry.importance_score).to be >= 0.6
      end
    end
  end

  describe 'GET /api/v1/ai/contexts/:context_id/entries/:id/history' do
    let(:entry) { create_entry.call(persistent_context) }

    context 'with permission' do
      it 'returns entry version history' do
        get "/api/v1/ai/contexts/#{persistent_context.id}/entries/#{entry.id}/history",
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to have_key('current_version')
        expect(data).to have_key('versions')
      end
    end
  end

  describe 'POST /api/v1/ai/contexts/:context_id/entries/bulk' do
    context 'with permission' do
      it 'creates multiple entries' do
        post "/api/v1/ai/contexts/#{persistent_context.id}/entries/bulk",
             params: {
               entries: [
                 { key: 'bulk_key1', type: 'memory', content_text: 'value1', content: { data: 'v1' } },
                 { key: 'bulk_key2', type: 'memory', content_text: 'value2', content: { data: 'v2' } }
               ]
             },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('created')
        expect(data).to have_key('errors')
        expect(data).to have_key('total')
      end
    end
  end
end
