# frozen_string_literal: true

require "rails_helper"

# R1 of the 0.3.0 roster activation: a global canonical is a read-only
# template, so a Claude Code run for a canonical slug attaches to the ACCOUNT'S
# SHADOW (clone), minted through Ai::Agents::AccountPrincipalResolver, never to
# the global row (6 runs had landed on the global platform-engineer). When no
# shadow can be minted the report is refused with a structured reason and
# writes nothing.
RSpec.describe Ai::ClaudeExport::ExecutionRecorder, "shadow resolution" do
  let(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }
  let!(:canonical) do
    create(:ai_agent, :global, is_system: true, slug: "platform-engineer", name: "Platform Engineer",
                               agent_type: "code_assistant")
  end

  before do
    Ai::ClaudeExport::ProviderScopeSeeder.ensure_for!(account)
    create(:ai_provider, :anthropic, account: account, is_active: true)
  end

  def record(recorder, **overrides)
    recorder.record({
      agent_slug: "platform-engineer", model: "claude-opus-5", outcome: "completed",
      duration_ms: 10, tokens: { input: 5, output: 2 }, run_key: "sess-1:run-1"
    }.merge(overrides))
  end

  it "lands the run on the account's shadow and mints it (cloned_from, version, snapshot)" do
    result = nil
    expect { result = record(described_class.new(account: account, user: user)) }
      .to change { Ai::Agent.owned_by_account(account.id).where(slug: "platform-engineer").count }.from(0).to(1)

    shadow = Ai::Agent.owned_by_account(account.id).find_by!(slug: "platform-engineer")
    expect(shadow.cloned_from_id).to eq(canonical.id)
    expect(shadow).to be_persisted
    expect(result[:agent_id]).to eq(shadow.id)
    expect(Ai::AgentExecution.find(result[:id]).ai_agent_id).to eq(shadow.id)
    expect(Ai::AgentExecution.where(ai_agent_id: canonical.id)).to be_empty
  end

  it "reuses the shadow on the next report and never mints a twin" do
    recorder = described_class.new(account: account, user: user)
    first = record(recorder)

    expect { record(recorder, run_key: "sess-1:run-2") }.not_to change(Ai::Agent, :count)
    expect(Ai::AgentExecution.where(ai_agent_id: first[:agent_id]).count).to eq(2)
  end

  it "credits assembled skills to the shadow, not the global row" do
    skill = create(:ai_skill, :global, slug: "skill-a", name: "Skill A")
    assembly = create(:ai_routing_decision, account: account, request_type: "task_assembly", strategy_used: "hybrid",
                                            request_metadata: { "agent_slug" => "platform-engineer",
                                                                "selected" => [ { "slug" => skill.slug } ] })

    record(described_class.new(account: account, user: user), assembly_id: assembly.id)

    shadow = Ai::Agent.owned_by_account(account.id).find_by!(slug: "platform-engineer")
    expect(Ai::SkillUsageRecord.where(account_id: account.id).pluck(:ai_agent_id).uniq).to eq([ shadow.id ])
  end

  context "when no shadow can be minted (the account has no user to own one)" do
    let(:empty_account) { create(:account) }

    before { Ai::ClaudeExport::ProviderScopeSeeder.ensure_for!(empty_account) }

    it "refuses with a structured reason and writes nothing" do
      recorder = described_class.new(account: empty_account, user: nil)

      expect { record(recorder) }.to raise_error(described_class::GlobalRowRefused) { |e|
        expect(e).to be_a(described_class::Refusal)
        expect(e.reason).to eq("no_mintable_principal")
        expect(e.details).to include(agent_slug: "platform-engineer", account_id: empty_account.id)
        expect(e.message).to include("platform-engineer", "no_mintable_principal")
      }
      expect(Ai::AgentExecution.count).to eq(0)
      expect(Ai::Agent.owned_by_account(empty_account.id).count).to eq(0)
      expect(Ai::SkillUsageRecord.count).to eq(0)
    end
  end

  it "records nothing against the global row even when the global row is all that exists" do
    allow_any_instance_of(Ai::Agents::AccountPrincipalResolver).to receive(:for).and_return(nil)

    expect { record(described_class.new(account: account, user: user)) }
      .to raise_error(described_class::GlobalRowRefused, /no_mintable_principal/)
    expect(Ai::AgentExecution.count).to eq(0)
  end
end
