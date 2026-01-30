# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Devops::PromptTemplates', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read_permission) { create(:user, account: account, permissions: ['devops.prompt_templates.read']) }
  let(:user_with_write_permission) { create(:user, account: account, permissions: ['devops.prompt_templates.read', 'devops.prompt_templates.write']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/devops/prompt_templates' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create_list(:shared_prompt_template, 3, account: account, domain: 'cicd', created_by: user_with_read_permission)
    end

    context 'with devops.prompt_templates.read permission' do
      it 'returns list of prompt templates' do
        get '/api/v1/devops/prompt_templates', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['prompt_templates']).to be_an(Array)
        expect(response_data['data']['prompt_templates'].length).to eq(3)
      end

      it 'includes meta information' do
        get '/api/v1/devops/prompt_templates', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['meta']).to include('total', 'by_category')
      end

      it 'filters by category' do
        create(:shared_prompt_template, account: account, domain: 'cicd', category: 'deploy', created_by: user_with_read_permission)

        get '/api/v1/devops/prompt_templates?category=deploy', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        categories = response_data['data']['prompt_templates'].map { |t| t['category'] }
        expect(categories.uniq).to eq(['deploy'])
      end

      it 'filters by is_active' do
        create(:shared_prompt_template, account: account, domain: 'cicd', is_active: false, created_by: user_with_read_permission)

        get '/api/v1/devops/prompt_templates?is_active=false', headers: headers, as: :json

        expect_success_response
      end

      it 'filters root templates only' do
        parent = create(:shared_prompt_template, account: account, domain: 'cicd', created_by: user_with_read_permission)
        create(:shared_prompt_template, account: account, domain: 'cicd', parent_template: parent, created_by: user_with_read_permission)

        get '/api/v1/devops/prompt_templates?root_only=true', headers: headers, as: :json

        expect_success_response
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/devops/prompt_templates', headers: headers, as: :json

        expect_error_response('Insufficient permissions to view prompt templates', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/devops/prompt_templates', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/devops/prompt_templates/:id' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:prompt_template) { create(:shared_prompt_template, account: account, domain: 'cicd', created_by: user_with_read_permission) }

    context 'with devops.prompt_templates.read permission' do
      it 'returns prompt template details' do
        get "/api/v1/devops/prompt_templates/#{prompt_template.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['prompt_template']).to include('id' => prompt_template.id)
      end

      it 'includes versions when requested' do
        create_list(:shared_prompt_template, 2, account: account, domain: 'cicd', parent_template: prompt_template, created_by: user_with_read_permission)

        get "/api/v1/devops/prompt_templates/#{prompt_template.id}?include_versions=true",
            headers: headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['prompt_template']).to have_key('versions')
      end
    end

    context 'when template does not exist' do
      it 'returns not found error' do
        get '/api/v1/devops/prompt_templates/nonexistent-id', headers: headers, as: :json

        expect_error_response('Prompt template not found', 404)
      end
    end

    context 'when accessing other account template' do
      let(:other_account) { create(:account) }
      let(:other_template) { create(:shared_prompt_template, account: other_account, domain: 'cicd') }

      it 'returns not found error' do
        get "/api/v1/devops/prompt_templates/#{other_template.id}", headers: headers, as: :json

        expect_error_response('Prompt template not found', 404)
      end
    end
  end

  describe 'POST /api/v1/devops/prompt_templates' do
    let(:headers) { auth_headers_for(user_with_write_permission) }

    context 'with devops.prompt_templates.write permission' do
      let(:valid_params) do
        {
          prompt_template: {
            name: 'Test Prompt Template',
            description: 'A test template',
            category: 'custom',
            content: 'Test content with {{ variable }}',
            is_active: true,
            variables: { variable: 'string' }
          }
        }
      end

      it 'creates a new prompt template' do
        expect {
          post '/api/v1/devops/prompt_templates', params: valid_params, headers: headers, as: :json
        }.to change(Shared::PromptTemplate, :count).by(1)

        expect(response).to have_http_status(:created)
        response_data = json_response

        expect(response_data['data']['prompt_template']['name']).to eq('Test Prompt Template')
      end

      it 'sets current user as creator' do
        post '/api/v1/devops/prompt_templates', params: valid_params, headers: headers, as: :json

        template = Shared::PromptTemplate.last
        expect(template.created_by).to eq(user_with_write_permission)
      end

      it 'sets domain to devops' do
        post '/api/v1/devops/prompt_templates', params: valid_params, headers: headers, as: :json

        template = Shared::PromptTemplate.last
        expect(template.domain).to eq('cicd')
      end
    end

    context 'with invalid params' do
      let(:invalid_params) do
        {
          prompt_template: {
            name: ''
          }
        }
      end

      it 'returns validation error' do
        post '/api/v1/devops/prompt_templates', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        post '/api/v1/devops/prompt_templates',
             params: { prompt_template: { name: 'Test' } },
             headers: headers,
             as: :json

        expect_error_response('Insufficient permissions to manage prompt templates', 403)
      end
    end
  end

  describe 'PATCH /api/v1/devops/prompt_templates/:id' do
    let(:headers) { auth_headers_for(user_with_write_permission) }
    let(:prompt_template) { create(:shared_prompt_template, account: account, domain: 'cicd', created_by: user_with_write_permission) }

    context 'with devops.prompt_templates.write permission' do
      it 'updates prompt template successfully' do
        patch "/api/v1/devops/prompt_templates/#{prompt_template.id}",
              params: { prompt_template: { description: 'Updated description' } },
              headers: headers,
              as: :json

        expect_success_response

        prompt_template.reload
        expect(prompt_template.description).to eq('Updated description')
      end

      it 'updates content' do
        patch "/api/v1/devops/prompt_templates/#{prompt_template.id}",
              params: { prompt_template: { content: 'New content' } },
              headers: headers,
              as: :json

        expect_success_response

        prompt_template.reload
        expect(prompt_template.content).to eq('New content')
      end
    end
  end

  describe 'DELETE /api/v1/devops/prompt_templates/:id' do
    let(:headers) { auth_headers_for(user_with_write_permission) }
    let(:prompt_template) { create(:shared_prompt_template, account: account, domain: 'cicd', created_by: user_with_write_permission) }

    context 'with devops.prompt_templates.write permission' do
      it 'deletes prompt template successfully' do
        template_id = prompt_template.id

        delete "/api/v1/devops/prompt_templates/#{template_id}", headers: headers, as: :json

        expect_success_response
        expect(Shared::PromptTemplate.find_by(id: template_id)).to be_nil
      end

      it 'prevents deletion when in use by pipeline steps' do
        allow_any_instance_of(Shared::PromptTemplate).to receive_message_chain(:ci_cd_pipeline_steps, :exists?).and_return(true)

        delete "/api/v1/devops/prompt_templates/#{prompt_template.id}", headers: headers, as: :json

        expect_error_response('Cannot delete template that is in use by pipeline steps', 422)
      end
    end
  end

  describe 'POST /api/v1/devops/prompt_templates/:id/preview' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:prompt_template) { create(:shared_prompt_template, account: account, domain: 'cicd', content: 'Hello {{ name }}!', created_by: user_with_read_permission) }

    context 'with devops.prompt_templates.read permission' do
      before do
        allow_any_instance_of(Shared::PromptTemplate).to receive(:validate_syntax).and_return({ valid: true, errors: [] })
        allow_any_instance_of(Shared::PromptTemplate).to receive(:render).and_return('Hello World!')
        allow_any_instance_of(Shared::PromptTemplate).to receive(:extract_variables).and_return(['name'])
      end

      it 'previews template with variables' do
        post "/api/v1/devops/prompt_templates/#{prompt_template.id}/preview",
             params: { variables: { name: 'World' } },
             headers: headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['rendered_content']).to eq('Hello World!')
      end

      it 'extracts variables from template' do
        post "/api/v1/devops/prompt_templates/#{prompt_template.id}/preview",
             params: { variables: {} },
             headers: headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to have_key('variables_used')
      end

      it 'handles syntax errors' do
        allow_any_instance_of(Shared::PromptTemplate).to receive(:validate_syntax).and_return({ valid: false, errors: ['Liquid syntax error'] })

        bad_template = create(:shared_prompt_template, account: account, domain: 'cicd', content: '{{ invalid', created_by: user_with_read_permission)

        post "/api/v1/devops/prompt_templates/#{bad_template.id}/preview",
             params: { variables: {} },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'POST /api/v1/devops/prompt_templates/:id/duplicate' do
    let(:headers) { auth_headers_for(user_with_write_permission) }
    let(:prompt_template) { create(:shared_prompt_template, account: account, domain: 'cicd', name: 'Original Template', created_by: user_with_write_permission) }

    context 'with devops.prompt_templates.write permission' do
      it 'duplicates template successfully' do
        allow_any_instance_of(Shared::PromptTemplate).to receive(:duplicate).and_return(
          create(:shared_prompt_template, account: account, domain: 'cicd', name: 'Original Template (Copy)', created_by: user_with_write_permission)
        )

        post "/api/v1/devops/prompt_templates/#{prompt_template.id}/duplicate", headers: headers, as: :json

        expect(response).to have_http_status(:created)
        response_data = json_response

        expect(response_data['data']['prompt_template']['name']).to include('Copy')
      end
    end
  end
end
