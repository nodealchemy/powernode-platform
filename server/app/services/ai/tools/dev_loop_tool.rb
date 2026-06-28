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
            holder: { type: "string", required: false, description: "Driver identity (lease holder) for campaign-loop pulls" }
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
              check_results: { type: "object", required: false, description: "Verification evidence (specs run, results)" },
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
          return { success: true, halted: true, reason: reason, task: nil }
        end
        if (reason = delegation_block_reason(loop_record, params[:holder]))
          return { success: true, halted: true, reason: reason, task: nil }
        end

        result = nil
        loop_record.with_lock do
          result = claim_under_lock(loop_record)
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
        return nil if loop_record.driver_kind.blank? # legacy / not routed → ungated
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

      def claim_under_lock(loop_record)
        if (mine = own_in_progress_task(loop_record))
          return task_payload(loop_record, mine, reclaimed: true)
        end

        task = claimable_task(loop_record)
        unless task
          return { success: true, task: nil, queue_empty: true,
                   queue: queue_snapshot(loop_record) }
        end

        loop_record.start! if loop_record.can_start?
        task.start!
        task.record_execution_attempt!
        task.update!(metadata: (task.metadata || {}).merge(
          "claimed_by" => claimant_ref,
          "claimed_at" => Time.current.iso8601
        ))

        task_payload(loop_record, task)
      end

      def complete_task(params)
        loop_record = find_loop(params[:loop_id])
        return error_result("Ralph loop not found") unless loop_record

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
          record_outcome(loop_record, task, iteration, outcome, summary, params)
        end
        return error_result(pairing_error) if pairing_error

        response = {
          success: true,
          task_key: task.task_key,
          task_status: task.reload.status,
          iteration_number: iteration.iteration_number,
          queue: queue_snapshot(loop_record.reload),
          all_tasks_completed: loop_record.all_tasks_completed?
        }
        # Governance annotation (report-only — no approval lane until an
        # executor consumes it; see audit finding F3-01 for why).
        if Array(params[:files_changed]).size > 5
          response[:governance] = { category: "dev.multi_file_change",
                                    files_changed: Array(params[:files_changed]).size }
        end
        response
      rescue Ai::RalphTask::InvalidTransitionError, Ai::RalphIteration::InvalidTransitionError,
             ActiveRecord::RecordInvalid => e
        error_result(e.message)
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

      def record_outcome(loop_record, task, iteration, outcome, summary, params)
        case outcome
        when "passed"
          # complete! promotes the learning onto the loop automatically
          iteration.complete!(
            output: summary,
            checks_passed: true,
            commit_sha: params[:commit_sha],
            learning: params[:learning]
          )
          task.pass!(iteration_number: iteration.iteration_number)
        when "failed"
          iteration.fail!(error_message: summary)
          task.fail!(error_message: summary)
          capture_learning(loop_record, task, iteration, params[:learning])
        when "blocked"
          iteration.fail!(error_message: summary, error_code: "blocked")
          task.block!(reason: summary)
          capture_learning(loop_record, task, iteration, params[:learning])
        when "skipped"
          iteration.skip!(reason: summary)
          task.skip!(reason: summary)
          capture_learning(loop_record, task, iteration, params[:learning])
        end
      end

      def capture_learning(loop_record, task, iteration, learning)
        return if learning.blank?

        loop_record.add_learning(learning, context: {
          iteration: iteration.iteration_number, task_key: task.task_key
        })
        iteration.update!(learning_extracted: learning)
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
          task.update!(metadata: (task.metadata || {}).merge("delegation_error" => spawn[:error]))
          return error_result("Delegation failed: #{spawn[:error]}")
        end

        task.update!(metadata: (task.metadata || {}).merge(
          "delegated_to" => spawn[:agent_id], "delegated_agent_name" => spawn[:agent_name],
          "a2a_task_id" => spawn[:task_id], "delegated_at" => Time.current.iso8601,
          "claimed_by" => "agent:#{spawn[:agent_id]}"
        ))

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
        record_outcome(loop_record, task, iteration, outcome, summary, {})

        { success: true, delegated: true, awaited: true, task_key: task.task_key,
          a2a_task_id: spawn[:task_id], outcome: outcome, task_status: task.reload.status, agent: spawn[:agent_name] }
      end

      def delegate_tool
        @delegate_tool ||= Ai::Tools::AgentManagementTool.new(account: account, user: user, agent: agent)
      end

      def delegation_brief(loop_record, task)
        config = loop_record.configuration || {}
        meta = task.metadata.is_a?(Hash) ? task.metadata : {}
        [
          "You are executing a delegated dev-loop task. Loop: #{loop_record.name} (branch #{loop_record.branch}).",
          "Task #{task.task_key}: #{task.description}",
          "Acceptance criteria: #{task.acceptance_criteria}",
          (meta["files"].present? ? "Files: #{Array(meta['files']).join(', ')}" : nil),
          (config["guardrails"].present? ? "Guardrails: #{Array(config['guardrails']).join(' | ')}" : nil)
        ].compact.join("\n")
      end

      # Halt checks — executors must stop pulling when any of these hold.
      def halt_reason(loop_record)
        return "emergency_halt" if account.respond_to?(:ai_suspended?) && account.ai_suspended?
        return "schedule_paused" if loop_record.schedule_paused?
        return "loop_#{loop_record.status}" if loop_record.status.in?(%w[paused completed cancelled failed])
        return "max_iterations_reached" if loop_record.max_iterations_reached?

        nil
      end

      def own_in_progress_task(loop_record)
        loop_record.ralph_tasks.in_progress.detect do |t|
          t.metadata&.dig("claimed_by") == claimant_ref
        end
      end

      # Mirrors RalphLoop#next_task ordering but excludes human-decision tasks —
      # those surface for operators, never for loop executors.
      def claimable_task(loop_record)
        loop_record.ralph_tasks.pending
                   .where.not(execution_type: "human")
                   .order(priority: :desc, position: :asc)
                   .detect(&:dependencies_satisfied?)
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
            repository_url: loop_record.repository_url,
            loop_spec_path: config["loop_spec_path"],
            guardrails: config["guardrails"],
            current_iteration: loop_record.current_iteration,
            max_iterations: loop_record.max_iterations,
            queue: queue_snapshot(loop_record)
          }
        }
      end

      def queue_snapshot(loop_record)
        tasks = loop_record.ralph_tasks
        snapshot = {
          pending: tasks.pending.count,
          in_progress: tasks.in_progress.count,
          passed: tasks.passed.count,
          failed: tasks.failed.count,
          blocked: tasks.blocked.count,
          progress_percentage: loop_record.progress_percentage
        }
        if (criteria = (loop_record.configuration || {})["completion"]).is_a?(Hash)
          snapshot[:completion] = completion_assessment(loop_record, criteria)
        end
        snapshot
      end

      # Evaluates configuration.completion criteria over executor-facing tasks
      # (human-decision tasks are excluded — the loop can't resolve them).
      # Report-only: operators complete the loop; executors use this to know
      # when a run is effectively done.
      def completion_assessment(loop_record, criteria)
        executable = loop_record.ralph_tasks.where.not(execution_type: "human")
        total = executable.count
        non_terminal = executable.where.not(status: Ai::RalphTask::TERMINAL_STATUSES).count
        failed_pct = total.zero? ? 0.0 : (executable.failed.count.to_f / total * 100).round(1)

        met = total.positive?
        met &&= non_terminal.zero? if criteria["all_tasks_terminal"]
        met &&= failed_pct <= criteria["max_failed_pct"].to_f if criteria["max_failed_pct"]

        { criteria: criteria, met: met, non_terminal: non_terminal, failed_pct: failed_pct }
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
        end
      end
    end
  end
end
