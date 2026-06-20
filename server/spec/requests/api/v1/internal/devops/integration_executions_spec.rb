# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Internal::Devops::IntegrationExecutions", type: :request do
  let(:account) { create(:account) }
  let(:execution) { create(:devops_integration_execution, account: account, status: "queued") }

  # Worker auth via InternalBaseController (mTLS CN = worker node_instance_id)
  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    { "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end

  describe "POST /api/v1/internal/devops/integration_executions/:id/run" do
    it "triggers run_queued for the execution and returns ok" do
      allow(Devops::ExecutionService).to receive(:run_queued)
        .and_return({ success: true, execution_id: execution.id, result: { status: "ok" } })

      post run_api_v1_internal_devops_integration_execution_path(execution), headers: internal_headers

      expect(response).to have_http_status(:ok)
      expect(Devops::ExecutionService).to have_received(:run_queued)
        .with(hash_including(execution: an_instance_of(Devops::IntegrationExecution)))
    end

    it "returns 404 for an unknown execution id" do
      post run_api_v1_internal_devops_integration_execution_path("00000000-0000-0000-0000-000000000000"),
           headers: internal_headers

      expect(response).to have_http_status(:not_found)
    end

    it "returns 422 when the run fails" do
      allow(Devops::ExecutionService).to receive(:run_queued)
        .and_return({ success: false, execution_id: execution.id, error: "executor down" })

      post run_api_v1_internal_devops_integration_execution_path(execution), headers: internal_headers

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects an unauthenticated request" do
      post run_api_v1_internal_devops_integration_execution_path(execution)

      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    end
  end
end
