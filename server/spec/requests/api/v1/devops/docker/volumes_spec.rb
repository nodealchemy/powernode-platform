# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Devops::Docker::Volumes', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read) { create(:user, account: account, permissions: ['docker.volumes.read']) }
  let(:user_with_manage) { create(:user, account: account, permissions: ['docker.volumes.read', 'docker.volumes.manage']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }
  let(:host) { create(:devops_docker_host, :connected, account: account) }

  let(:mock_volumes) do
    {
      "Volumes" => [
        { "Name" => "vol1", "Driver" => "local", "Mountpoint" => "/var/lib/docker/volumes/vol1/_data" },
        { "Name" => "vol2", "Driver" => "local", "Mountpoint" => "/var/lib/docker/volumes/vol2/_data" }
      ]
    }
  end

  describe 'GET /api/v1/devops/docker/hosts/:host_id/volumes' do
    let(:headers) { auth_headers_for(user_with_read) }

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:volume_list).and_return(mock_volumes)
    end

    it 'returns list of volumes' do
      get "/api/v1/devops/docker/hosts/#{host.id}/volumes", headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['items']).to be_an(Array)
      expect(response_data['data']['items'].length).to eq(2)
    end

    context 'when API error occurs' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:volume_list)
          .and_raise(Devops::Docker::ApiClient::ApiError.new("Connection refused"))
      end

      it 'returns error' do
        get "/api/v1/devops/docker/hosts/#{host.id}/volumes", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        get "/api/v1/devops/docker/hosts/#{host.id}/volumes", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/devops/docker/hosts/:host_id/volumes/:id' do
    let(:headers) { auth_headers_for(user_with_read) }

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:volume_inspect)
        .and_return({ "Name" => "vol1", "Driver" => "local", "Labels" => {}, "Options" => {} })
    end

    it 'returns volume details' do
      get "/api/v1/devops/docker/hosts/#{host.id}/volumes/vol1", headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['volume']['Name']).to eq('vol1')
    end

    context 'when volume not found' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:volume_inspect)
          .and_raise(Devops::Docker::ApiClient::NotFoundError.new("Volume not found"))
      end

      it 'returns not found error' do
        get "/api/v1/devops/docker/hosts/#{host.id}/volumes/nonexistent", headers: headers, as: :json

        expect_error_response('Volume not found', 404)
      end
    end
  end

  describe 'POST /api/v1/devops/docker/hosts/:host_id/volumes' do
    let(:headers) { auth_headers_for(user_with_manage) }

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:volume_create)
        .and_return({ "Name" => "new-volume", "Driver" => "local" })
    end

    it 'creates a new volume' do
      post "/api/v1/devops/docker/hosts/#{host.id}/volumes",
           params: { volume: { name: 'new-volume', driver: 'local' } },
           headers: headers, as: :json

      expect_success_response
    end

    context 'when API error occurs' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:volume_create)
          .and_raise(Devops::Docker::ApiClient::ApiError.new("Volume already exists"))
      end

      it 'returns error' do
        post "/api/v1/devops/docker/hosts/#{host.id}/volumes",
             params: { volume: { name: 'existing-volume' } },
             headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'DELETE /api/v1/devops/docker/hosts/:host_id/volumes/:id' do
    let(:headers) { auth_headers_for(user_with_manage) }

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:volume_delete).and_return(nil)
    end

    it 'removes the volume' do
      delete "/api/v1/devops/docker/hosts/#{host.id}/volumes/vol1",
             headers: headers, as: :json

      expect_success_response
    end

    context 'when volume not found' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:volume_delete)
          .and_raise(Devops::Docker::ApiClient::NotFoundError.new("Volume not found"))
      end

      it 'returns not found error' do
        delete "/api/v1/devops/docker/hosts/#{host.id}/volumes/nonexistent",
               headers: headers, as: :json

        expect_error_response('Volume not found', 404)
      end
    end
  end
end
