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

    # "in_progress", not "running": that is the wire status the worker jobs
    # actually send (stack_deploy_job.rb, service_update_job.rb) when a
    # deployment starts. No producer ever sends "running" — that was a stale
    # branch removed alongside this fix. #start! records the DB-internal
    # status as "running", which is a separate vocabulary from the wire status.
    it "answers 200 with status ok in the BODY, not a 500, after the transition" do
      patch "/api/v1/internal/devops/swarm/deployments/#{deployment.id}",
            params: { status: "in_progress" }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(body).to include("success" => true, "data" => { "status" => "ok" })
      expect(deployment.reload.status).to eq("running")
    end

    it "applies a completed transition and persists the result" do
      deployment.update!(status: "running", started_at: 1.minute.ago)

      patch "/api/v1/internal/devops/swarm/deployments/#{deployment.id}",
            params: { status: "completed", result: { services: ["web"], converged: true } },
            headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(body).to include("success" => true, "data" => { "status" => "ok" })
      deployment.reload
      expect(deployment.status).to eq("completed")
      expect(deployment.result).to include("services" => ["web"], "converged" => true)
    end

    # Before this fix, "partially_converged" (sent by stack_deploy_job.rb and
    # service_update_job.rb when convergence times out but some services came
    # up) matched no branch in the case statement: the controller answered 200
    # with no error, and the row stayed "pending" forever — a silent no-op the
    # worker's caller could not tell apart from success.
    it "applies a partially_converged transition and persists the result" do
      deployment.update!(status: "running", started_at: 1.minute.ago)

      patch "/api/v1/internal/devops/swarm/deployments/#{deployment.id}",
            params: { status: "partially_converged", result: { services: ["web"], converged: false } },
            headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(body).to include("success" => true, "data" => { "status" => "ok" })
      deployment.reload
      expect(deployment.status).to eq("partially_converged")
      expect(deployment.result).to include("services" => ["web"], "converged" => false)
    end

    it "applies a failed transition and persists the error result" do
      deployment.update!(status: "running", started_at: 1.minute.ago)

      patch "/api/v1/internal/devops/swarm/deployments/#{deployment.id}",
            params: { status: "failed", result: { error_message: "boom" } },
            headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(body).to include("success" => true, "data" => { "status" => "ok" })
      deployment.reload
      expect(deployment.status).to eq("failed")
      expect(deployment.result).to include("error_message" => "boom")
    end

    # Before this fix an unrecognized status (a typo, a future worker sending a
    # not-yet-handled value) matched no branch, answered 200 with no change,
    # and left the row wherever it already was — permanently, since nothing
    # ever retries a "successful" callback. A 422 naming the value makes the
    # gap visible instead of silent.
    it "refuses an unknown status with a 422 that names it, and leaves the row unchanged" do
      patch "/api/v1/internal/devops/swarm/deployments/#{deployment.id}",
            params: { status: "bogus_status" }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body["success"]).to be(false)
      expect(body["error"]).to include("bogus_status")
      expect(deployment.reload.status).to eq("pending")
    end

    # Before this fix a non-hash `result` (an Array, a String — anything
    # without #to_unsafe_h) raised NoMethodError with no rescue in this action,
    # answering a bare 500 while the row stayed "pending".
    it "answers 422 for a non-hash result instead of 500, and leaves the row unchanged" do
      patch "/api/v1/internal/devops/swarm/deployments/#{deployment.id}",
            params: { status: "completed", result: ["not", "a", "hash"] }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body["success"]).to be(false)
      expect(deployment.reload.status).to eq("pending")
    end
  end
end
