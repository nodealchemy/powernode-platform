# frozen_string_literal: true

module Ai
  module Tools
    class ApiReferenceTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.read"
      API_REFERENCE_PATH = Rails.root.join("../docs/platform/AI_ORCHESTRATION_API_REFERENCE.md")

      def self.definition
        {
          name: "get_api_reference",
          description: "Get the platform API reference documentation",
          parameters: {
            section: { type: "string", required: false, description: "Section filter: workflows, agents, teams, providers, git, monitoring, memory, rag" }
          }
        }
      end

      protected

      def call(params)
        unless File.exist?(API_REFERENCE_PATH)
          return { success: false, error: "API reference documentation not found" }
        end

        content = File.read(API_REFERENCE_PATH)
        content = filter_section(content, params[:section]) if params[:section].present?
        { success: true, reference: content, sections: extract_sections(content) }
      end

      private

      def filter_section(content, section)
        lines = content.lines
        section_start = nil
        section_end = nil

        lines.each_with_index do |line, idx|
          if line.match?(/^##\s+.*#{Regexp.escape(section)}/i)
            section_start = idx
          elsif section_start && line.match?(/^##\s+/) && idx > section_start
            section_end = idx
            break
          end
        end

        return content unless section_start

        section_end ||= lines.length
        lines[section_start...section_end].join
      end

      def extract_sections(content)
        content.lines.select { |l| l.match?(/^##\s+/) }.map { |l| l.gsub(/^##\s+/, "").strip }
      end
    end
  end
end
