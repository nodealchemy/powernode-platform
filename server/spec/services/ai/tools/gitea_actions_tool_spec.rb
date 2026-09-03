# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::GiteaActionsTool do
  let(:account) { create(:account) }
  let(:tool) { described_class.new(account: account) }

  let(:gitea_provider) do
    ::Devops::GitProvider.find_or_create_by!(account: account, provider_type: "gitea") do |p|
      p.name = "Gitea"
      p.slug = "gitea-#{SecureRandom.hex(4)}"
      p.api_base_url = "https://git.example.com"
      p.capabilities = { "actions" => true }
    end
  end
  let!(:credential) do
    # Factory uses :provider (not :git_provider) + encrypted_credentials column.
    # Token is stored encrypted; ApiClient.for unwraps it. We stub
    # ApiClient.for so the actual token doesn't matter for unit tests.
    create(:git_provider_credential,
           account: account,
           provider: gitea_provider,
           is_active: true,
           is_default: true)
  end

  let(:client) { instance_double(Devops::Git::GiteaApiClient) }

  before do
    # Always return our stubbed Gitea client when the tool resolves a credential.
    allow(::Devops::Git::ApiClient).to receive(:for).with(credential).and_return(client)
  end

  describe ".definition" do
    it "exposes the gitea_actions tool name" do
      expect(described_class.definition[:name]).to eq("gitea_actions")
    end

    it "lists all 18 actions in ACTIONS constant" do
      expect(described_class::ACTIONS).to contain_exactly(
        "set_gitea_action_secret",
        "set_gitea_action_secrets_bulk",
        "list_gitea_action_secrets",
        "delete_gitea_action_secret",
        "dispatch_gitea_workflow",
        "list_gitea_workflows",
        "list_gitea_workflow_runs",
        "get_gitea_workflow_run",
        "get_gitea_job_logs",
        "cancel_gitea_workflow_run",
        "delete_gitea_workflow_run",
        "rerun_gitea_workflow",
        "rerun_gitea_workflow_failed_jobs",
        "rerun_gitea_job",
        "list_gitea_run_artifacts",
        "create_gitea_user_token",
        "list_gitea_user_tokens",
        "delete_gitea_user_token"
      )
    end

    it "documents each action in action_definitions" do
      defs = described_class.action_definitions
      described_class::ACTIONS.each do |action|
        expect(defs).to have_key(action), "missing action_definitions[#{action.inspect}]"
        expect(defs[action][:description]).to be_present
      end
    end
  end

  describe "permission" do
    it "requires devops.ci.write" do
      expect(described_class::REQUIRED_PERMISSION).to eq("devops.ci.write")
    end
  end

  describe "#call — auth + dispatch guards" do
    it "returns error when no Gitea credential is configured for the account" do
      credential.update!(is_active: false)
      result = tool.execute(params: { action: "list_gitea_action_secrets", owner: "x", repo: "y" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/No active Gitea credential/)
    end

    it "returns error for an unknown action" do
      result = tool.execute(params: { action: "frobulate_gitea", owner: "x", repo: "y" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/Unknown action/)
    end

    # owner/repo blank-checks are enforced at BaseTool.validate_params!
    # (returns "Missing required parameters: ...") so the tool's own
    # require_owner_repo guard exists as a belt-and-suspenders for any
    # path that bypasses validate_params!.
  end

  describe "set_gitea_action_secret" do
    it "delegates to client.create_or_update_action_secret" do
      expect(client).to receive(:create_or_update_action_secret)
        .with("powernode", "powernode-system", "MY_SECRET", "plaintext-value")
        .and_return({ success: true, name: "MY_SECRET" })

      result = tool.execute(params: {
        action: "set_gitea_action_secret",
        owner: "powernode", repo: "powernode-system",
        secret_name: "MY_SECRET", secret_value: "plaintext-value"
      })
      expect(result[:success]).to be true
      expect(result[:secret_name]).to eq("MY_SECRET")
      expect(result[:message]).to match(/Plaintext is not retrievable/)
    end

    it "surfaces client errors" do
      expect(client).to receive(:create_or_update_action_secret)
        .and_return({ success: false, error: "API error (400): invalid variable or secret name" })

      result = tool.execute(params: {
        action: "set_gitea_action_secret",
        owner: "x", repo: "y",
        secret_name: "GITEA_FOO", secret_value: "v"
      })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/invalid variable or secret name/)
    end
  end

  describe "set_gitea_action_secrets_bulk" do
    it "sets multiple secrets and reports per-secret status" do
      expect(client).to receive(:create_or_update_action_secret).with("o", "r", "A", "1").and_return({ success: true })
      expect(client).to receive(:create_or_update_action_secret).with("o", "r", "B", "2").and_return({ success: true })

      result = tool.execute(params: {
        action: "set_gitea_action_secrets_bulk",
        owner: "o", repo: "r",
        secrets: { "A" => "1", "B" => "2" }
      })
      expect(result[:success]).to be true
      expect(result[:set_count]).to eq(2)
      expect(result[:failed_count]).to eq(0)
    end

    it "reports partial failures without blowing up the whole batch" do
      allow(client).to receive(:create_or_update_action_secret).with("o", "r", "A", "1").and_return({ success: true })
      allow(client).to receive(:create_or_update_action_secret).with("o", "r", "BAD", "x").and_return({ success: false, error: "rejected" })

      result = tool.execute(params: {
        action: "set_gitea_action_secrets_bulk",
        owner: "o", repo: "r",
        secrets: { "A" => "1", "BAD" => "x" }
      })
      expect(result[:success]).to be false
      expect(result[:set_count]).to eq(1)
      expect(result[:failed_count]).to eq(1)
      expect(result[:results].find { |r| r[:secret_name] == "BAD" }[:error]).to eq("rejected")
    end

    it "returns error when secrets hash is missing or empty" do
      result = tool.execute(params: { action: "set_gitea_action_secrets_bulk", owner: "o", repo: "r", secrets: {} })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/secrets hash required/)
    end
  end

  describe "list_gitea_action_secrets" do
    it "returns the list of secret name metadata" do
      allow(client).to receive(:list_action_secrets).with("o", "r").and_return([
        { name: "A", created_at: "2026-05-03T00:00:00Z" },
        { name: "B", created_at: "2026-05-03T00:01:00Z" }
      ])
      result = tool.execute(params: { action: "list_gitea_action_secrets", owner: "o", repo: "r" })
      expect(result[:success]).to be true
      expect(result[:count]).to eq(2)
      expect(result[:secrets].map { |s| s[:name] }).to contain_exactly("A", "B")
    end
  end

  describe "delete_gitea_action_secret" do
    it "delegates to client and returns success message" do
      allow(client).to receive(:delete_action_secret).with("o", "r", "A").and_return({ success: true })
      result = tool.execute(params: { action: "delete_gitea_action_secret", owner: "o", repo: "r", secret_name: "A" })
      expect(result[:success]).to be true
      expect(result[:message]).to eq("Secret deleted")
    end
  end

  describe "dispatch_gitea_workflow" do
    it "delegates to client.trigger_workflow with inputs" do
      expect(client).to receive(:trigger_workflow)
        .with("o", "r", "build.yaml", "master", { "platform_url" => "http://x" })
        .and_return({ success: true })

      result = tool.execute(params: {
        action: "dispatch_gitea_workflow",
        owner: "o", repo: "r",
        workflow_file: "build.yaml", ref: "master",
        inputs: { "platform_url" => "http://x" }
      })
      expect(result[:success]).to be true
      expect(result[:workflow_file]).to eq("build.yaml")
    end

    it "requires workflow_file" do
      result = tool.execute(params: { action: "dispatch_gitea_workflow", owner: "o", repo: "r", ref: "master" })
      expect(result[:error]).to eq("workflow_file required")
    end

    it "requires ref" do
      result = tool.execute(params: { action: "dispatch_gitea_workflow", owner: "o", repo: "r", workflow_file: "x.yaml" })
      expect(result[:error]).to eq("ref required")
    end
  end

  describe "list_gitea_workflows" do
    it "normalizes hash entries to {name, path, state}" do
      allow(client).to receive(:list_workflows).with("o", "r").and_return([
        { "name" => "build", "path" => ".gitea/workflows/build.yaml", "state" => "active" }
      ])
      result = tool.execute(params: { action: "list_gitea_workflows", owner: "o", repo: "r" })
      expect(result[:success]).to be true
      expect(result[:count]).to eq(1)
      expect(result[:workflows].first).to include(name: "build", state: "active")
    end

    it "handles bare-string entries gracefully" do
      allow(client).to receive(:list_workflows).with("o", "r").and_return(["build.yaml"])
      result = tool.execute(params: { action: "list_gitea_workflows", owner: "o", repo: "r" })
      expect(result[:workflows].first[:name]).to eq("build.yaml")
    end
  end

  describe "list_gitea_workflow_runs" do
    it "passes options through to client" do
      # Method signature uses `options = {}` (positional hash, Ruby 2 style).
      expect(client).to receive(:list_workflow_runs).with("o", "r", { workflow_file: "build.yaml", limit: 5 })
                                                    .and_return([{ id: 1 }, { id: 2 }])
      result = tool.execute(params: {
        action: "list_gitea_workflow_runs",
        owner: "o", repo: "r",
        workflow_file: "build.yaml", limit: 5
      })
      expect(result[:count]).to eq(2)
    end

    it "defaults limit to 20 when unspecified" do
      expect(client).to receive(:list_workflow_runs).with("o", "r", { limit: 20 }).and_return([])
      tool.execute(params: { action: "list_gitea_workflow_runs", owner: "o", repo: "r" })
    end
  end

  describe "get_gitea_workflow_run" do
    it "fetches run + jobs in one response" do
      allow(client).to receive(:get_workflow_run).with("o", "r", "42").and_return({ id: 42, status: "completed" })
      allow(client).to receive(:get_workflow_run_jobs).with("o", "r", "42").and_return([{ id: 100, name: "build" }])
      result = tool.execute(params: { action: "get_gitea_workflow_run", owner: "o", repo: "r", run_id: "42" })
      expect(result[:run][:status]).to eq("completed")
      expect(result[:jobs].first[:name]).to eq("build")
    end
  end

  describe "get_gitea_job_logs" do
    let(:full_logs) { (1..100).map { |i| "2026-05-03T00:00:00Z line #{i} #{'error' if i.even?}\n" }.join }

    it "returns full logs by default" do
      allow(client).to receive(:get_job_logs).with("o", "r", "999").and_return(full_logs)
      result = tool.execute(params: { action: "get_gitea_job_logs", owner: "o", repo: "r", job_id: "999" })
      expect(result[:success]).to be true
      expect(result[:logs].lines.length).to eq(100)
    end

    it "applies tail filter server-side" do
      allow(client).to receive(:get_job_logs).and_return(full_logs)
      result = tool.execute(params: { action: "get_gitea_job_logs", owner: "o", repo: "r", job_id: "999", tail: 5 })
      expect(result[:logs].lines.length).to eq(5)
    end

    it "applies grep filter server-side (case-insensitive)" do
      allow(client).to receive(:get_job_logs).and_return(full_logs)
      result = tool.execute(params: { action: "get_gitea_job_logs", owner: "o", repo: "r", job_id: "999", grep: "ERROR" })
      expect(result[:logs].lines.length).to eq(50) # only even-numbered lines have "error"
    end

    it "combines tail + grep" do
      allow(client).to receive(:get_job_logs).and_return(full_logs)
      result = tool.execute(params: { action: "get_gitea_job_logs", owner: "o", repo: "r", job_id: "999", grep: "error", tail: 3 })
      expect(result[:logs].lines.length).to eq(3)
    end

    it "errors when client returns no string" do
      allow(client).to receive(:get_job_logs).and_return(nil)
      result = tool.execute(params: { action: "get_gitea_job_logs", owner: "o", repo: "r", job_id: "999" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/no logs returned/)
    end

    it "requires job_id" do
      result = tool.execute(params: { action: "get_gitea_job_logs", owner: "o", repo: "r" })
      expect(result[:error]).to eq("job_id required")
    end
  end

  describe "cancel_gitea_workflow_run" do
    it "delegates to client.cancel_workflow_run" do
      expect(client).to receive(:cancel_workflow_run).with("o", "r", "42").and_return({ success: true })
      result = tool.execute(params: { action: "cancel_gitea_workflow_run", owner: "o", repo: "r", run_id: "42" })
      expect(result[:success]).to be true
      expect(result[:message]).to eq("Workflow run cancelled")
    end

    # Gitea has no cancel endpoint (verified against the live 1.27.0 Actions
    # API). The old code POSTed a GitHub-shaped path, so every call came back
    # "Resource not found" — indistinguishable from a run that doesn't exist,
    # which is how it burned real debugging time while trying to clear a CI
    # queue. The unsupported flag is what lets a caller tell the two apart.
    it "surfaces an unsupported backend distinctly from a missing run" do
      allow(client).to receive(:cancel_workflow_run).and_return(
        { success: false, unsupported: true, error: "Gitea exposes no API to cancel a workflow run" }
      )
      result = tool.execute(params: { action: "cancel_gitea_workflow_run", owner: "o", repo: "r", run_id: "42" })

      expect(result[:success]).to be false
      expect(result[:unsupported]).to be true
      expect(result[:error]).to match(/no API to cancel/i)
      expect(result[:run_id]).to eq("42")
    end

    # The one thing this must never do: quietly turn "cancel" into "delete".
    # DELETE is the only run-level mutation Gitea offers, it does not stop a
    # running job, and it destroys the run's logs.
    it "never falls back to deleting the run" do
      allow(client).to receive(:cancel_workflow_run).and_return({ success: false, unsupported: true, error: "unsupported" })
      expect(client).not_to receive(:delete_workflow_run)

      tool.execute(params: { action: "cancel_gitea_workflow_run", owner: "o", repo: "r", run_id: "42" })
    end
  end

  describe "delete_gitea_workflow_run" do
    it "delegates to client.delete_workflow_run and says it is not a cancel" do
      expect(client).to receive(:delete_workflow_run).with("o", "r", "42").and_return({ success: true })
      result = tool.execute(params: { action: "delete_gitea_workflow_run", owner: "o", repo: "r", run_id: "42" })

      expect(result[:success]).to be true
      expect(result[:message]).to match(/does not stop a running job/i)
    end

    it "requires a run_id" do
      result = tool.execute(params: { action: "delete_gitea_workflow_run", owner: "o", repo: "r" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/run_id required/)
    end
  end

  describe "rerun_gitea_workflow_failed_jobs" do
    it "delegates to client.rerun_workflow_failed_jobs" do
      expect(client).to receive(:rerun_workflow_failed_jobs).with("o", "r", "42").and_return({ success: true })
      result = tool.execute(params: { action: "rerun_gitea_workflow_failed_jobs", owner: "o", repo: "r", run_id: "42" })
      expect(result[:success]).to be true
      expect(result[:message]).to match(/failed jobs/i)
    end
  end

  describe "rerun_gitea_job" do
    it "delegates to client.rerun_job with both ids" do
      expect(client).to receive(:rerun_job).with("o", "r", "42", "7").and_return({ success: true })
      result = tool.execute(params: { action: "rerun_gitea_job", owner: "o", repo: "r", run_id: "42", job_id: "7" })
      expect(result[:success]).to be true
      expect(result[:job_id]).to eq("7")
    end

    it "requires a job_id" do
      result = tool.execute(params: { action: "rerun_gitea_job", owner: "o", repo: "r", run_id: "42" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/job_id required/)
    end
  end

  describe "list_gitea_run_artifacts" do
    it "delegates to client.list_run_artifacts" do
      expect(client).to receive(:list_run_artifacts).with("o", "r", "42")
        .and_return([ { "name" => "disk-image", "size_in_bytes" => 1024 } ])
      result = tool.execute(params: { action: "list_gitea_run_artifacts", owner: "o", repo: "r", run_id: "42" })

      expect(result[:success]).to be true
      expect(result[:count]).to eq(1)
    end
  end

  describe "rerun_gitea_workflow" do
    it "delegates to client.rerun_workflow" do
      expect(client).to receive(:rerun_workflow).with("o", "r", "42").and_return({ success: true })
      result = tool.execute(params: { action: "rerun_gitea_workflow", owner: "o", repo: "r", run_id: "42" })
      expect(result[:success]).to be true
      expect(result[:message]).to eq("Workflow run re-queued")
    end
  end

  # IMP-27cc7dceb97b — the minted PAT is no longer returned on this surface
  # (an MCP result is persisted into ai_messages.processing_metadata and
  # forwarded to the model provider). Gitea cannot re-show a PAT, so there is
  # no retrieval path to name: the out-of-band `set_as_secret` delivery is now
  # mandatory. The disclosure oracle proper lives in
  # gitea_actions_tool_mcp_disclosure_spec.rb.
  describe "create_gitea_user_token" do
    let(:delivery) { { owner: "o", repo: "r", secret_name: "PLATFORM_READ_TOKEN" } }

    it "mints and delivers the token to Gitea without returning the plaintext" do
      expect(client).to receive(:create_user_token)
        .with("my-token", scopes: %w[read:repository])
        .and_return({
          success: true, token_id: 42, name: "my-token",
          token: "abcdef0123456789abcdef0123456789abcdef01",
          scopes: %w[read:repository]
        })
      expect(client).to receive(:create_or_update_action_secret)
        .with("o", "r", "PLATFORM_READ_TOKEN", "abcdef0123456789abcdef0123456789abcdef01")
        .and_return({ success: true })

      result = tool.execute(params: {
        action: "create_gitea_user_token", token_name: "my-token", set_as_secret: delivery
      })
      expect(result[:success]).to be true
      expect(result).not_to have_key(:plaintext)
      expect(result[:token_id]).to eq(42)
      expect(result[:set_as_secret]).to include(ok: true, secret_name: "PLATFORM_READ_TOKEN")
      expect(result[:note]).to match(/secrets\.PLATFORM_READ_TOKEN/)
    end

    it "respects custom scopes" do
      expect(client).to receive(:create_user_token)
        .with("admin-token", scopes: %w[write:user write:repository])
        .and_return({ success: true, token_id: 1, name: "admin-token", token: "x" * 40, scopes: %w[write:user write:repository] })
      allow(client).to receive(:create_or_update_action_secret).and_return({ success: true })

      tool.execute(params: {
        action: "create_gitea_user_token", token_name: "admin-token",
        scopes: %w[write:user write:repository], set_as_secret: delivery
      })
    end

    it "refuses BEFORE minting when no delivery target is given" do
      expect(client).not_to receive(:create_user_token)

      result = tool.execute(params: { action: "create_gitea_user_token", token_name: "n" })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/set_as_secret/)
      expect(result[:error]).to match(/No token was created/)
    end

    it "refuses on a partial delivery target rather than minting an undeliverable token" do
      expect(client).not_to receive(:create_user_token)

      result = tool.execute(params: {
        action: "create_gitea_user_token", token_name: "n",
        set_as_secret: { owner: "o", repo: "r" }
      })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/set_as_secret/)
    end

    it "revokes the mint when delivery fails, since the plaintext is not returned" do
      allow(client).to receive(:create_user_token).and_return({ success: true, token_id: 7, name: "n", token: "t" * 40, scopes: [] })
      allow(client).to receive(:create_or_update_action_secret).and_return({ success: false, error: "rejected" })
      expect(client).to receive(:delete_user_token).with(7).and_return({ success: true })

      result = tool.execute(params: {
        action: "create_gitea_user_token", token_name: "n",
        set_as_secret: { owner: "o", repo: "r", secret_name: "X" }
      })
      expect(result[:success]).to be false
      expect(result).not_to have_key(:plaintext)
      expect(result[:set_as_secret][:ok]).to be false
      expect(result[:revoked_undeliverable_token]).to be true
      expect(result[:note]).to match(/revoked again/)
    end

    # GiteaApiClient#delete_user_token signals failure by RETURN VALUE, not by
    # raising (with_error_handling converts NotFoundError/ApiError into
    # {success: false}). This is the LIKELY failure mode, and a rescue-only
    # cleanup check would report revoked_undeliverable_token: true while a live
    # PAT stayed on the account.
    it "reports a return-value revoke failure as NOT revoked and says the token is live" do
      allow(client).to receive(:create_user_token).and_return({ success: true, token_id: 7, name: "n", token: "t" * 40, scopes: [] })
      allow(client).to receive(:create_or_update_action_secret).and_return({ success: false, error: "rejected" })
      allow(client).to receive(:delete_user_token).and_return({ success: false, error: "Gitea PAT deletion failed (404)" })

      result = tool.execute(params: {
        action: "create_gitea_user_token", token_name: "n",
        set_as_secret: { owner: "o", repo: "r", secret_name: "X" }
      })
      expect(result[:success]).to be false
      expect(result[:revoked_undeliverable_token]).to be false
      expect(result[:cleanup_error]).to match(/404/)
      expect(result[:note]).to match(/revoke it by hand/)
    end

    it "reports a cleanup failure instead of raising when the revoke also fails" do
      allow(client).to receive(:create_user_token).and_return({ success: true, token_id: 7, name: "n", token: "t" * 40, scopes: [] })
      allow(client).to receive(:create_or_update_action_secret).and_return({ success: false, error: "rejected" })
      allow(client).to receive(:delete_user_token).and_raise(StandardError, "gitea down")

      result = tool.execute(params: {
        action: "create_gitea_user_token", token_name: "n",
        set_as_secret: { owner: "o", repo: "r", secret_name: "X" }
      })
      expect(result[:success]).to be false
      expect(result[:revoked_undeliverable_token]).to be false
      expect(result[:cleanup_error]).to match(/gitea down/)
      expect(result[:note]).to match(/revoke it by hand/)
    end

    it "does not claim an automatic revoke when Gitea returned no token_id" do
      allow(client).to receive(:create_user_token).and_return({ success: true, token_id: nil, name: "n", token: "t" * 40, scopes: [] })
      allow(client).to receive(:create_or_update_action_secret).and_return({ success: false, error: "rejected" })
      expect(client).not_to receive(:delete_user_token)

      result = tool.execute(params: {
        action: "create_gitea_user_token", token_name: "n",
        set_as_secret: { owner: "o", repo: "r", secret_name: "X" }
      })
      expect(result[:revoked_undeliverable_token]).to be false
      expect(result[:cleanup_error]).to match(/no token_id/)
    end

    it "rejects blank token_name" do
      result = tool.execute(params: { action: "create_gitea_user_token", token_name: "" })
      expect(result[:success]).to be false
      expect(result[:error]).to eq("token_name required")
    end

    it "surfaces upstream Gitea PAT creation errors" do
      expect(client).to receive(:create_user_token).and_return({ success: false, error: "Gitea PAT creation failed (401): bad credentials" })
      result = tool.execute(params: {
        action: "create_gitea_user_token", token_name: "x", set_as_secret: delivery
      })
      expect(result[:success]).to be false
      expect(result[:error]).to match(/Gitea PAT creation failed/)
    end
  end

  describe "list_gitea_user_tokens" do
    it "returns the list shape with id + name + scopes per token" do
      expect(client).to receive(:list_user_tokens).and_return([
        { id: 1, name: "dev",      scopes: %w[all] },
        { id: 2, name: "platform", scopes: %w[read:repository] }
      ])
      result = tool.execute(params: { action: "list_gitea_user_tokens" })
      expect(result[:success]).to be true
      expect(result[:count]).to eq(2)
      expect(result[:tokens].map { |t| t[:name] }).to contain_exactly("dev", "platform")
    end
  end

  describe "delete_gitea_user_token" do
    it "delegates to client.delete_user_token" do
      expect(client).to receive(:delete_user_token).with("dev").and_return({ success: true })
      result = tool.execute(params: { action: "delete_gitea_user_token", name_or_id: "dev" })
      expect(result[:success]).to be true
      expect(result[:message]).to eq("User token deleted")
    end

    it "rejects blank name_or_id" do
      result = tool.execute(params: { action: "delete_gitea_user_token" })
      expect(result[:success]).to be false
      expect(result[:error]).to eq("name_or_id required")
    end
  end
end
