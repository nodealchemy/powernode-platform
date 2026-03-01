# frozen_string_literal: true

module Ai
  class TrajectoryService
    attr_reader :account

    def initialize(account:)
      @account = account
    end

    # Build a trajectory from a completed team execution
    def build_from_team_execution(team_execution)
      trajectory = Ai::Trajectory.create!(
        account: account,
        team_execution_id: team_execution.id,
        workflow_run_id: team_execution.workflow_run_id,
        title: "Execution: #{team_execution.objective || 'Team Task'}",
        status: "building",
        trajectory_type: "task_completion",
        tags: extract_tags(team_execution),
        metadata: {
          "team_id" => team_execution.agent_team_id,
          "execution_id" => team_execution.id,
          "triggered_by" => team_execution.triggered_by_id
        }
      )

      build_chapters(trajectory, team_execution)
      finalize_trajectory(trajectory, team_execution)

      trajectory
    rescue StandardError => e
      Rails.logger.error "[TrajectoryService] Failed to build trajectory: #{e.message}"
      nil
    end

    # Search for relevant past trajectories
    def search_relevant(query:, agent_id: nil, tags: nil, limit: 5)
      trajectories = account.ai_trajectories.completed.recent

      if agent_id.present?
        trajectories = trajectories.for_agent(agent_id)
      end

      if tags.present?
        trajectories = trajectories.with_tags(tags)
      end

      if query.present?
        trajectories = trajectories.where(
          "title ILIKE :q OR summary ILIKE :q", q: "%#{sanitize_sql_like(query)}%"
        )
      end

      trajectories.limit(limit)
    end

    # Format trajectories for prompt injection
    def inject_context(agent_id:, task_description:, max_trajectories: 3)
      trajectories = search_relevant(
        query: task_description,
        agent_id: agent_id,
        limit: max_trajectories
      )

      return nil if trajectories.empty?

      lines = ["## Past Trajectories"]

      trajectories.each do |traj|
        traj.record_access!
        lines << format_trajectory_for_prompt(traj)
      end

      lines.join("\n\n")
    end

    # List trajectories with filters
    def list_trajectories(filters = {})
      trajectories = account.ai_trajectories.recent

      trajectories = trajectories.by_type(filters[:type]) if filters[:type].present?
      trajectories = trajectories.with_tags(filters[:tags]) if filters[:tags].present?
      trajectories = trajectories.where(status: filters[:status]) if filters[:status].present?

      if filters[:query].present?
        trajectories = trajectories.where(
          "title ILIKE :q OR summary ILIKE :q", q: "%#{sanitize_sql_like(filters[:query])}%"
        )
      end

      trajectories = trajectories.limit(filters[:limit] || 20)
      trajectories
    end

    # Get a trajectory with chapters
    def get_trajectory(trajectory_id)
      account.ai_trajectories
             .includes(:chapters)
             .find(trajectory_id)
    end

    private

    def build_chapters(trajectory, execution)
      chapter_start = Time.current
      # Eager load tasks once to prevent N+1 queries
      tasks = execution.tasks.includes(:assigned_role).order(:created_at).to_a

      build_understanding_chapter(trajectory, execution, chapter_start)
      build_planning_chapter(trajectory, tasks, chapter_start)
      build_implementation_chapters(trajectory, tasks, chapter_start)
      build_reflection_chapter(trajectory, tasks, chapter_start)
    end

    def build_understanding_chapter(trajectory, execution, start_time)
      trajectory.add_chapter(
        title: "Understanding the Objective",
        chapter_type: "understanding",
        content: build_understanding_content(execution),
        reasoning: "Analyzing the execution objective and input context",
        key_decisions: [],
        artifacts: [],
        duration_ms: ((Time.current - start_time) * 1000).to_i
      )
    end

    def build_planning_chapter(trajectory, tasks, start_time)
      return if tasks.empty?

      task_breakdown = tasks.map.with_index do |task, idx|
        role_name = task.assigned_role&.role_name || "Unassigned"
        "#{idx + 1}. #{task.description} (assigned to: #{role_name})"
      end

      team_type = tasks.first&.team_execution&.agent_team&.team_type

      trajectory.add_chapter(
        title: "Task Planning & Breakdown",
        chapter_type: "planning",
        content: "The objective was broken into #{tasks.count} tasks:\n#{task_breakdown.join("\n")}",
        reasoning: "Task decomposition based on team structure and capabilities",
        key_decisions: [{
          "decision" => "Split into #{tasks.count} parallel/sequential tasks",
          "rationale" => "Based on team type: #{team_type}",
          "alternatives" => ["Single monolithic task", "Different task grouping"]
        }],
        duration_ms: ((Time.current - start_time) * 1000).to_i
      )
    end

    def build_implementation_chapters(trajectory, tasks, start_time)
      tasks.each do |task|
        artifacts = extract_task_artifacts(task)

        trajectory.add_chapter(
          title: "Task: #{task.description.truncate(80)}",
          chapter_type: "implementation",
          content: build_task_content(task),
          reasoning: task.output_data&.dig("reasoning"),
          key_decisions: extract_task_decisions(task),
          artifacts: artifacts,
          duration_ms: task.duration_ms
        )
      end
    end

    def build_reflection_chapter(trajectory, tasks, start_time)
      completed = tasks.count { |t| t.status == "completed" }
      failed = tasks.count { |t| t.status == "failed" }
      total = tasks.size

      lessons = []
      lessons << "All #{total} tasks completed successfully" if failed.zero? && total.positive?
      lessons << "#{failed} of #{total} tasks failed — review error handling" if failed.positive?

      tasks.select { |t| t.status == "failed" }.each do |task|
        lessons << "Failed task '#{task.description.truncate(50)}': #{task.failure_reason}"
      end

      trajectory.add_chapter(
        title: "Reflection & Lessons Learned",
        chapter_type: "reflection",
        content: "Execution completed with #{completed}/#{total} tasks successful.\n\nKey learnings:\n#{lessons.map { |l| "- #{l}" }.join("\n")}",
        reasoning: "Post-execution analysis of outcomes and process",
        key_decisions: [],
        artifacts: [],
        duration_ms: ((Time.current - start_time) * 1000).to_i
      )
    end

    def finalize_trajectory(trajectory, execution)
      tasks = execution.tasks.to_a
      completed = tasks.count { |t| t.status == "completed" }
      failed = tasks.count { |t| t.status == "failed" }
      total = tasks.size
      quality = total.positive? ? (completed.to_f / total).round(2) : 0.0

      trajectory.complete!(
        quality_score: quality,
        outcome_summary: {
          "tasks_total" => total,
          "tasks_completed" => completed,
          "tasks_failed" => failed,
          "duration_ms" => execution.duration_ms,
          "status" => execution.status
        }
      )
    end

    def build_understanding_content(execution)
      parts = []
      parts << "Objective: #{execution.objective}" if execution.objective.present?

      if execution.input_context.present?
        parts << "Input context provided with #{execution.input_context.keys.count} parameters"
      end

      team = execution.agent_team
      if team
        parts << "Team: #{team.name} (#{team.team_type})"
        parts << "Members: #{team.ai_team_roles.count} roles assigned"
      end

      parts.join("\n")
    end

    def build_task_content(task)
      parts = []
      parts << "Description: #{task.description}"
      parts << "Status: #{task.status}"
      parts << "Type: #{task.task_type}"

      if task.assigned_role
        parts << "Assigned to: #{task.assigned_role.role_name}"
      end

      if task.output_data.present?
        output_preview = task.output_data.to_json.truncate(500)
        parts << "Output: #{output_preview}"
      end

      if task.failure_reason.present?
        parts << "Failure reason: #{task.failure_reason}"
      end

      parts.join("\n")
    end

    def extract_task_artifacts(task)
      artifacts = []
      output = task.output_data || {}

      if output["files"].is_a?(Array)
        output["files"].each do |file|
          artifacts << {
            "type" => "file",
            "path" => file["path"] || file["name"],
            "action" => file["action"] || "modified"
          }
        end
      end

      artifacts
    end

    def extract_task_decisions(task)
      decisions = []
      output = task.output_data || {}

      if output["decisions"].is_a?(Array)
        output["decisions"].each do |d|
          decisions << {
            "decision" => d["decision"],
            "rationale" => d["rationale"],
            "alternatives" => d["alternatives"] || []
          }
        end
      end

      decisions
    end

    def extract_tags(execution)
      tags = []
      tags << execution.agent_team&.team_type if execution.agent_team
      tags << "execution"
      tags.compact
    end

    def sanitize_sql_like(string)
      string.to_s.gsub(/[%_\\]/) { |m| "\\#{m}" }
    end

    def format_trajectory_for_prompt(trajectory)
      lines = ["### #{trajectory.title}"]
      lines << "Score: #{trajectory.quality_score || 'N/A'} | Type: #{trajectory.trajectory_type}"
      lines << trajectory.summary if trajectory.summary.present?

      reflection = trajectory.chapters.by_type("reflection").ordered.last
      if reflection
        lines << "Lessons: #{reflection.content.truncate(200)}"
      end

      lines.join("\n")
    end
  end
end
