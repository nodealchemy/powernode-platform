# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::PromptTemplates', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'ai.prompt_templates.read', 'ai.prompt_templates.write' ]) }
  let(:limited_user) { create(:user, account: account, permissions: [ 'ai.prompt_templates.read' ]) }
  let(:headers) { auth_headers_for(user) }
  let(:limited_headers) { auth_headers_for(limited_user) }

  describe 'GET /api/v1/ai/prompt_templates' do
    let!(:template1) { create(:shared_prompt_template, account: account, category: 'workflow') }
    let!(:template2) { create(:shared_prompt_template, account: account, category: 'custom') }

    context 'with proper permissions' do
      it 'returns list of prompt templates' do
        get '/api/v1/ai/prompt_templates', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['prompt_templates']).to be_an(Array)
        expect(data).to have_key('meta')
      end

      it 'filters by category' do
        get "/api/v1/ai/prompt_templates?category=workflow",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data['prompt_templates']).to be_an(Array)
      end

      it 'filters by domain' do
        get "/api/v1/ai/prompt_templates?domain=ai_workflow",
            headers: headers,
            as: :json

        expect_success_response
      end

      it 'filters by active status' do
        get "/api/v1/ai/prompt_templates?is_active=true",
            headers: headers,
            as: :json

        expect_success_response
      end

      it 'searches by name or description' do
        get "/api/v1/ai/prompt_templates?search=test",
            headers: headers,
            as: :json

        expect_success_response
      end

      it 'filters for root templates only' do
        get "/api/v1/ai/prompt_templates?root_only=true",
            headers: headers,
            as: :json

        expect_success_response
      end
    end

    context 'without proper permissions' do
      it 'returns forbidden error' do
        user_without_permissions = create(:user, account: account, permissions: [])
        headers_without_permissions = auth_headers_for(user_without_permissions)

        get '/api/v1/ai/prompt_templates', headers: headers_without_permissions, as: :json

        expect_error_response('Insufficient permissions to view prompt templates', 403)
      end
    end
  end

  describe 'GET /api/v1/ai/prompt_templates/:id' do
    let(:template) { create(:shared_prompt_template, account: account) }

    context 'with proper permissions' do
      it 'returns template details' do
        get "/api/v1/ai/prompt_templates/#{template.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['prompt_template']).to include('id', 'name', 'content')
      end

      it 'includes versions when requested' do
        get "/api/v1/ai/prompt_templates/#{template.id}?include_versions=true",
            headers: headers,
            as: :json

        expect_success_response
      end
    end

    context 'with invalid template id' do
      it 'returns not found error' do
        get "/api/v1/ai/prompt_templates/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('Prompt template not found', 404)
      end
    end
  end

  describe 'POST /api/v1/ai/prompt_templates' do
    let(:template_params) do
      {
        prompt_template: {
          name: 'New Template',
          description: 'Test template',
          category: 'workflow',
          content: 'This is a {{ variable }} template',
          is_active: true
        }
      }
    end

    context 'with proper permissions' do
      it 'creates a new prompt template' do
        expect {
          post '/api/v1/ai/prompt_templates', params: template_params, headers: headers, as: :json
        }.to change { account.shared_prompt_templates.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['prompt_template']).to be_present
        expect(data['message']).to eq('Prompt template created successfully')
      end

      it 'returns validation errors for invalid params' do
        invalid_params = { prompt_template: { name: nil } }

        post '/api/v1/ai/prompt_templates', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without write permission' do
      it 'returns forbidden error' do
        post '/api/v1/ai/prompt_templates', params: template_params, headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions to manage prompt templates', 403)
      end
    end
  end

  describe 'PATCH /api/v1/ai/prompt_templates/:id' do
    let(:template) { create(:shared_prompt_template, account: account) }
    let(:update_params) do
      {
        prompt_template: {
          name: 'Updated Template Name',
          description: 'Updated description'
        }
      }
    end

    context 'with proper permissions' do
      it 'updates the prompt template' do
        patch "/api/v1/ai/prompt_templates/#{template.id}",
              params: update_params,
              headers: headers,
              as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('Prompt template updated successfully')
      end

      it 'returns validation errors for invalid update' do
        invalid_params = { prompt_template: { name: nil } }

        patch "/api/v1/ai/prompt_templates/#{template.id}",
              params: invalid_params,
              headers: headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'DELETE /api/v1/ai/prompt_templates/:id' do
    let!(:template) { create(:shared_prompt_template, account: account) }

    context 'with proper permissions' do
      it 'deletes the prompt template when not in use' do
        allow_any_instance_of(Shared::PromptTemplate).to receive_message_chain(:ai_workflow_nodes, :exists?)
          .and_return(false)
        allow_any_instance_of(Shared::PromptTemplate).to receive_message_chain(:ci_cd_pipeline_steps, :exists?)
          .and_return(false)

        expect {
          delete "/api/v1/ai/prompt_templates/#{template.id}", headers: headers, as: :json
        }.to change { account.shared_prompt_templates.count }.by(-1)

        expect_success_response
        expect(json_response_data['message']).to eq('Prompt template deleted successfully')
      end

      it 'returns error when template is in use by workflow nodes' do
        allow_any_instance_of(Shared::PromptTemplate).to receive_message_chain(:ai_workflow_nodes, :exists?)
          .and_return(true)

        delete "/api/v1/ai/prompt_templates/#{template.id}", headers: headers, as: :json

        expect_error_response('Cannot delete template that is in use by AI workflow nodes', 422)
      end

      it 'returns error when template is in use by pipeline steps' do
        allow_any_instance_of(Shared::PromptTemplate).to receive_message_chain(:ai_workflow_nodes, :exists?)
          .and_return(false)
        allow_any_instance_of(Shared::PromptTemplate).to receive_message_chain(:ci_cd_pipeline_steps, :exists?)
          .and_return(true)

        delete "/api/v1/ai/prompt_templates/#{template.id}", headers: headers, as: :json

        expect_error_response('Cannot delete template that is in use by pipeline steps', 422)
      end
    end
  end

  describe 'POST /api/v1/ai/prompt_templates/:id/preview' do
    let(:template) { create(:shared_prompt_template, account: account, content: 'Hello {{ name }}!') }

    context 'with proper permissions' do
      it 'previews template with variables' do
        allow_any_instance_of(Shared::PromptTemplate).to receive(:render)
          .and_return('Hello World!')
        allow_any_instance_of(Shared::PromptTemplate).to receive(:extract_variables)
          .and_return([ 'name' ])

        post "/api/v1/ai/prompt_templates/#{template.id}/preview",
             params: { variables: { name: 'World' } },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('rendered_content')
        expect(data).to have_key('variables_used')
      end

      it 'returns error when render fails' do
        # Stub the render method to raise a StandardError
        allow_any_instance_of(Shared::PromptTemplate).to receive(:render)
          .and_raise(StandardError, 'Render failed')

        post "/api/v1/ai/prompt_templates/#{template.id}/preview",
             params: { variables: {} },
             headers: headers,
             as: :json

        # The controller catches StandardError and returns a 500
        expect(response).to have_http_status(:internal_server_error)
      end
    end
  end

  describe 'POST /api/v1/ai/prompt_templates/:id/duplicate' do
    let(:template) { create(:shared_prompt_template, account: account, name: 'Original') }

    context 'with proper permissions' do
      it 'duplicates the template' do
        duplicated = create(:shared_prompt_template, account: account, name: 'Original (Copy)')
        allow_any_instance_of(Shared::PromptTemplate).to receive(:duplicate)
          .and_return(duplicated)

        expect {
          post "/api/v1/ai/prompt_templates/#{template.id}/duplicate", headers: headers, as: :json
        }.to change { account.shared_prompt_templates.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['message']).to eq('Prompt template duplicated successfully')
      end
    end

    context 'without write permission' do
      it 'returns forbidden error' do
        post "/api/v1/ai/prompt_templates/#{template.id}/duplicate",
             headers: limited_headers,
             as: :json

        expect_error_response('Insufficient permissions to manage prompt templates', 403)
      end
    end
  end
end
