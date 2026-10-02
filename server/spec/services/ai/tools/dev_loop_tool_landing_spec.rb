# frozen_string_literal: true

require "rails_helper"

# IMP-6d060f65ccae — dev_complete_task's reachability guard. `commit_sha` used to
# be stored verbatim, so a PASSED task could name a commit that only ever existed
# in the executor's worktree (the stranded-commit failure). The guard records
# whether the sha LANDED and downgrades an unlanded pass to attested; it never
# refuses the call, so existing callers keep working.
RSpec.describe Ai::Tools::DevLoopTool, "landing guard" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, user: user) }
  let(:ralph_loop) { create(:ai_ralph_loop, account: account, name: "dev-landing") }
  let(:sha) { "d" * 40 }
  let(:green) { { "rspec" => "2 examples, 0 failures" } }

  before do
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)
    create(:ai_ralph_task, ralph_loop: ralph_loop, task_key: "LAND-1")
    ralph_loop.update!(status: "running", started_at: Time.current)
    tool.execute(params: { action: "dev_next_task", loop_id: ralph_loop.id })
  end

  def complete(extra = {})
    tool.execute(params: {
      action: "dev_complete_task", loop_id: ralph_loop.id, task_key: "LAND-1",
      outcome: "passed", summary: "Landed the change", check_results: green
    }.merge(extra))
  end

  def iteration
    ralph_loop.ralph_iterations.last
  end

  context "when the sha is landed" do
    before do
      allow(Ai::DevLoop::LandingCheck).to receive(:call)
        .and_return(Ai::DevLoop::LandingCheck::Result.new(landed: true, via: "dev_merge_audit"))
    end

    it "keeps the verified pass and records landed: true" do
      result = complete(commit_sha: sha)

      expect(result[:success]).to be true
      expect(result[:verification]).to eq("verified")
      expect(result[:landed]).to be true
      expect(result).not_to have_key(:warning)
      expect(iteration.checks_passed).to be true
      expect(iteration.git_commit_sha).to eq(sha)
      expect(iteration.check_results).to include("landed" => true)
      expect(iteration.check_results["landing_check"]).to include("via" => "dev_merge_audit")
    end
  end

  context "when the git host answered and the sha is not landed" do
    before do
      allow(Ai::DevLoop::LandingCheck).to receive(:call)
        .and_return(Ai::DevLoop::LandingCheck::Result.new(landed: false, via: "git_host",
                                                          warning: "commit #{sha} is not reachable from develop"))
    end

    it "still passes the task but downgrades to attested, records landed: false and warns" do
      result = complete(commit_sha: sha)

      expect(result[:success]).to be true
      expect(result[:task_status]).to eq("passed")
      expect(result[:verification]).to eq("attested")
      expect(result[:landed]).to be false
      expect(result[:warning]).to match(/not reachable from develop/)
      expect(iteration.checks_passed).to be false
      expect(iteration.check_results).to include("landed" => false)
    end

    it "does not auto-apply a linked offer on the downgraded pass" do
      expect_any_instance_of(described_class).not_to receive(:apply_linked_recommendation!)

      complete(commit_sha: sha, check_results: { "evidence" => { "framework" => "rspec", "passed" => 3, "failed" => 0 } })
    end

    it "does not touch a failed outcome" do
      result = tool.execute(params: {
        action: "dev_complete_task", loop_id: ralph_loop.id, task_key: "LAND-1",
        outcome: "failed", summary: "red", commit_sha: sha
      })

      expect(result[:success]).to be true
      expect(result).not_to have_key(:landed)
      expect(Ai::DevLoop::LandingCheck).not_to have_received(:call)
    end
  end

  context "when the landed sha does not name this task" do
    before do
      allow(Ai::DevLoop::LandingCheck).to receive(:call)
        .and_return(Ai::DevLoop::LandingCheck::Result.new(
          landed: true, via: "git_host", bound: false, bound_via: "commit_message",
          bound_warning: "commit #{sha} does not reference task LAND-1 in its message"
        ))
    end

    it "refuses the pass with the named reason, and records nothing" do
      result = complete(commit_sha: sha)

      expect(Ai::DevLoop::LandingCheck).to have_received(:call).with(hash_including(task_key: "LAND-1", commit_sha: sha))

      expect(result[:success]).to be false
      expect(result[:error]).to match(/does not reference task LAND-1/)
      expect(ralph_loop.ralph_iterations.count).to eq(0)
      expect(ralph_loop.ralph_tasks.find_by(task_key: "LAND-1").status).to eq("in_progress")
    end

    it "does not refuse a blocked or failed report that names the same sha" do
      result = complete(commit_sha: sha, outcome: "blocked", summary: "waiting on operator")

      expect(result[:success]).to be true
    end
  end

  context "when the task binding could not be determined" do
    it "keeps the pass" do
      allow(Ai::DevLoop::LandingCheck).to receive(:call)
        .and_return(Ai::DevLoop::LandingCheck::Result.new(landed: true, via: "git_host", bound: nil, bound_via: "commit_unreadable"))

      expect(complete(commit_sha: sha)[:success]).to be true
    end
  end

  context "when the landing could not be verified" do
    it "keeps today's verdict and records landed: unverified with a warning" do
      allow(Ai::DevLoop::LandingCheck).to receive(:call)
        .and_return(Ai::DevLoop::LandingCheck::Result.new(landed: "unverified", via: "no_repository",
                                                          warning: "no repository resolves — recorded as unverified"))
      result = complete(commit_sha: sha)

      expect(result[:success]).to be true
      expect(result[:verification]).to eq("verified")
      expect(result[:landed]).to eq("unverified")
      expect(result[:warning]).to match(/unverified/)
      expect(iteration.checks_passed).to be true
      expect(iteration.check_results).to include("landed" => "unverified")
    end
  end

  context "when the landing check itself raises" do
    it "never fails the completion and does not downgrade it" do
      allow(Ai::DevLoop::LandingCheck).to receive(:call).and_raise(StandardError, "boom")

      result = complete(commit_sha: sha)

      expect(result[:success]).to be true
      expect(result[:task_status]).to eq("passed")
      expect(result[:landed]).to eq("unverified")
      expect(result[:verification]).to eq("verified")
      expect(result[:warning]).to match(/could not be verified/)
    end
  end

  it "keeps the caller's own check_results.landing beside the server's landing_check" do
    allow(Ai::DevLoop::LandingCheck).to receive(:call)
      .and_return(Ai::DevLoop::LandingCheck::Result.new(landed: true, via: "git_host"))
    mine = { "landed_core_sha" => sha, "batch_id" => "b-1", "promoted" => [ { "environment" => "staging" } ] }

    complete(commit_sha: sha, check_results: green.merge("landing" => mine))

    expect(iteration.check_results["landing"]).to eq(mine)
    expect(iteration.check_results["landing_check"]).to include("via" => "git_host")
    expect(iteration.check_results["landed"]).to be true
  end

  context "without a commit_sha" do
    it "keeps today's behaviour (verified) and adds a warning" do
      result = complete

      expect(result[:success]).to be true
      expect(result[:verification]).to eq("verified")
      expect(result[:warning]).to match(/no commit_sha/)
      expect(iteration.checks_passed).to be true
      expect(iteration.check_results).not_to have_key("landed")
    end
  end

  it "is recorded end to end against a real dev_merge.succeeded audit row for the loop's repository" do
    repo = create(:git_repository, account: account, full_name: "owner/platform", owner: "owner", name: "platform")
    ralph_loop.update!(repository_url: "https://git.example.test/#{repo.full_name}.git")
    create(:audit_log, account: account, action: "dev_merge.succeeded", resource_type: "Ai::DeferredOperation",
                       metadata: { "repository" => repo.full_name, "outcome" => { "merged_sha" => sha } })

    result = complete(commit_sha: sha)

    expect(result[:landed]).to be true
    expect(result[:verification]).to eq("verified")
  end
end
