# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Devops::ContainerTemplates authorization', type: :request do
  let(:account) { create(:account) }
  let(:no_perm_user) { create(:user, account: account, permissions: []) }
  let(:read_user) { create(:user, account: account, permissions: [ 'devops.container_templates.read' ]) }
  let(:write_user) { create(:user, account: account, permissions: [ 'devops.container_templates.write' ]) }

  let(:template) { create(:devops_container_template, account: account) }

  describe 'read actions require devops.container_templates.read' do
    context 'without permission' do
      let(:headers) { auth_headers_for(no_perm_user) }

      it 'GET index is forbidden' do
        get '/api/v1/devops/container_templates', headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'GET show is forbidden' do
        get "/api/v1/devops/container_templates/#{template.id}", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'GET executions is forbidden' do
        get "/api/v1/devops/container_templates/#{template.id}/executions", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'GET stats is forbidden' do
        get "/api/v1/devops/container_templates/#{template.id}/stats", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'GET categories is forbidden' do
        get '/api/v1/devops/container_templates/categories', headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'GET featured is forbidden' do
        get '/api/v1/devops/container_templates/featured', headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'GET builds is forbidden' do
        get "/api/v1/devops/container_templates/#{template.id}/builds", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with permission' do
      let(:headers) { auth_headers_for(read_user) }

      it 'GET index is not forbidden' do
        get '/api/v1/devops/container_templates', headers: headers, as: :json
        expect(response).not_to have_http_status(:forbidden)
      end

      it 'GET show is not forbidden' do
        get "/api/v1/devops/container_templates/#{template.id}", headers: headers, as: :json
        expect(response).not_to have_http_status(:forbidden)
      end

      it 'GET categories is not forbidden' do
        get '/api/v1/devops/container_templates/categories', headers: headers, as: :json
        expect(response).not_to have_http_status(:forbidden)
      end

      it 'GET featured is not forbidden' do
        get '/api/v1/devops/container_templates/featured', headers: headers, as: :json
        expect(response).not_to have_http_status(:forbidden)
      end
    end
  end

  describe 'write actions require devops.container_templates.write' do
    let(:create_params) do
      {
        template: {
          name: 'Authz Test Template',
          image_name: 'powernode/ai-agent',
          image_tag: 'latest'
        }
      }
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(no_perm_user) }

      it 'POST create is forbidden' do
        post '/api/v1/devops/container_templates', params: create_params.to_json, headers: headers
        expect(response).to have_http_status(:forbidden)
      end

      it 'PATCH update is forbidden' do
        patch "/api/v1/devops/container_templates/#{template.id}",
              params: { template: { description: 'changed' } }.to_json, headers: headers
        expect(response).to have_http_status(:forbidden)
      end

      it 'DELETE destroy is forbidden' do
        delete "/api/v1/devops/container_templates/#{template.id}", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'POST publish is forbidden' do
        post "/api/v1/devops/container_templates/#{template.id}/publish", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'POST unpublish is forbidden' do
        post "/api/v1/devops/container_templates/#{template.id}/unpublish", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'POST trigger_build is forbidden' do
        post "/api/v1/devops/container_templates/#{template.id}/trigger_build", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'POST create_image_repo is forbidden' do
        post '/api/v1/devops/container_templates/create_image_repo',
             params: { image_repo: { name: 'repo', variant_type: 'base' } }.to_json, headers: headers
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with read permission but not write' do
      let(:headers) { auth_headers_for(read_user) }

      it 'POST create is forbidden' do
        post '/api/v1/devops/container_templates', params: create_params.to_json, headers: headers
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with write permission' do
      let(:headers) { auth_headers_for(write_user) }

      it 'POST create is not forbidden' do
        post '/api/v1/devops/container_templates', params: create_params.to_json, headers: headers
        expect(response).not_to have_http_status(:forbidden)
      end

      it 'PATCH update is not forbidden' do
        patch "/api/v1/devops/container_templates/#{template.id}",
              params: { template: { description: 'changed' } }.to_json, headers: headers
        expect(response).not_to have_http_status(:forbidden)
      end

      it 'POST publish is not forbidden' do
        post "/api/v1/devops/container_templates/#{template.id}/publish", headers: headers, as: :json
        expect(response).not_to have_http_status(:forbidden)
      end
    end
  end
end
