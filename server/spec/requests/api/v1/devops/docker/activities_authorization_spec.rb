# frozen_string_literal: true

require 'rails_helper'

# Authorization gate specs for the docker activities controller.
# READ actions require "devops.docker.read". This controller has NO mutation actions.
RSpec.describe 'Api::V1::Devops::Docker::Activities authorization', type: :request do
  let(:account) { create(:account) }
  let(:no_perm_user) { create(:user, account: account, permissions: []) }
  let(:read_user) { create(:user, account: account, permissions: ['devops.docker.read']) }
  let(:host) { create(:devops_docker_host, :connected, account: account) }
  let(:activity) { create(:devops_docker_activity, docker_host: host) }

  describe 'no permissions -> 403' do
    it 'forbids a READ (GET index)' do
      get "/api/v1/devops/docker/hosts/#{host.id}/activities",
          headers: auth_headers_for(no_perm_user), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'forbids a READ (GET show)' do
      get "/api/v1/devops/docker/hosts/#{host.id}/activities/#{activity.id}",
          headers: auth_headers_for(no_perm_user), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'devops.docker.read holder' do
    it 'is not forbidden on a READ (GET index)' do
      get "/api/v1/devops/docker/hosts/#{host.id}/activities",
          headers: auth_headers_for(read_user), as: :json
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'is not forbidden on a READ (GET show)' do
      get "/api/v1/devops/docker/hosts/#{host.id}/activities/#{activity.id}",
          headers: auth_headers_for(read_user), as: :json
      expect(response).not_to have_http_status(:forbidden)
    end
  end
end
