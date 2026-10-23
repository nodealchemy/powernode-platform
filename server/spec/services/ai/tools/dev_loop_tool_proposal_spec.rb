# frozen_string_literal: true

require "rails_helper"

# A dev-improve task handed off by an approved Ai::AgentProposal closes that
# proposal when dev_complete_task reports it passed with a commit that LANDED,
# the commit being the proposal's implemented_ref.
RSpec.describe Ai::Tools::DevLoopTool, "agent proposal completion" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, user: user) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:sha) { "a" * 40 }
  let!(:proposal) do
    account.ai_agent_proposals.create!(ai_agent_id: agent.id, target_user: user, title: "Ship the thing",
                                       proposal_type: "feature", priority: "high")
  end
  let(:ralph_loop) { Ai::RalphLoop.find_by!(account_id: account.id, name: "dev-improve") }
  let(:task) { Ai::RalphTask.find(proposal.reload.handoff_id) }

  before do
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)
    proposal.approve!(user, origin: Ai::ApprovalDecision::REST_SESSION)
    ralph_loop.update!(status: "running", started_at: Time.current)
    tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })
  end

  def complete(outcome: "passed", landed: true, commit_sha: sha, **extra)
    allow(Ai::DevLoop::LandingCheck).to receive(:call)
      .and_return(Ai::DevLoop::LandingCheck::Result.new(landed: landed, via: "test"))
    tool.execute(params: {
      action: "dev_complete_task", loop_id: ralph_loop.id, task_key: task.task_key, outcome: outcome,
      summary: "done", commit_sha: commit_sha,
      check_results: { "evidence" => { "framework" => "rspec", "passed" => 3, "failed" => 0 } }
    }.merge(extra))
  end

  it "marks the proposal implemented with the landed commit as its ref" do
    expect(complete[:success]).to be true

    proposal.reload
    expect(proposal.status).to eq("implemented")
    expect(proposal.implemented_ref).to eq(sha)
    expect(proposal.implemented_at).to be_present
    expect(AuditLog.where(resource_id: proposal.id, action: "ai.proposal.implemented").count).to eq(1)
  end

  it "does nothing when the commit did not land" do
    complete(landed: false)
    expect(proposal.reload.status).to eq("approved")
  end

  it "does nothing when the landing could not be verified" do
    complete(landed: "unverified")
    expect(proposal.reload.status).to eq("approved")
  end

  it "does nothing when no commit is reported" do
    complete(landed: true, commit_sha: nil)
    expect(proposal.reload.status).to eq("approved")
  end

  it "does nothing for a failed outcome" do
    complete(outcome: "failed", landed: true)
    expect(proposal.reload.status).to eq("approved")
  end
end
