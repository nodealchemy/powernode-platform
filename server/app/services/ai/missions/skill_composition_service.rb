# frozen_string_literal: true

module Ai
  module Missions
    class SkillCompositionService
      class CompositionError < StandardError; end

      attr_reader :mission, :account

      def initialize(mission:)
        @mission = mission
        @account = mission.account
      end

      # Compose a task plan by matching skills to mission phases.
      # Creates a RalphLoop with RalphTasks mapped to each phase.
      def compose!
        phases = mission.phases_for_type
        raise CompositionError, "Mission has no phases defined" if phases.blank?

        ralph_loop = find_or_create_ralph_loop!
        tasks = []

        phases.each_with_index do |phase_key, index|
          next if phase_key == "completed"

          phase_config = mission_phase_config(phase_key)
          next if phase_config&.dig("requires_approval")

          matched_skills = discover_skills_for_phase(phase_key, phase_config)

          if matched_skills.present?
            matched_skills.each_with_index do |skill, skill_idx|
              tasks << create_skill_task!(ralph_loop, phase_key, skill, index, skill_idx)
            end
          else
            tasks << create_generic_task!(ralph_loop, phase_key, phase_config, index)
          end
        end

        mission.update!(ralph_loop_id: ralph_loop.id) unless mission.ralph_loop_id == ralph_loop.id

        build_task_graph(ralph_loop, tasks)
      end

      private

      def find_or_create_ralph_loop!
        if mission.ralph_loop.present?
          mission.ralph_loop
        else
          Ai::RalphLoop.create!(
            account: account,
            name: "Mission: #{mission.name}",
            description: "Auto-composed task plan for mission #{mission.id}",
            status: "active",
            loop_type: "mission",
            max_iterations: 1,
            total_tasks: 0,
            completed_tasks: 0,
            failed_tasks: 0
          )
        end
      end

      def mission_phase_config(phase_key)
        if mission.custom_phases.present?
          mission.custom_phases.find { |p| p["key"] == phase_key }
        elsif mission.mission_template.present?
          mission.mission_template.phases&.find { |p| p["key"] == phase_key }
        end
      end

      def discover_skills_for_phase(phase_key, phase_config)
        return [] unless defined?(Ai::Tools::SemanticToolDiscoveryService)

        query = [
          phase_key.humanize,
          phase_config&.dig("description"),
          mission.objective
        ].compact.join(" — ")

        discovery = Ai::Tools::SemanticToolDiscoveryService.new(account: account)
        results = discovery.discover(query: query, limit: 3)

        results.select { |r| r[:relevance_score].to_f > 0.4 }
      rescue StandardError => e
        Rails.logger.warn("Skill discovery failed for phase #{phase_key}: #{e.message}")
        []
      end

      def create_skill_task!(ralph_loop, phase_key, skill, phase_index, skill_index)
        ralph_loop.ralph_tasks.create!(
          task_key: "#{phase_key}_skill_#{skill_index}",
          description: skill[:description] || skill[:name],
          status: "pending",
          execution_type: "agent",
          priority: 100 - phase_index,
          position: (phase_index * 10) + skill_index,
          required_capabilities: [skill[:name]].compact,
          capability_match_strategy: "any",
          metadata: {
            "phase" => phase_key,
            "skill_id" => skill[:id],
            "skill_name" => skill[:name],
            "composed" => true
          },
          delegation_config: {}
        )
      end

      def create_generic_task!(ralph_loop, phase_key, phase_config, phase_index)
        ralph_loop.ralph_tasks.create!(
          task_key: phase_key,
          description: phase_config&.dig("description") || phase_key.humanize,
          status: "pending",
          execution_type: "agent",
          priority: 100 - phase_index,
          position: phase_index * 10,
          metadata: {
            "phase" => phase_key,
            "composed" => true
          },
          delegation_config: {}
        )
      end

      def build_task_graph(ralph_loop, tasks)
        nodes = tasks.map do |task|
          {
            id: task.id,
            task_key: task.task_key,
            description: task.description,
            status: task.status,
            execution_type: task.execution_type,
            priority: task.priority,
            position: task.position,
            dependencies: task.dependencies || [],
            executor_type: task.executor_type,
            executor_name: task.executor&.try(:name),
            phase: task.metadata&.dig("phase"),
            metadata: task.metadata
          }
        end

        edges = tasks.flat_map do |task|
          (task.dependencies || []).filter_map do |dep_key|
            source = tasks.find { |t| t.task_key == dep_key }
            next unless source

            { id: "#{source.id}-#{task.id}", source: source.id, target: task.id }
          end
        end

        { nodes: nodes, edges: edges }
      end
    end
  end
end
