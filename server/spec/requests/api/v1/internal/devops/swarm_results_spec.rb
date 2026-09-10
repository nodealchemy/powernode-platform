# frozen_string_literal: true

require "rails_helper"

# Three swarm worker callbacks ended in `render_success(status: "ok")`. Written
# braceless, that `status:` binds render_success's HTTP-status keyword
# (api_response.rb:16), so "ok" raised "Invalid HTTP status":
#
#   * sync_results / health_results rescue StandardError, so a callback whose
#     work had ALREADY COMMITTED answered 422. The worker's client raises on a
#     4xx and Sidekiq retries — and health_results has a side effect per call
#     (it increments the failure streak and creates events), so a retry
#     double-counts what the first call already recorded.
#   * update_deployment rescues only RecordNotFound, so it answered 500 on the
#     worker seam: a retry-storm trigger.
#
# The rows were always written, which is why only the BODY and the HTTP status
# can see this. Every example below asserts both, plus the row it changed.
RSpec.describe "Api::V1::Internal::Devops::Swarm result callbacks", type: :request do
  let(:account) { create(:account) }
  let(:worker) { create(:worker, account: account) }
  let(:headers) do
    { "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{worker.node_instance_id}")) }
  end
  let(:cluster) do
    create(:devops_swarm_cluster, account: account, status: "connected", consecutive_failures: 2)
  end

  def body = JSON.parse(response.body)

  describe "POST sync_results" do
    it "answers 200 with status ok in the BODY after the sync commits" do
      post "/api/v1/internal/devops/swarm/clusters/#{cluster.id}/sync_results",
           params: {}, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(body).to include("success" => true, "data" => { "status" => "ok" })

      cluster.reload
      expect(cluster.last_synced_at).to be_present
      expect(cluster.consecutive_failures).to eq(0)
    end
  end

  describe "POST health_results" do
    it "answers 200 with status ok in the BODY for a healthy report" do
      post "/api/v1/internal/devops/swarm/clusters/#{cluster.id}/health_results",
           params: { status: "healthy" }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(body).to include("success" => true, "data" => { "status" => "ok" })
      expect(cluster.reload.consecutive_failures).to eq(0)
    end

    # A single unhealthy report must count ONCE. Before the fix it answered 422
    # after recording, so the worker retried and the streak climbed per retry.
    it "answers 200 for an unhealthy report and counts the failure exactly once" do
      expect do
        post "/api/v1/internal/devops/swarm/clusters/#{cluster.id}/health_results",
             params: { status: "unhealthy" }, headers: headers, as: :json
      end.to change { cluster.reload.consecutive_failures }.by(1)

      expect(response).to have_http_status(:ok)
      expect(body).to include("success" => true, "data" => { "status" => "ok" })
    end
  end

  describe "PATCH deployments/:id" do
    let(:deployment) do
      Devops::SwarmDeployment.create!(cluster: cluster, deployment_type: "deploy", status: "pending")
    end

    it "answers 200 with status ok in the BODY, not a 500, after the transition" do
      patch "/api/v1/internal/devops/swarm/deployments/#{deployment.id}",
            params: { status: "running" }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(body).to include("success" => true, "data" => { "status" => "ok" })
      expect(deployment.reload.status).to eq("running")
    end
  end
end
