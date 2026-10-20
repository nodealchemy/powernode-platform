# frozen_string_literal: true

require "rails_helper"

# Independent review used to be appended to EVERY promoted task's acceptance
# criteria. A full review pass measures 130-190k tokens — comparable to an entire
# iteration — so mandating one on a comment correction roughly doubled the cost of
# that iteration for no benefit.
#
# Two properties are pinned here:
#
#   1. The review requirement is TRIGGERED (multi-file, sensitive path, or
#      security-relevant text) and absent otherwise. It fails TOWARD review.
#   2. When required, the instruction routes to a SYNCHRONOUS UNNAMED SUBAGENT and
#      explicitly not to /code-review. A slash-forked skill delivers its result to
#      the PARENT session rather than to the executor that invoked it, so the
#      mandated review was being paid for in full and delivered where the executor
#      could not read it.
RSpec.describe Ai::DevLoop::ImprovementPromotionService, "independent-review trigger" do
  let(:account) { create(:account) }

  def promote(files:, title:, description:)
    rec = create(:ai_improvement_recommendation,
                 account: account,
                 recommendation_type: "code_lint",
                 status: "approved",
                 confidence_score: 0.8,
                 target_type: "Account",
                 target_id: account.id,
                 evidence: {
                   "title" => title,
                   "fingerprint" => "code_lint|#{files.first}|#{title.parameterize}",
                   "files" => files,
                   "description" => description
                 })
    described_class.new(recommendation: rec).call.ralph_task.acceptance_criteria
  end

  describe "when the finding is low-risk" do
    it "does NOT append an independent-review requirement" do
      criteria = promote(files: %w[app/services/foo.rb],
                         title: "Reword a stale comment",
                         description: "The comment describes an older return shape.")

      expect(criteria).not_to include("Independent review REQUIRED")
      expect(criteria).not_to include("/code-review")
    end

    it "still requires re-verification and a red-first spec" do
      criteria = promote(files: %w[app/services/foo.rb],
                         title: "Reword a stale comment",
                         description: "The comment describes an older return shape.")

      expect(criteria).to include("Re-verify the finding holds on current code")
      expect(criteria).to include("Write a failing spec FIRST")
    end
  end

  describe "when the finding is risky" do
    it "requires review on blast radius alone (3+ files)" do
      criteria = promote(files: %w[app/services/a.rb app/services/b.rb app/services/c.rb],
                         title: "Reword a stale comment",
                         description: "Cosmetic only.")

      expect(criteria).to include("Independent review REQUIRED")
    end

    it "requires review for a single file on a sensitive path" do
      criteria = promote(files: %w[app/controllers/api/v1/things_controller.rb],
                         title: "Reword a stale comment",
                         description: "Cosmetic only.")

      expect(criteria).to include("Independent review REQUIRED")
    end

    it "requires review when the finding reads as security-relevant, whatever the path" do
      criteria = promote(files: %w[app/services/foo.rb],
                         title: "Caller can bypass the check",
                         description: "An unprivileged caller reaches the action.")

      expect(criteria).to include("Independent review REQUIRED")
    end
  end

  # The per-task criteria above are computed fresh on every promotion, so editing
  # the constant fixed them immediately. The GUARDRAILS line is different: it is
  # served from each loop's PERSISTED snapshot, taken when the loop was created.
  # dev-improve is a long-lived singleton, so it kept instructing every executor to
  # "run /code-review" after the constant was changed — which is exactly what
  # happened, and is why an iteration ran a 77k-token review its own task did not
  # require.
  describe "guardrail refresh for already-created loops" do
    let(:stale_snapshot) do
      [
        *Ai::DevLoop::LoopGuardrails::HEAD,
        "Re-verify the finding against current code BEFORE changing anything (findings rot)",
        "Independent review: run /code-review on the diff BEFORE committing (don't trust spec-green alone)",
        "Commit only to the loop branch — never develop/master, never push",
        *Ai::DevLoop::LoopGuardrails::TAIL
      ]
    end

    let(:refreshed) { Ai::DevLoop::LoopGuardrails.refresh(stale_snapshot) }

    it "stops serving the superseded /code-review instruction" do
      expect(refreshed.join(" ")).not_to include("run /code-review on the diff")
    end

    it "replaces it rather than dropping it — no review guidance would be worse than stale" do
      expect(refreshed.join(" ")).to include("SYNCHRONOUS UNNAMED subagent")
      expect(refreshed.join(" ")).to include("don't trust spec-green alone")
    end

    it "drops a retired shared line rather than serving it beside its rewording (B8)" do
      old = Ai::DevLoop::LoopGuardrails::RETIRED_SHARED.first
      refreshed = Ai::DevLoop::LoopGuardrails.refresh(stale_snapshot + [ old ])
      expect(refreshed).not_to include(old)
      expect(refreshed.join(" ")).to include("When you brief or prompt a Fable/Mythos agent")
    end

    it "preserves loop-specific lines it does not recognise" do
      expect(refreshed).to include("Re-verify the finding against current code BEFORE changing anything (findings rot)")
      expect(refreshed).to include("Commit only to the loop branch — never develop/master, never push")
    end

    it "leaves a snapshot with no superseded line untouched" do
      clean = [*Ai::DevLoop::LoopGuardrails::HEAD, "Some loop-specific rule", *Ai::DevLoop::LoopGuardrails::TAIL]

      expect(Ai::DevLoop::LoopGuardrails.refresh(clean)).to include("Some loop-specific rule")
    end
  end

  describe "routing of the required review" do
    let(:criteria) do
      promote(files: %w[app/controllers/api/v1/things_controller.rb],
              title: "Caller can bypass the check",
              description: "An unprivileged caller reaches the action.")
    end

    it "routes to a synchronous unnamed subagent so the result reaches the executor" do
      expect(criteria).to include("SYNCHRONOUS UNNAMED subagent")
      expect(criteria).to match(/reports? back/)
    end

    it "explicitly steers away from /code-review, which forks to the parent session" do
      expect(criteria).to match(%r{NOT /code-review}i)
      expect(criteria).to include("parent session")
    end

    it "bars the reviewer from rspec, because the test DB is shared" do
      expect(criteria).to include("Bar the reviewer from running rspec")
    end

    # A delegated subagent (platform-engineer) has no tool to spawn a reviewer:
    # subagents cannot spawn subagents. The review stays REQUIRED; only who runs
    # it moves to the delegating session or driver.
    it "keeps the review REQUIRED but moves who runs it when the executor is a delegated subagent" do
      expect(criteria).to include("Independent review REQUIRED")
      expect(criteria).to match(/delegated subagent/i)
      expect(criteria).to match(/cannot spawn/i)
      expect(criteria).to match(/report your diff/i)
      expect(criteria).to match(/delegating session or (the )?(loop )?driver runs the independent review/i)
      expect(criteria).to match(/do not (self-review|review it yourself|skip)/i)
    end
  end

  describe "the loop driver is told it runs the review" do
    it "says so explicitly in the shared wording" do
      expect(Ai::DevLoop::LoopGuardrails::REVIEW_WHO_RUNS_IT).to match(/if you are the (delegating session or the )?loop driver,? you run the (independent )?review/i)
    end
  end

  # The criteria text is stored when a task is promoted, so tasks promoted before
  # the wording changed carry the old instruction. It is rewritten when the task
  # is SERVED (SUPERSEDED_MIDDLE style: no migration, idempotent, stored text untouched).
  describe "pending tasks promoted with the previous instruction" do
    let(:previous) do
      "Re-verify the finding holds on current code. Independent review REQUIRED before committing (this finding is " \
      "multi-file, touches a sensitive path, or reads as security-relevant): spawn a SYNCHRONOUS UNNAMED subagent to " \
      "review the diff and report back to you — NOT /code-review, which forks its result to the " \
      "parent session. Bar the reviewer from running rspec; the test DB is shared."
    end

    it "serves the current instruction in place of the old one, keeping the rest of the brief" do
      served = Ai::DevLoop::LoopGuardrails.refresh_review_text(previous)

      expect(served).to start_with("Re-verify the finding holds on current code. Independent review REQUIRED before committing")
      expect(served).to match(/delegated subagent/i)
      expect(served).not_to include("report back to you")
    end

    it "is idempotent and leaves current and unrelated text alone" do
      once = Ai::DevLoop::LoopGuardrails.refresh_review_text(previous)

      expect(Ai::DevLoop::LoopGuardrails.refresh_review_text(once)).to eq(once)
      expect(Ai::DevLoop::LoopGuardrails.refresh_review_text("Fix the typo.")).to eq("Fix the typo.")
      expect(Ai::DevLoop::LoopGuardrails.refresh_review_text(nil)).to be_nil
    end

    it "is applied to the task a dev_next_task claim serves" do
      expect(Ai::Tools::DevLoopTool.instance_method(:task_payload).source_location).to be_present
      source = File.read(Rails.root.join("app/services/ai/tools/dev_loop_tool.rb"))
      expect(source.scan("refresh_review_text").size).to be >= 2
    end
  end

  describe "the review guardrail line" do
    let(:line) { described_class::GUARDRAILS.find { |g| g.start_with?("Independent review") } }

    it "carries the same split: the session or driver spawns the reviewer, a delegated subagent reports its diff" do
      expect(line).to include("SYNCHRONOUS UNNAMED subagent")
      expect(line).to match(/delegated subagent/i)
      expect(line).to match(/cannot spawn/i)
      expect(line).to match(/report your diff/i)
      expect(line).to match(/delegating session or (the )?(loop )?driver runs the independent review/i)
      expect(line).to include("don't trust spec-green alone")
      expect(line).to include("Bar the reviewer from running rspec")
    end

    it "replaces the previous wording in an already-created loop's persisted snapshot" do
      previous = "Independent review, WHEN THE TASK'S ACCEPTANCE CRITERIA ASK FOR IT: spawn a " \
                 "SYNCHRONOUS UNNAMED subagent to review the diff before committing (don't trust " \
                 "spec-green alone). Do NOT use /code-review — a slash-forked skill routes its result " \
                 "to the PARENT session, not to you, so you pay for a review you cannot read. A " \
                 "teammate also cannot spawn named or background agents; the synchronous unnamed form " \
                 "is the one that reports back. Bar the reviewer from running rspec — the test DB is " \
                 "shared and concurrent runs deadlock"
      snapshot = [ *Ai::DevLoop::LoopGuardrails::HEAD, previous, "Some loop-specific rule", *Ai::DevLoop::LoopGuardrails::TAIL ]

      refreshed = Ai::DevLoop::LoopGuardrails.refresh(snapshot)

      expect(refreshed).not_to include(previous)
      expect(refreshed.join(" ")).to match(/delegated subagent/i)
      expect(refreshed).to include("Some loop-specific rule")
    end
  end
end
