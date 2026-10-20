# frozen_string_literal: true

require "rails_helper"

# record_agent_execution(assembly_id) (skills-first agents, PRE-2): the report
# of a Claude Code run that was assembled by assemble_task links the assembly's
# RoutingDecision to the execution and writes one SkillUsageRecord per selected
# skill, so a Claude Code run credits the skills it used.
RSpec.describe Ai::ClaudeExport::ExecutionRecorder, "with an assembly_id" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let!(:agent) { create(:ai_agent, :global, is_system: true, slug: "platform-engineer", name: "Platform Engineer", agent_type: "code_assistant") }
  let!(:skill_a) { create(:ai_skill, :global, slug: "skill-a", name: "Skill A") }
  let!(:skill_b) { create(:ai_skill, :global, slug: "skill-b", name: "Skill B") }
  let(:recorder) { described_class.new(account: account, user: user) }
  let!(:assembly) do
    create(:ai_routing_decision, account: account, request_type: "task_assembly", strategy_used: "hybrid",
                                 request_metadata: { "agent_slug" => "platform-engineer", "context" => "claude_code",
                                                     "selected" => [ { "slug" => "skill-a" }, { "slug" => "skill-b" } ] })
  end

  before { Ai::ClaudeExport::ProviderScopeSeeder.ensure_for!(account) }

  def report(**overrides)
    recorder.record({
      agent_slug: "platform-engineer", model: "claude-sonnet-5", outcome: "completed", duration_ms: 1200,
      tokens: { input: 5, output: 2 }, run_key: "sess-1:platform-engineer:20261020T000000Z", assembly_id: assembly.id
    }.merge(overrides))
  end

  it "links the assembly's decision to the execution" do
    result = report

    expect(assembly.reload.agent_execution_id).to eq(result[:id])
    expect(result[:assembly_id]).to eq(assembly.id)
  end

  it "writes one SkillUsageRecord per selected skill, on the target agent and the execution" do
    result = report

    records = Ai::SkillUsageRecord.where(execution_id: result[:id])
    expect(records.map { |r| r.ai_skill.slug }).to match_array(%w[skill-a skill-b])
    expect(records).to all(have_attributes(account_id: account.id, ai_agent_id: agent.id, outcome: "success",
                                           execution_type: "Ai::AgentExecution", duration_ms: 1200))
    expect(result[:skills_credited]).to eq(2)
  end

  it "maps the run outcome onto the usage outcome: failed -> failure, cancelled -> partial" do
    failed = report(outcome: "failed", run_key: "sess-1:run-f")
    expect(Ai::SkillUsageRecord.where(execution_id: failed[:id]).pluck(:outcome).uniq).to eq([ "failure" ])

    other = create(:ai_routing_decision, account: account, request_type: "task_assembly", strategy_used: "hybrid",
                                         request_metadata: { "agent_slug" => "platform-engineer", "selected" => [ { "slug" => "skill-a" } ] })
    cancelled = report(outcome: "cancelled", run_key: "sess-1:run-c", assembly_id: other.id)
    expect(Ai::SkillUsageRecord.where(execution_id: cancelled[:id]).pluck(:outcome)).to eq([ "partial" ])
  end

  it "is idempotent on run_key: a retry adds no usage record and no second link" do
    first = report
    expect { report }.not_to change(Ai::SkillUsageRecord, :count)
    expect(Ai::AgentExecution.where(id: first[:id]).count).to eq(1)
  end

  it "credits an assembly once: a second execution with the same assembly_id writes no usage record and does not relink" do
    first = report
    second = nil
    expect { second = report(run_key: "sess-2:platform-engineer:20261020T010000Z") }.not_to change(Ai::SkillUsageRecord, :count)

    expect(second[:id]).not_to eq(first[:id])
    expect(second[:skills_credited]).to eq(0)
    expect(assembly.reload.agent_execution_id).to eq(first[:id])
    # …and a retry of the FIRST run stays idempotent (still credited, still no new rows).
    expect { report }.not_to change(Ai::SkillUsageRecord, :count)
    expect(report[:skills_credited]).to eq(2)
  end

  it "skips a selected skill that no longer exists instead of failing the report" do
    skill_b.destroy!

    result = report

    expect(Ai::SkillUsageRecord.where(execution_id: result[:id]).count).to eq(1)
  end

  it "still records a run reported without an assembly_id, crediting nothing" do
    result = report(assembly_id: nil)

    expect(result[:id]).to be_present
    expect(Ai::SkillUsageRecord.where(execution_id: result[:id])).to be_empty
  end

  it "refuses an unknown assembly_id, another account's, or a decision that is not an assembly, recording nothing" do
    theirs = create(:ai_routing_decision, account: create(:account), request_type: "task_assembly", strategy_used: "hybrid")
    plain = create(:ai_routing_decision, account: account, request_type: "agent_execution", strategy_used: "hybrid")

    [ SecureRandom.uuid, theirs.id, plain.id ].each do |bad|
      expect { report(assembly_id: bad, run_key: "sess-1:bad-#{bad}") }.to raise_error(described_class::Refusal, /assembly/i)
    end
    expect(Ai::AgentExecution.count).to eq(0)
  end

  it "refuses an assembly made for a different agent than the one reported" do
    create(:ai_agent, :global, is_system: true, slug: "platform-reviewer", name: "Platform Reviewer")

    expect { report(agent_slug: "platform-reviewer") }.to raise_error(described_class::Refusal, /assembly.*platform-engineer/i)
  end
end
