# frozen_string_literal: true

require "rails_helper"

# Worker -> server door for retrying post-deletion cleanup (PlatformPurgeTask).
RSpec.describe "Api::V1::Internal platform purge task sweep", type: :request do
  let(:account) { create(:account) }
  let(:system_worker) { create(:worker, :system_worker, account: account) }
  let(:worker_headers) do
    { "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{system_worker.node_instance_id}")),
      "Content-Type" => "application/json" }
  end

  it "refuses a request with no worker identity" do
    post "/api/v1/internal/platform/purge_tasks/sweep", params: "{}", headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "runs the due tasks and reports totals" do
    task = PlatformPurgeTask.enqueue!(kind: "secret_store_account", subject_id: SecureRandom.uuid, error: StandardError.new)
    task.update_columns(next_attempt_at: 1.minute.ago)
    allow(Security::SecretStore).to receive(:purge_account).and_return(1)
    system_worker

    post "/api/v1/internal/platform/purge_tasks/sweep", params: "{}", headers: worker_headers

    expect(response).to have_http_status(:ok)
    expect(json_response_data).to include("completed" => 1, "failed" => 0, "pending" => 0)
  end
end
