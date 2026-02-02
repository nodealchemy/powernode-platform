# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Devops::AiConfigs', type: :request do
  let(:account) { create(:account) }
  let(:user_with_permission) { create(:user, account: account, permissions: [ 'devops.ai.manage' ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/devops/ai_configs' do
    let(:headers) { auth_headers_for(user_with_permission) }

    before do
      create_list(:devops_ai_config, 3, account: account, created_by: user_with_permission)
    end

    context 'with devops.ai.manage permission' do
      it 'returns list of AI configs' do
        get '/api/v1/devops/ai_configs', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['ai_configs']).to be_an(Array)
        expect(response_data['data']['ai_configs'].length).to eq(3)
      end

      it 'includes config details' do
        get '/api/v1/devops/ai_configs', headers: headers, as: :json

        response_data = json_response
        first_config = response_data['data']['ai_configs'].first

        expect(first_config).to include('id', 'name', 'provider', 'model', 'status')
      end

      it 'includes pagination meta' do
        get '/api/v1/devops/ai_configs', headers: headers, as: :json

        response_data = json_response
        expect(response_data['meta']).to include('current_page', 'per_page', 'total_count')
      end

      it 'filters by status' do
        create(:devops_ai_config, account: account, status: 'inactive', created_by: user_with_permission)

        get '/api/v1/devops/ai_configs?status=inactive', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        statuses = response_data['data']['ai_configs'].map { |c| c['status'] }
        expect(statuses.uniq).to eq([ 'inactive' ])
      end

      it 'filters by type' do
        create(:devops_ai_config, account: account, config_type: 'chat', created_by: user_with_permission)

        get '/api/v1/devops/ai_configs?type=chat', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        types = response_data['data']['ai_configs'].map { |c| c['config_type'] }
        expect(types.uniq).to eq([ 'chat' ])
      end

      it 'filters by provider' do
        create(:devops_ai_config, account: account, provider: 'anthropic', created_by: user_with_permission)

        get '/api/v1/devops/ai_configs?provider=anthropic', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        providers = response_data['data']['ai_configs'].map { |c| c['provider'] }
        expect(providers.uniq).to eq([ 'anthropic' ])
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/devops/ai_configs', headers: headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/devops/ai_configs', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/devops/ai_configs/:id' do
    let(:headers) { auth_headers_for(user_with_permission) }
    let(:ai_config) { create(:devops_ai_config, account: account, created_by: user_with_permission) }

    context 'with devops.ai.manage permission' do
      it 'returns AI config details' do
        get "/api/v1/devops/ai_configs/#{ai_config.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['ai_config']).to include(
          'id' => ai_config.id,
          'name' => ai_config.name
        )
      end

      it 'includes detailed configuration' do
        get "/api/v1/devops/ai_configs/#{ai_config.id}", headers: headers, as: :json

        response_data = json_response
        config = response_data['data']['ai_config']

        expect(config).to include('max_tokens', 'temperature', 'system_prompt', 'usage_stats')
      end
    end

    context 'when config does not exist' do
      it 'returns not found error' do
        get '/api/v1/devops/ai_configs/nonexistent-id', headers: headers, as: :json

        expect_error_response('AI configuration not found', 404)
      end
    end

    context 'when accessing other account config' do
      let(:other_account) { create(:account) }
      let(:other_config) { create(:devops_ai_config, account: other_account, created_by: user_with_permission) }

      it 'returns not found error' do
        get "/api/v1/devops/ai_configs/#{other_config.id}", headers: headers, as: :json

        expect_error_response('AI configuration not found', 404)
      end
    end
  end

  describe 'POST /api/v1/devops/ai_configs' do
    let(:headers) { auth_headers_for(user_with_permission) }

    context 'with devops.ai.manage permission' do
      let(:valid_params) do
        {
          ai_config: {
            name: 'Test AI Config',
            description: 'A test configuration',
            config_type: 'chat',
            provider: 'openai',
            model: 'gpt-4',
            max_tokens: 4000,
            temperature: 0.7
          }
        }
      end

      it 'creates a new AI config' do
        expect {
          post '/api/v1/devops/ai_configs', params: valid_params, headers: headers, as: :json
        }.to change(Devops::AiConfig, :count).by(1)

        expect(response).to have_http_status(:created)
        response_data = json_response

        expect(response_data['data']['ai_config']['name']).to eq('Test AI Config')
      end

      it 'sets current user as creator' do
        post '/api/v1/devops/ai_configs', params: valid_params, headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['ai_config']['created_by']['id']).to eq(user_with_permission.id)
      end

      it 'sets status to active by default' do
        post '/api/v1/devops/ai_configs', params: valid_params, headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['ai_config']['status']).to eq('active')
      end
    end

    context 'with invalid params' do
      let(:invalid_params) do
        {
          ai_config: {
            name: ''
          }
        }
      end

      it 'returns validation error' do
        post '/api/v1/devops/ai_configs', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'PATCH /api/v1/devops/ai_configs/:id' do
    let(:headers) { auth_headers_for(user_with_permission) }
    let(:ai_config) { create(:devops_ai_config, account: account, created_by: user_with_permission) }

    context 'with devops.ai.manage permission' do
      it 'updates AI config successfully' do
        patch "/api/v1/devops/ai_configs/#{ai_config.id}",
              params: { ai_config: { description: 'Updated description' } },
              headers: headers,
              as: :json

        expect_success_response

        ai_config.reload
        expect(ai_config.description).to eq('Updated description')
      end

      it 'updates temperature setting' do
        patch "/api/v1/devops/ai_configs/#{ai_config.id}",
              params: { ai_config: { temperature: 0.9 } },
              headers: headers,
              as: :json

        expect_success_response

        ai_config.reload
        expect(ai_config.temperature).to eq(0.9)
      end
    end
  end

  describe 'DELETE /api/v1/devops/ai_configs/:id' do
    let(:headers) { auth_headers_for(user_with_permission) }
    let(:ai_config) { create(:devops_ai_config, account: account, created_by: user_with_permission, is_default: false) }

    context 'with devops.ai.manage permission' do
      it 'deletes AI config successfully' do
        config_id = ai_config.id

        delete "/api/v1/devops/ai_configs/#{config_id}", headers: headers, as: :json

        expect_success_response
        expect(Devops::AiConfig.find_by(id: config_id)).to be_nil
      end

      it 'prevents deletion of default config' do
        default_config = create(:devops_ai_config, account: account, created_by: user_with_permission, is_default: true)

        delete "/api/v1/devops/ai_configs/#{default_config.id}", headers: headers, as: :json

        expect_error_response('Cannot delete default configuration', 422)
      end
    end
  end

  describe 'POST /api/v1/devops/ai_configs/:id/set_default' do
    let(:headers) { auth_headers_for(user_with_permission) }
    let(:ai_config) { create(:devops_ai_config, account: account, config_type: 'chat', created_by: user_with_permission, is_default: false) }

    context 'with devops.ai.manage permission' do
      it 'sets config as default' do
        post "/api/v1/devops/ai_configs/#{ai_config.id}/set_default", headers: headers, as: :json

        expect_success_response

        ai_config.reload
        expect(ai_config.is_default).to be true
      end

      it 'removes default from other configs of same type' do
        old_default = create(:devops_ai_config, account: account, config_type: 'chat', created_by: user_with_permission, is_default: true)

        post "/api/v1/devops/ai_configs/#{ai_config.id}/set_default", headers: headers, as: :json

        expect_success_response

        old_default.reload
        expect(old_default.is_default).to be false
      end
    end
  end
end
