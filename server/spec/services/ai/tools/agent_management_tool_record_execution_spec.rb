# frozen_string_literal: true

require "rails_helper"

# HIER-P1C — a Claude Code run of a platform agent (Agent(subagent_type:
# "<slug>") on a committed .claude/agents/powernode/ skeleton) reports back
# through platform.record_agent_execution and lands as ONE Ai::AgentExecution
# attributed to the TARGET agent, executed by the calling session's mcp_client
# identity. The row goes through the model's own terminal-status hooks
# UNCHANGED (trust evaluation + Ai::AgentModelPerformance.record!), so the
# platform's trust and model statistics see the run exactly as they see a
# platform execution — while autonomy budgets, approval and consent accounting
# (platform-execution concepts) are never touched.
RSpec.describe Ai::Tools::AgentManagementTool, "record_agent_execution" do
  RSpec::Matchers.define_negated_matcher :not_change, :change

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: %w[ai.agents.read ai.agents.execute]) }
  let!(:provider) { create(:ai_provider, account: account, is_active: true) }
  # The synthetic scope is SEEDED (db/seeds/ai_claude_code_provider_seed.rb /
  # Accounts::ProvisionService), never minted by the report path —
  # spec/services/ai/claude_export/execution_recorder_spec.rb pins the refusal.
  let!(:claude_code_scope) { Ai::ClaudeExport::ProviderScopeSeeder.ensure_for!(account) }
  # The calling Claude Code session's identity (Ai::McpClientIdentityService
  # auto-registers one per MCP session); McpPlatformToolRegistrar hands it to
  # the tool as `agent:`.
  let(:session_agent) { create(:ai_agent, :mcp_client, account: account) }
  let(:tool) { described_class.new(account: account, user: user, agent: session_agent) }

  let!(:canonical) do
    create(:ai_agent, :global, is_system: true, name: "CVE Responder", agent_type: "monitor",
                               description: "CVE intake and remediation.")
  end

  def report(**overrides)
    params = {
      action: "record_agent_execution",
      agent_slug: canonical.slug,
      model: "claude-opus-5",
      outcome: "completed",
      duration_ms: 42_000,
      tokens: { input: 1200, output: 340 },
      task_digest: "triage the new critical CVE",
      run_key: "sess-1:agent-a1"
    }.merge(overrides)
    tool.execute(params: params)
  end

  describe "declaration" do
    it "is registered in the platform registry on this tool and declared mutating, NOT autonomy-gated" do
      expect(Ai::Tools::PlatformApiToolRegistry::TOOLS["record_agent_execution"]).to eq("Ai::Tools::AgentManagementTool")
      declaration = described_class.declared_action("record_agent_execution")
      expect(declaration[:mutating]).to be true
      expect(declaration[:action_category]).to be_nil
      expect(described_class.action_definitions.dig("record_agent_execution", :description)).to include("not autonomy-gated")
    end

    it "advertises the report parameters" do
      params = described_class.action_definitions.dig("record_agent_execution", :parameters)
      expect(params.keys).to include(:agent_slug, :model, :outcome, :duration_ms, :tokens, :cost_usd, :task_digest, :run_key)
    end
  end

  describe "minting the row" do
    it "mints ONE completed Ai::AgentExecution on the target agent, executed by the session's mcp_client agent" do
      expect { report }.to change { Ai::AgentExecution.for_agent(canonical).count }.by(1)

      execution = Ai::AgentExecution.for_agent(canonical).last
      expect(execution.status).to eq("completed")
      expect(execution.account_id).to eq(account.id)
      expect(execution.duration_ms).to eq(42_000)
      expect(execution.tokens_used).to eq(1540)
      expect(execution.claude_code_run?).to be true
      expect(execution.execution_context).to include(
        "source" => "claude_code",
        "executor_agent_id" => session_agent.id,
        "run_key" => "sess-1:agent-a1"
      )
      expect(execution.performance_metrics["model"]).to eq("claude-opus-5")
    end

    it "returns the row and the executor kind" do
      result = report
      expect(result[:success]).to be true
      expect(result[:data]).to include(created: true, executor_kind: "claude_code", status: "completed",
                                       agent_id: canonical.id, agent_slug: canonical.slug, model: "claude-opus-5")
    end

    it "records a failed outcome through the same hooks with the model's required error message" do
      report(outcome: "failed")
      execution = Ai::AgentExecution.for_agent(canonical).last
      expect(execution.status).to eq("failed")
      expect(execution.error_message).to be_present
    end

    it "redacts the task digest through the core PII path and caps it at 500 chars" do
      report(task_digest: "contact me at someone@example.com " + ("x" * 600))
      digest = Ai::AgentExecution.for_agent(canonical).last.input_parameters["task_digest"]
      expect(digest).not_to include("someone@example.com")
      expect(digest.length).to be <= 500
    end

    # A placeholder can be LONGER than the text it replaces ("1.2.3.4" ->
    # "[REDACTED:IP_ADDRESS]"), so a digest capped BEFORE redaction can come
    # back over the ceiling the parameter advertises.
    it "keeps the cap after redaction even when the placeholders EXPAND the text" do
      expanding = (1..40).map { |i| "host 10.0.#{i / 256}.#{i % 256} failed" }.join(" ")
      report(task_digest: expanding)

      digest = Ai::AgentExecution.for_agent(canonical).last.input_parameters["task_digest"]
      expect(digest).to include("[REDACTED:")
      expect(digest.length).to be <= 500
    end

    it "resolves the slug override-aware: the account's clone wins over the canonical" do
      clone = create(:ai_agent, account: account, name: "CVE Responder", agent_type: "monitor")
      expect(clone.slug).to eq(canonical.slug)

      report
      expect(Ai::AgentExecution.for_agent(clone).count).to eq(1)
      expect(Ai::AgentExecution.for_agent(canonical).count).to eq(0)
    end

    it "refuses an unknown slug, an mcp_client target, a bad outcome and a missing run_key" do
      expect(report(agent_slug: "no-such-agent")[:error]).to include("no-such-agent")
      expect(report(agent_slug: session_agent.slug)[:error]).to include("mcp_client")
      expect(report(outcome: "exploded")[:error]).to include("outcome")
      expect(report(run_key: "")[:error]).to include("run_key")
    end
  end

  describe "statistics (the acceptance criterion)" do
    it "fires the trust evaluation and lands a trust score row for a GLOBAL canonical" do
      expect { report }.to change { Ai::AgentTrustScore.where(agent_id: canonical.id).count }.from(0).to(1)
      expect(Ai::AgentTrustScore.find_by(agent_id: canonical.id).evaluation_count).to eq(1)
    end

    it "records model performance under the mapped provider and the reported model" do
      report
      perf = Ai::AgentModelPerformance.find_by(account_id: account.id, model: "claude-opus-5", agent_type: "monitor")
      expect(perf).to be_present
      expect(perf.total_runs).to eq(1)
      expect(perf.successful_runs).to eq(1)
      expect(perf.total_tokens).to eq(1540)
    end
  end

  describe "model mapping (item 2)" do
    it "credits the account's credentialed Anthropic provider when one exists" do
      anthropic = create(:ai_provider, :anthropic, account: account, is_active: true)
      create(:ai_provider_credential, account: account, provider: anthropic, is_active: true)

      report
      execution = Ai::AgentExecution.for_agent(canonical).last
      expect(execution.ai_provider_id).to eq(anthropic.id)
      expect(Ai::AgentModelPerformance.find_by(account_id: account.id, model: "claude-opus-5").ai_provider_id).to eq(anthropic.id)
      expect(execution.ai_provider_id).not_to eq(claude_code_scope.id)
    end

    it "records under the SEEDED synthetic, inactive claude-code provider when no credentialed Anthropic provider exists" do
      report
      synthetic = account.ai_providers.find_by(slug: Ai::ClaudeExport::ExecutionRecorder::SYNTHETIC_PROVIDER_SLUG)
      expect(synthetic).to eq(claude_code_scope)
      expect(synthetic.is_active).to be false
      expect(synthetic.metadata["execution_source"]).to eq("claude_code")
      expect(Ai::AgentExecution.for_agent(canonical).last.ai_provider_id).to eq(synthetic.id)
      expect(Ai::AgentModelPerformance.find_by(account_id: account.id, model: "claude-opus-5").ai_provider_id).to eq(synthetic.id)
    end

    it "reuses the seeded provider across reports (one row per account)" do
      report
      report(run_key: "sess-1:agent-b2")
      expect(account.ai_providers.where(slug: Ai::ClaudeExport::ExecutionRecorder::SYNTHETIC_PROVIDER_SLUG).count).to eq(1)
    end

    it "refuses by name, naming the seed, when the account's scope was never seeded — and mints no provider row" do
      unseeded = create(:account)
      unseeded_user = create(:user, account: unseeded, permissions: %w[ai.agents.execute])
      create(:ai_provider, account: unseeded, is_active: true)

      result = described_class.new(account: unseeded, user: unseeded_user)
                              .execute(params: { action: "record_agent_execution", agent_slug: canonical.slug, model: "claude-opus-5",
                                                 outcome: "completed", duration_ms: 1, tokens: { input: 1, output: 1 }, run_key: "u:1" })

      expect(result[:success]).to be false
      expect(result[:error]).to include("ai_claude_code_provider_seed")
      expect(unseeded.ai_providers.where(slug: Ai::ClaudeExport::ExecutionRecorder::SYNTHETIC_PROVIDER_SLUG)).to be_empty
      expect(Ai::AgentExecution.for_agent(canonical).count).to eq(0)
    end

    it "the model selector never routes a platform execution to the synthetic provider" do
      report
      synthetic = account.ai_providers.find_by(slug: Ai::ClaudeExport::ExecutionRecorder::SYNTHETIC_PROVIDER_SLUG)
      # Even with NO other provider at all — the fallback arm's last resort —
      # the Claude Code-only scope is not a platform routing candidate.
      account.ai_providers.where.not(id: synthetic.id).find_each { |p| p.update_columns(is_active: false) }
      Ai::AgentBudget.where(account: account).delete_all
      account.ai_providers.where.not(id: synthetic.id).destroy_all

      result = Ai::AgentModelSelector.recommend(account: account, agent_type: "monitor")
      expect(result[:provider]).to be_nil
      expect(Ai::Provider.platform_routable.where(account: account)).not_to include(synthetic)
    end

    it "classifies every Claude Code model id onto the tier ladder" do
      expect(Ai::ModelTiers.classify("claude-opus-5")).to eq(:reasoning)
      expect(Ai::ModelTiers.classify("claude-sonnet-5")).to eq(:standard)
      expect(Ai::ModelTiers.classify("claude-haiku-4-5")).to eq(:light)
      expect(Ai::ModelTiers.classify("claude-fable-5-1")).to eq(:frontier)
    end
  end

  describe "idempotency on run_key" do
    it "updates the same row on a retry instead of minting a second one" do
      report(duration_ms: 1000, tokens: { input: 10, output: 5 })
      expect { report(duration_ms: 2000, tokens: { input: 20, output: 5 }) }
        .not_to change { Ai::AgentExecution.for_agent(canonical).count }

      execution = Ai::AgentExecution.for_agent(canonical).last
      expect(execution.duration_ms).to eq(2000)
      expect(execution.tokens_used).to eq(25)
      expect(Ai::AgentModelPerformance.find_by(account_id: account.id, model: "claude-opus-5").total_runs).to eq(1)
    end

    it "keys the row on (account, run_key): another account's identical run_key is a different row" do
      other_account = create(:account)
      other_user = create(:user, account: other_account, permissions: %w[ai.agents.execute])
      create(:ai_provider, account: other_account, is_active: true)
      Ai::ClaudeExport::ProviderScopeSeeder.ensure_for!(other_account)
      other_tool = described_class.new(account: other_account, user: other_user)

      report
      other_tool.execute(params: { action: "record_agent_execution", agent_slug: canonical.slug, model: "claude-opus-5",
                                   outcome: "completed", duration_ms: 1, tokens: { input: 1, output: 1 }, run_key: "sess-1:agent-a1" })
      expect(Ai::AgentExecution.for_agent(canonical).count).to eq(2)
    end
  end

  describe "boundary rule (item 3): never autonomy budgets, consent ceilings or approval accounting" do
    it "leaves the agent's Ai::AgentBudget, budget ledger, approvals and deferred operations untouched even with a cost" do
      clone = create(:ai_agent, account: account, name: "CVE Responder", agent_type: "monitor")
      budget = create(:ai_agent_budget, account: account, agent: clone, total_budget_cents: 10_000, spent_cents: 0)

      expect {
        report(cost_usd: 0.75)
        report(cost_usd: 1.25) # a retry that CHANGES the cost — the model's cost hook must still stay out
      }.to not_change { budget.reload.spent_cents }
        .and not_change { Ai::BudgetTransaction.count }
        .and not_change { Ai::ApprovalRequest.count }
        .and not_change { Ai::DeferredOperation.count }

      expect(Ai::AgentExecution.for_agent(clone).last.cost_usd.to_f).to eq(1.25)
    end
  end

  describe "permission" do
    it "is denied for an ai.agents.read-only holder (the execute grant is required)" do
      reader = create(:user, account: account, permissions: %w[ai.agents.read])
      result = described_class.new(account: account, user: reader, agent: session_agent)
                              .execute(params: { action: "record_agent_execution", agent_slug: canonical.slug,
                                                 model: "claude-opus-5", outcome: "completed", run_key: "k" })
      expect(result[:success]).to be false
      expect(result[:error]).to include("ai.agents.execute")
      expect(Ai::AgentExecution.count).to eq(0)
    end
  end

  # The SubagentStop hook reaches the platform through the local proxy as an
  # mTLS INSTANCE principal: no User at all, while Ai::AgentExecution#user is a
  # required belongs_to. This is the hook's own path, not an edge case.
  describe "attribution when the reporting principal is not a User" do
    def instance_tool(for_account)
      described_class.new(account: for_account, user: nil).tap { |t| t.instance_authorized = true }
    end

    it "attributes a userless report to a DETERMINISTIC account user (oldest first)" do
      first_user = create(:user, account: account, created_at: 3.days.ago)
      create(:user, account: account, created_at: 1.day.ago)

      result = instance_tool(account).execute(
        params: { action: "record_agent_execution", agent_slug: canonical.slug, model: "claude-opus-5",
                  outcome: "completed", duration_ms: 5, tokens: { input: 1, output: 1 }, run_key: "sess-9:agent-z" }
      )

      expect(result[:success]).to be true
      expect(Ai::AgentExecution.for_agent(canonical).last.user_id).to eq(first_user.id)
    end

    it "refuses by name when the account has no user at all instead of raising RecordInvalid" do
      empty_account = create(:account)
      create(:ai_provider, account: empty_account, is_active: true)
      Ai::ClaudeExport::ProviderScopeSeeder.ensure_for!(empty_account)
      expect(empty_account.users.count).to eq(0)

      result = instance_tool(empty_account).execute(
        params: { action: "record_agent_execution", agent_slug: canonical.slug, model: "claude-opus-5",
                  outcome: "completed", duration_ms: 5, tokens: { input: 1, output: 1 }, run_key: "sess-10:agent-z" }
      )

      expect(result[:success]).to be false
      expect(result[:error]).to include("no user to attribute")
      expect(Ai::AgentExecution.for_agent(canonical).count).to eq(0)
    end
  end

  describe "visibility (item 5)" do
    it "get_agent exposes executions by executor kind" do
      report
      result = tool.execute(params: { action: "get_agent", slug: canonical.slug })
      expect(result[:agent][:execution_stats]).to include(
        total_executions: 1,
        by_executor_kind: { platform: 0, claude_code: 1 }
      )
    end

    # A GLOBAL canonical is shared by every account and every account's reports
    # land on that one ai_agent_id, so the counts MUST be account-scoped or
    # get_agent discloses another tenant's run volume.
    it "counts only the calling account's runs on a shared GLOBAL canonical" do
      other_account = create(:account)
      other_user = create(:user, account: other_account, permissions: %w[ai.agents.execute])
      create(:ai_provider, account: other_account, is_active: true)
      Ai::ClaudeExport::ProviderScopeSeeder.ensure_for!(other_account)
      2.times do |i|
        described_class.new(account: other_account, user: other_user)
                       .execute(params: { action: "record_agent_execution", agent_slug: canonical.slug,
                                          model: "claude-opus-5", outcome: "completed", duration_ms: 1,
                                          tokens: { input: 1, output: 1 }, run_key: "other:#{i}" })
      end
      report
      expect(Ai::AgentExecution.for_agent(canonical).count).to eq(3)

      result = tool.execute(params: { action: "get_agent", slug: canonical.slug })
      expect(result[:agent][:execution_stats]).to include(
        total_executions: 1,
        by_executor_kind: { platform: 0, claude_code: 1 }
      )
    end
  end
end
