# frozen_string_literal: true

require 'rails_helper'

# Authorization gate specs for the docker images controller.
# READ actions require "devops.docker.read"; MUTATION actions require "devops.docker.manage".
RSpec.describe 'Api::V1::Devops::Docker::Images authorization', type: :request do
  let(:account) { create(:account) }
  let(:no_perm_user) { create(:user, account: account, permissions: []) }
  let(:read_user) { create(:user, account: account, permissions: ['devops.docker.read']) }
  let(:manage_user) { create(:user, account: account, permissions: ['devops.docker.manage']) }
  let(:host) { create(:devops_docker_host, :connected, account: account) }
  let(:image) { create(:devops_docker_image, docker_host: host) }

  describe 'no permissions -> 403' do
    it 'forbids a READ (GET index)' do
      get "/api/v1/devops/docker/hosts/#{host.id}/images",
          headers: auth_headers_for(no_perm_user), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'forbids a MUTATION (POST pull)' do
      post "/api/v1/devops/docker/hosts/#{host.id}/images/pull",
           params: { image: 'nginx', tag: 'latest' },
           headers: auth_headers_for(no_perm_user), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'forbids a MUTATION (DELETE :id)' do
      delete "/api/v1/devops/docker/hosts/#{host.id}/images/#{image.id}",
             headers: auth_headers_for(no_perm_user), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'devops.docker.read holder' do
    it 'is not forbidden on a READ (GET index)' do
      get "/api/v1/devops/docker/hosts/#{host.id}/images",
          headers: auth_headers_for(read_user), as: :json
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'is forbidden on a MUTATION (POST pull)' do
      post "/api/v1/devops/docker/hosts/#{host.id}/images/pull",
           params: { image: 'nginx', tag: 'latest' },
           headers: auth_headers_for(read_user), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'devops.docker.manage holder' do
    it 'is not forbidden on a MUTATION (DELETE :id)' do
      manager = instance_double(::Devops::Docker::ImageManager)
      allow(::Devops::Docker::ImageManager).to receive(:new).and_return(manager)
      allow(manager).to receive(:remove_image).and_return(true)

      delete "/api/v1/devops/docker/hosts/#{host.id}/images/#{image.id}",
             headers: auth_headers_for(manage_user), as: :json
      expect(response).not_to have_http_status(:forbidden)
    end
  end
end
