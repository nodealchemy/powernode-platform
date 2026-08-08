# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::DevLoopTool, "#delegate_ralph_task" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, user: user) }
  let(:ralph_loop) do
    create(:ai_ralph_loop, account: account, name: "dev-improve-test", branch: "dev-loop/dev-improve")
  end
  let!(:task) { create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "IMP-1", priority: 10) }

  let(:agent_tool) { instance_double(Ai::Tools::AgentManagementTool) }
  before { allow(Ai::Tools::AgentManagementTool).to receive(:new).and_return(agent_tool) }

  def spawn_ok
    { success: true, task_id: "a2a-123", status: "pending", agent_id: "agent-9", agent_name: "Worker" }
  end

  def delegate(extra = {})
    tool.execute(params: {
      action: "delegate_ralph_task", loop_id: ralph_loop.name, task_key: "IMP-1", agent_id: "agent-9"
    }.merge(extra))
  end

  it "exposes delegate_ralph_task as a bridge action" do
    expect(described_class.action_definitions.keys).to include("delegate_ralph_task")
  end

  it "includes CURRENT (refreshed) guardrails in the delegation brief, not the stale persisted snapshot" do
    ralph_loop.update!(configuration: { "guardrails" => ["specific: stale-only middle line"] })
    expected_brief_guardrails = Ai::DevLoop::LoopGuardrails.refresh(["specific: stale-only middle line"])

    expect(agent_tool).to receive(:execute) do |params:|
      brief = params[:task]
      expect(brief).to include("Guardrails:")
      expected_brief_guardrails.each { |line| expect(brief).to include(line) }
      spawn_ok
    end

    delegate
  end

  it "delegates a pending task to a platform agent and records the A2A handle (no await)" do
    expect(agent_tool).to receive(:execute)
      .with(params: hash_including(action: "spawn_task", agent_id: "agent-9")).and_return(spawn_ok)

    result = delegate

    expect(result[:success]).to be true
    expect(result[:delegated]).to be true
    expect(result[:awaited]).to be false
    expect(result[:a2a_task_id]).to eq("a2a-123")
    task.reload
    expect(task.status).to eq("in_progress")
    expect(task.metadata["a2a_task_id"]).to eq("a2a-123")
    expect(task.metadata["delegated_to"]).to eq("agent-9")
  end

  it "awaits and records a passed outcome when the agent completes" do
    allow(agent_tool).to receive(:execute).with(params: hash_including(action: "spawn_task")).and_return(spawn_ok)
    allow(agent_tool).to receive(:execute).with(params: hash_including(action: "wait_for_task"))
      .and_return({ success: true, status: "completed", output: "Fixed the lint", duration_ms: 1200 })

    result = delegate(await: true)

    expect(result[:outcome]).to eq("passed")
    expect(task.reload.status).to eq("passed")
    expect(ralph_loop.ralph_iterations.count).to eq(1)
    # IMP-f2b3e9a67d11 — DELIBERATE: a delegated completion is the sub-agent's
    # own attestation (no test evidence crosses the A2A boundary), so the pass
    # records as attested and must not read as verified.
    expect(result[:verification]).to eq("unverified")
    expect(ralph_loop.ralph_iterations.last.checks_passed).to be(false)
  end

  it "awaits and records a failed outcome when the agent fails" do
    allow(agent_tool).to receive(:execute).with(params: hash_including(action: "spawn_task")).and_return(spawn_ok)
    allow(agent_tool).to receive(:execute).with(params: hash_including(action: "wait_for_task"))
      .and_return({ success: true, status: "failed", error_message: "agent could not complete" })

    result = delegate(await: true)

    expect(result[:outcome]).to eq("failed")
    expect(task.reload.status).to eq("failed")
  end

  it "propagates a delegation-authority denial without claiming the work" do
    allow(agent_tool).to receive(:execute).with(params: hash_including(action: "spawn_task"))
      .and_return({ success: false, error: "Delegation denied: budget exceeded" })

    result = delegate

    expect(result[:success]).to be false
    expect(result[:error]).to include("Delegation denied")
    expect(task.reload.metadata["delegation_error"]).to include("budget exceeded")
  end

  it "is a no-op when the account kill switch is active" do
    allow_any_instance_of(Account).to receive(:ai_suspended?).and_return(true)
    result = delegate
    expect(result[:halted]).to be true
    expect(task.reload.status).to eq("pending")
  end

  it "requires an agent_id" do
    result = tool.execute(params: { action: "delegate_ralph_task", loop_id: ralph_loop.id, task_key: "IMP-1" })
    expect(result[:success]).to be false
    expect(result[:error]).to include("agent_id is required")
  end

  it "refuses to delegate a terminal task" do
    task.update_column(:status, "passed")
    result = delegate
    expect(result[:success]).to be false
    expect(result[:error]).to include("only pending/in_progress")
  end
end
