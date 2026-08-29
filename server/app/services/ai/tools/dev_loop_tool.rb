# frozen_string_literal: true

module Ai
  module Tools
    # MCP tool bridging Ralph Loop task queues to external loop executors
    # (Claude Code sessions today, container agents later). Executors PULL
    # work via dev_next_task and report results via dev_complete_task —
    # the platform schedules, tracks, and governs but never pushes work.
    class DevLoopTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.update"

      OUTCOMES = %w[passed failed blocked skipped].freeze

      # G12: byte caps for the base structural file CONTENTS re-injected into every
      # dev_next_task payload (rides every iteration, so bound the token/payload cost).
      BASE_CONTEXT_PER_FILE_LIMIT = 12_288  # head bytes kept per base file (~12 KiB)
      BASE_CONTEXT_TOTAL_LIMIT    = 49_152  # bytes kept across all base files (~48 KiB)

      # C3: cap on compound learnings surfaced per claimed task — small and lean by
      # design (see #relevant_compound_learnings).
      RELEVANT_LEARNINGS_LIMIT = 4

      def self.definition
        {
          name: "dev_loop",
          description: "Pull-based task bridge for Ralph Loop executors (Claude Code or platform agents)",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            loop_id: { type: "string", required: false, description: "Ralph loop ID or name" },
            task_key: { type: "string", required: false, description: "Task key being reported" },
            outcome: { type: "string", required: false, description: "passed | failed | blocked | skipped" },
            summary: { type: "string", required: false, description: "What was done / why it failed, blocked, or was skipped" },
            check_results: { type: "object", required: false, description: "Verification evidence (specs run, results)" },
            learning: { type: "string", required: false, description: "Reusable learning extracted from this task" },
            git_branch: { type: "string", required: false, description: "Branch the work was committed to" },
            commit_sha: { type: "string", required: false, description: "Commit SHA for the passed task" },
            files_changed: { type: "array", required: false, description: "Paths touched by this task" },
            agent_id: { type: "string", required: false, description: "Platform agent to delegate a task to" },
            await: { type: "boolean", required: false, description: "Block until the delegated agent finishes" },
            timeout: { type: "integer", required: false, description: "Await timeout seconds (max 300)" },
            budget_cents: { type: "integer", required: false, description: "Budget for the delegated task" },
            holder: { type: "string", required: false, description: "Driver identity (lease holder) for campaign-loop pulls" },
            description: { type: "string", required: false, description: "Task title (dev_update_task)" },
            acceptance_criteria: { type: "string", required: false, description: "Executor-facing brief (dev_update_task)" },
            priority: { type: "integer", required: false, description: "Queue priority (dev_update_task)" },
            note: { type: "string", required: false, description: "Append-only operator note (dev_update_task)" },
            required_capabilities: { type: "array", required: false, description: "Capabilities an executor must match" },
            capability_match_strategy: { type: "string", required: false, description: "all | any | weighted" },
            # Kept in sync with action_definitions["dev_update_task"] on purpose:
            # the per-action MCP schema comes from there, but the LLM agent
            # tool-calling path reads THIS flat one, so an omission here silently
            # denies agents a parameter the MCP surface advertises.
            execution_type: { type: "string", required: false, description: "agent | pipeline | a2a_task | container | human | community" },
            delegation_config: { type: "object", required: false, description: "Delegation settings (dev_update_task)" }
          }
        }
      end

      def self.action_definitions
        {
          "dev_next_task" => {
            description: "Claim the next pending task from a Ralph Loop queue (priority/dependency ordered). " \
                         "Returns the task with acceptance criteria, guardrails, and loop context. " \
                         "Idempotent: re-claiming returns your own in-progress task. " \
                         "Refuses when the loop is halted (kill switch, paused, terminal, max iterations).",
            parameters: {
              loop_id: { type: "string", required: true, description: "Ralph loop ID or name" },
              holder: { type: "string", required: false,
                        description: "Driver identity (lease holder). For a campaign loop the single-driver " \
                                     "lease gates pulls — pass the same holder you claimed the campaign with; " \
                                     "the pull renews the lease so another driver can't race in." }
            }
          },
          "dev_complete_task" => {
            description: "Report the outcome of a claimed (in_progress) task, OR resolve a blocked task " \
                         "(operator disposition — no re-claim needed). Records a RalphIteration with verification " \
                         "evidence, transitions the task (passed/failed/blocked/skipped), and captures learnings on the loop.",
            parameters: {
              loop_id: { type: "string", required: true, description: "Ralph loop ID or name" },
              task_key: { type: "string", required: true, description: "Task key being reported" },
              outcome: { type: "string", required: true, description: "passed | failed | blocked | skipped" },
              summary: { type: "string", required: true, description: "What was done / why it failed, blocked, or was skipped" },
              check_results: { type: "object", required: false,
                               description: "Verification evidence. DECLARE it to get automatic credit: " \
                                            "{\"evidence\": {\"framework\": \"rspec\", \"passed\": 173, " \
                                            "\"failed\": 0, \"command\": \"bundle exec rspec …\"}} — an array " \
                                            "for several suites. A declared block is adjudicated on its own " \
                                            "fields alone (surrounding gate/lint summaries are ignored, so they " \
                                            "can neither credit nor contradict it) and ALL declared suites must " \
                                            "be green — so declare only the FINAL green runs and keep a red-first " \
                                            "run in a plain key beside it, never inside evidence. Anything else is " \
                                            "INFERRED by parsing: it still records a pass, but will NOT auto-apply " \
                                            "the linked improvement offer (the response says which via " \
                                            "evidence_source)." },
              learning: { type: "string", required: false, description: "Reusable learning extracted from this task" },
              git_branch: { type: "string", required: false, description: "Branch the work was committed to" },
              commit_sha: { type: "string", required: false, description: "Commit SHA for the passed task" },
              files_changed: { type: "array", required: false, description: "Paths touched by this task" }
            }
          },
          "dev_list_tasks" => {
            description: "List tasks in a Ralph Loop queue, optionally filtered by status (pending | in_progress | passed | failed | blocked | skipped). Use to inspect blocked tasks awaiting disposition or audit the queue. Ordered by position then priority.",
            parameters: {
              loop_id: { type: "string", required: true, description: "Ralph loop ID or name" },
              status:  { type: "string", required: false, description: "Filter by status: pending | in_progress | passed | failed | blocked | skipped (omit for all)" },
              limit:   { type: "integer", required: false, description: "Max tasks to return (default 50, max 200)" }
            }
          },
          "delegate_ralph_task" => {
            description: "Hand a pending/in-progress Ralph task to a platform agent (A2A) instead of executing it " \
                         "yourself. Reuses spawn_task's capability-matrix + delegation-authority checks. With await, " \
                         "blocks until the agent finishes and records the outcome on the loop. No-op when halted.",
            parameters: {
              loop_id: { type: "string", required: true, description: "Ralph loop ID or name" },
              task_key: { type: "string", required: true, description: "Task to delegate" },
              agent_id: { type: "string", required: true, description: "Platform agent to delegate to" },
              await: { type: "boolean", required: false, description: "Block until the agent finishes (default false)" },
              timeout: { type: "integer", required: false, description: "Await timeout seconds (max 300)" },
              budget_cents: { type: "integer", required: false, description: "Budget for the delegated task" }
            }
          },
          "dev_update_task" => {
            description: "Amend a queued task's brief or routing AFTER it was created — the seam for a decision " \
                         "the operator made post-approval (scope narrowed, one of two offered directions chosen). " \
                         "Edits reach the executor on the next dev_next_task claim. Overwrites are journalled with " \
                         "their prior value in metadata.operator_edits; `note` appends without touching the brief. " \
                         "Cannot change status — use dev_complete_task for transitions.",
            parameters: {
              loop_id: { type: "string", required: true, description: "Ralph loop ID or name" },
              task_key: { type: "string", required: true, description: "Task key (or task UUID) to amend" },
              note: { type: "string", required: false,
                      description: "Append an attributed operator note, leaving the brief intact" },
              description: { type: "string", required: false, description: "Replace the task title" },
              acceptance_criteria: { type: "string", required: false,
                                     description: "Replace the executor-facing brief" },
              priority: { type: "integer", required: false, description: "Requeue priority (higher drains first)" },
              execution_type: { type: "string", required: false,
                                description: Ai::RalphTask::EXECUTION_TYPES.join(" | ") },
              required_capabilities: { type: "array", required: false,
                                       description: "Capabilities an executor must match" },
              capability_match_strategy: { type: "string", required: false,
                                           description: Ai::RalphTask::CAPABILITY_STRATEGIES.join(" | ") },
              delegation_config: { type: "object", required: false, description: "Delegation settings" }
            }
          }
        }
      end

      protected

      def call(params)
        return error_result("Account context required") unless account
        return error_result("User or agent context required") unless claimant_ref

        case params[:action]
        when "dev_next_task" then next_task(params)
        when "dev_complete_task" then complete_task(params)
        when "dev_list_tasks" then list_tasks(params)
        when "dev_update_task" then update_task(params)
        when "delegate_ralph_task" then delegate_ralph_task(params)
        else
          error_result("Unknown action: #{params[:action]}")
        end
      end

      private

      def next_task(params)
        loop_record = find_loop(params[:loop_id])
        return error_result("Ralph loop not found") unless loop_record

        if (reason = halt_reason(loop_record))
          # G5: goal-driven terminator — when the configured completion goal is
          # met, actually finish the loop (transition to completed) instead of
          # handing out more work. Other halt reasons just stop the pull.
          loop_record.complete! if reason == "goal_met" && loop_record.can_complete?
          return { success: true, halted: true, reason: reason, task: nil }
        end
        if (reason = delegation_block_reason(loop_record, params[:holder]))
          return { success: true, halted: true, reason: reason, task: nil }
        end

        result = nil
        loop_record.with_lock do
          result = claim_under_lock(loop_record, params[:holder])
        end
        result
      rescue Ai::RalphTask::InvalidTransitionError, ActiveRecord::RecordInvalid => e
        error_result(e.message)
      end

      # Campaign loops are gated by their driver routing + the single-driver lease so a
      # Claude Code session and the platform executor never drain the same campaign at once.
      # Legacy loops (no campaign, or driver_kind unset) are unaffected. Returns a halt
      # reason string when this caller must back off, else nil (and renews the lease).
      def delegation_block_reason(loop_record, holder)
        return nil if loop_record.campaign_id.blank?

        # Re-read driver_kind: a concurrent #delegate may have just reassigned this loop, so
        # the in-memory copy from find_loop could be stale.
        loop_record.reload
        # NOTE: a blank driver_kind is NOT an exemption. It used to return nil here
        # ("legacy / not routed → ungated"), which skipped the lease check and let two
        # drivers drain one campaign. No supported path produces that row
        # (CampaignDriver#create_campaign_loop always sets driver_kind), so an unrouted
        # campaign loop falls through to the lease below and is gated like any other.
        return "delegated_to_platform" if loop_record.platform_driven?

        campaign = loop_record.campaign
        return nil unless campaign

        if holder.present?
          # Single atomic step: acquires the lease if it's free or already ours, returns
          # false if another driver holds it (no check-then-acquire gap).
          return campaign.acquire_driver_lease!(holder: holder) ? nil : "leased_to:#{campaign.driver_lease_holder}"
        end

        # Legacy CC caller without a holder: allow only when the lease is free.
        campaign.driver_lease_active? ? "leased_to:#{campaign.driver_lease_holder}" : nil
      end

      def list_tasks(params)
        loop_record = find_loop(params[:loop_id])
        return error_result("Ralph loop not found") unless loop_record

        status = params[:status].to_s.strip
        scope = loop_record.ralph_tasks
        if status.present?
          unless Ai::RalphTask::STATUSES.include?(status)
            return error_result("Invalid status '#{status}'; expected one of: #{Ai::RalphTask::STATUSES.join(', ')}")
          end
          scope = scope.where(status: status)
        end

        total = scope.count
        limit = params[:limit].present? ? params[:limit].to_i.clamp(1, 200) : 50
        tasks = scope.ordered.limit(limit)

        {
          success: true,
          loop: { id: loop_record.id, name: loop_record.name },
          status: status.presence,
          count: tasks.size,
          total_matching: total,
          tasks: tasks.map(&:task_details),
          queue: queue_snapshot(loop_record)
        }
      end

      # Keys that steer the call rather than name a task attribute to amend.
      UPDATE_CONTROL_KEYS = %w[action loop_id task_key note].freeze

      def update_task(params)
        loop_record = find_loop(params[:loop_id])
        return error_result("Ralph loop not found") unless loop_record

        # Kill switch, matching both sibling write actions. Without it an
        # emergency halt stopped executors CLAIMING and REPORTING work while
        # still letting any principal rewrite task state — and this action is
        # reachable by agent and instance principals, which is the whole threat
        # model the credit guard below addresses.
        if account.respond_to?(:ai_suspended?) && account.ai_suspended?
          return { success: true, halted: true, reason: "emergency_halt", task_key: params[:task_key] }
        end

        task = find_task(loop_record, params[:task_key])
        return error_result("Task not found: #{params[:task_key]}") unless task

        supplied = params.to_h.keys.map(&:to_s) - UPDATE_CONTROL_KEYS
        # Only reject keys that ARE task columns but are not operator-editable —
        # naming `status` should fail loudly rather than be dropped on the floor.
        # Unknown non-column keys are ignored so harness/transport noise can't
        # turn a valid amendment into an error.
        protected_keys = supplied & (Ai::RalphTask.column_names - Ai::RalphTask::OPERATOR_EDITABLE_FIELDS)
        if protected_keys.any?
          return error_result(
            "Cannot edit #{protected_keys.join(', ')} via dev_update_task. " \
            "Status transitions go through dev_complete_task; loop bookkeeping is not operator-editable. " \
            "Editable: #{Ai::RalphTask::OPERATOR_EDITABLE_FIELDS.join(', ')}."
          )
        end

        attrs = params.to_h.stringify_keys.slice(*Ai::RalphTask::OPERATOR_EDITABLE_FIELDS).compact
        note = params[:note]
        if attrs.empty? && note.blank?
          return error_result("Nothing to update — supply a note or one of: " \
                              "#{Ai::RalphTask::OPERATOR_EDITABLE_FIELDS.join(', ')}.")
        end

        changed = task.apply_operator_edit!(attrs, note: note, author: claimant_ref)
        return error_result("No change — the supplied values already match the task.") if changed.empty?

        {
          success: true,
          loop: { id: loop_record.id, name: loop_record.name },
          task: task.reload.task_details,
          changed: changed,
          warning: task.amendment_delivery_warning
        }.compact
      rescue ActiveRecord::RecordInvalid => e
        error_result(e.record.errors.full_messages.join("; "))
      rescue ArgumentError => e
        # Shape rejection from RalphTask::OPERATOR_FIELD_SHAPES — fail at the seam
        # rather than persisting a scalar that raises TypeError later.
        error_result(e.message)
      end

      # IMP-3c15b871f6bd. The abuse shape is self-serving: weaken the brief you
      # are about to be judged against, then report passed — a :verified
      # adjudication auto-applies the linked improvement offer, closing it as
      # though the original finding were addressed.
      #
      # This guards the CREDIT, not the edit, after two earlier designs failed:
      #   - Refusing agent:/instance: principals, or requiring a permission, is
      #     backwards here. The operator reaches MCP as an INSTANCE principal
      #     (dev-cell drives the loop), and enforce_permission! returns early for
      #     instance principals — so both proxies could only refuse the operator
      #     while leaving a user-principal executor free.
      #   - Refusing a self-claimed brief edit was BOTH bypassable and harmful:
      #     an executor drops out of in_progress with dev_complete_task(blocked),
      #     amends, then passes (blocked -> passed is a legal transition); while a
      #     genuine drain session, where the claim and the amendment come from the
      #     same session, was blocked from narrowing a brief at all.
      #
      # Editing stays open. What closes is the automatic credit: if the principal
      # reporting the outcome is also the one that amended the brief, the pass is
      # recorded as attested and the offer stays `approved` for operator
      # judgement. Keyed on the journal, so status juggling cannot evade it —
      # operator_edits records the author of every brief edit.
      def self_amended_brief?(task)
        # Reads the dedicated, UNCAPPED record rather than scanning
        # operator_edits: that journal is truncated to OPERATOR_JOURNAL_LIMIT, so
        # scanning it let a flood of trivial edits evict the brief edit and
        # restore the credit. RalphTask#apply_operator_edit! maintains this key
        # and deliberately omits an operator's approval-time direction.
        amended_by = task.metadata.is_a?(Hash) ? task.metadata["brief_amended_by"] : nil
        Array(amended_by).include?(claimant_ref)
      end

      def find_task(loop_record, key)
        return nil if key.blank?

        loop_record.ralph_tasks.find_by(task_key: key) || loop_record.ralph_tasks.find_by(id: key)
      end

      # Per-holder concurrent claims: a single user may run several driver lanes
      # (e.g. cc-lane-a / cc-lane-b) against the same loop. The re-claim below is
      # scoped to (user, holder) so lane B doesn't silently re-claim lane A's task;
      # a legacy in-progress task with no stored holder (pre-fix) is a wildcard —
      # reclaimable by any holder of the same user, so it never strands.
      def claim_under_lock(loop_record, holder)
        if (mine = own_in_progress_task(loop_record, holder))
          return task_payload(loop_record, mine, reclaimed: true)
        end

        cap = max_concurrent_claims(loop_record)
        if user_in_progress_count(loop_record) >= cap
          return { success: true, task: nil, halted: true, reason: "max_concurrent_claims_reached",
                   queue: queue_snapshot(loop_record) }
        end

        eligible = eligible_pending_tasks(loop_record)
        if eligible.empty?
          return { success: true, task: nil, queue_empty: true,
                   queue: queue_snapshot(loop_record) }
        end

        # File-collision guard only engages once a loop opts into parallelism
        # (cap > 1) — under the default cap of 1 the ordering is identical to the
        # pre-fix single-claim behavior (see characterization spec).
        task =
          if cap > 1
            others = other_in_progress_tasks(loop_record, holder)
            eligible.detect { |t| !collides_with_any?(task_files(t), others) }
          else
            eligible.first
          end

        unless task
          return { success: true, task: nil, queue_empty: false, no_eligible_task: true,
                   reason: "file_collision", queue: queue_snapshot(loop_record) }
        end

        loop_record.start! if loop_record.can_start?
        task.start!
        task.record_execution_attempt!
        # Targeted merge: this runs under the LOOP lock while dev_complete_task
        # and dev_update_task write the same column under the TASK lock, so a
        # whole-column rewrite here would drop their keys.
        task.merge_metadata!(
          "claimed_by" => claimant_ref,
          "claimed_holder" => normalized_holder(holder),
          "claimed_at" => Time.current.iso8601
        )

        task_payload(loop_record, task)
      end

      def max_concurrent_claims(loop_record)
        config = loop_record.configuration || {}
        raw = config["max_concurrent_claims"]
        raw.present? ? [raw.to_i, 1].max : 1
      end

      def user_in_progress_count(loop_record)
        loop_record.ralph_tasks.in_progress.to_a.count { |t| t.metadata&.dig("claimed_by") == claimant_ref }
      end

      def eligible_pending_tasks(loop_record)
        loop_record.ralph_tasks.pending
                   .where.not(execution_type: "human")
                   .order(priority: :desc, position: :asc)
                   .select(&:dependencies_satisfied?)
      end

      def normalized_holder(holder)
        holder.presence || "default"
      end

      # True when `task` is the current claimant's own in-progress task under `holder`.
      # A missing claimed_holder (pre-fix task) is a wildcard: matches any holder of
      # the same user so an existing session's claim never strands.
      def claimed_by_holder?(task, holder)
        meta = task.metadata || {}
        return false unless meta["claimed_by"] == claimant_ref

        stored = meta["claimed_holder"]
        stored.blank? || stored == normalized_holder(holder)
      end

      # G12/collision guard: files of an in-progress task, for intersection checks
      # against newly-eligible pending tasks.
      def task_files(task)
        meta = task.metadata.is_a?(Hash) ? task.metadata : {}
        Array(meta["files"]).compact.map(&:to_s)
      end

      # Missing/empty files = unknown blast radius = always colliding (not safe to
      # parallelize). Two tasks touching the same extensions/private/<x> submodule
      # collide even when their file sets don't intersect (shared submodule index).
      def files_collide?(files_a, files_b)
        return true if files_a.empty? || files_b.empty?
        return true if (files_a & files_b).any?

        (private_submodules(files_a) & private_submodules(files_b)).any?
      end

      def private_submodules(files)
        files.filter_map { |f| f[%r{\Aextensions/private/([^/]+)/}, 1] }
      end

      def collides_with_any?(candidate_files, other_tasks)
        other_tasks.any? { |t| files_collide?(candidate_files, task_files(t)) }
      end

      def complete_task(params)
        loop_record = find_loop(params[:loop_id])
        return error_result("Ralph loop not found") unless loop_record

        # Kill-switch: while the account's AI is emergency-halted, do not let an executor
        # write task transitions / iterations / learnings (mirrors next_task's halt guard).
        if account.respond_to?(:ai_suspended?) && account.ai_suspended?
          return { success: true, halted: true, reason: "emergency_halt", task_key: params[:task_key] }
        end

        task = loop_record.ralph_tasks.find_by(task_key: params[:task_key])
        return error_result("Task not found: #{params[:task_key]}") unless task
        # in_progress: report a claimed task. blocked: operator resolution of a
        # task that stopped for a decision (no re-claim needed).
        unless task.status.in?(%w[in_progress blocked])
          return error_result("Task is #{task.status}, not in_progress or blocked — claim it via dev_next_task first, or resolve a blocked task directly")
        end

        outcome = params[:outcome].to_s
        return error_result("Invalid outcome: #{outcome} (use #{OUTCOMES.join(' | ')})") unless OUTCOMES.include?(outcome)

        summary = params[:summary].to_s
        return error_result("summary is required") if summary.blank?


        # G10: scope guardrail. A "passed" outcome that touches a protected path
        # (payments/auth/crypto/secrets) or a critical-tier file is NOT silently
        # accepted — it is remapped to a human-gated "blocked" (a park for review).
        # Only remap an in_progress task: a blocked task can't re-block (operator
        # resolution entries arrive already blocked).
        guardrail = nil
        if outcome == "passed" && task.status == "in_progress" &&
           (violation = scope_guardrail_violation(loop_record, params[:files_changed]))
          guardrail = violation
          outcome = "blocked"
          summary = "[scope-guardrail] #{violation[:summary]} — parked for human review. #{summary}"
        end

        # IMP-f2b3e9a67d11: adjudicate the executor's own evidence — AFTER the
        # G10 remap, so a park-for-review pays no scan cost for a verdict the
        # blocked branch would discard. The bridge cannot run the suite, but a
        # "passed" whose parsed tallies all show failures is rejected outright,
        # and a pass with no parseable test evidence records as attested
        # (checks_passed: false) without auto-applying the linked offer — the
        # response's `verification` field says which happened.
        verification = nil
        evidence_source = nil
        if outcome == "passed"
          # IMP-b103e873ee6d: a PRESENT evidence block that can't be used as
          # declared (unrecognized framework, or a stray-closing-tag-truncated
          # shape missing a count) used to fall back to inference silently — the
          # task still passed, but its offer never closed and nothing said why.
          # Refuse instead: the executor gets an actionable message and the task
          # stays claimable for a corrected re-report, rather than shipping a
          # pass whose evidence contract quietly downgraded.
          if (problem = ::Ai::Ralph::TestVerificationService.declared_evidence_problem(params[:check_results]))
            return error_result(
              "check_results.evidence could not be used as declared evidence (#{problem}). Declaring evidence " \
              "is optional, but a PRESENT block must be usable — fix it and re-report, or drop the evidence key " \
              "entirely to let the pass be adjudicated by inference (checks_passed still records, but the linked " \
              "offer will not auto-apply)."
            )
          end

          adjudication = ::Ai::Ralph::TestVerificationService.adjudicate_check_results(params[:check_results])
          return error_result(contradiction_error(adjudication)) if adjudication[:verdict] == :contradicted
          verification = adjudication[:verdict]
          evidence_source = adjudication[:source]
        end

        iteration = nil
        pairing_error = nil
        # Lock the task so the (status → outcome) pre-check, the iteration record, and
        # the task transition are atomic. The entry guard admits in_progress|blocked,
        # but not every outcome is legal for both (skipped is invalid for in_progress;
        # blocked is invalid for an already-blocked task), so we re-validate against the
        # task's own transition guards under the lock — BEFORE creating an iteration —
        # and the autonomous loop can't flip a blocked task's status mid-transition and
        # orphan a half-applied iteration.
        task.with_lock do
          unless transition_allowed?(task, outcome)
            pairing_error = "Cannot mark #{task.status} task as #{outcome}"
            next
          end

          iteration = prepare_iteration(loop_record, task, params)
          record_outcome(loop_record, task, iteration, outcome, summary, params,
                         verification: verification, evidence_source: evidence_source)
        end
        return error_result(pairing_error) if pairing_error

        # Credit-loop half B (IMP-5f8a744b8892): a VERIFIED passed outcome
        # resolves the claim-time injections positively. Attested-only passes
        # do not credit (IMP-f2b3e9a67d11: the platform does not trust the
        # outcome enough to auto-apply the offer, so it must not inflate
        # learning effectiveness on it either); failed/blocked leave the
        # injections unresolved — that depression is the intended signal.
        credit_injected_learnings!(task) if outcome == "passed" && verification == :verified

        loop_record.reload
        all_tasks_completed = loop_record.all_tasks_completed?
        # IMP-af21b11d476c: this was the ONLY place manual/claude_code loops ever
        # observed all_tasks_completed? (the field was already computed below for
        # the response) but never acted on it — the loop-level status only flipped
        # to "completed" via the scheduled sweep, which structurally excludes
        # scheduling_mode: manual loops. Complete it here, deterministically, the
        # moment the last task passes/skips, instead of leaving it accidental.
        #
        # campaign_id.blank? guard is load-bearing, not incidental: a campaign's
        # loop is open-ended (more record_increment!/delegated tasks are expected
        # on it), and Campaign#should_stop?/#fully_drained? deliberately rely on
        # the loop staying `active` as the ONLY guard against a completion_pct-
        # based premature finalization on an unseeded campaign (see that
        # comment, and memory: "Campaign premature-finalization bug"). Verified
        # live two campaign-tied loops ("Migrate Claude-only rules", "Model
        # Routing v4") have no plan_increments seeded — completing them here
        # would silently reopen that exact bug via this shared code path (this
        # method is also how /dev-loop <campaign-loop> drains a campaign's own
        # loop). Non-campaign loops (plain dev-improve-style backlogs) have no
        # such open-ended-refill expectation, so completing them here is safe.
        loop_record.complete! if all_tasks_completed && loop_record.campaign_id.blank? && loop_record.can_complete?

        response = {
          success: true,
          task_key: task.task_key,
          task_status: task.reload.status,
          iteration_number: iteration.iteration_number,
          queue: queue_snapshot(loop_record.reload),
          all_tasks_completed: all_tasks_completed
        }
        # Surface the adjudication so an attested-only pass is VISIBLE to the
        # caller (an unverified pass silently skipping auto-apply otherwise
        # looks identical to a verified one).
        response[:verification] = verification.to_s if verification
        # WHICH path decided, and whether the offer actually closed. Without
        # these, a :verified pass from INFERRED evidence is byte-identical to a
        # declared one — the executor sees "verified", the offer silently stays
        # approved, and a malformed declaration (e.g. string counts, which
        # declared_tally rejects) is indistinguishable from a good one.
        if evidence_source
          response[:evidence_source] = evidence_source.to_s
          if verification == :verified && evidence_source != :declared
            response[:auto_apply_skipped] =
              "verified from INFERRED evidence — the linked offer stays approved. Declare " \
              "check_results.evidence = {framework:, passed:, failed:} to close it automatically."
          end
        end
        # Governance annotation (report-only — no approval lane until an
        # executor consumes it; see audit finding F3-01 for why).
        if Array(params[:files_changed]).size > 5
          response[:governance] = { category: "dev.multi_file_change",
                                    files_changed: Array(params[:files_changed]).size }
        end
        # G10: surface the guardrail verdict and park a question for the operator.
        if guardrail
          response[:guardrail] = { blocked: true, violations: guardrail[:violations],
                                   highest_tier: guardrail[:highest_tier] }
          begin
            loop_record.campaign&.park_question!(
              question: "Scope guardrail blocked an autonomous change: #{guardrail[:summary]}",
              context: "scope-guardrail"
            )
          rescue StandardError => e
            Rails.logger.warn("[DevLoopTool] scope-guardrail park failed for loop #{loop_record.id}: #{e.message}")
          end
        end
        response
      rescue Ai::RalphTask::InvalidTransitionError, Ai::RalphIteration::InvalidTransitionError,
             ActiveRecord::RecordInvalid => e
        error_result(e.message)
      end

      # G10: evaluate the executor-reported files against the loop's scope guardrail
      # (no worker git diff needed). Returns the violation result hash, or nil when
      # clean. Delegates to the shared ScopeGuardrail.violation_for seam — the same
      # entry point the platform executor and land paths use.
      def scope_guardrail_violation(loop_record, files_changed)
        ::Ai::CodeFactory::ScopeGuardrail.violation_for(files_changed, loop_record: loop_record)
      end

      def prepare_iteration(loop_record, task, params)
        iteration = loop_record.create_iteration(task: task)
        iteration.update!(ralph_task: task) if iteration.ralph_task_id != task.id

        check_results = params[:check_results].is_a?(Hash) ? params[:check_results] : {}
        check_results = check_results.merge("files_changed" => params[:files_changed]) if params[:files_changed].present?

        iteration.start!
        iteration.update!(check_results: check_results, git_branch: params[:git_branch])
        iteration
      end

      # Delegates to the task's state-machine guards so the (status, outcome)
      # pairing is the single source of truth: in_progress → passed/failed/blocked;
      # blocked → passed/failed/skipped (operator resolution).
      def transition_allowed?(task, outcome)
        case outcome
        when "passed" then task.can_pass?
        when "failed" then task.can_fail?
        when "blocked" then task.can_block?
        when "skipped" then task.can_skip?
        else false
        end
      end

      # The two adjudication paths contradict for DIFFERENT reasons, and saying
      # which is the difference between a message that teaches the fix and one
      # that reads like a bug. The old single message claimed "every parsed tally
      # shows failures", true of neither: DECLARED is ALL-green so one failure
      # contradicts even beside a passing suite, and INFERRED can contradict with
      # a 0-failure/0-passed tally present. Offer 019fed52 was filed off that
      # wording — it concluded the adjudicator mishandled red-first, when the
      # contract routes red-first safely and the message just never said how.
      #
      # Names only the FAILING suites: listing a green one as evidence against the
      # pass is what made the old message read as a false positive.
      def contradiction_error(adjudication)
        failing = Array(adjudication[:tallies])
                  .select { |t| t[:failures].to_i.positive? }
                  .map { |t| "#{t[:framework]}: #{t[:failures]}" }.join(", ")

        if adjudication[:source] == :declared
          "passed outcome contradicted by its own DECLARED evidence — declared suites must ALL be green, " \
            "and these reported failures (#{failing}). Declare only the FINAL GREEN runs and put a red-first " \
            "run in a plain key beside evidence (e.g. red_first: \"5 examples, 5 failures before the fix\"), " \
            "never inside it — or report outcome=failed"
        else
          "passed outcome contradicted by its own check_results evidence — no parsed tally shows a clean run, " \
            "and these show failures (#{failing}) — fix and re-report, or report outcome=failed"
        end
      end

      def record_outcome(loop_record, task, iteration, outcome, summary, params,
                         verification: nil, evidence_source: nil)
        # IMP-9d49b9833a67 — CAPTURE BOUNDARY for executor-supplied learning text.
        #
        # This is where raw `params[:learning]` first enters the system, and it
        # fans out to three sinks: the loop's `learnings` jsonb, the durable
        # `ai_ralph_iterations.learning_extracted` column, and the embedded
        # compound-learning store. Only the first was scrubbed (in
        # RalphLoop#add_learning). All three are durable and all three are
        # re-served; what makes 2 and 3 the sharper exposure is SCOPE. Sink 1 is
        # re-served only within its own loop (recent_learnings(limit: 5) ->
        # `context.recent_learnings`), whereas the compound store is
        # account-scoped and its rows are ranked and injected as
        # `context.relevant_learnings` into every later dev_next_task ACROSS
        # loops — so unscrubbed material there is actively redistributed to other
        # loops' executors. Sink 2 is iteration-keyed, durable, and additionally
        # exposed over the iterations API.
        #
        # Scrub ONCE here and hand the clean value to every branch, rather than
        # adding a sanitize_output call to each of the three writes — the
        # per-call-site control is what rots (same reasoning as the audit-log
        # redaction seam, 36951df81). Note this must sit ABOVE the case: the
        # "passed" branch does not go through #capture_learning, so a scrub
        # placed there would leave the passed path's compound-store write raw.
        # .to_s is load-bearing, not defensive noise: sanitize_output returns its
        # input UNTOUCHED for a non-String, and BaseTool skips type validation for
        # `type:`-style param defs, so a caller sending learning: {"text" => "..."}
        # would otherwise land raw in every sink. .presence restores the nil that
        # the downstream `learning.present?` / blank? guards expect.
        learning = ::DataManagement::Sanitizer.sanitize_output(params[:learning].to_s).presence

        case outcome
        when "passed"
          # complete! promotes the learning onto the loop automatically.
          # checks_passed reflects the ADJUDICATED evidence, never a hardcoded
          # true (IMP-f2b3e9a67d11): an unevidenced pass records as attested.
          iteration.complete!(
            output: summary,
            checks_passed: verification == :verified,
            commit_sha: params[:commit_sha],
            learning: learning
          )
          task.pass!(iteration_number: iteration.iteration_number)
          # complete! appends the learning to the loop but doesn't embed it; do the
          # mid-run embed here so the passed path matches the others (G12).
          embed_learning_mid_run(loop_record, learning, task: task, files: params[:files_changed])
          # Closing an offer is the one IRREVERSIBLE, self-crediting act here, so
          # it requires DECLARED evidence (IMP-019fed52): a verdict inferred by
          # sniffing key names may still record checks_passed, but it can no
          # longer close an offer on a guessed number. Everything else about a
          # verified pass is unchanged.
          if verification == :verified && evidence_source != :declared
            Rails.logger.info(
              "[DevLoopTool] #{task.task_key} verified from INFERRED evidence — not auto-applying its offer. " \
              "Declare check_results[:evidence] = {framework:, passed:, failed:} to close it automatically."
            )
          end
          apply_linked_recommendation!(task) if verification == :verified && evidence_source == :declared
        when "failed"
          iteration.fail!(error_message: summary)
          task.fail!(error_message: summary)
          capture_learning(loop_record, task, iteration, learning, files: params[:files_changed])
        when "blocked"
          iteration.fail!(error_message: summary, error_code: "blocked")
          task.block!(reason: summary, blocked_for: "review")
          capture_learning(loop_record, task, iteration, learning, files: params[:files_changed])
        when "skipped"
          iteration.skip!(reason: summary)
          task.skip!(reason: summary)
          capture_learning(loop_record, task, iteration, learning, files: params[:files_changed])
        end
      end

      # IMP-a091565577cc: a passed dev-improve task is the ground-truth closure
      # for the Ai::ImprovementRecommendation it was promoted from (see
      # Ai::DevLoop::ImprovementPromotionService) — without this, approved
      # offers never reach "applied" and the /improve scoreboard's applied
      # funnel stays stuck at 0 no matter how many tasks land. Only acts on an
      # "approved" recommendation so it's a no-op on replay/re-pass and never
      # clobbers a dismissed/pending record.
      def apply_linked_recommendation!(task)
        rec_id = task.metadata.is_a?(Hash) ? task.metadata["recommendation_id"] : nil
        return if rec_id.blank?

        recommendation = account.ai_improvement_recommendations.find_by(id: rec_id)
        return unless recommendation&.status == "approved"

        # Self-amended brief => no automatic credit. The work may well be right,
        # but the reporter moved the goalposts, so an operator decides rather than
        # the offer closing itself.
        if self_amended_brief?(task)
          Rails.logger.warn(
            "[DevLoopTool] NOT auto-applying #{rec_id} for #{task.task_key}: its brief was amended by " \
            "#{claimant_ref}, the same principal reporting the outcome — leaving the offer approved for review"
          )
          return
        end

        # apply!(user) reassigns approved_by — an agent-driven pass has no `user`
        # (BaseTool#user is nil for agent callers), so fall back to whoever
        # already approved it rather than clobbering that attribution with nil.
        recommendation.apply!(user || recommendation.approved_by)
      rescue StandardError => e
        Rails.logger.warn("[DevLoopTool] apply_linked_recommendation! failed for task #{task.task_key}: #{e.message}")
      end

      def capture_learning(loop_record, task, iteration, learning, files: nil)
        return if learning.blank?

        loop_record.add_learning(learning, context: {
          iteration: iteration.iteration_number, task_key: task.task_key, files: files
        })
        iteration.update!(learning_extracted: learning)
        embed_learning_mid_run(loop_record, learning, task: task, files: files)
      end

      # G12: promote a learning to the embedded/compound store as soon as it's
      # captured — not only at loop completion (which a long campaign never reaches
      # mid-run). Inc7: thread the loop/task context (task_key, changed files) so the
      # extractor can derive title/tags/importance. extract_learning is idempotent
      # (near-dup dedup) and rescue-safe.
      def embed_learning_mid_run(loop_record, learning, task: nil, files: nil)
        return if learning.blank?

        context = { task_key: task&.task_key, files: files }.compact
        ::Ai::Learning::RalphLearningExtractor.new(account: account)
                                              .extract_learning(loop_record, learning, context: context)
      rescue StandardError => e
        Rails.logger.warn("[DevLoopTool] mid-run learning embed failed for loop #{loop_record.id}: #{e.message}")
      end

      # --- Delegation: hand a Ralph task to a platform agent (Claude -> agent) ---

      def delegate_ralph_task(params)
        loop_record = find_loop(params[:loop_id])
        return error_result("Ralph loop not found") unless loop_record

        if (reason = halt_reason(loop_record))
          return { success: true, halted: true, reason: reason }
        end

        task = loop_record.ralph_tasks.find_by(task_key: params[:task_key])
        return error_result("Task not found: #{params[:task_key]}") unless task
        unless task.status.in?(%w[pending in_progress])
          return error_result("Task is #{task.status} — only pending/in_progress tasks can be delegated")
        end
        return error_result("agent_id is required (the platform agent to delegate to)") if params[:agent_id].blank?
        if task.status == "pending" && !task.dependencies_satisfied?
          return error_result("Task dependencies are not satisfied yet")
        end

        loop_record.start! if loop_record.can_start?
        task.start! if task.status == "pending"
        task.record_execution_attempt!

        spawn = delegate_tool.execute(params: {
          action: "spawn_task", agent_id: params[:agent_id],
          task: delegation_brief(loop_record, task), budget_cents: params[:budget_cents]
        })
        unless spawn[:success]
          task.merge_metadata!("delegation_error" => spawn[:error])
          return error_result("Delegation failed: #{spawn[:error]}")
        end

        task.merge_metadata!(
          "delegated_to" => spawn[:agent_id], "delegated_agent_name" => spawn[:agent_name],
          "a2a_task_id" => spawn[:task_id], "delegated_at" => Time.current.iso8601,
          "claimed_by" => "agent:#{spawn[:agent_id]}"
        )

        return delegation_submitted(task, spawn) unless params[:await]

        waited = delegate_tool.execute(params: {
          action: "wait_for_task", task_id: spawn[:task_id], timeout_seconds: params[:timeout]
        })
        record_delegated_outcome(loop_record, task, spawn, waited)
      rescue Ai::RalphTask::InvalidTransitionError, ActiveRecord::RecordInvalid => e
        error_result(e.message)
      end

      def delegation_submitted(task, spawn)
        {
          success: true, delegated: true, awaited: false, task_key: task.task_key,
          a2a_task_id: spawn[:task_id], agent: spawn[:agent_name], status: "submitted",
          note: "Track via check_task_status(#{spawn[:task_id]}); task stays in_progress until reported."
        }
      end

      def record_delegated_outcome(loop_record, task, spawn, waited)
        unless waited[:success]
          return { success: true, delegated: true, awaited: true, task_key: task.task_key,
                   a2a_task_id: spawn[:task_id], outcome: "pending", detail: waited[:error] }
        end

        outcome = waited[:status] == "completed" ? "passed" : "failed"
        summary = (waited[:output].presence || waited[:error_message].presence ||
                   "Delegated agent #{waited[:status]}").to_s
        iteration = prepare_iteration(loop_record, task,
                                      { check_results: { "delegated_a2a_task" => spawn[:task_id], "agent" => spawn[:agent_name] } })
        # DELIBERATE (IMP-f2b3e9a67d11): a delegated completion is the
        # sub-agent's own attestation — no test evidence crosses the A2A
        # boundary — so a delegated pass records as attested (checks_passed
        # false) and does NOT auto-apply a linked offer. Pre-adjudication this
        # path hardcoded verified-and-applied, which is exactly the
        # self-attestation hole this fix closes; the offer stays approved for
        # operator judgment or an evidence-bearing re-report.
        record_outcome(loop_record, task, iteration, outcome, summary, {},
                       verification: (outcome == "passed" ? :unverified : nil))

        { success: true, delegated: true, awaited: true, task_key: task.task_key,
          a2a_task_id: spawn[:task_id], outcome: outcome, task_status: task.reload.status, agent: spawn[:agent_name],
          verification: (outcome == "passed" ? "unverified" : nil) }.compact
      end

      # A TOOL-TO-TOOL hop, so it carries this call's instance provenance the
      # same way an executor-nested tool does. DevLoopTool is instance-aware
      # (#claimant_ref scopes claims as "instance:<id>") and delegate_ralph_task
      # is on the MCP surface, so an instance principal reaches here with no
      # User — and AgentManagementTool carries destroy-shaped actions. Without
      # the mark the nested tool cannot tell a grant-gated instance principal
      # from any other userless caller, and BaseTool#enforce_instance_deny_
      # overlay! never engages on the nested action. Safe today only because
      # both call sites pass hardcoded literals ("spawn_task", "wait_for_task");
      # that is a structural bound, not a fence. Guarded, so the user and
      # reconciler paths are unchanged. (IMP-c2e3e5d3cff0)
      def delegate_tool
        @delegate_tool ||= mark_instance_provenance(
          Ai::Tools::AgentManagementTool.new(account: account, user: user, agent: agent)
        )
      end

      def delegation_brief(loop_record, task)
        config = loop_record.configuration || {}
        meta = task.metadata.is_a?(Hash) ? task.metadata : {}
        [
          "You are executing a delegated dev-loop task. Loop: #{loop_record.name} (branch #{loop_record.branch}).",
          "Task #{task.task_key}: #{task.description}",
          "Acceptance criteria: #{task.acceptance_criteria}",
          (meta["files"].present? ? "Files: #{Array(meta['files']).join(', ')}" : nil),
          "Guardrails: #{Ai::DevLoop::LoopGuardrails.refresh(config['guardrails']).join(' | ')}"
        ].compact.join("\n")
      end

      # Halt checks — executors must stop pulling when any of these hold.
      # Delegates to the loop's shared Ai::RalphLoop#halt_reason so the dev-loop
      # pull path and the platform executor evaluate IDENTICAL stop conditions
      # (kill switch, schedule, terminal state, goal-met, iteration cap, and the
      # runtime resource caps — wall-clock for any loop, token/$ for metered).
      def halt_reason(loop_record)
        loop_record.halt_reason
      end

      def own_in_progress_task(loop_record, holder)
        loop_record.ralph_tasks.in_progress.detect { |t| claimed_by_holder?(t, holder) }
      end

      # In-progress tasks NOT claimed by this (user, holder) — the pool a new
      # claim's files must not collide with.
      def other_in_progress_tasks(loop_record, holder)
        loop_record.ralph_tasks.in_progress.reject { |t| claimed_by_holder?(t, holder) }
      end

      def task_payload(loop_record, task, reclaimed: false)
        config = loop_record.configuration || {}
        {
          success: true,
          reclaimed: reclaimed,
          task: task.task_details,
          loop: {
            id: loop_record.id,
            name: loop_record.name,
            status: loop_record.status,
            branch: loop_record.branch,
            # G9: vendor-neutral executor identity for per-vendor attribution/telemetry
            # (the flat-rate CLI draining this loop — claude_code/external_cli + its vendor).
            driver_kind: loop_record.driver_kind,
            executor_vendor: loop_record.executor_vendor,
            repository_url: loop_record.repository_url,
            loop_spec_path: config["loop_spec_path"],
            guardrails: Ai::DevLoop::LoopGuardrails.refresh(config["guardrails"]),
            current_iteration: loop_record.current_iteration,
            max_iterations: loop_record.max_iterations,
            queue: queue_snapshot(loop_record)
          },
          # G12: re-inject prior context every iteration so the loop learns from
          # itself and doesn't drift — recent lessons, open campaign decisions, and
          # the base structural files the executor should re-read.
          context: iteration_context(loop_record, config, task)
        }
      end

      # The feedback the framework's "lessons_learned" state file is meant to
      # provide, surfaced into each dev_next_task payload (the campaign/dev-loop path
      # otherwise never re-reads its own learnings or decisions).
      def iteration_context(loop_record, config, task)
        ctx = { recent_learnings: loop_record.recent_learnings(limit: 5) }

        if (campaign = loop_record.campaign)
          ctx[:open_decisions] = campaign.campaign_decisions.recent(5).map(&:summary)
        end

        # C3: unlike recent_learnings (this loop's own raw captures), this pulls the
        # top-k MOST RELEVANT compound learnings across the corpus for this specific
        # task — closing the gap where the primary (Claude Code) executor learns via
        # dev_complete_task but was never handed anything back on the next claim.
        relevant = relevant_compound_learnings(task)
        ctx[:relevant_learnings] = relevant if relevant.present?
        # Credit-loop half A (IMP-5f8a744b8892): remember exactly which
        # learnings this claim injected so complete_task can resolve the
        # neutral injections positively on a passed outcome. Without this the
        # injections stay unresolved forever and the corpus degrades in
        # proportion to use (hard 0.0 effectiveness at 3 injections, promotion
        # barred, recall ranking inverted). Written UNCONDITIONALLY (even as
        # []) so a reclaim whose retrieval returns nothing can never inherit —
        # and later credit — a previous claim's ids.
        task.merge_metadata!("injected_learning_ids" => relevant.map { |l| l[:id] })

        base = config["base_context_files"]
        if base.present?
          ctx[:base_context_files] = base
          # G12: inject the CONTENTS of the curated base files (CLAUDE.md / conventions),
          # not just the paths — a non-Claude platform executor can't read the repo
          # itself, so path-only injection doesn't mitigate goal drift for it.
          contents = base_context_contents(Array(base))
          ctx[:base_context_contents] = contents if contents.present?
        end
        ctx
      end

      # Credit-loop half B (see complete_task): resolve this claim's injections
      # positively via the learning service, then clear the marker so an
      # operator resolution or replayed report cannot double-credit. Best-effort
      # — a crediting hiccup must never fail the completion itself.
      def credit_injected_learnings!(task)
        ids = Array(task.metadata["injected_learning_ids"])
        return if ids.empty?

        ::Ai::Learning::CompoundLearningService.new(account: account)
          .credit_injections!(learning_ids: ids)
        # Key REMOVAL, so jsonb `-` rather than the `||` merge — same reason:
        # rewriting the whole column would drop concurrent writers' keys.
        Ai::RalphTask.where(id: task.id)
                     .update_all([ "metadata = COALESCE(metadata, '{}'::jsonb) - ?, updated_at = ?",
                                   "injected_learning_ids", Time.current ])
        task.reload
      rescue StandardError => e
        Rails.logger.warn("[DevLoopTool] credit_injected_learnings failed for #{task.task_key}: #{e.message}")
      end

      # C3: reuses Ai::Learning::CompoundLearningService's existing retrieval/
      # ranking (the same embedding search + effective_importance rank that
      # build_compound_context already uses for platform-agent executions) so
      # this consumer never drifts from that one. Feature-flagged behind the
      # same :compound_learning_injection flag; excludes retired learnings via
      # the surfacing set both retrieval paths already restrict to
      # (active/verified); bumps injection_count/last_injected on each
      # surfaced learning. Query text is the task's own description +
      # acceptance criteria — no separate tags/category field exists on
      # Ai::RalphTask to key off instead.
      def relevant_compound_learnings(task)
        return [] unless task

        task_description = [task.description, task.acceptance_criteria].compact_blank.join("\n")
        return [] if task_description.blank?

        ::Ai::Learning::CompoundLearningService.new(account: account)
          .top_relevant_learnings(task_description: task_description, k: RELEVANT_LEARNINGS_LIMIT)
      rescue StandardError => e
        Rails.logger.warn("[DevLoopTool] relevant_compound_learnings failed for task #{task&.task_key}: #{e.message}")
        []
      end

      # Read each curated base structural file and return size-bounded contents so any
      # executor re-reads the base rules every iteration. Size-bounded (per-file + total
      # byte caps, rides every payload), outage-safe core (CLAUDE.md) prioritized under the
      # total budget, best-effort (a missing/unreadable/non-file/out-of-repo path is
      # skipped, never raises). The curated path list is NOT broadened here.
      def base_context_contents(paths)
        remaining = BASE_CONTEXT_TOTAL_LIMIT
        # CLAUDE.md (the outage-safe core) first so it survives the total budget; stable
        # otherwise (preserve the configured order via the original index).
        ordered = paths.each_with_index
                       .sort_by { |path, i| [File.basename(path.to_s) == "CLAUDE.md" ? 0 : 1, i] }
                       .map(&:first)
        ordered.each_with_object([]) do |path, entries|
          next if remaining <= 0

          entry = read_base_context_file(path, [BASE_CONTEXT_PER_FILE_LIMIT, remaining].min)
          next unless entry

          entries << entry
          remaining -= entry[:bytes]
        end
      end

      # Best-effort read of one base file's head, capped at `cap` bytes. Returns nil for a
      # missing/unreadable/non-file/out-of-repo path (skipped, never raised). Reads only
      # cap+1 bytes so a large file isn't loaded whole just to detect truncation.
      def read_base_context_file(path, cap)
        resolved = resolve_base_context_path(path)
        return nil unless resolved && File.file?(resolved)

        raw = File.binread(resolved, cap + 1)
        return nil if raw.nil?

        truncated = raw.bytesize > cap
        raw = raw.byteslice(0, cap) if truncated
        contents = raw.force_encoding("UTF-8").scrub
        { path: path.to_s, bytes: contents.bytesize, truncated: truncated, contents: contents }
      rescue SystemCallError, IOError
        nil
      end

      # Resolve a curated repo-relative base path against the repo root (CLAUDE.md /
      # docs live above server/). Confined to the repo — a path that escapes the root
      # (traversal / absolute) is rejected so only the curated tree is ever read.
      def resolve_base_context_path(path)
        return nil if path.blank?

        root = Rails.root.parent.to_s
        resolved = File.expand_path(path.to_s, root)
        return nil unless resolved == root || resolved.start_with?("#{root}/")

        resolved
      end

      def queue_snapshot(loop_record)
        tasks = loop_record.ralph_tasks
        in_progress_tasks = tasks.in_progress.to_a
        snapshot = {
          pending: tasks.pending.count,
          in_progress: in_progress_tasks.size,
          passed: tasks.passed.count,
          failed: tasks.failed.count,
          blocked: tasks.blocked.count,
          # Read-only signal: claims sitting past Ai::RalphTask::STALE_CLAIM_THRESHOLD
          # with no reported outcome — surfaced, never auto-released.
          stale_tasks: in_progress_tasks.count(&:stale?),
          progress_percentage: loop_record.progress_percentage
        }
        # Report-only here (operators/executors read it); the goal-driven
        # terminator that acts on `met` lives in dev_next_task (G5).
        if (completion = loop_record.completion_status)
          snapshot[:completion] = completion
        end
        snapshot
      end

      def find_loop(id_or_name)
        return nil if id_or_name.blank?

        account.ai_ralph_loops.find_by(id: id_or_name) ||
          account.ai_ralph_loops.where("name ILIKE ?", id_or_name).first
      end

      def claimant_ref
        if user
          "user:#{user.id}"
        elsif agent
          "agent:#{agent.id}"
        elsif node_instance
          # Instance principal (mTLS node cert; no User/Agent) — e.g. a managed
          # dev-cell driving the dev-loop over MCP. Opaque claim-scope string that
          # flows through claim → reclaim → complete like user:/agent:. (BUG-S)
          "instance:#{node_instance.id}"
        end
      end
    end
  end
end
