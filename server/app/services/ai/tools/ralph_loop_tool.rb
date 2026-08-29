# frozen_string_literal: true

module Ai
  module Tools
    # MCP tool for managing Ralph Loops — autonomous agent duty cycles.
    # Provides list, get, pause/resume schedule, and delete operations.
    class RalphLoopTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.update"

      # === Per-action permission gating (G4 tail) ===
      #
      # REST twin: RalphLoopsController maps destroy -> ai.loops.delete,
      # update -> ai.loops.update and start/pause/resume/cancel/reset ->
      # ai.loops.execute. The floor here is ai.agents.update — a DIFFERENT
      # NAMESPACE — so before this map an agent permission deleted loops
      # (measured: Ai::RalphLoop 1 -> 0).
      #
      # READ actions are deliberately LEFT ON THE FLOOR rather than mapped down
      # to their REST read permission. That leaves them stricter than REST,
      # which is safe; mapping them would LOOSEN a live surface, and this change
      # is scoped to closing an escalation, not to widening access.
      #
      # Keyed on the action that RUNS, never the invoked NAME — a user principal
      # is not pinned to the name (McpPlatformToolRegistrar#action_pinned_to_name?),
      # so a name-keyed check is bypassable via a sibling :action.
      ACTION_PERMISSIONS = {
        "delete_ralph_loop" => "ai.loops.delete",
        "update_ralph_loop" => "ai.loops.update",
        "pause_ralph_loop" => "ai.loops.execute",
        "resume_ralph_loop" => "ai.loops.execute",
        "reopen_ralph_loop" => "ai.loops.execute"
      }.freeze

      # Upper bound on how many tasks one driver may hold at once. Not a
      # correctness limit — DevLoopTool's file-collision guard is what keeps
      # parallel claims from editing the same file — but a blast-radius one:
      # every concurrent claim is an agent making commits against one branch,
      # and they contend on a single shared test database. The worktree tooling
      # caps its own fan-out at 4 for the same reason.
      MAX_CONCURRENT_CLAIMS_CEILING = 4


      def self.definition
        {
          name: "ralph_loop",
          description: "Manage Ralph Loops (autonomous agent duty cycles)",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            loop_id: { type: "string", required: false, description: "Ralph loop ID or name" },
            reason: { type: "string", required: false, description: "Reason for pause/cancel" }
          }
        }
      end

      def self.action_definitions
        {
          "list_ralph_loops" => {
            description: "List all Ralph Loops with status, agent assignment, schedule config, and pause state",
            parameters: {}
          },
          "get_ralph_loop" => {
            description: "Get detailed Ralph Loop info including iterations, schedule config, and agent assignment",
            parameters: {
              loop_id: { type: "string", required: true, description: "Ralph loop ID or name" }
            }
          },
          "pause_ralph_loop" => {
            description: "Pause a Ralph Loop's autonomous scheduling. Running iterations complete but no new ones start.",
            parameters: {
              loop_id: { type: "string", required: true, description: "Ralph loop ID or name" },
              reason: { type: "string", required: false, description: "Reason for pausing" }
            }
          },
          "resume_ralph_loop" => {
            description: "Resume a paused Ralph Loop's autonomous scheduling",
            parameters: {
              loop_id: { type: "string", required: true, description: "Ralph loop ID or name" }
            }
          },
          "update_ralph_loop" => {
            description: "Update mutable Ralph Loop config: name, default_agent_id, cycle_interval_minutes, max_iterations_per_day, max_iterations, schedule_paused, " \
                         "max_concurrent_claims. Useful for repointing default_agent_id when consolidating duplicate agents, adjusting cadence without delete+recreate, " \
                         "raising a loop's lifetime iteration cap before it halts on max_iterations_reached, or letting one driver hold several claims at once.",
            parameters: {
              loop_id: { type: "string", required: true, description: "Ralph loop ID or name" },
              name: { type: "string", required: false, description: "New loop name" },
              default_agent_id: { type: "string", required: false, description: "Repoint to a different agent (UUID, slug, or name)" },
              cycle_interval_minutes: { type: "integer", required: false, description: "Time between iterations in minutes" },
              max_iterations_per_day: { type: "integer", required: false, description: "Daily iteration cap" },
              max_iterations: { type: "integer", required: false, description: "Lifetime iteration cap (distinct from the daily max_iterations_per_day throttle)" },
              schedule_paused: { type: "boolean", required: false, description: "Pause/resume scheduling without a state machine event" },
              max_concurrent_claims: { type: "integer", required: false,
                                       description: "How many tasks ONE driver may hold in_progress at once (default 1). " \
                                                    "Above 1, dev_next_task additionally refuses a task whose metadata.files collide with " \
                                                    "another in-flight claim, so parallel holders never edit the same file. Set 1 to restore " \
                                                    "strict single-claim behaviour." }
            }
          },
          "delete_ralph_loop" => {
            description: "Delete a Ralph Loop permanently. Cannot be undone.",
            parameters: {
              loop_id: { type: "string", required: true, description: "Ralph loop ID or name" }
            }
          },
          "get_ralph_loop_statistics" => {
            description: "Get aggregate statistics across all Ralph Loops — iteration counts, success rates, timing, " \
                         "improvement scoreboard, and the convergence metric (recurrence rate of already-learned bug classes per discovery window)",
            parameters: {}
          },
          "reopen_ralph_loop" => {
            description: "Non-destructively reopen a terminal (completed/failed/cancelled) Ralph Loop back to " \
                         "running — preserves ralph_iterations and every task's status (contrast with the " \
                         "destructive reset!, which wipes iteration history and requeues non-skipped tasks). Use " \
                         "when more work needs to be queued onto a loop that already finished draining.",
            parameters: {
              loop_id: { type: "string", required: true, description: "Ralph loop ID or name" }
            }
          }
        }
      end

      protected

      def call(params)
        action = params[:action].to_s

        unless action_permitted?(action)
          Rails.logger.warn(
            "[RalphLoopTool] Refused action for insufficient permission: " \
            "action=#{action} requires=#{required_perm_for(action)} user=#{user&.id}"
          )
          return error_result("permission denied: #{required_perm_for(action)} required")
        end

        # Gate on the ACCOUNT, not the user (IMP-2d49d530fc6d). The account is what
        # every one of these 8 actions actually scopes on, and McpPlatformToolRegistrar
        # injects it for every principal kind; none of the action bodies read `user`.
        # Gating on `user` made all 8 unreachable for a principal that carries no User.
        #
        # The arm this unblocks is RESTRICTED principals, not instance ones alone:
        # StreamableHttpController sets instance_authorized from
        # `current_mcp_principal&.restricted?`, and Mcp::Principal#restricted? is
        # `instance? || federation?`. Reaching here still requires that principal's
        # specific tool name to have cleared #may_invoke? (grant globs plus the
        # destroy-shaped deny list) and the registrar to have pinned the action to
        # that name. Mirrors the sibling DevLoopTool#call, which never broke because
        # it already gated on the account.
        return { success: false, error: "Account context required" } unless account

        case params[:action]
        when "list_ralph_loops" then list_loops
        when "get_ralph_loop" then get_loop(params)
        when "pause_ralph_loop" then pause_loop(params)
        when "resume_ralph_loop" then resume_loop(params)
        when "update_ralph_loop" then update_loop(params)
        when "delete_ralph_loop" then delete_loop(params)
        when "get_ralph_loop_statistics" then get_statistics
        when "reopen_ralph_loop" then reopen_loop(params)
        else
          { success: false, error: "Unknown action: #{params[:action]}" }
        end
      end

      private

      def list_loops
        loops = account.ai_ralph_loops.includes(:default_agent).order(created_at: :desc)

        {
          success: true,
          count: loops.size,
          loops: loops.map { |l| serialize_loop(l) }
        }
      end

      def get_loop(params)
        loop_record = find_loop(params[:loop_id])
        return { success: false, error: "Ralph loop not found" } unless loop_record

        detail = serialize_loop(loop_record)
        detail[:recent_iterations] = loop_record.ralph_iterations
          .order(created_at: :desc)
          .limit(5)
          .map { |i| { id: i.id, status: i.status, started_at: i.started_at, completed_at: i.completed_at } }

        { success: true, loop: detail }
      end

      def pause_loop(params)
        loop_record = find_loop(params[:loop_id])
        return { success: false, error: "Ralph loop not found" } unless loop_record
        return { success: false, error: "Schedule already paused" } if loop_record.schedule_paused?

        loop_record.pause_schedule!(reason: params[:reason] || "Paused via MCP")
        { success: true, loop_id: loop_record.id, name: loop_record.name, schedule_paused: true }
      end

      def resume_loop(params)
        loop_record = find_loop(params[:loop_id])
        return { success: false, error: "Ralph loop not found" } unless loop_record
        return { success: false, error: "Schedule not paused" } unless loop_record.schedule_paused?

        loop_record.resume_schedule!
        { success: true, loop_id: loop_record.id, name: loop_record.name, schedule_paused: false,
          next_scheduled_at: loop_record.next_scheduled_at }
      end

      def update_loop(params)
        loop_record = find_loop(params[:loop_id])
        return { success: false, error: "Ralph loop not found" } unless loop_record

        attrs = {}
        attrs[:name] = params[:name] if params[:name].present?
        attrs[:max_iterations] = params[:max_iterations].to_i if params[:max_iterations].present?

        if params[:default_agent_id].present?
          agent = ::Ai::Agent.for_account(account.id).find_by(id: params[:default_agent_id]) ||
                  account.ai_agents.find_by(slug: params[:default_agent_id]) ||
                  account.ai_agents.find_by(name: params[:default_agent_id])
          return { success: false, error: "default_agent_id agent not found" } unless agent
          attrs[:default_agent_id] = agent.id
        end

        unless params[:schedule_paused].nil?
          attrs[:schedule_paused] = ActiveModel::Type::Boolean.new.cast(params[:schedule_paused])
        end

        # Targeted merge, not a whole-column rewrite: `configuration` is a shared
        # jsonb document and this tool owns exactly one key in it. Rewriting the
        # column from an in-memory read would drop whatever another writer put
        # there between the read and the save.
        if params[:max_concurrent_claims].present?
          cap = params[:max_concurrent_claims].to_i
          if cap < 1 || cap > MAX_CONCURRENT_CLAIMS_CEILING
            return { success: false,
                     error: "max_concurrent_claims must be between 1 and #{MAX_CONCURRENT_CLAIMS_CEILING}" }
          end
          attrs[:configuration] = (loop_record.configuration || {}).merge("max_concurrent_claims" => cap)
        end

        if params[:cycle_interval_minutes].present? || params[:max_iterations_per_day].present?
          sc = (loop_record.schedule_config || {}).dup
          sc["cycle_interval_minutes"] = params[:cycle_interval_minutes].to_i if params[:cycle_interval_minutes].present?
          sc["max_iterations_per_day"] = params[:max_iterations_per_day].to_i if params[:max_iterations_per_day].present?
          attrs[:schedule_config] = sc
        end

        loop_record.update!(attrs)
        { success: true, loop: serialize_loop(loop_record.reload) }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end

      def delete_loop(params)
        loop_record = find_loop(params[:loop_id])
        return { success: false, error: "Ralph loop not found" } unless loop_record

        name = loop_record.name
        loop_record.destroy!
        { success: true, deleted: name }
      end

      def reopen_loop(params)
        loop_record = find_loop(params[:loop_id])
        return { success: false, error: "Ralph loop not found" } unless loop_record
        unless loop_record.can_reopen?
          return { success: false, error: "Loop is #{loop_record.status}, not terminal — nothing to reopen" }
        end

        loop_record.reopen!
        { success: true, loop_id: loop_record.id, name: loop_record.name, status: loop_record.status }
      end

      def get_statistics
        loops = account.ai_ralph_loops.includes(:default_agent)
        # IMP-4bc71cfb2d2c: loop growth was invisible on every summary surface —
        # the `learnings` array reached 548 kB and NOTHING reported it. Weigh the
        # whole account in ONE aggregate query (never a query per loop, and never
        # a row walk: that is the O(n) read this increment exists to report on).
        records = ::Ai::RalphLoop.preload_storage_metrics(loops.to_a)
        over_budget = records.select(&:storage_limit_exceeded?)
        {
          success: true,
          total_loops: loops.count,
          active: loops.where(status: "running").count,
          paused: loops.where(schedule_paused: true).count,
          total_iterations_today: loops.sum(:daily_iteration_count),
          # Tier-2(c): ungameable improvement metric (revert-adjusted velocity + per-kind revert_rate)
          improvement: Ai::RalphTask.improvement_scoreboard(account: account),
          # Convergence: recurrence rate of already-learned bug classes per discovery window
          convergence: Ai::Autonomy::LoopConvergenceService.compute(account: account),
          # ai_output and ai_prompt stay SEPARATE: ai_prompt is 0 bytes in
          # production only because the MCP dev_loop bridge never writes it, while
          # the in-platform ExecutionService does. Summing them hides that and
          # invites a wrong "unused, drop it" read of a live column.
          storage: {
            iterations: records.sum { |l| l.storage_metrics[:iteration_count] },
            learning_iterations: records.sum { |l| l.storage_metrics[:learning_iteration_count] },
            ai_output_bytes: records.sum { |l| l.storage_metrics[:ai_output_bytes] },
            ai_prompt_bytes: records.sum { |l| l.storage_metrics[:ai_prompt_bytes] },
            learnings_column_bytes: records.sum { |l| l.storage_metrics[:learnings_column_bytes] },
            total_bytes: records.sum(&:storage_total_bytes),
            # The threshold half. A size with no verdict is the same non-signal
            # as no size at all — that silence is the original defect.
            loops_over_limit: over_budget.size,
            over_limit: over_budget.map { |l|
              { name: l.name, total_bytes: l.storage_total_bytes,
                limit_bytes: l.storage_limit_bytes, usage_pct: l.storage_usage_pct }
            }
          },
          loops: records.map { |l|
            { name: l.name, status: l.status, paused: l.schedule_paused,
              iterations_today: l.daily_iteration_count, agent: l.default_agent&.name,
              storage_bytes: l.storage_total_bytes,
              storage_limit_exceeded: l.storage_limit_exceeded? }
          }
        }
      end

      def find_loop(id_or_name)
        return nil if id_or_name.blank?

        account.ai_ralph_loops.find_by(id: id_or_name) ||
          account.ai_ralph_loops.where("name ILIKE ?", id_or_name).first
      end

      def serialize_loop(loop_record)
        {
          id: loop_record.id,
          name: loop_record.name,
          status: loop_record.status,
          schedule_paused: loop_record.schedule_paused,
          agent_id: loop_record.default_agent_id,
          agent_name: loop_record.default_agent&.name,
          cycle_interval_minutes: loop_record.schedule_config&.dig("cycle_interval_minutes") ||
                                  loop_record.duty_cycle_config&.dig("frequency_minutes") || 15,
          max_iterations_per_day: loop_record.schedule_config&.dig("max_iterations_per_day"),
          current_iteration: loop_record.current_iteration,
          max_iterations: loop_record.max_iterations,
          max_concurrent_claims: loop_record.configuration&.dig("max_concurrent_claims") || 1,
          daily_iteration_count: loop_record.daily_iteration_count,
          next_scheduled_at: loop_record.next_scheduled_at,
          created_at: loop_record.created_at
        }
      end

      def required_perm_for(action)
        ACTION_PERMISSIONS[action] || REQUIRED_PERMISSION
      end

      # Two explicit bypasses, matching the sibling tools' ladder: in-process
      # callers that opted in with `internal: true`, and an mTLS node principal
      # whose specific tool name already cleared Mcp::Principal#may_invoke?.
      # Never inferred from a nil user.
      def action_permitted?(action)
        return true if internal?
        return true if instance_authorized?
        return false unless user.respond_to?(:has_permission?)

        user.has_permission?(required_perm_for(action)) == true
      end

    end
  end
end
