# frozen_string_literal: true

require "rails_helper"

# Authorization gate for swarm stacks: reads -> devops.swarm.read,
# mutations -> devops.swarm.manage. Filters sit above set_* so authz
# halts before the DB lookup; no-perm cases need no stack records.
RSpec.describe "Api::V1::Devops::Swarm::Stacks authorization", type: :request do
  let(:account) { create(:account) }
  let(:cluster) { create(:devops_swarm_cluster, account: account) }

  let(:no_perm)  { create(:user, account: account, permissions: []) }
  let(:reader)   { create(:user, account: account, permissions: ["devops.swarm.read"]) }
  let(:manager)  { create(:user, account: account, permissions: ["devops.swarm.manage"]) }

  describe "no permission" do
    it "forbids a read (index)" do
      get "/api/v1/devops/swarm/clusters/#{cluster.id}/stacks",
          headers: auth_headers_for(no_perm), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "forbids a mutation (create)" do
      post "/api/v1/devops/swarm/clusters/#{cluster.id}/stacks",
           params: { stack: { name: "web", compose_file: "version: '3'" } },
           headers: auth_headers_for(no_perm), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "read permission" do
    it "permits a read (index)" do
      get "/api/v1/devops/swarm/clusters/#{cluster.id}/stacks",
          headers: auth_headers_for(reader), as: :json
      expect(response).not_to have_http_status(:forbidden)
      expect(response).to have_http_status(:ok)
    end

    it "forbids a mutation (read perm insufficient to manage)" do
      post "/api/v1/devops/swarm/clusters/#{cluster.id}/stacks",
           params: { stack: { name: "web", compose_file: "version: '3'" } },
           headers: auth_headers_for(reader), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "manage permission" do
    it "permits a mutation (create)" do
      post "/api/v1/devops/swarm/clusters/#{cluster.id}/stacks",
           params: { stack: { name: "web", compose_file: "version: '3'" } },
           headers: auth_headers_for(manager), as: :json
      expect(response).not_to have_http_status(:forbidden)
      expect(response).to have_http_status(:created)
    end
  end
end
