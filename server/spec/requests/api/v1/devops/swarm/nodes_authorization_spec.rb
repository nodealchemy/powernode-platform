# frozen_string_literal: true

require "rails_helper"

# Authorization gate for swarm nodes: reads (index/show) ->
# devops.swarm.read; node lifecycle ops (promote/demote/drain/activate/
# remove) MUTATE the cluster -> devops.swarm.manage. Filters sit above
# set_*; the no-perm/read cases need no node record (authz halts first).
RSpec.describe "Api::V1::Devops::Swarm::Nodes authorization", type: :request do
  let(:account) { create(:account) }
  let(:cluster) { create(:devops_swarm_cluster, account: account) }
  let(:node) do
    Devops::SwarmNode.create!(
      cluster: cluster, docker_node_id: "node-abc", hostname: "host-1",
      role: "worker", status: "ready", availability: "active"
    )
  end

  let(:no_perm)  { create(:user, account: account, permissions: []) }
  let(:reader)   { create(:user, account: account, permissions: ["devops.swarm.read"]) }
  let(:manager)  { create(:user, account: account, permissions: ["devops.swarm.manage"]) }

  describe "no permission" do
    it "forbids a read (index)" do
      get "/api/v1/devops/swarm/clusters/#{cluster.id}/nodes",
          headers: auth_headers_for(no_perm), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "forbids a mutation (promote)" do
      post "/api/v1/devops/swarm/clusters/#{cluster.id}/nodes/#{node.id}/promote",
           headers: auth_headers_for(no_perm), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "read permission" do
    it "permits a read (index)" do
      get "/api/v1/devops/swarm/clusters/#{cluster.id}/nodes",
          headers: auth_headers_for(reader), as: :json
      expect(response).not_to have_http_status(:forbidden)
      expect(response).to have_http_status(:ok)
    end

    it "forbids a mutation (read perm insufficient to manage)" do
      post "/api/v1/devops/swarm/clusters/#{cluster.id}/nodes/#{node.id}/promote",
           headers: auth_headers_for(reader), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "manage permission" do
    let(:node_manager_stub) { instance_double(::Devops::Docker::NodeManager) }

    before do
      allow(::Devops::Docker::NodeManager).to receive(:new).and_return(node_manager_stub)
      allow(node_manager_stub).to receive(:promote).and_return(true)
    end

    it "permits a mutation (promote)" do
      post "/api/v1/devops/swarm/clusters/#{cluster.id}/nodes/#{node.id}/promote",
           headers: auth_headers_for(manager), as: :json
      expect(response).not_to have_http_status(:forbidden)
    end
  end
end
