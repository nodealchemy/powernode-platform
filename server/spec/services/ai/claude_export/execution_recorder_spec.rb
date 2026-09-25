# frozen_string_literal: true

require "rails_helper"

# IMP-e8513b30152d — the synthetic `claude-code` provider scope is SEEDED
# (db/seeds/ai_claude_code_provider_seed.rb: one inactive, non-routable row per
# account, plus Accounts::ProvisionService for tenants created after first
# boot) and never minted by the report path. platform.record_agent_execution
# is reachable by any ai.agents.execute holder — including the SubagentStop
# hook's instance principal — and that grant must not be able to create a
# provider row; a missing scope is an operator-fixable seed gap, refused by
# name.
RSpec.describe Ai::ClaudeExport::ExecutionRecorder do
  RSpec::Matchers.define_negated_matcher :not_change, :change

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let!(:canonical) do
    create(:ai_agent, :global, is_system: true, name: "CVE Responder", agent_type: "monitor",
                               description: "CVE intake and remediation.")
  end
  let(:recorder) { described_class.new(account: account, user: user) }

  def report(**overrides)
    recorder.record({
      agent_slug: canonical.slug, model: "claude-opus-5", outcome: "completed",
      duration_ms: 10, tokens: { input: 5, output: 2 }, run_key: "sess-1:run-1"
    }.merge(overrides))
  end

  describe "provider scope resolution" do
    context "when the account holds no credentialed Anthropic provider" do
      it "records under the SEEDED inactive claude-code scope" do
        scope = Ai::ClaudeExport::ProviderScopeSeeder.ensure_for!(account)

        result = report

        expect(result[:provider_id]).to eq(scope.id)
        expect(result[:provider_slug]).to eq("claude-code")
        expect(Ai::AgentExecution.find(result[:id]).ai_provider_id).to eq(scope.id)
        expect(scope.reload.is_active).to be false
      end

      it "never creates the scope itself: refuses by name, naming the seed, and records nothing" do
        expect(account.ai_providers.where(slug: "claude-code")).to be_empty

        expect { report }
          .to raise_error(described_class::MissingProviderScope, /ai_claude_code_provider_seed/)
          .and not_change { account.ai_providers.count }
        expect(Ai::AgentExecution.count).to eq(0)
      end

      it "surfaces the missing scope as a Refusal so the MCP verb reports it instead of raising" do
        expect(described_class::MissingProviderScope.ancestors).to include(described_class::Refusal)
      end
    end

    it "prefers the account's credentialed Anthropic provider over the seeded scope" do
      scope = Ai::ClaudeExport::ProviderScopeSeeder.ensure_for!(account)
      anthropic = create(:ai_provider, :anthropic, account: account, is_active: true)
      create(:ai_provider_credential, account: account, provider: anthropic, is_active: true)

      result = report

      expect(result[:provider_id]).to eq(anthropic.id)
      expect(result[:provider_id]).not_to eq(scope.id)
    end
  end

  describe "cost" do
    before { Ai::ClaudeExport::ProviderScopeSeeder.ensure_for!(account) }

    it "prices the reported cache reads and writes at their own rates; input stays the total" do
      allow(Ai::CostCalculationService).to receive(:calculate).and_return(0.42)

      result = report(tokens: { input: 1000, output: 100, cache_read: 600, cache_creation: 200 })

      expect(Ai::CostCalculationService).to have_received(:calculate).with(
        model_id: "claude-opus-5", prompt_tokens: 1000, completion_tokens: 100,
        cached_tokens: 600, cache_creation_tokens: 200
      )
      execution = Ai::AgentExecution.find(result[:id])
      expect(execution.cost_usd.to_f).to eq(0.42)
      expect(execution.performance_metrics).to include("prompt_tokens" => 1000, "cached_tokens" => 600,
                                                       "cache_creation_tokens" => 200)
    end

    it "treats a report without cache counts as all uncached input" do
      allow(Ai::CostCalculationService).to receive(:calculate).and_return(0.0)

      report

      expect(Ai::CostCalculationService).to have_received(:calculate).with(
        model_id: "claude-opus-5", prompt_tokens: 5, completion_tokens: 2, cached_tokens: 0, cache_creation_tokens: 0
      )
    end

    it "never lets the cache counts exceed the input total" do
      allow(Ai::CostCalculationService).to receive(:calculate).and_return(0.0)

      report(tokens: { input: 100, output: 1, cache_read: 90, cache_creation: 50 })

      expect(Ai::CostCalculationService).to have_received(:calculate)
        .with(hash_including(prompt_tokens: 100, cached_tokens: 90, cache_creation_tokens: 10))
    end
  end
end
