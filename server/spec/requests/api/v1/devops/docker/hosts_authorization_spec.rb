# frozen_string_literal: true

require 'rails_helper'

# Authorization gate specs for the docker hosts controller.
# READ actions require "devops.docker.read"; MUTATION actions require "devops.docker.manage".
RSpec.describe 'Api::V1::Devops::Docker::Hosts authorization', type: :request do
  let(:account) { create(:account) }
  let(:no_perm_user) { create(:user, account: account, permissions: []) }
  let(:read_user) { create(:user, account: account, permissions: ['devops.docker.read']) }
  let(:manage_user) { create(:user, account: account, permissions: ['devops.docker.manage']) }
  let(:host) { create(:devops_docker_host, :connected, account: account) }

  describe 'no permissions -> 403' do
    it 'forbids a READ (GET index)' do
      get "/api/v1/devops/docker/hosts",
          headers: auth_headers_for(no_perm_user), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'forbids a MUTATION (POST create)' do
      post "/api/v1/devops/docker/hosts",
           params: { host: { name: 'h1', api_endpoint: 'https://h1.example.com:2376' } },
           headers: auth_headers_for(no_perm_user), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'forbids a MUTATION (POST :id/sync)' do
      post "/api/v1/devops/docker/hosts/#{host.id}/sync",
           headers: auth_headers_for(no_perm_user), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'devops.docker.read holder' do
    it 'is not forbidden on a READ (GET index)' do
      get "/api/v1/devops/docker/hosts",
          headers: auth_headers_for(read_user), as: :json
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'is forbidden on a MUTATION (POST :id/sync)' do
      post "/api/v1/devops/docker/hosts/#{host.id}/sync",
           headers: auth_headers_for(read_user), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'devops.docker.manage holder' do
    it 'is not forbidden on a MUTATION (POST :id/sync)' do
      manager = instance_double(::Devops::Docker::HostManager)
      allow(::Devops::Docker::HostManager).to receive(:new).and_return(manager)
      allow(manager).to receive(:sync_host).and_return(true)

      post "/api/v1/devops/docker/hosts/#{host.id}/sync",
           headers: auth_headers_for(manage_user), as: :json
      expect(response).not_to have_http_status(:forbidden)
    end
  end
end
