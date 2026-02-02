# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::Marketplace', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read_permission) { create(:user, account: account, permissions: [ 'ai.workflows.read' ]) }
  let(:user_with_create_permission) { create(:user, account: account, permissions: [ 'ai.workflows.read', 'ai.workflows.create' ]) }
  let(:user_with_update_permission) { create(:user, account: account, permissions: [ 'ai.workflows.read', 'ai.workflows.update' ]) }
  let(:user_with_delete_permission) { create(:user, account: account, permissions: [ 'ai.workflows.read', 'ai.workflows.delete' ]) }
  let(:user_with_manage_permission) { create(:user, account: account, permissions: [ 'ai.workflows.read', 'ai.workflows.manage' ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/ai/marketplace/templates' do
    before do
      create_list(:ai_workflow_template, 3, :public, account: account, created_by_user: user_with_read_permission)
    end

    context 'without authentication (public access)' do
      it 'returns list of public templates' do
        get '/api/v1/ai/marketplace/templates', as: :json

        expect_success_response
        data = json_response_data

        expect(data['items']).to be_an(Array)
      end

      it 'includes pagination' do
        get '/api/v1/ai/marketplace/templates', as: :json

        expect_success_response
        data = json_response_data
        expect(data['pagination']).to include('current_page', 'per_page', 'total_count')
      end
    end

    context 'with authentication' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns templates accessible to account' do
        get '/api/v1/ai/marketplace/templates', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['items']).to be_an(Array)
      end

      it 'filters by category' do
        create(:ai_workflow_template, :public, account: account, category: 'data_processing')

        get '/api/v1/ai/marketplace/templates?category=data_processing',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data

        categories = data['items'].map { |t| t['category'] }
        expect(categories.uniq).to eq([ 'data_processing' ])
      end
    end
  end

  describe 'GET /api/v1/ai/marketplace/templates/:id' do
    let(:template) { create(:ai_workflow_template, :public, account: account, created_by_user: user_with_read_permission) }

    context 'without authentication (public template)' do
      it 'returns template details' do
        get "/api/v1/ai/marketplace/templates/#{template.id}", as: :json

        expect_success_response
        data = json_response_data

        expect(data['template']['id']).to eq(template.id)
        expect(data['template']['name']).to eq(template.name)
      end
    end

    context 'when template does not exist' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns not found error' do
        get '/api/v1/ai/marketplace/templates/nonexistent-id', headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/ai/marketplace/templates' do
    let(:headers) { auth_headers_for(user_with_create_permission) }

    context 'with ai.workflows.create permission' do
      let(:valid_params) do
        {
          template: {
            name: 'New Marketplace Template',
            description: 'A test marketplace template',
            category: 'general',
            difficulty_level: 'beginner',
            is_public: false,
            template_data: {
              nodes: [
                { node_id: 'start', node_type: 'start', name: 'Start' }
              ],
              edges: []
            }
          }
        }
      end

      it 'creates a new template' do
        expect {
          post '/api/v1/ai/marketplace/templates', params: valid_params, headers: headers, as: :json
        }.to change(Ai::WorkflowTemplate, :count).by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data

        expect(data['template']['name']).to eq('New Marketplace Template')
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        post '/api/v1/ai/marketplace/templates',
             params: { template: { name: 'Test' } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/ai/marketplace/templates/:id/install' do
    let(:headers) { auth_headers_for(user_with_create_permission) }
    let(:template) { create(:ai_workflow_template, :public, account: account) }

    context 'with ai.workflows.create permission' do
      it 'installs template' do
        subscription_double = double(
          id: 'sub-123',
          metadata: { 'template_version' => '1.0.0' },
          subscribed_at: Time.current,
          created_at: Time.current,
          configuration: {}
        )
        workflow_double = double(
          id: 'wf-123',
          name: 'Test',
          description: 'Desc',
          status: 'active',
          version: '1.0.0',
          created_at: Time.current
        )

        allow_any_instance_of(Ai::Marketplace::InstallationService).to receive(:install).and_return(
          { success: true, subscription: subscription_double, workflow: workflow_double, message: 'Installed successfully' }
        )

        post "/api/v1/ai/marketplace/templates/#{template.id}/install", headers: headers, as: :json

        expect(response).to have_http_status(:created)
      end
    end
  end

  describe 'POST /api/v1/ai/marketplace/templates/:id/publish' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:template) { create(:ai_workflow_template, account: account, created_by_user: user_with_update_permission, is_public: false) }

    context 'with ai.workflows.update permission' do
      it 'publishes template' do
        allow(template).to receive(:can_publish?).and_return(true)
        allow_any_instance_of(Ai::WorkflowTemplate).to receive(:publish!).and_return(true)

        post "/api/v1/ai/marketplace/templates/#{template.id}/publish", headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/marketplace/templates/:id/rate' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:template) { create(:ai_workflow_template, :public, account: account) }

    context 'with ai.workflows.update permission' do
      it 'rates template' do
        allow_any_instance_of(Ai::Marketplace::InstallationService).to receive(:rate_template).and_return(
          { success: true, message: 'Rating submitted' }
        )

        post "/api/v1/ai/marketplace/templates/#{template.id}/rate",
             params: { rating: 5 },
             headers: headers,
             as: :json

        expect_success_response
      end

      it 'validates rating range' do
        post "/api/v1/ai/marketplace/templates/#{template.id}/rate",
             params: { rating: 10 },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe 'GET /api/v1/ai/marketplace/discover' do
    before do
      create_list(:ai_workflow_template, 3, :public)
    end

    context 'without authentication (public access)' do
      it 'returns discovered templates' do
        get '/api/v1/ai/marketplace/discover', as: :json

        expect_success_response
        data = json_response_data

        expect(data['templates']).to be_an(Array)
      end
    end
  end

  describe 'POST /api/v1/ai/marketplace/search' do
    before do
      create(:ai_workflow_template, :public, name: 'Unique Search Template')
    end

    context 'without authentication (public access)' do
      it 'searches templates' do
        post '/api/v1/ai/marketplace/search',
             params: { query: 'Unique Search' },
             as: :json

        expect_success_response
        data = json_response_data

        expect(data['templates']).to be_an(Array)
      end
    end
  end

  describe 'GET /api/v1/ai/marketplace/featured' do
    before do
      create_list(:ai_workflow_template, 2, :public, is_featured: true)
    end

    context 'without authentication (public access)' do
      it 'returns featured templates' do
        get '/api/v1/ai/marketplace/featured', as: :json

        expect_success_response
        data = json_response_data

        expect(data['templates']).to be_an(Array)
      end
    end
  end

  describe 'GET /api/v1/ai/marketplace/popular' do
    before do
      create_list(:ai_workflow_template, 2, :public, usage_count: 100)
    end

    context 'without authentication (public access)' do
      it 'returns popular templates' do
        get '/api/v1/ai/marketplace/popular', as: :json

        expect_success_response
        data = json_response_data

        expect(data['templates']).to be_an(Array)
      end
    end
  end

  describe 'GET /api/v1/ai/marketplace/categories' do
    context 'without authentication (public access)' do
      it 'returns categories' do
        get '/api/v1/ai/marketplace/categories', as: :json

        expect_success_response
        data = json_response_data

        expect(data).to have_key('categories')
      end
    end
  end

  describe 'GET /api/v1/ai/marketplace/tags' do
    context 'without authentication (public access)' do
      it 'returns tags' do
        get '/api/v1/ai/marketplace/tags', as: :json

        expect_success_response
        data = json_response_data

        expect(data).to have_key('tags')
      end
    end
  end

  describe 'GET /api/v1/ai/marketplace/statistics' do
    context 'without authentication (public access)' do
      it 'returns marketplace statistics' do
        get '/api/v1/ai/marketplace/statistics', as: :json

        expect_success_response
        data = json_response_data

        expect(data).to have_key('statistics')
      end
    end

    context 'with authentication' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'includes account-specific statistics' do
        get '/api/v1/ai/marketplace/statistics', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['statistics']).to have_key('account')
      end
    end
  end

  describe 'GET /api/v1/ai/marketplace/installations' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    context 'with ai.workflows.read permission' do
      it 'returns list of installations' do
        get '/api/v1/ai/marketplace/installations', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['installations']).to be_an(Array)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/ai/marketplace/installations', headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/ai/marketplace/recommendations' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    context 'with ai.workflows.read permission' do
      it 'returns recommendations' do
        get '/api/v1/ai/marketplace/recommendations', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data).to have_key('recommendations')
      end
    end
  end

  describe 'POST /api/v1/ai/marketplace/compare' do
    let(:headers) { auth_headers_for(user_with_manage_permission) }
    let(:templates) { create_list(:ai_workflow_template, 3, :public) }

    context 'with ai.workflows.manage permission' do
      it 'compares templates' do
        post '/api/v1/ai/marketplace/compare',
             params: { template_ids: templates.map(&:id) },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data

        expect(data).to have_key('comparison')
      end

      it 'validates template count' do
        post '/api/v1/ai/marketplace/compare',
             params: { template_ids: [ templates.first.id ] },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe 'GET /api/v1/ai/marketplace/updates' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    context 'with ai.workflows.read permission' do
      it 'checks for updates' do
        get '/api/v1/ai/marketplace/updates', headers: headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data).to have_key('updates_available')
      end
    end
  end
end
