# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Devops::Containers authorization', type: :request do
  let(:account) { create(:account) }
  let(:no_perm_user) { create(:user, account: account, permissions: []) }
  let(:read_user) { create(:user, account: account, permissions: [ 'devops.containers.read' ]) }
  let(:execute_user) { create(:user, account: account, permissions: [ 'devops.containers.execute' ]) }
  let(:cancel_user) { create(:user, account: account, permissions: [ 'devops.containers.cancel' ]) }

  let(:template) { create(:devops_container_template, account: account) }
  let(:instance) { create(:devops_container_instance, account: account, template: template) }

  describe 'read actions require devops.containers.read' do
    context 'without permission' do
      let(:headers) { auth_headers_for(no_perm_user) }

      it 'GET index is forbidden' do
        get '/api/v1/devops/containers', headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'GET show is forbidden' do
        get "/api/v1/devops/containers/#{instance.id}", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'GET logs is forbidden' do
        get "/api/v1/devops/containers/#{instance.id}/logs", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'GET artifacts is forbidden' do
        get "/api/v1/devops/containers/#{instance.id}/artifacts", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'GET active is forbidden' do
        get '/api/v1/devops/containers/active', headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'GET stats is forbidden' do
        get '/api/v1/devops/containers/stats', headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with permission' do
      let(:headers) { auth_headers_for(read_user) }

      it 'GET index is not forbidden' do
        get '/api/v1/devops/containers', headers: headers, as: :json
        expect(response).not_to have_http_status(:forbidden)
      end

      it 'GET show is not forbidden' do
        get "/api/v1/devops/containers/#{instance.id}", headers: headers, as: :json
        expect(response).not_to have_http_status(:forbidden)
      end

      it 'GET active is not forbidden' do
        get '/api/v1/devops/containers/active', headers: headers, as: :json
        expect(response).not_to have_http_status(:forbidden)
      end

      it 'GET stats is not forbidden' do
        get '/api/v1/devops/containers/stats', headers: headers, as: :json
        expect(response).not_to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST execute requires devops.containers.execute' do
    context 'without permission' do
      let(:headers) { auth_headers_for(no_perm_user) }

      it 'is forbidden' do
        post '/api/v1/devops/containers/execute',
             params: { template_id: template.id }.to_json,
             headers: headers
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with read permission but not execute' do
      let(:headers) { auth_headers_for(read_user) }

      it 'is forbidden' do
        post '/api/v1/devops/containers/execute',
             params: { template_id: template.id }.to_json,
             headers: headers
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with execute permission' do
      let(:headers) { auth_headers_for(execute_user) }

      it 'is not forbidden (authorization passes)' do
        allow_any_instance_of(::Devops::ContainerOrchestrationService)
          .to receive(:execute)
          .and_return(instance)

        post '/api/v1/devops/containers/execute',
             params: { template_id: template.id }.to_json,
             headers: headers
        expect(response).not_to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST cancel requires devops.containers.cancel' do
    context 'without permission' do
      let(:headers) { auth_headers_for(no_perm_user) }

      it 'is forbidden' do
        post "/api/v1/devops/containers/#{instance.id}/cancel", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with read permission but not cancel' do
      let(:headers) { auth_headers_for(read_user) }

      it 'is forbidden' do
        post "/api/v1/devops/containers/#{instance.id}/cancel", headers: headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with cancel permission' do
      let(:headers) { auth_headers_for(cancel_user) }

      it 'is not forbidden (authorization passes)' do
        allow_any_instance_of(::Devops::ContainerOrchestrationService)
          .to receive(:cancel)
          .and_return(true)

        post "/api/v1/devops/containers/#{instance.id}/cancel", headers: headers, as: :json
        expect(response).not_to have_http_status(:forbidden)
      end
    end
  end
end
