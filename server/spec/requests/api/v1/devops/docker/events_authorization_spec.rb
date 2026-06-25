# frozen_string_literal: true

require 'rails_helper'

# Authorization gate specs for the docker events controller.
# READ actions require "devops.docker.read"; MUTATION (acknowledge) requires "devops.docker.manage".
RSpec.describe 'Api::V1::Devops::Docker::Events authorization', type: :request do
  let(:account) { create(:account) }
  let(:no_perm_user) { create(:user, account: account, permissions: []) }
  let(:read_user) { create(:user, account: account, permissions: ['devops.docker.read']) }
  let(:manage_user) { create(:user, account: account, permissions: ['devops.docker.manage']) }
  let(:host) { create(:devops_docker_host, :connected, account: account) }
  let(:event) { create(:devops_docker_event, docker_host: host) }

  describe 'no permissions -> 403' do
    it 'forbids a READ (GET index)' do
      get "/api/v1/devops/docker/hosts/#{host.id}/events",
          headers: auth_headers_for(no_perm_user), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'forbids a MUTATION (POST :id/acknowledge)' do
      post "/api/v1/devops/docker/hosts/#{host.id}/events/#{event.id}/acknowledge",
           headers: auth_headers_for(no_perm_user), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'devops.docker.read holder' do
    it 'is not forbidden on a READ (GET index)' do
      get "/api/v1/devops/docker/hosts/#{host.id}/events",
          headers: auth_headers_for(read_user), as: :json
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'is forbidden on a MUTATION (POST :id/acknowledge)' do
      post "/api/v1/devops/docker/hosts/#{host.id}/events/#{event.id}/acknowledge",
           headers: auth_headers_for(read_user), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'devops.docker.manage holder' do
    it 'is not forbidden on a MUTATION (POST :id/acknowledge)' do
      post "/api/v1/devops/docker/hosts/#{host.id}/events/#{event.id}/acknowledge",
           headers: auth_headers_for(manage_user), as: :json
      expect(response).not_to have_http_status(:forbidden)
    end
  end
end
