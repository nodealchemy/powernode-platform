# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::Contexts', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read_permission) { create(:user, account: account, permissions: ['ai.context.read']) }
  let(:user_with_create_permission) { create(:user, account: account, permissions: ['ai.context.read', 'ai.context.create']) }
  let(:user_with_update_permission) { create(:user, account: account, permissions: ['ai.context.read', 'ai.context.update']) }
  let(:user_with_delete_permission) { create(:user, account: account, permissions: ['ai.context.read', 'ai.context.delete']) }
  let(:user_with_export_permission) { create(:user, account: account, permissions: ['ai.context.read', 'ai.context.export']) }
  let(:user_with_import_permission) { create(:user, account: account, permissions: ['ai.context.read', 'ai.context.import']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  # Helper to create AI context
  let(:create_context) do
    ->(attrs = {}) {
      Ai::PersistentContext.create!({
        account: account,
        created_by_user: user_with_read_permission,
        name: "Test Context #{SecureRandom.hex(4)}",
        description: 'A test context',
        context_type: 'knowledge_base',
        scope: 'account',
        version: 1,
        context_data: { data: 'test content' },
        metadata: {}
      }.merge(attrs))
    }
  end

  describe 'GET /api/v1/ai/contexts' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      3.times { create_context.call }
    end

    context 'with ai.context.read permission' do
      it 'returns list of contexts' do
        get '/api/v1/ai/contexts', headers: headers

        expect_success_response
        data = json_response_data

        expect(data['contexts']).to be_an(Array)
        expect(data['contexts'].length).to eq(3)
      end

      it 'includes context details' do
        get '/api/v1/ai/contexts', headers: headers

        data = json_response_data
        first_context = data['contexts'].first

        expect(first_context).to include('id', 'name', 'context_type', 'status')
      end

      it 'includes pagination metadata' do
        get '/api/v1/ai/contexts', headers: headers

        data = json_response_data
        expect(data['pagination']).to include('current_page', 'total_count', 'total_pages')
      end

      it 'filters by type' do
        create_context.call(context_type: 'shared_context')

        get "/api/v1/ai/contexts?type=shared_context", headers: headers

        expect_success_response
        data = json_response_data

        context_types = data['contexts'].map { |c| c['context_type'] }
        expect(context_types.uniq).to eq(['shared_context'])
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/ai/contexts', headers: headers

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/ai/contexts'

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/ai/contexts/:id' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:context_record) { create_context.call }

    context 'with ai.context.read permission' do
      it 'returns context details' do
        get "/api/v1/ai/contexts/#{context_record.id}", headers: headers

        expect_success_response
        data = json_response_data

        expect(data['context']).to include(
          'id' => context_record.id,
          'name' => context_record.name,
          'context_type' => context_record.context_type
        )
      end

      it 'includes content' do
        get "/api/v1/ai/contexts/#{context_record.id}", headers: headers

        data = json_response_data
        expect(data['context']).to have_key('context_data')
      end
    end

    context 'when context does not exist' do
      it 'returns not found error' do
        get '/api/v1/ai/contexts/nonexistent-id', headers: headers

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when accessing other account context' do
      let(:other_account) { create(:account) }
      let(:other_user) { create(:user, account: other_account) }
      let(:other_context) do
        Ai::PersistentContext.create!(
          account: other_account,
          created_by_user: other_user,
          name: 'Other Context',
          context_type: 'knowledge_base',
          scope: 'account',
          version: 1,
          context_data: {}
        )
      end

      it 'returns not found error' do
        get "/api/v1/ai/contexts/#{other_context.id}", headers: headers

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/ai/contexts' do
    let(:headers) { auth_headers_for(user_with_create_permission) }

    context 'with ai.context.create permission' do
      let(:valid_params) do
        {
          context: {
            name: 'New Test Context',
            description: 'A test context for AI',
            context_type: 'knowledge_base',
            context_data: { data: 'test content' }
          }
        }
      end

      it 'creates a new context' do
        expect {
          post '/api/v1/ai/contexts', params: valid_params, headers: headers, as: :json
        }.to change(Ai::PersistentContext, :count).by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data

        expect(data['context']['name']).to eq('New Test Context')
      end

      it 'sets current user as owner' do
        post '/api/v1/ai/contexts', params: valid_params, headers: headers, as: :json

        expect_success_response
        created_context = Ai::PersistentContext.last
        expect(created_context.created_by_user_id).to eq(user_with_create_permission.id)
      end

      it 'sets scope to account by default' do
        post '/api/v1/ai/contexts', params: valid_params, headers: headers, as: :json

        data = json_response_data
        expect(data['context']['scope']).to eq('account')
      end
    end

    context 'with invalid data' do
      it 'returns validation error for blank name' do
        post '/api/v1/ai/contexts',
             params: { context: { name: '' } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        post '/api/v1/ai/contexts',
             params: { context: { name: 'Test' } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PUT /api/v1/ai/contexts/:id' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:context_record) { create_context.call(created_by_user: user_with_update_permission) }

    context 'with ai.context.update permission' do
      it 'updates context successfully' do
        put "/api/v1/ai/contexts/#{context_record.id}",
            params: { context: { description: 'Updated description' } },
            headers: headers,
            as: :json

        expect_success_response

        context_record.reload
        expect(context_record.description).to eq('Updated description')
      end

      it 'updates context name' do
        put "/api/v1/ai/contexts/#{context_record.id}",
            params: { context: { name: 'Updated Name' } },
            headers: headers,
            as: :json

        expect_success_response

        context_record.reload
        expect(context_record.name).to eq('Updated Name')
      end
    end
  end

  describe 'DELETE /api/v1/ai/contexts/:id' do
    let(:headers) { auth_headers_for(user_with_delete_permission) }
    let(:context_record) { create_context.call(created_by_user: user_with_delete_permission) }

    context 'with ai.context.delete permission' do
      it 'deletes context successfully' do
        context_id = context_record.id

        delete "/api/v1/ai/contexts/#{context_id}", headers: headers

        expect_success_response
        expect(Ai::PersistentContext.find_by(id: context_id)).to be_nil
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        delete "/api/v1/ai/contexts/#{context_record.id}", headers: headers

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/ai/contexts/:id/search' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:context_record) { create_context.call(name: 'Searchable Context', context_data: { keywords: ['marketing', 'sales'] }) }

    context 'with ai.context.read permission' do
      it 'searches within context' do
        post "/api/v1/ai/contexts/#{context_record.id}/search",
             params: { q: 'marketing' },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data

        expect(data).to have_key('results')
      end
    end
  end

  describe 'POST /api/v1/ai/contexts/:id/archive' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:context_record) { create_context.call(created_by_user: user_with_update_permission) }

    context 'with ai.context.update permission' do
      it 'archives the context' do
        post "/api/v1/ai/contexts/#{context_record.id}/archive", headers: headers

        expect_success_response

        context_record.reload
        expect(context_record.archived_at).not_to be_nil
      end
    end
  end

  describe 'POST /api/v1/ai/contexts/:id/unarchive' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:context_record) { create_context.call(created_by_user: user_with_update_permission, archived_at: Time.current) }

    context 'with ai.context.update permission' do
      it 'unarchives the context' do
        post "/api/v1/ai/contexts/#{context_record.id}/unarchive", headers: headers

        expect_success_response

        context_record.reload
        expect(context_record.archived_at).to be_nil
      end
    end
  end

  describe 'GET /api/v1/ai/contexts/:id/export' do
    let(:headers) { auth_headers_for(user_with_export_permission) }
    let(:context_record) { create_context.call(created_by_user: user_with_export_permission) }

    context 'with ai.context.export permission' do
      it 'exports the context' do
        get "/api/v1/ai/contexts/#{context_record.id}/export", headers: headers

        expect_success_response
        data = json_response_data

        expect(data).to have_key('export')
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        get "/api/v1/ai/contexts/#{context_record.id}/export", headers: headers

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/ai/contexts/:id/clone' do
    let(:headers) { auth_headers_for(user_with_create_permission) }
    let(:context_record) { create_context.call(created_by_user: user_with_create_permission, name: 'Original Context') }

    context 'with ai.context.create permission' do
      it 'creates a clone of the context' do
        context_record # materialize before count assertion

        expect {
          post "/api/v1/ai/contexts/#{context_record.id}/clone", headers: headers
        }.to change(Ai::PersistentContext, :count).by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data

        expect(data['context']['name']).to include('Original Context')
      end
    end
  end

  describe 'POST /api/v1/ai/contexts/import' do
    let(:headers) { auth_headers_for(user_with_import_permission) }

    context 'with ai.context.import permission' do
      let(:valid_params) do
        {
          data: {
            context: {
              name: 'Imported Context',
              context_type: 'knowledge_base',
              scope: 'account',
              context_data: { data: 'imported content' }
            }
          }.to_json
        }
      end

      it 'imports a new context' do
        expect {
          post '/api/v1/ai/contexts/import', params: valid_params, headers: headers, as: :json
        }.to change(Ai::PersistentContext, :count).by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data

        expect(data['context']['name']).to eq('Imported Context')
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        post '/api/v1/ai/contexts/import',
             params: { data: { context: { name: 'Test', context_type: 'knowledge_base', scope: 'account' } }.to_json },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/ai/contexts/stats' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create_context.call
    end

    context 'with ai.context.read permission' do
      it 'returns context statistics' do
        get '/api/v1/ai/contexts/stats', headers: headers

        expect_success_response
        data = json_response_data

        expect(data).to have_key('stats')
      end
    end
  end
end
