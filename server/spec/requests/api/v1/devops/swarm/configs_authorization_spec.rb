# frozen_string_literal: true

require "rails_helper"

# Authorization gate for swarm configs: reads (index/show) ->
# devops.swarm.read; mutations (create/destroy) -> devops.swarm.manage.
RSpec.describe "Api::V1::Devops::Swarm::Configs authorization", type: :request do
  let(:account) { create(:account) }
  let(:cluster) { create(:devops_swarm_cluster, account: account) }

  let(:no_perm)  { create(:user, account: account, permissions: []) }
  let(:reader)   { create(:user, account: account, permissions: ["devops.swarm.read"]) }
  let(:manager)  { create(:user, account: account, permissions: ["devops.swarm.manage"]) }

  let(:secret_manager_stub) { instance_double(::Devops::Docker::SecretManager) }

  before do
    allow(::Devops::Docker::SecretManager).to receive(:new).and_return(secret_manager_stub)
    allow(secret_manager_stub).to receive(:list_configs).and_return([])
    allow(secret_manager_stub).to receive(:create_config).and_return({ "ID" => "cfg" })
  end

  describe "no permission" do
    it "forbids a read (index)" do
      get "/api/v1/devops/swarm/clusters/#{cluster.id}/configs",
          headers: auth_headers_for(no_perm), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "forbids a mutation (create)" do
      post "/api/v1/devops/swarm/clusters/#{cluster.id}/configs",
           params: { config: { name: "cfg", data: "ZGF0YQ==" } },
           headers: auth_headers_for(no_perm), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "read permission" do
    it "permits a read (index)" do
      get "/api/v1/devops/swarm/clusters/#{cluster.id}/configs",
          headers: auth_headers_for(reader), as: :json
      expect(response).not_to have_http_status(:forbidden)
      expect(response).to have_http_status(:ok)
    end

    it "forbids a mutation (read perm insufficient to manage)" do
      post "/api/v1/devops/swarm/clusters/#{cluster.id}/configs",
           params: { config: { name: "cfg", data: "ZGF0YQ==" } },
           headers: auth_headers_for(reader), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "manage permission" do
    it "permits a mutation (create)" do
      post "/api/v1/devops/swarm/clusters/#{cluster.id}/configs",
           params: { config: { name: "cfg", data: "ZGF0YQ==" } },
           headers: auth_headers_for(manager), as: :json
      expect(response).not_to have_http_status(:forbidden)
      expect(response).to have_http_status(:created)
    end
  end
end
