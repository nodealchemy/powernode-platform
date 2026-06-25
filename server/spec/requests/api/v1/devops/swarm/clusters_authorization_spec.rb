# frozen_string_literal: true

require "rails_helper"

# Authorization gate for swarm clusters: reads (index/show/health/
# test_connection) -> devops.swarm.read; mutations (create/update/
# destroy/sync) -> devops.swarm.manage. test_connection is a POST but
# only PROBES, so it is a read. Filters sit above set_cluster.
RSpec.describe "Api::V1::Devops::Swarm::Clusters authorization", type: :request do
  let(:account) { create(:account) }
  let(:cluster) { create(:devops_swarm_cluster, account: account) }

  let(:no_perm)  { create(:user, account: account, permissions: []) }
  let(:reader)   { create(:user, account: account, permissions: ["devops.swarm.read"]) }
  let(:manager)  { create(:user, account: account, permissions: ["devops.swarm.manage"]) }

  describe "no permission" do
    it "forbids a read (index)" do
      get "/api/v1/devops/swarm/clusters",
          headers: auth_headers_for(no_perm), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "forbids a mutation (create)" do
      post "/api/v1/devops/swarm/clusters",
           params: { cluster: { name: "c1", api_endpoint: "https://swarm.example.com:2377" } },
           headers: auth_headers_for(no_perm), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "read permission" do
    it "permits a read (index)" do
      get "/api/v1/devops/swarm/clusters",
          headers: auth_headers_for(reader), as: :json
      expect(response).not_to have_http_status(:forbidden)
      expect(response).to have_http_status(:ok)
    end

    it "forbids a mutation (read perm insufficient to manage)" do
      post "/api/v1/devops/swarm/clusters",
           params: { cluster: { name: "c1", api_endpoint: "https://swarm.example.com:2377" } },
           headers: auth_headers_for(reader), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "manage permission" do
    let(:swarm_manager_stub) { instance_double(::Devops::Docker::SwarmManager) }

    before do
      allow(::Devops::Docker::SwarmManager).to receive(:new).and_return(swarm_manager_stub)
      allow(swarm_manager_stub).to receive(:register_cluster).and_return(cluster)
    end

    it "permits a mutation (create)" do
      post "/api/v1/devops/swarm/clusters",
           params: { cluster: { name: "c1", api_endpoint: "https://swarm.example.com:2377" } },
           headers: auth_headers_for(manager), as: :json
      expect(response).not_to have_http_status(:forbidden)
      expect(response).to have_http_status(:created)
    end
  end
end
