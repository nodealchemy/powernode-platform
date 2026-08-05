# frozen_string_literal: true

module Ai
  module Tools
    # MCP tool for managing Ralph Loops — autonomous agent duty cycles.
    # Provides list, get, pause/resume schedule, and delete operations.
    class RalphLoopTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.update"

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
            description: "Update mutable Ralph Loop config: name, default_agent_id, cycle_interval_minutes, max_iterations_per_day, max_iterations, schedule_paused. " \
                         "Useful for repointing default_agent_id when consolidating duplicate agents, adjusting cadence without delete+recreate, or raising a loop's " \
                         "lifetime iteration cap before it halts on max_iterations_reached.",
            parameters: {
              loop_id: { type: "string", required: true, description: "Ralph loop ID or name" },
              name: { type: "string", required: false, description: "New loop name" },
              default_agent_id: { type: "string", required: false, description: "Repoint to a different agent (UUID, slug, or name)" },
              cycle_interval_minutes: { type: "integer", required: false, description: "Time between iterations in minutes" },
              max_iterations_per_day: { type: "integer", required: false, description: "Daily iteration cap" },
              max_iterations: { type: "integer", required: false, description: "Lifetime iteration cap (distinct from the daily max_iterations_per_day throttle)" },
              schedule_paused: { type: "boolean", required: false, description: "Pause/resume scheduling without a state machine event" }
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
        return { success: false, error: "User context required" } unless user

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
          loops: loops.map { |l|
            { name: l.name, status: l.status, paused: l.schedule_paused,
              iterations_today: l.daily_iteration_count, agent: l.default_agent&.name }
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
          daily_iteration_count: loop_record.daily_iteration_count,
          next_scheduled_at: loop_record.next_scheduled_at,
          created_at: loop_record.created_at
        }
      end

      def account
        user.account
      end
    end
  end
end
