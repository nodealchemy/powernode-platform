# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Devops::IntegrationTemplates', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read_permission) { create(:user, account: account, permissions: ['devops.integrations.read']) }
  let(:user_with_admin_permission) { create(:user, account: account, permissions: ['devops.integrations.read', 'admin.devops.integration_templates.create', 'admin.devops.integration_templates.update', 'admin.devops.integration_templates.delete']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/devops/integration_templates' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      allow(Devops::RegistryService).to receive(:list_templates).and_return(
        double(map: [
          { id: '1', name: 'Template 1' },
          { id: '2', name: 'Template 2' }
        ], current_page: 1, total_pages: 1, total_count: 2, limit_value: 20)
      )
    end

    context 'with devops.integrations.read permission' do
      it 'returns list of templates' do
        get '/api/v1/devops/integration_templates', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['templates']).to be_an(Array)
      end

      it 'includes pagination meta' do
        get '/api/v1/devops/integration_templates', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['pagination']).to include('current_page', 'total_pages', 'total_count')
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/devops/integration_templates', headers: headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/devops/integration_templates', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/devops/integration_templates/:id' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:template) { create(:devops_integration_template) }

    context 'with devops.integrations.read permission' do
      it 'returns template details' do
        allow(Devops::RegistryService).to receive(:find_template).and_return(template)

        get "/api/v1/devops/integration_templates/#{template.id}", headers: headers, as: :json

        expect_success_response
      end
    end

    context 'when template does not exist' do
      it 'returns not found error' do
        allow(Devops::RegistryService).to receive(:find_template).and_raise(
          Devops::RegistryService::TemplateNotFoundError
        )

        get '/api/v1/devops/integration_templates/nonexistent-id', headers: headers, as: :json

        expect_error_response('Template', 404)
      end
    end
  end

  describe 'POST /api/v1/devops/integration_templates' do
    let(:headers) { auth_headers_for(user_with_admin_permission) }

    context 'with admin.devops.integration_templates.create permission' do
      let(:valid_params) do
        {
          template: {
            name: 'Test Template',
            slug: 'test-template',
            integration_type: 'rest_api',
            category: 'testing',
            version: '1.0.0',
            configuration_schema: { type: 'object' }
          }
        }
      end

      it 'creates a new template' do
        template = double(template_details: { id: 'test-id', name: 'Test Template' })
        allow(Devops::RegistryService).to receive(:create_template).and_return(template)

        post '/api/v1/devops/integration_templates', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
      end

      it 'handles validation errors' do
        allow(Devops::RegistryService).to receive(:create_template).and_raise(
          Devops::RegistryService::ValidationError.new('Invalid template')
        )

        post '/api/v1/devops/integration_templates', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        post '/api/v1/devops/integration_templates',
             params: { template: { name: 'Test' } },
             headers: headers,
             as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'PATCH /api/v1/devops/integration_templates/:id' do
    let(:headers) { auth_headers_for(user_with_admin_permission) }
    let(:template) { create(:devops_integration_template) }

    context 'with admin.devops.integration_templates.update permission' do
      it 'updates template successfully' do
        updated_template = double(template_details: { id: template.id, name: 'Updated Template' })
        allow(Devops::RegistryService).to receive(:find_template).and_return(template)
        allow(Devops::RegistryService).to receive(:update_template).and_return(updated_template)

        patch "/api/v1/devops/integration_templates/#{template.id}",
              params: { template: { name: 'Updated Template' } },
              headers: headers,
              as: :json

        expect_success_response
      end

      it 'handles validation errors' do
        allow(Devops::RegistryService).to receive(:find_template).and_return(template)
        allow(Devops::RegistryService).to receive(:update_template).and_raise(
          Devops::RegistryService::ValidationError.new('Invalid update')
        )

        patch "/api/v1/devops/integration_templates/#{template.id}",
              params: { template: { name: '' } },
              headers: headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'DELETE /api/v1/devops/integration_templates/:id' do
    let(:headers) { auth_headers_for(user_with_admin_permission) }
    let(:template) { create(:devops_integration_template) }

    context 'with admin.devops.integration_templates.delete permission' do
      it 'deletes template successfully' do
        allow(Devops::RegistryService).to receive(:find_template).and_return(template)
        allow(template).to receive(:destroy!).and_return(true)

        delete "/api/v1/devops/integration_templates/#{template.id}", headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/devops/integration_templates/search' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    context 'with devops.integrations.read permission' do
      it 'searches templates successfully' do
        allow(Devops::RegistryService).to receive(:search_templates).and_return(
          double(map: [{ id: '1', name: 'Found Template' }], current_page: 1, total_pages: 1, total_count: 1, limit_value: 20)
        )

        get '/api/v1/devops/integration_templates/search',
            params: { q: 'test' },
            headers: headers

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/devops/integration_templates/categories' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    context 'with devops.integrations.read permission' do
      it 'returns template categories' do
        allow(Devops::RegistryService).to receive(:template_categories).and_return(
          ['ci_cd', 'version_control', 'monitoring']
        )

        get '/api/v1/devops/integration_templates/categories', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['categories']).to be_an(Array)
      end
    end
  end

  describe 'GET /api/v1/devops/integration_templates/types' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    context 'with devops.integrations.read permission' do
      it 'returns integration types' do
        allow(Devops::RegistryService).to receive(:integration_types).and_return(
          ['rest_api', 'graphql', 'webhook']
        )

        get '/api/v1/devops/integration_templates/types', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['types']).to be_an(Array)
      end
    end
  end
end
