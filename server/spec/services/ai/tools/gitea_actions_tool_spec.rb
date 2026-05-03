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

    it "lists all 11 actions in ACTIONS constant" do
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
        "rerun_gitea_workflow"
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
    it "requires ai.workflows.update" do
      expect(described_class::REQUIRED_PERMISSION).to eq("ai.workflows.update")
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
  end

  describe "rerun_gitea_workflow" do
    it "delegates to client.rerun_workflow" do
      expect(client).to receive(:rerun_workflow).with("o", "r", "42").and_return({ success: true })
      result = tool.execute(params: { action: "rerun_gitea_workflow", owner: "o", repo: "r", run_id: "42" })
      expect(result[:success]).to be true
      expect(result[:message]).to eq("Workflow run re-queued")
    end
  end
end
