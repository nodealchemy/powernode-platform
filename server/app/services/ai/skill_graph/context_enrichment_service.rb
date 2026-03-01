# frozen_string_literal: true

module Ai
  module SkillGraph
    class ContextEnrichmentService
      DEFAULT_TOKEN_BUDGET = 2000

      attr_reader :account

      def initialize(account)
        @account = account
      end

      # Enrich agent context with skill graph traversal results
      def enrich(agent:, input_text:, mode: :auto, token_budget: DEFAULT_TOKEN_BUDGET)
        result = traversal_service.traverse(
          task_context: input_text,
          agent: agent,
          mode: mode.to_sym,
          token_budget: token_budget
        )

        case mode.to_sym
        when :auto
          format_auto_context(result)
        when :manifest
          format_manifest_context(result)
        else
          { context_block: "", metadata: {} }
        end
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::ContextEnrichmentService] Enrichment failed: #{e.message}"
        { context_block: "", metadata: { error: e.message } }
      end

      private

      def format_auto_context(result)
        skills = result[:discovered_skills]
        return { context_block: "", metadata: { reason: "no_skills_found" } } if skills.blank?

        lines = ["=== RELEVANT SKILL CONTEXT ==="]

        skills.each do |skill|
          header = "[Skill: #{skill[:name]}] (#{skill[:category]}, relevance: #{skill[:score]})"
          lines << header
          lines << skill[:system_prompt].to_s.strip if skill[:system_prompt].present?
          lines << ""
        end

        {
          context_block: lines.join("\n").strip,
          metadata: {
            mode: :auto,
            skill_count: skills.size,
            seed_count: result[:seed_count],
            token_estimate: result[:token_estimate]
          }
        }
      end

      def format_manifest_context(result)
        nav_map = result[:navigation_map]
        return { context_block: "", metadata: { reason: "no_skills_found" } } if nav_map.blank?

        lines = ["=== SKILL NAVIGATION MAP ===", "You have access to:"]

        nav_map.each do |name, data|
          adjacent = data[:adjacent_skills]
          if adjacent.any?
            adjacent_names = adjacent.map { |a| a[:name] }.join(", ")
            lines << "- #{name} -> [#{adjacent_names}]"
          else
            lines << "- #{name} (no connected skills)"
          end
        end

        if result[:recommendations].present?
          lines << ""
          lines << "Recommendations:"
          result[:recommendations].each do |rec|
            lines << "- #{rec[:message]}"
          end
        end

        {
          context_block: lines.join("\n").strip,
          metadata: {
            mode: :manifest,
            skill_count: nav_map.size,
            total_skill_nodes: result[:total_skill_nodes],
            recommendations_count: result[:recommendations]&.size || 0
          }
        }
      end

      def traversal_service
        @traversal_service ||= Ai::SkillGraph::TraversalService.new(account)
      end
    end
  end
end
