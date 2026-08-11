# frozen_string_literal: true

module Ai
  module DevLoop
    # Shared guardrail spine for the autonomous dev-loop executors (audit-backlog,
    # improvement-promotion, campaign). Each driver appends its own task-specific
    # lines; the safety / governance / honesty / Fable lines live here so they
    # can't drift across the three callers and any tuning lands ONCE.
    #
    # Delivered to every executor (Claude and non-Claude) in the dev_next_task
    # payload's "guardrails" field.
    #
    # The TAIL carries two Fable-5 tunings (adapted from Anthropic's Fable-5
    # prompting guidance, recallable as guidance-fable5-compliance). They are
    # stated model-agnostically because they improve every long-running executor,
    # not only Fable:
    #   * autonomous-operation — don't pause to ask permission mid-loop for
    #     reversible in-scope work, and don't end a turn on a plan/question/promise
    #     (Fable "rare early stopping", most likely deep in long runs).
    #   * progress-grounding — audit each progress/completion claim against a real
    #     tool result before reporting it (Fable testing: nearly eliminates
    #     fabricated status reports).
    module LoopGuardrails
      # Opening cluster — identical across all three loops.
      HEAD = [
        "One task per iteration — finish or report before pulling the next",
        "Consult model-agnostic guidance BEFORE changing code: run search_knowledge with tag guidance-* and honor the applicable safety/governance/convention rules — the SessionStart digest is Claude-only, so non-Claude executors MUST query",
        "Never batch-approve — review auto-discovered changes, permission grants, and financial/training decisions ONE at a time; state the count before any bulk action (>5 items needs explicit confirmation)"
      ].freeze

      # Closing cluster — verification, autonomy, honesty, stop-rule, refusal.
      TAIL = [
        "Run the verification gate before reporting done: scripts/validate.sh (specs + tsc + pattern-validation + gitleaks) or the targeted specs/tsc/pattern-validation for what you changed — do not rely on '/verify' (Claude-only)",
        "DECLARE your test evidence when reporting: check_results.evidence = {framework, passed, failed, command} (an array for several suites). A declared block is judged on its own fields and ALL suites must be green; anything else is inferred by parsing and will NOT close the linked improvement offer",
        "You are operating autonomously — the user is not watching and cannot answer mid-task. Do not pause to ask permission before a reversible action that follows from the task; proceed. Before ending a turn, if your final message is a plan, a question, or a promise ('I'll…', 'next…') rather than completed work, do that work now with a tool call instead of ending on the promise",
        "Ground every progress or completion claim in a tool result from this session: audit each claim against real evidence before reporting it, and say plainly when a step failed, was skipped, or is unverified — never report success you cannot point to",
        "After 3 failed attempts on the same task, report outcome=failed and stop",
        "On a Fable/Mythos refusal (stop_reason \"refusal\"), don't panic or manually retry — it auto-reframes once then falls back to Opus and logs it; prefer goal+constraints prompting over step-by-step for Fable (search_knowledge tag:guidance-fable5-compliance)"
      ].freeze

      module_function

      # Compose a loop's guardrail list: shared head + this loop's task-specific
      # lines + shared tail. Returns a frozen Array<String>.
      def compose(*specific)
        [*HEAD, *specific.flatten, *TAIL].freeze
      end

      # Re-derive a loop's served guardrails from its PERSISTED snapshot at pull
      # time, so a long-lived loop (dev-improve singleton, campaign loops) picks
      # up HEAD/TAIL tuning without waiting for its config to be reseeded.
      #
      # persisted was built at create time as HEAD + loop-specific middle lines +
      # TAIL. We can't recover exactly which persisted lines were "the middle"
      # once HEAD/TAIL have since changed, so we approximate: strip any line that
      # exactly matches a CURRENT HEAD/TAIL entry, and recompose with the
      # CURRENT HEAD/TAIL around whatever remains.
      #
      # Documented limitation: this only catches lines that are unchanged from
      # (or literally absent from) the persisted snapshot. A shared line whose
      # TEXT was tuned (not just added/removed) still has its old wording linger
      # in the served list as a stray "middle" line until the loop's config is
      # reseeded — new/removed shared lines propagate correctly (the main drift
      # class this guards against); text-edited shared lines do not fully
      # self-heal without a reseed.
      def refresh(persisted)
        middle = Array(persisted) - HEAD - TAIL
        compose(middle)
      end
    end
  end
end
