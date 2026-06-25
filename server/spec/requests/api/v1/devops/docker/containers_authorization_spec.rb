# frozen_string_literal: true

require 'rails_helper'

# Authorization gate specs for the docker containers controller.
# READ actions require "devops.docker.read"; MUTATION actions require "devops.docker.manage".
RSpec.describe 'Api::V1::Devops::Docker::Containers authorization', type: :request do
  let(:account) { create(:account) }
  let(:no_perm_user) { create(:user, account: account, permissions: []) }
  let(:read_user) { create(:user, account: account, permissions: ['devops.docker.read']) }
  let(:manage_user) { create(:user, account: account, permissions: ['devops.docker.manage']) }
  let(:host) { create(:devops_docker_host, :connected, account: account) }
  let(:container) { create(:devops_docker_container, :running, docker_host: host) }

  describe 'no permissions -> 403' do
    it 'forbids a READ (GET index)' do
      get "/api/v1/devops/docker/hosts/#{host.id}/containers",
          headers: auth_headers_for(no_perm_user), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'forbids a MUTATION (POST create)' do
      post "/api/v1/devops/docker/hosts/#{host.id}/containers",
           params: { container: { name: 'c1', image: 'nginx:latest' } },
           headers: auth_headers_for(no_perm_user), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'forbids a MUTATION (POST :id/start)' do
      post "/api/v1/devops/docker/hosts/#{host.id}/containers/#{container.id}/start",
           headers: auth_headers_for(no_perm_user), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'devops.docker.read holder' do
    it 'is not forbidden on a READ (GET index)' do
      get "/api/v1/devops/docker/hosts/#{host.id}/containers",
          headers: auth_headers_for(read_user), as: :json
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'is forbidden on a MUTATION (POST create)' do
      post "/api/v1/devops/docker/hosts/#{host.id}/containers",
           params: { container: { name: 'c1', image: 'nginx:latest' } },
           headers: auth_headers_for(read_user), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'devops.docker.manage holder' do
    it 'is not forbidden on a MUTATION (POST :id/start)' do
      manager = instance_double(::Devops::Docker::ContainerManager)
      allow(::Devops::Docker::ContainerManager).to receive(:new).and_return(manager)
      allow(manager).to receive(:start_container).and_return(container)

      post "/api/v1/devops/docker/hosts/#{host.id}/containers/#{container.id}/start",
           headers: auth_headers_for(manage_user), as: :json
      expect(response).not_to have_http_status(:forbidden)
    end
  end
end
