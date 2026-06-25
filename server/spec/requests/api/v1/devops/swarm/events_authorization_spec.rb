# frozen_string_literal: true

require "rails_helper"

# Authorization gate for swarm events: reads (index/show) require devops.swarm.read,
# acknowledge (state-changing) requires devops.swarm.manage. The before_action
# filters sit before set_cluster so authz halts before any DB lookup — the
# no-perm cases therefore need no event records.
RSpec.describe "Api::V1::Devops::Swarm::Events authorization", type: :request do
  let(:account) { create(:account) }
  let(:cluster) { create(:devops_swarm_cluster, account: account) }

  let(:no_perm) { create(:user, account: account, permissions: []) }
  let(:reader)  { create(:user, account: account, permissions: [ "devops.swarm.read" ]) }
  let(:manager) { create(:user, account: account, permissions: [ "devops.swarm.read", "devops.swarm.manage" ]) }

  describe "no permission" do
    it "forbids index" do
      get "/api/v1/devops/swarm/clusters/#{cluster.id}/events",
          headers: auth_headers_for(no_perm), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "forbids acknowledge" do
      post "/api/v1/devops/swarm/clusters/#{cluster.id}/events/#{SecureRandom.uuid}/acknowledge",
           headers: auth_headers_for(no_perm), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "read permission (read cannot acknowledge)" do
    it "permits index" do
      get "/api/v1/devops/swarm/clusters/#{cluster.id}/events",
          headers: auth_headers_for(reader), as: :json
      expect(response).not_to have_http_status(:forbidden)
    end

    it "forbids acknowledge (read is not manage)" do
      post "/api/v1/devops/swarm/clusters/#{cluster.id}/events/#{SecureRandom.uuid}/acknowledge",
           headers: auth_headers_for(reader), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "manage permission" do
    it "permits acknowledge (reaches the action, not 403)" do
      # The gate passes; the action then 404s on the missing event id — still NOT forbidden.
      post "/api/v1/devops/swarm/clusters/#{cluster.id}/events/#{SecureRandom.uuid}/acknowledge",
           headers: auth_headers_for(manager), as: :json
      expect(response).not_to have_http_status(:forbidden)
    end
  end
end
