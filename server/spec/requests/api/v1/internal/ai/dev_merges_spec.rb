# frozen_string_literal: true

require "rails_helper"

# The worker reports a dev_merge_increment outcome here. The server decides
# succeeded vs failed from the remotes IT dispatched to, not from the worker's
# summary, and takes the refs and the gate attestation from the approved
# operation, never from the report.
RSpec.describe "Api::V1::Internal::Ai::DevMerges", type: :request do
  include_context "internal api auth"

  let(:sha) { "b" * 40 }
  let(:attestation) { { "framework" => "rspec", "passed" => 3, "failed" => 0 } }
  let(:remotes) do
    [ { "repository_id" => "repo-primary", "full_name" => "o/primary" },
      { "repository_id" => "repo-mirror", "full_name" => "m/mirror" } ]
  end
  let!(:operation) do
    Ai::DeferredOperation.create!(
      account: internal_account, action_category: "dev.merge", executor_class: "Ai::Executors::DeferredToolCall",
      status: "completed",
      params: { "tool_class" => "Ai::Tools::DevMergeTool", "action" => "dev_merge_increment",
                "tool_params" => { "repository" => "o/primary", "source_ref" => "feature/x", "target_branch" => "develop",
                                   "expected_source_sha" => sha, "gate_attestation" => attestation } },
      result: { "success" => true, "data" => { "dispatched" => true, "remotes" => remotes } }
    )
  end
  let(:pointer_remotes) { nil }
  # The dispatch marker: DevMergeTool writes this row BEFORE it enqueues the
  # job, so it exists before the worker can report.
  let!(:dispatched_row) do
    AuditLog.log_action(action: "dev_merge.dispatched", resource: operation, account: internal_account,
                        source: "automation", severity: "high", risk_level: "high",
                        metadata: { "remotes" => remotes,
                                    "pointer_bump" => pointer_remotes && { "remotes" => pointer_remotes } }.compact)
  end

  def report(id: operation.id, **body)
    post "/api/v1/internal/ai/dev_merges/#{id}/report", params: body.to_json, headers: service_headers
  end

  def remote(id, status, error: nil)
    { repository_id: id, full_name: id, status: status, error: error }.compact
  end

  it "accepts a report that arrives before the operation records its own result (the marker is the audit row)" do
    operation.update!(result: {})

    report(status: "succeeded", merged_sha: sha, remotes: [ remote("repo-primary", "pushed"), remote("repo-mirror", "pushed") ])

    expect(JSON.parse(response.body).dig("data", "outcome")).to eq("succeeded")
  end

  it "answers 409 for an operation with no dispatch marker" do
    dispatched_row.delete

    report(status: "succeeded", merged_sha: sha, remotes: [])

    expect(response).to have_http_status(:conflict)
  end

  it "does not take the worker's word for the merged SHA" do
    report(status: "succeeded", merged_sha: "c" * 40,
           remotes: [ remote("repo-primary", "pushed"), remote("repo-mirror", "pushed") ])

    expect(JSON.parse(response.body).dig("data", "outcome")).to eq("failed")
  end

  context "when a pointer bump was dispatched" do
    let(:pointer_remotes) { [ { "repository_id" => "repo-parent", "full_name" => "o/parent" } ] }

    it "requires the pointer commit SHA for a success" do
      report(status: "succeeded", merged_sha: sha, remotes: [ remote("repo-primary", "pushed"), remote("repo-mirror", "pushed") ],
             pointer_remotes: [ remote("repo-parent", "pushed") ])

      expect(JSON.parse(response.body).dig("data", "outcome")).to eq("failed")
    end

    it "succeeds with it" do
      report(status: "succeeded", merged_sha: sha, pointer_commit_sha: "d" * 40,
             remotes: [ remote("repo-primary", "pushed"), remote("repo-mirror", "pushed") ],
             pointer_remotes: [ remote("repo-parent", "pushed") ])

      expect(JSON.parse(response.body).dig("data", "outcome")).to eq("succeeded")
    end
  end

  it "records once even when the operation's result is overwritten between two reports" do
    report(status: "succeeded", merged_sha: sha, remotes: [ remote("repo-primary", "pushed"), remote("repo-mirror", "pushed") ])
    operation.update!(result: { "success" => true, "data" => { "dispatched" => true } })
    report(status: "failed", remotes: [])

    expect(JSON.parse(response.body).dig("data", "already_recorded")).to be(true)
    expect(AuditLog.where(resource_id: operation.id, action: %w[dev_merge.succeeded dev_merge.failed]).count).to eq(1)
  end

  it "records a merge that reached every dispatched remote as succeeded, with the approved refs and attestation" do
    report(status: "succeeded", merged_sha: sha,
           remotes: [ remote("repo-primary", "pushed"), remote("repo-mirror", "up_to_date") ])

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig("data", "outcome")).to eq("succeeded")
    row = AuditLog.find_by!(action: "dev_merge.succeeded", resource_id: operation.id)
    expect(row.metadata).to include("gate_attestation" => attestation, "expected_source_sha" => sha,
                                    "source_ref" => "feature/x", "target_branch" => "develop")
    expect(row.metadata.dig("outcome", "remotes").map { |r| r["status"] }).to eq(%w[pushed up_to_date])
  end

  it "records a push that reached only some remotes as FAILED, whatever the worker's summary says" do
    report(status: "succeeded", merged_sha: sha,
           remotes: [ remote("repo-primary", "pushed"), remote("repo-mirror", "failed", error: "rejected") ])

    expect(JSON.parse(response.body).dig("data", "outcome")).to eq("failed")
    expect(AuditLog.where(action: "dev_merge.succeeded")).to be_empty
    expect(AuditLog.find_by!(action: "dev_merge.failed", resource_id: operation.id).metadata.dig("outcome", "worker_status"))
      .to eq("succeeded")
  end

  it "records a dispatched remote the report leaves out as FAILED" do
    report(status: "succeeded", merged_sha: sha, remotes: [ remote("repo-primary", "pushed") ])

    expect(JSON.parse(response.body).dig("data", "outcome")).to eq("failed")
  end

  it "ignores an attestation the report tries to supply" do
    report(status: "failed", stage: "verify_source", error: "moved", remotes: [], gate_attestation: { "passed" => 999 })

    expect(AuditLog.find_by!(action: "dev_merge.failed").metadata["gate_attestation"]).to eq(attestation)
  end

  it "records once: a repeated report writes no second row" do
    report(status: "succeeded", merged_sha: sha,
           remotes: [ remote("repo-primary", "pushed"), remote("repo-mirror", "pushed") ])
    report(status: "failed", remotes: [])

    expect(JSON.parse(response.body).dig("data", "already_recorded")).to be(true)
    expect(AuditLog.where(resource_id: operation.id, action: %w[dev_merge.succeeded dev_merge.failed]).count).to eq(1)
    expect(operation.reload.result.dig("merge_outcome", "status")).to eq("succeeded")
  end

  it "404s an operation in another account" do
    foreign = Ai::DeferredOperation.create!(account: create(:account), action_category: "dev.merge",
                                            executor_class: "Ai::Executors::DeferredToolCall", status: "completed",
                                            result: { "data" => { "dispatched" => true } })

    report(id: foreign.id, status: "succeeded", remotes: [])

    expect(response).to have_http_status(:not_found)
  end
end
