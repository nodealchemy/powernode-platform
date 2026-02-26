# frozen_string_literal: true

module Ai
  module TeamStrategies
    # Provides memory integration for team strategies:
    # - Inject agent-specific memory context before execution
    # - Write agent contributions to experiential memory after execution
    # - Extract compound learnings from team execution patterns
    module MemoryIntegrationConcern
      extend ActiveSupport::Concern

      # Inject relevant memory context into the agent's input using
      # ContextInjectorService. Returns enriched input with memory prepended.
      def inject_agent_memory(agent, input)
        injector = Ai::Memory::ContextInjectorService.new(agent: agent, account: account)
        context = injector.build_context(
          task: input,
          query: input,
          include_types: %w[factual working experiential compound_learnings]
        )

        return input if context.blank?

        "#{context}\n\n---\nTask:\n#{input}"
      rescue StandardError => e
        Rails.logger.warn "[MemoryIntegration] Failed to inject memory for agent #{agent.id}: #{e.message}"
        input
      end

      # Write each agent's output to experiential memory so the team
      # builds shared knowledge over time.
      def write_team_memory(outputs)
        return if outputs.blank?

        written = 0

        outputs.each do |output_record|
          next if output_record[:output].blank?

          agent = find_agent(output_record[:agent_id])
          next unless agent

          storage = Ai::Memory::StorageService.new(account: account, agent: agent)
          storage.store_experiential(
            content: output_record[:output],
            context: {
              team_id: team.id,
              team_name: team.name,
              execution_id: execution&.id,
              role: output_record[:role],
              agent_name: output_record[:agent_name]
            },
            outcome_success: true,
            importance: calculate_importance(output_record),
            tags: ["team_execution", "team:#{team.id}", "role:#{output_record[:role]}"],
            source_type: "team_execution"
          )

          written += 1
        end

        Rails.logger.info "[MemoryIntegration] Wrote #{written} memory entries for team #{team.id}"
      rescue StandardError => e
        Rails.logger.error "[MemoryIntegration] Failed to write team memory: #{e.message}"
      end

      # Extract compound learnings from the team execution pattern.
      # Called after execution completes to capture reusable knowledge.
      def extract_team_learnings(outputs)
        return if outputs.blank? || execution.nil?

        learning_service = Ai::Learning::CompoundLearningService.new(account: account)
        learning_service.post_execution_extract(execution)

        Rails.logger.info "[MemoryIntegration] Extracted learnings from team #{team.id} execution"
      rescue StandardError => e
        Rails.logger.error "[MemoryIntegration] Failed to extract learnings: #{e.message}"
      end

      private

      def find_agent(agent_id)
        return nil unless agent_id

        account.ai_agents.find_by(id: agent_id)
      end

      def calculate_importance(output_record)
        base = output_record[:output].present? ? 0.6 : 0.2
        base += 0.2 if output_record[:role]&.include?("lead")
        base.clamp(0.0, 1.0)
      end
    end
  end
end
