# frozen_string_literal: true

require "rails_helper"

# Authorization gate for kubernetes nodes: read-only controller
# (index/show) -> devops.kubernetes.read. No mutations, so no manage gate.
RSpec.describe "Api::V1::Devops::Kubernetes::Nodes authorization", type: :request do
  let(:account) { create(:account) }
  let(:cluster) { create(:devops_kubernetes_cluster, account: account) }

  let(:no_perm) { create(:user, account: account, permissions: []) }
  let(:reader)  { create(:user, account: account, permissions: ["devops.kubernetes.read"]) }

  describe "no permission" do
    it "forbids a read (index)" do
      get "/api/v1/devops/kubernetes/clusters/#{cluster.id}/nodes",
          headers: auth_headers_for(no_perm), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "read permission" do
    it "permits a read (index)" do
      get "/api/v1/devops/kubernetes/clusters/#{cluster.id}/nodes",
          headers: auth_headers_for(reader), as: :json
      expect(response).not_to have_http_status(:forbidden)
      expect(response).to have_http_status(:ok)
    end
  end
end
