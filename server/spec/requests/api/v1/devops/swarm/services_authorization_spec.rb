# frozen_string_literal: true

require "rails_helper"

# Authorization gate for swarm services: reads require devops.swarm.read,
# mutations require devops.swarm.manage. The before_action filters sit at
# the top of the controller so authz halts before any DB lookup — the
# no-perm cases therefore need no service records.
RSpec.describe "Api::V1::Devops::Swarm::Services authorization", type: :request do
  let(:account) { create(:account) }
  let(:cluster) { create(:devops_swarm_cluster, account: account) }

  let(:no_perm)  { create(:user, account: account, permissions: []) }
  let(:reader)   { create(:user, account: account, permissions: ["devops.swarm.read"]) }
  let(:manager)  { create(:user, account: account, permissions: ["devops.swarm.manage"]) }

  describe "no permission" do
    it "forbids a read (index)" do
      get "/api/v1/devops/swarm/clusters/#{cluster.id}/services",
          headers: auth_headers_for(no_perm), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "forbids a mutation (import)" do
      post "/api/v1/devops/swarm/clusters/#{cluster.id}/services/import",
           params: { docker_service_ids: ["abc"] },
           headers: auth_headers_for(no_perm), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "read permission" do
    it "permits a read (index)" do
      get "/api/v1/devops/swarm/clusters/#{cluster.id}/services",
          headers: auth_headers_for(reader), as: :json
      expect(response).not_to have_http_status(:forbidden)
      expect(response).to have_http_status(:ok)
    end

    it "forbids a mutation (read perm insufficient to manage)" do
      post "/api/v1/devops/swarm/clusters/#{cluster.id}/services/import",
           params: { docker_service_ids: ["abc"] },
           headers: auth_headers_for(reader), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "manage permission" do
    let(:swarm_manager_stub) { instance_double(::Devops::Docker::SwarmManager) }

    before do
      allow(::Devops::Docker::SwarmManager).to receive(:new).and_return(swarm_manager_stub)
      allow(swarm_manager_stub).to receive(:import_services).and_return([])
    end

    it "permits a mutation (import)" do
      post "/api/v1/devops/swarm/clusters/#{cluster.id}/services/import",
           params: { docker_service_ids: ["abc"] },
           headers: auth_headers_for(manager), as: :json
      expect(response).not_to have_http_status(:forbidden)
    end
  end
end
