# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DevLoop::ImprovementPromotionService do
  let(:account) { create(:account) }
  let(:recommendation) do
    create(:ai_improvement_recommendation,
           account: account,
           recommendation_type: "dead_code",
           status: "approved",
           confidence_score: 0.8,
           target_type: "Account",
           target_id: account.id,
           evidence: {
             "title" => "Remove dead method",
             "fingerprint" => "dead_code|app/foo.rb|bar",
             "files" => ["app/foo.rb", "app/baz.rb"],
             "description" => "bar is never called"
           })
  end

  describe "#call" do
    it "bootstraps the dev-improve loop manual on first promotion (autonomy is opt-in)" do
      loop_record = described_class.new(recommendation: recommendation).call.ralph_loop

      expect(loop_record.name).to eq("dev-improve")
      expect(loop_record.branch).to eq("dev-loop/dev-improve")
      expect(loop_record.scheduling_mode).to eq("manual")
      expect(loop_record.max_iterations).to eq(500)
    end

    it "creates a task back-linked to the recommendation with kind + blast_radius" do
      result = described_class.new(recommendation: recommendation).call
      task = result.ralph_task

      expect(result.created).to be true
      expect(task.execution_type).to eq("agent")
      expect(task.metadata["recommendation_id"]).to eq(recommendation.id)
      expect(task.metadata["kind"]).to eq("dead_code")
      expect(task.metadata["blast_radius"]).to eq(2) # two files in evidence
      expect(task.priority).to eq(16) # 0.8 * 20
    end

    it "is idempotent — re-promoting reuses the same task" do
      first = described_class.new(recommendation: recommendation).call
      second = described_class.new(recommendation: recommendation).call

      expect(second.created).to be false
      expect(second.ralph_task.id).to eq(first.ralph_task.id)
      expect(first.ralph_loop.ralph_tasks.count).to eq(1)
    end

    it "re-queues a promoted task that previously failed, when the offer is re-approved (IMP-938f68b16a1a)" do
      first = described_class.new(recommendation: recommendation).call
      first.ralph_task.start!
      first.ralph_task.fail!(error_message: "3-strikes: could not reproduce")
      expect(first.ralph_task.reload.status).to eq("failed")

      second = described_class.new(recommendation: recommendation).call

      expect(second.ralph_task.id).to eq(first.ralph_task.id)
      expect(second.ralph_task.status).to eq("pending")
      expect(second.ralph_task.error_message).to be_nil
    end

    it "re-queues a promoted task that was left blocked, when the offer is re-approved" do
      first = described_class.new(recommendation: recommendation).call
      first.ralph_task.block!(reason: "needs operator input", blocked_for: "review")
      expect(first.ralph_task.reload.status).to eq("blocked")

      second = described_class.new(recommendation: recommendation).call

      expect(second.ralph_task.status).to eq("pending")
    end

    # IMP-60f457f6e8a6: "passed" alone is not proof the work closed the offer.
    # DevLoopTool only applies the linked recommendation when the evidence
    # adjudicated :verified, recording checks_passed on the iteration; an
    # attested-only pass left the offer at approved with NO way back — the task
    # is terminal, dev_next_task claims only pending, and dev_complete_task
    # refuses a passed task. Re-approval is that missing seam, so the invariant
    # narrows from "never disturb a passed task" to "never disturb a VERIFIED
    # passed task".
    def pass_task!(task, loop_record, checks_passed:)
      task.start!
      create(:ai_ralph_iteration, ralph_loop: loop_record, ralph_task: task,
                                  status: "completed", checks_passed: checks_passed)
      task.pass!(iteration_number: 1)
      expect(task.reload.status).to eq("passed")
    end

    it "does NOT disturb a passed task whose evidence verified" do
      first = described_class.new(recommendation: recommendation).call
      pass_task!(first.ralph_task, first.ralph_loop, checks_passed: true)

      second = described_class.new(recommendation: recommendation).call

      expect(second.ralph_task.status).to eq("passed")
    end

    it "re-queues a passed task whose evidence never verified (IMP-60f457f6e8a6)" do
      first = described_class.new(recommendation: recommendation).call
      pass_task!(first.ralph_task, first.ralph_loop, checks_passed: false)

      second = described_class.new(recommendation: recommendation).call

      expect(second.ralph_task.id).to eq(first.ralph_task.id)
      expect(second.ralph_task.status).to eq("pending")
      expect(second.requeued).to be true
    end

    it "re-queues a passed task that recorded no evidence at all" do
      first = described_class.new(recommendation: recommendation).call
      first.ralph_task.start!
      first.ralph_task.pass!(iteration_number: 1)

      second = described_class.new(recommendation: recommendation).call

      expect(second.ralph_task.status).to eq("pending")
    end

    it "does NOT disturb a task that is still in_progress on re-approval" do
      first = described_class.new(recommendation: recommendation).call
      first.ralph_task.start!
      expect(first.ralph_task.reload.status).to eq("in_progress")

      second = described_class.new(recommendation: recommendation).call

      expect(second.ralph_task.status).to eq("in_progress")
    end

    it "refuses to promote a recommendation that is not approved" do
      recommendation.update!(status: "pending")
      expect { described_class.new(recommendation: recommendation).call }
        .to raise_error(ArgumentError, /approved/)
    end

    # IMP-c4d5b7abb697: defense-in-depth — the tool layer refuses this first,
    # but the service must not promote a non-code-quality type either, in case
    # it is ever called directly.
    it "refuses to promote a non-code-quality recommendation type" do
      non_code = create(:ai_improvement_recommendation,
                        account: account,
                        recommendation_type: "agent_reliability",
                        status: "approved",
                        target_type: "Account",
                        target_id: account.id,
                        evidence: { "title" => "Low approval rate" })

      expect { described_class.new(recommendation: non_code).call }
        .to raise_error(ArgumentError, /agent_reliability/)
    end

    # Regression: task_key_for truncated the de-hyphenated fingerprint to its first
    # 12 chars, so every same-recommendation_type finding collapsed to one key
    # (e.g. "IMP-convention_a") and the 2nd promotion silently reused the 1st task.
    it "derives distinct task_keys for distinct findings of the same recommendation_type" do
      rec_a = create(:ai_improvement_recommendation, account: account, recommendation_type: "convention_adherence",
                     status: "approved", target_type: "Account", target_id: account.id,
                     evidence: { "fingerprint" => "convention_adherence|frontend/a.tsx|hardcoded-colors", "title" => "A" })
      rec_b = create(:ai_improvement_recommendation, account: account, recommendation_type: "convention_adherence",
                     status: "approved", target_type: "Account", target_id: account.id,
                     evidence: { "fingerprint" => "convention_adherence|frontend/b.tsx|no-any", "title" => "B" })

      result_a = described_class.new(recommendation: rec_a).call
      result_b = described_class.new(recommendation: rec_b).call

      expect(result_a.ralph_task.task_key).not_to eq(result_b.ralph_task.task_key)
      expect(result_b.created).to be true # a distinct finding must create its own task
    end
  end
end
