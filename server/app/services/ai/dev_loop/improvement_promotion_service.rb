# frozen_string_literal: true

module Ai
  module DevLoop
    # Turns an APPROVED Ai::ImprovementRecommendation into a dev-improve Ralph
    # Loop task. Mirrors AuditBacklogSeeder's loop bootstrap + idempotent task
    # creation, but the source is an approved "offer" (recommendation) rather
    # than a parsed markdown file. Tier-1 of the improvement-discovery loop.
    #
    # The created task carries a recommendation_id back-link; the dev_loop bridge
    # (DevLoopTool) drains it via /dev-loop dev-improve with no bridge change.
    class ImprovementPromotionService
      LOOP_NAME = "dev-improve"
      LOOP_SPEC_PATH = ".claude/loops/dev-improve/PROMPT.md"
      LOOP_BRANCH = "dev-loop/dev-improve"

      # Shared head + tail (incl. Fable autonomy/honesty tunings) live in
      # Ai::DevLoop::LoopGuardrails; only the improve-specific middle lines are here.
      GUARDRAILS = LoopGuardrails.compose(
        "Re-verify the finding against current code BEFORE changing anything (findings rot)",
        "Write a failing spec reproducing the finding FIRST; confirm it is red",
        "Independent review: run /code-review on the diff BEFORE committing (don't trust spec-green alone)",
        "Never introduce a core->extension dependency or a private-extension name into a core file",
        "Commit only to the loop branch — never develop/master, never push"
      )

      Result = Struct.new(:ralph_loop, :ralph_task, :created, :requeued, keyword_init: true)

      # `direction` is the operator's post-discovery decision, captured at approval
      # time. Offers that surface a genuine fork ("delete it OR wire it") used to
      # promote that fork verbatim into the brief, so the executor re-litigated a
      # decision the operator had already made off-record.
      def initialize(recommendation:, direction: nil)
        @recommendation = recommendation
        @account = recommendation.account
        @direction = direction.presence
      end

      def call
        raise ArgumentError, "recommendation must be approved" unless recommendation.status == "approved"
        unless Ai::ImprovementRecommendation::CODE_QUALITY_TYPES.include?(recommendation.recommendation_type)
          raise ArgumentError, "recommendation_type #{recommendation.recommendation_type} is not a code-quality " \
                                "type — dev-improve tasks are code changes; promote via Ai::Learning::" \
                                "ImprovementRecommender#apply_recommendation! instead"
        end

        ralph_loop = find_or_create_loop
        task = ralph_loop.ralph_tasks.find_or_initialize_by(task_key: task_key_for(recommendation))
        created = task.new_record?
        requeued = false

        if created
          task.assign_attributes(task_attributes(recommendation))
          task.save!
        elsif direction
          # Re-approving with a direction is how an operator revises a decision on
          # an already-promoted offer; applying it only on create would silently
          # drop the revision (the common case, since the offer is already promoted).
          apply_direction!(task)
        end

        if !created && (task.status.in?(%w[failed blocked]) || unverified_pass?(task))
          # IMP-938f68b16a1a: re-approving an offer whose promoted task already
          # failed/blocked previously returned it untouched -- dev_next_task
          # only ever claims pending tasks, so the operator's retry intent was
          # silently swallowed (no other seam re-queues a non-repeating task).
          # Re-approval is an explicit "try again" signal; honor it.
          # IMP-60f457f6e8a6 extends the same reasoning to a pass that never
          # produced verified evidence — see #unverified_pass? for why that is
          # a stranded task and not a finished one.
          task.reset!
          requeued = true
        end

        Result.new(ralph_loop: ralph_loop, ralph_task: task, created: created, requeued: requeued)
      end

      private

      attr_reader :account, :recommendation, :direction

      # Applies a direction to an ALREADY-promoted task, journalling the prior
      # brief through the same operator-edit trail dev_update_task writes.
      def apply_direction!(task)
        meta = (task.metadata.presence || {}).dup
        return if meta["operator_direction"] == direction

        meta["operator_direction"] = direction
        task.metadata = meta
        task.apply_operator_edit!(
          { "acceptance_criteria" => directed_criteria(task.acceptance_criteria) },
          note: "Operator direction recorded at re-approval: #{direction}"
        )
      end

      # The direction goes FIRST. It is the one line that must survive an executor
      # skimming a brief whose tail is verifier evidence.
      def directed_criteria(base)
        "OPERATOR DIRECTION (decided at approval — do not re-litigate): #{direction}\n\n#{base}"
      end

      def find_or_create_loop
        account.ai_ralph_loops.find_or_create_by!(name: LOOP_NAME) do |l|
          l.description = "Operator-approved code-quality improvements discovered via /improve. " \
                          "Executed via dev_next_task/dev_complete_task."
          l.ai_tool = "claude_code"
          l.scheduling_mode = "manual"
          l.status = "pending"
          l.branch = LOOP_BRANCH
          l.max_iterations = 500
          l.configuration = {
            "workload" => "improvement-discovery",
            "loop_spec_path" => LOOP_SPEC_PATH,
            "guardrails" => GUARDRAILS
          }
        end
      end

      # IMP-60f457f6e8a6: "passed" is not proof the offer closed. DevLoopTool
      # applies the linked recommendation only when the executor's evidence
      # adjudicated :verified (recorded as the iteration's checks_passed); an
      # attested-only pass left the offer at approved with NO route back --
      # passed is terminal, dev_next_task claims only pending tasks, and
      # dev_complete_task refuses anything not in_progress/blocked. Re-approval
      # is that missing seam, so the invariant narrows from "never disturb a
      # passed task" to "never disturb a VERIFIED passed task".
      #
      # Any verified iteration counts, not merely the last: a task that failed,
      # then passed with real evidence, is done and must not be re-queued.
      # Reaching here already means the offer is still `approved` (the #call
      # guard), i.e. no pass has yet closed it.
      def unverified_pass?(task)
        task.status == "passed" && !task.ralph_iterations.where(checks_passed: true).exists?
      end

      def task_key_for(rec)
        fingerprint = rec.evidence.is_a?(Hash) ? rec.evidence["fingerprint"] : nil
        # Hash the fingerprint so distinct findings get distinct keys — the raw
        # first-12-chars truncation collided on the shared recommendation_type
        # prefix (every convention_adherence finding -> "IMP-convention_a"). Stable
        # for the same fingerprint, so re-promotion stays idempotent.
        basis = (fingerprint.presence || rec.id).to_s
        "IMP-#{Digest::SHA256.hexdigest(basis)[0, 12]}"
      end

      def task_attributes(rec)
        evidence = rec.evidence.is_a?(Hash) ? rec.evidence : {}
        {
          description: evidence["title"].presence || "#{rec.recommendation_type} improvement",
          acceptance_criteria: acceptance_criteria(rec, evidence),
          priority: priority_for(rec),
          execution_type: "agent",
          metadata: {
            "operator_direction" => direction,
            "recommendation_id" => rec.id,
            "kind" => rec.recommendation_type,
            "files" => evidence["files"],
            "repository" => evidence["repository"],
            "extension" => evidence["extension"],
            "fingerprint" => evidence["fingerprint"],
            "verifier_evidence" => evidence["verifier_evidence"],
            "confidence" => rec.confidence_score,
            "blast_radius" => Array(evidence["files"]).size, # Tier-2(c): metric weight
            "executor_hint" => "claude_code",
            "source" => "improve_discovery"
          }.compact
        }
      end

      def acceptance_criteria(rec, evidence)
        fix = rec.recommended_config.is_a?(Hash) ? rec.recommended_config["fix"] : nil
        detail = evidence["description"].presence || fix.presence || "Resolve the finding."
        base = "Re-verify the finding holds on current code. Write a failing spec FIRST and confirm it is red. " \
               "Then: #{detail} Run /code-review on the diff before committing."
        direction ? directed_criteria(base) : base
      end

      # confidence 0..1 -> 0..20 band; audit S1 findings (priority 30) still outrank.
      def priority_for(rec)
        (rec.confidence_score.to_f * 20).round.clamp(1, 20)
      end
    end
  end
end
