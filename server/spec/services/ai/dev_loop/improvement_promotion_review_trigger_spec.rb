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
      expect(criteria).to include("report back to you")
    end

    it "explicitly steers away from /code-review, which forks to the parent session" do
      expect(criteria).to match(%r{NOT /code-review}i)
      expect(criteria).to include("parent session")
    end

    it "bars the reviewer from rspec, because the test DB is shared" do
      expect(criteria).to include("Bar the reviewer from running rspec")
    end
  end
end
