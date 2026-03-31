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
          "delete_ralph_loop" => {
            description: "Delete a Ralph Loop permanently. Cannot be undone.",
            parameters: {
              loop_id: { type: "string", required: true, description: "Ralph loop ID or name" }
            }
          },
          "get_ralph_loop_statistics" => {
            description: "Get aggregate statistics across all Ralph Loops — iteration counts, success rates, timing",
            parameters: {}
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
        when "delete_ralph_loop" then delete_loop(params)
        when "get_ralph_loop_statistics" then get_statistics
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
        detail[:recent_iterations] = loop_record.iterations
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

      def delete_loop(params)
        loop_record = find_loop(params[:loop_id])
        return { success: false, error: "Ralph loop not found" } unless loop_record

        name = loop_record.name
        loop_record.destroy!
        { success: true, deleted: name }
      end

      def get_statistics
        loops = account.ai_ralph_loops
        {
          success: true,
          total_loops: loops.count,
          active: loops.where(status: "running").count,
          paused: loops.where(schedule_paused: true).count,
          total_iterations_today: loops.sum(:daily_iteration_count),
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
