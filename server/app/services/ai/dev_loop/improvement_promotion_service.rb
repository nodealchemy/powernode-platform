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
      DIRECTION_MAX = 4_096
      DIRECTION_PREFIX = "OPERATOR DIRECTION (decided at approval — do not re-litigate): "

      LOOP_NAME = "dev-improve"
      LOOP_SPEC_PATH = ".claude/loops/dev-improve/PROMPT.md"
      LOOP_BRANCH = "dev-loop/dev-improve"

      # Shared head + tail (incl. Fable autonomy/honesty tunings) live in
      # Ai::DevLoop::LoopGuardrails; only the improve-specific middle lines are here.
      GUARDRAILS = LoopGuardrails.compose(
        "Re-verify the finding against current code BEFORE changing anything (findings rot)",
        "Write a failing spec reproducing the finding FIRST; confirm it is red",
        "Independent review, WHEN THE TASK'S ACCEPTANCE CRITERIA ASK FOR IT: spawn a SYNCHRONOUS UNNAMED subagent to review the diff before committing (don't trust spec-green alone). Do NOT use /code-review — a slash-forked skill routes its result to the PARENT session, not to you, so you pay for a review you cannot read. A teammate also cannot spawn named or background agents; the synchronous unnamed form is the one that reports back. Bar the reviewer from running rspec — the test DB is shared and concurrent runs deadlock",
        "Never introduce a core->extension dependency or a private-extension name into a core file",
        "Commit only to the loop branch — never develop/master, never push"
      )

      Result = Struct.new(:ralph_loop, :ralph_task, :created, :requeued, keyword_init: true)

      # `direction` is the operator's post-discovery decision, captured at approval
      # time. Offers that surface a genuine fork ("delete it OR wire it") used to
      # promote that fork verbatim into the brief, so the executor re-litigated a
      # decision the operator had already made off-record.
      # `actor` is the user issuing THIS call. recommendation.approved_by is not a
      # substitute: apply_direction! only runs on the re-approval path, where the
      # rec is already "approved" and ImprovementTool's `rec.approve!(user) unless
      # approved` is therefore skipped — so approved_by still names the FIRST
      # approver. Attributing Bob's direction to Alice is exactly the confusion the
      # journal exists to prevent.
      def initialize(recommendation:, direction: nil, actor: nil)
        @recommendation = recommendation
        @account = recommendation.account
        # Raw, NOT .presence: "" and nil must be distinguishable. `.presence`
        # collapsed them, so there was no input meaning "remove the direction I
        # set earlier" — a superseded do-not-re-litigate order stayed pinned with
        # no seam to clear it, and the dev_update_task workaround desynced
        # metadata["operator_direction"] and reintroduced header stacking.
        # Bounded here, at the single seam: metadata["operator_direction"] is
        # exempt from journal truncation (strip_direction needs an exact match),
        # and the same string is ALSO prefixed onto acceptance_criteria — so an
        # unbounded direction rides every dev_next_task claim payload twice.
        # Truncating once, before both writes, keeps them identical.
        @direction = direction.is_a?(String) ? direction.truncate(DIRECTION_MAX) : direction
        @direction_given = !direction.nil?
        @actor = actor
      end

      # Supplied at all (including "" to clear) vs. omitted entirely.
      def direction_given? = @direction_given

      def clearing_direction? = direction_given? && @direction.to_s.strip.empty?

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
        elsif direction_given?
          # Re-approving with a direction is how an operator revises a decision on
          # an already-promoted offer; applying it only on create would silently
          # drop the revision (the common case, since the offer is already promoted).
          apply_direction!(task)
        end

        # `skipped` belongs here for the same reason as failed/blocked: it is
        # terminal, apply_linked_recommendation! never runs for it, dev_next_task
        # claims only pending, and dev_complete_task refuses it — so its offer sits
        # at approved with no route back, which is the exact stranding this branch
        # exists to undo. A dismissal cascade produces skipped routinely.
        if !created && (task.status.in?(%w[failed blocked skipped]) || stranded_pass?(task))
          # IMP-938f68b16a1a: re-approving an offer whose promoted task already
          # failed/blocked previously returned it untouched -- dev_next_task
          # only ever claims pending tasks, so the operator's retry intent was
          # silently swallowed (no other seam re-queues a non-repeating task).
          # Re-approval is an explicit "try again" signal; honor it.
          # IMP-60f457f6e8a6 extends the same reasoning to a pass that never
          # closed its offer — see #stranded_pass? for why that is
          # a stranded task and not a finished one.
          task.reset!
          requeued = true
        end

        Result.new(ralph_loop: ralph_loop, ralph_task: task, created: created, requeued: requeued)
      end

      private

      attr_reader :account, :recommendation, :direction, :actor

      # Applies a direction to an ALREADY-promoted task, journalling the prior
      # brief through the same operator-edit trail dev_update_task writes.
      def apply_direction!(task)
        prior = task.metadata.is_a?(Hash) ? task.metadata["operator_direction"] : nil
        return if prior.to_s == direction.to_s

        # The model owns the metadata write so it happens inside the row lock —
        # pre-assigning task.metadata here would make with_lock refuse the record.
        # author: the journal is the improvement queue's auditability guarantee, and
        # without it every direction recorded at (re-)approval wrote author nil
        # while the dev_update_task seam wrote user:<id> — so two operators issuing
        # conflicting directions could not be told apart. Falls back to the first
        # approver only when no acting user was threaded through.
        who = actor || recommendation.approved_by
        note = if clearing_direction?
          "Operator direction CLEARED at re-approval (was: #{prior})"
        else
          "Operator direction recorded at re-approval: #{direction}"
        end

        # A LAMBDA, not a computed string: apply_operator_edit! evaluates it inside
        # the row lock against post-reload state. Computing the brief here would
        # read pre-lock state and silently discard any dev_update_task amendment
        # that committed between this read and the lock.
        # `prior` is re-read INSIDE the lambda (which apply_operator_edit! evaluates
        # after its reload), NOT captured from the pre-lock read above. Two
        # operators re-approving concurrently both see prior=nil out here; the
        # second would then strip with nil against the first's already-committed
        # brief and prefix a SECOND contradictory header. The pre-lock `prior` is
        # only an early-exit hint; correctness lives in the lambda.
        task.apply_operator_edit!(
          { "acceptance_criteria" =>
              ->(current) { directed_criteria(current, task.metadata.is_a?(Hash) ? task.metadata["operator_direction"] : nil) } },
          note: note,
          author: (who && "user:#{who.id}"),
          # Tags the journal entry so DevLoopTool#self_amended_brief? can tell an
          # OPERATOR's approval-time direction from an executor rewriting its own
          # brief. Without it the two are byte-identical when the operator and the
          # drain session are the same user — which is every directed offer in
          # core mode — and the offer could never auto-apply again.
          edit_source: "approval_direction",
          # nil (not "") so the key is dropped rather than left as an empty string
          # that strip_direction would then try to match on the next revision.
          meta: { "operator_direction" => (clearing_direction? ? nil : direction) }
        )
      end

      # The direction goes FIRST. It is the one line that must survive an executor
      # skimming a brief whose tail is verifier evidence.
      #
      # Any PRIOR direction is stripped before re-prefixing. Revising a decision
      # otherwise stacks headers, and since each one reads "do not re-litigate" the
      # executor receives N mutually contradictory orders — the exact failure this
      # feature exists to prevent. The newest direction is the operative one.
      def directed_criteria(base, prior = nil)
        stripped = strip_direction(base, prior)
        # Clearing removes the header and leaves the brief as it was.
        return stripped if clearing_direction?

        "#{DIRECTION_PREFIX}#{direction}\n\n#{stripped}"
      end

      # Strips the EXACT prior header using the direction stored in metadata,
      # rather than a lazy /\A…\n\n/m match. A multi-paragraph direction ends at
      # its first blank line, so the regex left the superseded rationale sitting
      # directly under the new order — contradictory text that a header COUNT
      # assertion cannot see.
      def strip_direction(text, prior)
        return text.to_s if prior.blank?

        # delete_prefix, not sub: sub removes the first occurrence ANYWHERE, so a
        # brief quoting the prior direction in its body would have the quote
        # stripped and the real leading header left in place — stacking headers.
        text.to_s.delete_prefix("#{DIRECTION_PREFIX}#{prior}\n\n")
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
      # A passed task whose OFFER never closed. Keyed on the offer, not on
      # checks_passed (IMP-019fed52).
      #
      # The old predicate asked "did any iteration record checks_passed?", which
      # was a proxy for "did the offer close" only while those two moved together.
      # The declared-evidence gate split them: an INFERRED verified pass still
      # records checks_passed: true but no longer auto-applies, so the proxy
      # answered "closed" for an offer that was still `approved` — reviving the
      # exact permanent stranding IMP-60f457f6e8a6 fixed, this time for every
      # executor that has not adopted the contract.
      #
      # Reaching here already means the recommendation is pending/approved (the
      # #call guard) — i.e. it did NOT close. So a passed task here is stranded by
      # definition, and re-approval is the operator's explicit retry signal.
      def stranded_pass?(task)
        task.status == "passed"
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
            "operator_direction" => direction.presence,
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

      # Independent review is TRIGGERED, not unconditional. A full review pass has
      # measured 130-190k tokens here — comparable to an entire iteration — so
      # mandating one on every promoted finding roughly doubled loop cost, including
      # on comment corrections and one-line guards.
      #
      # The trigger is derived from data already on the recommendation, never from
      # the executor's own assessment of its change: an executor judging whether its
      # own diff is risky is precisely the judgement that fails.
      #
      # It FAILS TOWARD REVIEW. A finding is exempt only when it is small AND touches
      # no sensitive path AND does not read as security-relevant. Anything ambiguous
      # is reviewed, because the cost of a missed review is unbounded and the cost of
      # a surplus one is a known number.
      REVIEW_FILE_THRESHOLD = 3

      # Paths where a wrong change is an authorization, credential, contract or
      # schema problem rather than a local one.
      REVIEW_SENSITIVE_PATH = %r{
        (^|/)(controllers|serializers)/ | (^|/)db/migrate/
        | permission | auth | token | secret | vault | crypt | signing
        | approval | autonomy_gate | intervention_policy | principal
      }xi

      REVIEW_SENSITIVE_TEXT = /
        security | credential | permission | authoriz | authenticat
        | token | secret | key[\s_]material | bypass | escalat | leak
      /xi

      # Routed to a SYNCHRONOUS UNNAMED subagent deliberately. A slash-forked
      # /code-review delivers its result to the PARENT session rather than to the
      # executor that invoked it, so the mandated review was being paid for in full
      # and delivered to an address the executor could not read — observed three
      # times, once leaving an iteration blocked for 14 minutes on a reply that
      # structurally could not arrive.
      REVIEW_INSTRUCTION =
        "Independent review REQUIRED before committing (this finding is multi-file, touches a " \
        "sensitive path, or reads as security-relevant): spawn a SYNCHRONOUS UNNAMED subagent to " \
        "review the diff and report back to you — NOT /code-review, which forks its result to the " \
        "parent session. Bar the reviewer from running rspec; the test DB is shared."

      def independent_review_required?(_rec, evidence)
        files = Array(evidence["files"])
        return true if files.size >= REVIEW_FILE_THRESHOLD
        return true if files.any? { |f| REVIEW_SENSITIVE_PATH.match?(f.to_s) }

        REVIEW_SENSITIVE_TEXT.match?("#{evidence['title']} #{evidence['description']}")
      end

      def acceptance_criteria(rec, evidence)
        fix = rec.recommended_config.is_a?(Hash) ? rec.recommended_config["fix"] : nil
        detail = evidence["description"].presence || fix.presence || "Resolve the finding."
        base = "Re-verify the finding holds on current code. Write a failing spec FIRST and confirm it is red. " \
               "Then: #{detail}"
        base = "#{base} #{REVIEW_INSTRUCTION}" if independent_review_required?(rec, evidence)
        direction.present? ? directed_criteria(base) : base
      end

      # confidence 0..1 -> 0..20 band; audit S1 findings (priority 30) still outrank.
      def priority_for(rec)
        (rec.confidence_score.to_f * 20).round.clamp(1, 20)
      end
    end
  end
end
