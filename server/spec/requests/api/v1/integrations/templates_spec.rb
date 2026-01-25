# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Integrations::Templates', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['integrations.read']) }
  let(:admin_user) { create(:user, account: account, permissions: ['admin.integrations.templates.create', 'admin.integrations.templates.update', 'admin.integrations.templates.delete']) }
  let(:limited_user) { create(:user, account: account, permissions: []) }

  let(:headers) { auth_headers_for(user) }
  let(:admin_headers) { auth_headers_for(admin_user) }
  let(:limited_headers) { auth_headers_for(limited_user) }

  describe 'GET /api/v1/integrations/templates' do
    let!(:template1) { create(:devops_integration_template, name: "Template 1") }
    let!(:template2) { create(:devops_integration_template, :featured, name: "Template 2") }
    let!(:inactive_template) { create(:devops_integration_template, :inactive) }

    before do
      allow(Devops::RegistryService).to receive(:list_templates).and_return(
        double(map: [template1.template_summary, template2.template_summary],
               current_page: 1, total_pages: 1, total_count: 2, limit_value: 25)
      )
    end

    context 'with proper permissions' do
      it 'returns list of templates' do
        get '/api/v1/integrations/templates', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['templates']).to be_an(Array)
        expect(data['templates'].length).to eq(2)
        expect(data['pagination']).to have_key('current_page')
      end

      it 'filters by type' do
        allow(Devops::RegistryService).to receive(:list_templates).and_return(
          double(map: [template1.template_summary], current_page: 1, total_pages: 1, total_count: 1, limit_value: 25)
        )

        get '/api/v1/integrations/templates', params: { type: 'rest_api' }, headers: headers, as: :json

        expect_success_response
      end

      it 'filters by category' do
        allow(Devops::RegistryService).to receive(:list_templates).and_return(
          double(map: [], current_page: 1, total_pages: 1, total_count: 0, limit_value: 25)
        )

        get '/api/v1/integrations/templates', params: { category: 'notifications' }, headers: headers, as: :json

        expect_success_response
      end

      it 'filters by featured' do
        allow(Devops::RegistryService).to receive(:list_templates).and_return(
          double(map: [template2.template_summary], current_page: 1, total_pages: 1, total_count: 1, limit_value: 25)
        )

        get '/api/v1/integrations/templates', params: { featured: 'true' }, headers: headers, as: :json

        expect_success_response
      end

      it 'supports pagination' do
        get '/api/v1/integrations/templates', params: { page: 1, per_page: 10 }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['pagination']).to have_key('per_page')
      end
    end

    context 'without integrations.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/integrations/templates', headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/integrations/templates', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/integrations/templates/:id' do
    let(:template) { create(:devops_integration_template) }

    before do
      allow(Devops::RegistryService).to receive(:find_template).with(template.id).and_return(template)
    end

    context 'with proper permissions' do
      it 'returns template details' do
        get "/api/v1/integrations/templates/#{template.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['template']).to include(
          'id' => template.id,
          'name' => template.name,
          'slug' => template.slug,
          'integration_type' => template.integration_type
        )
        expect(data['template']).to have_key('configuration_schema')
        expect(data['template']).to have_key('credential_requirements')
      end

      it 'returns not found for non-existent template' do
        allow(Devops::RegistryService).to receive(:find_template).and_raise(Devops::RegistryService::TemplateNotFoundError)

        get "/api/v1/integrations/templates/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('Template not found', 404)
      end
    end
  end

  describe 'POST /api/v1/integrations/templates' do
    let(:valid_params) do
      {
        template: {
          name: 'New Template',
          slug: 'new-template',
          integration_type: 'rest_api',
          category: 'ci_cd',
          version: '1.0.0',
          description: 'A new integration template',
          configuration_schema: {
            type: 'object',
            properties: {
              api_key: { type: 'string' }
            }
          },
          capabilities: ['execute'],
          is_public: true
        }
      }
    end

    context 'with admin permissions' do
      it 'creates a new template' do
        new_template = build(:devops_integration_template, name: 'New Template')
        allow(Devops::RegistryService).to receive(:create_template).and_return(new_template)

        post '/api/v1/integrations/templates', params: valid_params, headers: admin_headers, as: :json

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['template']).to include(
          'name' => 'New Template'
        )
      end

      it 'returns validation error for invalid params' do
        allow(Devops::RegistryService).to receive(:create_template).and_raise(
          Devops::RegistryService::ValidationError.new('Name is required')
        )

        invalid_params = valid_params.deep_merge(template: { name: nil })

        post '/api/v1/integrations/templates', params: invalid_params, headers: admin_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without admin.integrations.templates.create permission' do
      it 'returns forbidden error' do
        post '/api/v1/integrations/templates', params: valid_params, headers: headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'PATCH /api/v1/integrations/templates/:id' do
    let(:template) { create(:devops_integration_template) }
    let(:update_params) do
      {
        template: {
          name: 'Updated Template Name',
          description: 'Updated description'
        }
      }
    end

    before do
      allow(Devops::RegistryService).to receive(:find_template).and_return(template)
    end

    context 'with admin permissions' do
      it 'updates the template' do
        updated_template = template.dup
        updated_template.name = 'Updated Template Name'
        allow(Devops::RegistryService).to receive(:update_template).and_return(updated_template)

        patch "/api/v1/integrations/templates/#{template.id}", params: update_params, headers: admin_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['template']['name']).to eq('Updated Template Name')
      end

      it 'returns validation error for invalid update' do
        allow(Devops::RegistryService).to receive(:update_template).and_raise(
          Devops::RegistryService::ValidationError.new('Invalid version format')
        )

        invalid_params = { template: { version: 'invalid' } }

        patch "/api/v1/integrations/templates/#{template.id}", params: invalid_params, headers: admin_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without admin.integrations.templates.update permission' do
      it 'returns forbidden error' do
        patch "/api/v1/integrations/templates/#{template.id}", params: update_params, headers: headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'DELETE /api/v1/integrations/templates/:id' do
    let(:template) { create(:devops_integration_template) }

    before do
      allow(Devops::RegistryService).to receive(:find_template).and_return(template)
      allow(template).to receive(:destroy!).and_return(true)
    end

    context 'with admin permissions' do
      it 'deletes the template' do
        delete "/api/v1/integrations/templates/#{template.id}", headers: admin_headers, as: :json

        expect_success_response
        expect(json_response_data['message']).to eq('Template deleted')
      end
    end

    context 'without admin.integrations.templates.delete permission' do
      it 'returns forbidden error' do
        delete "/api/v1/integrations/templates/#{template.id}", headers: headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'GET /api/v1/integrations/templates/search' do
    let!(:matching_template) { create(:devops_integration_template, name: "GitHub Integration") }
    let!(:other_template) { create(:devops_integration_template, name: "Slack Integration") }

    before do
      allow(Devops::RegistryService).to receive(:search_templates).and_return(
        double(map: [matching_template.template_summary],
               current_page: 1, total_pages: 1, total_count: 1, limit_value: 25)
      )
    end

    context 'with proper permissions' do
      it 'searches templates by query' do
        get '/api/v1/integrations/templates/search', params: { q: 'GitHub' }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['templates']).to be_an(Array)
        expect(data['pagination']).to have_key('current_page')
      end

      it 'returns empty results for non-matching query' do
        allow(Devops::RegistryService).to receive(:search_templates).and_return(
          double(map: [], current_page: 1, total_pages: 0, total_count: 0, limit_value: 25)
        )

        get '/api/v1/integrations/templates/search', params: { q: 'NonExistent' }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['templates']).to be_empty
      end

      it 'supports filters with search' do
        get '/api/v1/integrations/templates/search', params: { q: 'Integration', type: 'rest_api' }, headers: headers, as: :json

        expect_success_response
      end
    end

    context 'without integrations.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/integrations/templates/search', params: { q: 'test' }, headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'GET /api/v1/integrations/templates/categories' do
    context 'with proper permissions' do
      it 'returns list of template categories' do
        allow(Devops::RegistryService).to receive(:template_categories).and_return(
          ['ci_cd', 'notifications', 'monitoring', 'deployment', 'security', 'analytics', 'testing']
        )

        get '/api/v1/integrations/templates/categories', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['categories']).to be_an(Array)
        expect(data['categories']).to include('ci_cd', 'notifications', 'monitoring')
      end
    end

    context 'without integrations.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/integrations/templates/categories', headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'GET /api/v1/integrations/templates/types' do
    context 'with proper permissions' do
      it 'returns list of integration types' do
        allow(Devops::RegistryService).to receive(:integration_types).and_return(
          ['github_action', 'webhook', 'mcp_server', 'rest_api', 'custom']
        )

        get '/api/v1/integrations/templates/types', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['types']).to be_an(Array)
        expect(data['types']).to include('github_action', 'webhook', 'mcp_server', 'rest_api')
      end
    end

    context 'without integrations.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/integrations/templates/types', headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end
end
