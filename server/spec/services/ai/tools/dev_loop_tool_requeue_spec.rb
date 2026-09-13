# frozen_string_literal: true

require "rails_helper"

# dev_requeue_task — the missing way back to the queue for a task parked for
# operator review. dev_update_task records an operator's answer but warns it
# "will not be delivered until the task is re-queued", and no tool could re-queue.
#
# Unblocking a review park is a PERSON's decision: an executor that could requeue
# its own review parks would defeat the park. The operator reaches MCP as an
# instance principal (dev_loop_tool.rb, #self_amended_brief?), so refusing
# principals would refuse the operator. The action is therefore human_only
# (MCP identity plan R2): from any tool door it parks for a person to confirm in
# their own session, and the replay runs as that person.
RSpec.describe Ai::Tools::DevLoopTool, "dev_requeue_task" do
  let(:account) { create(:account) }
  let!(:user) { create(:user, account: account) } # first user: account owner
  let(:tool) { described_class.new(account: account, user: user) }
  let(:ralph_loop) { create(:ai_ralph_loop, account: account, name: "dev-requeue-test") }
  let!(:task) do
    create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "IMP-parked", status: "blocked",
                           error_message: "BLOCKED on a decision",
                           metadata: { "blocked_for" => "review", "claimed_by" => "user:#{user.id}" })
  end

  before do
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)
  end

  def exec(params, with: tool)
    with.execute(params: params.with_indifferent_access)
  end

  def requeue(**params)
    exec({ action: "dev_requeue_task", loop_id: ralph_loop.name, task_key: task.task_key,
           reason: "operator answered the question" }.merge(params))
  end

  def confirm!(parked, as: user)
    request = Ai::ApprovalRequest.find(parked[:data][:approval_request_id])
    approved = Ai::Autonomy::ApprovalWorkflowService.new(account: account)
                                                   .approve(request: request, approver: as,
                                                            origin: Ai::ApprovalDecision::REST_SESSION)
    expect(approved).to be(true)
    Ai::DeferredOperation.find(parked[:data][:deferred_operation_id]).result.with_indifferent_access
  end

  it "is advertised beside the other bridge actions" do
    expect(described_class.action_definitions.keys).to include("dev_requeue_task")
    expect(described_class.declared_action("dev_requeue_task")).to include(human_only: true,
                                                                           action_category: "dev.task_requeue")
  end

  it "parks for a person's confirmation and leaves the task blocked" do
    parked = requeue

    expect(parked[:success]).to be(true)
    expect(parked[:data]).to include(pending: true, requires_human_session: true)
    expect(task.reload.status).to eq("blocked")
    expect(Ai::ApprovalRequest.find(parked[:data][:approval_request_id]).description)
      .to include("IMP-parked")
  end

  it "requeues the task on a person's confirmation, and the next pull hands it out" do
    result = confirm!(requeue)

    expect(result[:success]).to be(true), result[:error].to_s
    expect(task.reload.status).to eq("pending")
    expect(task.metadata["requeue_history"].last).to include("by" => "user:#{user.id}",
                                                             "reason" => "operator answered the question")

    pulled = exec({ action: "dev_next_task", loop_id: ralph_loop.name })
    expect(pulled.dig(:task, :task_key)).to eq("IMP-parked")
  end

  describe "refused before it parks, so no person is asked to confirm a call that can only fail" do
    def expect_refused(result, message)
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(message)
      expect(Ai::ApprovalRequest.count).to eq(0)
    end

    it "an unknown task" do
      expect_refused(requeue(task_key: "IMP-nope"), /not found/i)
    end

    it "a task that is not blocked" do
      task.update!(status: "pending")

      expect_refused(requeue, /not blocked/i)
    end

    it "a missing reason" do
      expect_refused(requeue(reason: ""), /reason/i)
    end

    it "an unknown loop" do
      expect_refused(requeue(loop_id: "no-such-loop"), /loop not found/i)
    end
  end

  it "is a no-op while the account's AI is suspended (kill switch)" do
    account.update!(ai_suspended: true)

    result = requeue

    expect(result[:halted]).to be(true)
    expect(task.reload.status).to eq("blocked")
    expect(Ai::ApprovalRequest.count).to eq(0)
  end

  it "re-checks on the replay: a task that is no longer blocked when confirmed is not touched" do
    parked = requeue
    task.update!(status: "passed")

    result = confirm!(parked)

    expect(result[:success]).to be(false)
    expect(task.reload.status).to eq("passed")
  end

  it "parks for an agent's call too; an agent never requeues by itself" do
    provider = create(:ai_provider, account: account)
    agent = create(:ai_agent, account: account, creator: user, provider: provider)
    agent_tool = described_class.new(account: account, agent: agent)

    parked = exec({ action: "dev_requeue_task", loop_id: ralph_loop.name, task_key: task.task_key,
                    reason: "agent asks" }, with: agent_tool)

    expect(parked[:data]).to include(pending: true, requires_human_session: true)
    expect(task.reload.status).to eq("blocked")
  end
end
