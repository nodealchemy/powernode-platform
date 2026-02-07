# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Devops::Docker::Networks', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read) { create(:user, account: account, permissions: ['docker.networks.read']) }
  let(:user_with_manage) { create(:user, account: account, permissions: ['docker.networks.read', 'docker.networks.manage']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }
  let(:host) { create(:devops_docker_host, :connected, account: account) }

  let(:mock_networks) do
    [
      { "Id" => "net1", "Name" => "bridge", "Driver" => "bridge", "Scope" => "local" },
      { "Id" => "net2", "Name" => "host", "Driver" => "host", "Scope" => "local" }
    ]
  end

  describe 'GET /api/v1/devops/docker/hosts/:host_id/networks' do
    let(:headers) { auth_headers_for(user_with_read) }

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:network_list).and_return(mock_networks)
    end

    it 'returns list of networks' do
      get "/api/v1/devops/docker/hosts/#{host.id}/networks", headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['items']).to be_an(Array)
      expect(response_data['data']['items'].length).to eq(2)
    end

    context 'when API error occurs' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:network_list)
          .and_raise(Devops::Docker::ApiClient::ApiError.new("Connection refused"))
      end

      it 'returns error' do
        get "/api/v1/devops/docker/hosts/#{host.id}/networks", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        get "/api/v1/devops/docker/hosts/#{host.id}/networks", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/devops/docker/hosts/:host_id/networks/:id' do
    let(:headers) { auth_headers_for(user_with_read) }

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:network_inspect)
        .and_return({ "Id" => "net1", "Name" => "bridge", "Driver" => "bridge", "Containers" => {} })
    end

    it 'returns network details' do
      get "/api/v1/devops/docker/hosts/#{host.id}/networks/net1", headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['network']['Name']).to eq('bridge')
    end

    context 'when network not found' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:network_inspect)
          .and_raise(Devops::Docker::ApiClient::NotFoundError.new("Network not found"))
      end

      it 'returns not found error' do
        get "/api/v1/devops/docker/hosts/#{host.id}/networks/nonexistent", headers: headers, as: :json

        expect_error_response('Network not found', 404)
      end
    end
  end

  describe 'POST /api/v1/devops/docker/hosts/:host_id/networks' do
    let(:headers) { auth_headers_for(user_with_manage) }

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:network_create)
        .and_return({ "Id" => "newnet1", "Warning" => "" })
    end

    it 'creates a new network' do
      post "/api/v1/devops/docker/hosts/#{host.id}/networks",
           params: { network: { name: 'my-network', driver: 'bridge' } },
           headers: headers, as: :json

      expect_success_response
    end

    context 'when API error occurs' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:network_create)
          .and_raise(Devops::Docker::ApiClient::ApiError.new("Network already exists"))
      end

      it 'returns error' do
        post "/api/v1/devops/docker/hosts/#{host.id}/networks",
             params: { network: { name: 'existing-network' } },
             headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'DELETE /api/v1/devops/docker/hosts/:host_id/networks/:id' do
    let(:headers) { auth_headers_for(user_with_manage) }

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:network_delete).and_return(nil)
    end

    it 'removes the network' do
      delete "/api/v1/devops/docker/hosts/#{host.id}/networks/net1",
             headers: headers, as: :json

      expect_success_response
    end

    context 'when network not found' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:network_delete)
          .and_raise(Devops::Docker::ApiClient::NotFoundError.new("Network not found"))
      end

      it 'returns not found error' do
        delete "/api/v1/devops/docker/hosts/#{host.id}/networks/nonexistent",
               headers: headers, as: :json

        expect_error_response('Network not found', 404)
      end
    end
  end
end
