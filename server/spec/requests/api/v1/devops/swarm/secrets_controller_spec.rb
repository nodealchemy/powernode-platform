# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Devops::Swarm::Secrets", type: :request do
  let(:account) { create(:account) }
  let(:cluster) { create(:devops_swarm_cluster, account: account) }

  # Swarm secrets are sensitive credential material. Reads gate on
  # devops.containers.read; writes (create/destroy) on
  # devops.container_templates.write (no dedicated devops.swarm.* perm exists).
  let(:reader)  { create(:user, account: account, permissions: %w[devops.containers.read]) }
  let(:manager) { create(:user, account: account, permissions: %w[devops.containers.read devops.container_templates.write]) }
  let(:unprivileged) { create(:user, account: account, permissions: []) }

  let(:manager_stub) { instance_double(::Devops::Docker::SecretManager) }

  before do
    allow(::Devops::Docker::SecretManager).to receive(:new).and_return(manager_stub)
    allow(manager_stub).to receive(:list).and_return([])
    allow(manager_stub).to receive(:inspect_secret).and_return({ "ID" => "abc" })
    allow(manager_stub).to receive(:create).and_return({ "ID" => "abc" })
    allow(manager_stub).to receive(:remove).and_return(true)
  end

  describe "GET .../secrets (index)" do
    it "forbids an authenticated user without the read permission" do
      get "/api/v1/devops/swarm/clusters/#{cluster.id}/secrets",
          headers: auth_headers_for(unprivileged), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "permits a user with the read permission" do
      get "/api/v1/devops/swarm/clusters/#{cluster.id}/secrets",
          headers: auth_headers_for(reader), as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET .../secrets/:id (show)" do
    it "forbids an authenticated user without the read permission" do
      get "/api/v1/devops/swarm/clusters/#{cluster.id}/secrets/abc",
          headers: auth_headers_for(unprivileged), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "permits a user with the read permission" do
      get "/api/v1/devops/swarm/clusters/#{cluster.id}/secrets/abc",
          headers: auth_headers_for(reader), as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST .../secrets (create)" do
    let(:params) { { secret: { name: "db-pass", data: "c2VjcmV0" } } }

    it "forbids an authenticated user without the manage permission" do
      post "/api/v1/devops/swarm/clusters/#{cluster.id}/secrets",
           params: params, headers: auth_headers_for(unprivileged), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "forbids a read-only user (read perm is insufficient to write)" do
      post "/api/v1/devops/swarm/clusters/#{cluster.id}/secrets",
           params: params, headers: auth_headers_for(reader), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "permits a user with the manage permission" do
      post "/api/v1/devops/swarm/clusters/#{cluster.id}/secrets",
           params: params, headers: auth_headers_for(manager), as: :json
      expect(response).not_to have_http_status(:forbidden)
      expect(response).to have_http_status(:created)
    end
  end

  describe "DELETE .../secrets/:id (destroy)" do
    it "forbids an authenticated user without the manage permission" do
      delete "/api/v1/devops/swarm/clusters/#{cluster.id}/secrets/abc",
             headers: auth_headers_for(unprivileged), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "permits a user with the manage permission" do
      delete "/api/v1/devops/swarm/clusters/#{cluster.id}/secrets/abc",
             headers: auth_headers_for(manager), as: :json
      expect(response).not_to have_http_status(:forbidden)
      expect(response).to have_http_status(:ok)
    end
  end
end
