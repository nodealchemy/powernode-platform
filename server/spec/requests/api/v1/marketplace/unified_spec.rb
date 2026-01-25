# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Marketplace::Unified', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(user) }

  describe 'GET /api/v1/marketplace/unified' do
    context 'without authentication (public access)' do
      it 'returns marketplace items' do
        get '/api/v1/marketplace/unified', as: :json

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
        expect(json_response['meta']).to include(
          'current_page',
          'per_page',
          'total_count',
          'total_pages'
        )
      end

      it 'filters by types parameter' do
        get '/api/v1/marketplace/unified', params: { types: 'app,plugin' }, as: :json

        expect_success_response
        expect(json_response['meta']['filters']['types']).to eq(['app', 'plugin'])
      end

      it 'defaults to all types when no types specified' do
        get '/api/v1/marketplace/unified', as: :json

        expect_success_response
        expect(json_response['meta']['filters']['types']).to eq(['app', 'plugin', 'template'])
      end

      it 'filters by search parameter' do
        get '/api/v1/marketplace/unified', params: { search: 'productivity' }, as: :json

        expect_success_response
        expect(json_response['meta']['filters']['search']).to eq('productivity')
      end

      it 'paginates results' do
        get '/api/v1/marketplace/unified', params: { page: 2, per_page: 5 }, as: :json

        expect_success_response
        meta = json_response['meta']
        expect(meta['current_page']).to eq(2)
        expect(meta['per_page']).to eq(5)
      end
    end

    context 'with authentication' do
      it 'returns marketplace items with auth context' do
        get '/api/v1/marketplace/unified', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
      end
    end
  end

  describe 'GET /api/v1/marketplace/unified/:type/:id' do
    let(:workflow_template) { create(:ai_workflow_template, :published) }

    context 'without authentication' do
      it 'returns item details for valid type' do
        get "/api/v1/marketplace/unified/template/#{workflow_template.id}", as: :json

        expect_success_response
        data = json_response_data
        expect(data['id']).to eq(workflow_template.id)
        expect(data['type']).to eq('template')
        expect(data).to have_key('name')
        expect(data).to have_key('description')
      end

      it 'returns error for invalid type' do
        get '/api/v1/marketplace/unified/invalid_type/123', as: :json

        expect_error_response('Invalid item type: invalid_type', 400)
      end

      it 'returns error for non-existent item' do
        get "/api/v1/marketplace/unified/template/#{SecureRandom.uuid}", as: :json

        expect_error_response('Template not found', 404)
      end
    end

    context 'with authentication' do
      it 'returns item details with auth context' do
        get "/api/v1/marketplace/unified/template/#{workflow_template.id}",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data['id']).to eq(workflow_template.id)
      end
    end
  end

  describe 'POST /api/v1/marketplace/unified/:type/:id/install' do
    let(:workflow_template) { create(:ai_workflow_template, :published) }

    context 'with authentication' do
      it 'installs a template' do
        installation = double(
          id: SecureRandom.uuid,
          created_at: Time.current,
          persisted?: true
        )
        allow_any_instance_of(Ai::WorkflowTemplate)
          .to receive(:install_to_account)
          .and_return(installation)

        post "/api/v1/marketplace/unified/template/#{workflow_template.id}/install",
             headers: headers,
             as: :json

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['item_id']).to eq(workflow_template.id)
        expect(data['item_type']).to eq('template')
        expect(data['status']).to eq('active')
      end

      it 'returns error when installation fails' do
        installation = double(
          persisted?: false,
          errors: double(full_messages: ['Installation failed'])
        )
        allow_any_instance_of(Ai::WorkflowTemplate)
          .to receive(:install_to_account)
          .and_return(installation)

        post "/api/v1/marketplace/unified/template/#{workflow_template.id}/install",
             headers: headers,
             as: :json

        expect_error_response('Installation failed', 422)
      end

      it 'handles exceptions during installation' do
        allow_any_instance_of(Ai::WorkflowTemplate)
          .to receive(:install_to_account)
          .and_raise(StandardError.new('Something went wrong'))

        post "/api/v1/marketplace/unified/template/#{workflow_template.id}/install",
             headers: headers,
             as: :json

        expect_error_response('Installation failed', 422)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post "/api/v1/marketplace/unified/template/#{workflow_template.id}/install", as: :json

        expect_error_response('Authentication required', 401)
      end
    end

    context 'for invalid item type' do
      it 'returns error' do
        post '/api/v1/marketplace/unified/invalid_type/123/install',
             headers: headers,
             as: :json

        expect_error_response('Invalid item type: invalid_type', 400)
      end
    end
  end

  describe 'installing apps' do
    let(:app) { create(:marketplace_definition) }
    let(:app_plan) { create(:app_plan, app: app, is_primary: true) }

    context 'with authentication' do
      before do
        app_plan # Ensure plan exists
      end

      it 'creates app subscription' do
        post "/api/v1/marketplace/unified/app/#{app.id}/install",
             headers: headers,
             as: :json

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['item_id']).to eq(app.id)
        expect(data['item_type']).to eq('app')
      end

      it 'returns error when no plans available' do
        app_plan.destroy

        post "/api/v1/marketplace/unified/app/#{app.id}/install",
             headers: headers,
             as: :json

        expect_error_response('No plans available for this app', 422)
      end
    end
  end

  describe 'installing plugins' do
    let(:plugin) { create(:plugin, account: account) }

    context 'with authentication' do
      it 'installs plugin' do
        installation = double(
          id: SecureRandom.uuid,
          status: 'active',
          installed_at: Time.current
        )
        allow_any_instance_of(Plugin)
          .to receive(:install_for_account)
          .and_return(installation)

        post "/api/v1/marketplace/unified/plugin/#{plugin.id}/install",
             headers: headers,
             as: :json

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['item_id']).to eq(plugin.id)
        expect(data['item_type']).to eq('plugin')
        expect(data['status']).to eq('active')
      end

      it 'handles plugin installation errors' do
        allow_any_instance_of(Plugin)
          .to receive(:install_for_account)
          .and_raise(StandardError.new('Installation error'))

        post "/api/v1/marketplace/unified/plugin/#{plugin.id}/install",
             headers: headers,
             as: :json

        expect_error_response('Installation failed', 422)
      end
    end
  end
end
