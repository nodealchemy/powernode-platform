# frozen_string_literal: true

# Helper methods for downloading and exporting workflow run data
#
# Provides methods for:
# - Preparing download data from workflow runs
# - Extracting text content from run data
# - Formatting run data as markdown
# - Building static workflow templates
#
# Usage:
#   class WorkflowsController < ApplicationController
#     include Ai::WorkflowDownloadHelpers
#
#     def run_download
#       download_data = prepare_download_data(@workflow_run)
#       ...
#     end
#   end
#
module Ai
  module WorkflowDownloadHelpers
    extend ActiveSupport::Concern

    private

    # Prepare comprehensive download data for a workflow run
    # @param workflow_run [Ai::WorkflowRun] The workflow run to export
    # @return [Hash] Structured download data
    def prepare_download_data(workflow_run)
      {
        workflow_execution: {
          id: workflow_run.id,
          run_id: workflow_run.run_id,
          status: workflow_run.status,
          started_at: workflow_run.started_at,
          completed_at: workflow_run.completed_at,
          duration_ms: workflow_run.execution_time_ms,
          total_cost: workflow_run.total_cost,
          input_variables: workflow_run.input_variables,
          output_variables: workflow_run.output_variables
        },
        workflow: {
          id: workflow_run.workflow.id,
          name: workflow_run.workflow.name,
          description: workflow_run.workflow.description
        },
        node_executions: workflow_run.node_executions.includes(:node).map do |exec|
          {
            node_name: exec.node.name,
            node_type: exec.node.node_type,
            status: exec.status,
            started_at: exec.started_at,
            completed_at: exec.completed_at,
            duration_ms: exec.duration_ms,
            input_data: exec.input_data,
            output_data: exec.output_data,
            error_details: exec.failed? ? exec.error_details : nil
          }
        end,
        generated_at: Time.current.iso8601
      }
    end

    # Extract plain text content from download data
    # @param download_data [Hash] Download data from prepare_download_data
    # @return [String] Plain text representation
    def extract_text_content(download_data)
      exec = download_data[:workflow_execution]
      parts = [
        "Workflow: #{download_data[:workflow][:name]}",
        "Run ID: #{exec[:run_id]}",
        "Status: #{exec[:status]}"
      ]
      parts << "Duration: #{(exec[:duration_ms] / 1000.0).round(1)} seconds" if exec[:duration_ms]
      parts << ""
      parts.join("\n")
    end

    # Format download data as markdown
    # @param download_data [Hash] Download data from prepare_download_data
    # @return [String] Markdown formatted content
    def format_as_markdown(download_data)
      exec = download_data[:workflow_execution]
      output_vars = exec[:output_variables] || {}

      # Try to find markdown content in various locations
      markdown = find_markdown_content(output_vars, download_data)

      return markdown.to_s if markdown.present? && markdown.to_s.length > 50

      # Fall back to basic markdown template
      build_fallback_markdown(download_data, exec)
    end

    # Find markdown content from output variables or node executions
    # @param output_vars [Hash] Output variables from the run
    # @param download_data [Hash] Full download data
    # @return [String, nil] Found markdown content or nil
    def find_markdown_content(output_vars, download_data)
      # Check direct markdown key
      return output_vars["markdown"] if output_vars["markdown"].present?

      # Check nested result structures
      if output_vars.dig("result", "final_output").is_a?(Hash)
        final_output = output_vars.dig("result", "final_output")
        return final_output["markdown"] if final_output["markdown"].present?
        return final_output["result"] if final_output["result"].present?
      end

      # Check alternative keys
      %w[final_markdown markdown_formatter_output].each do |key|
        return output_vars[key] if output_vars[key].present?
      end

      # Try to find from node executions
      find_markdown_from_node_executions(download_data[:node_executions])
    end

    # Find markdown content from node execution outputs
    # @param node_executions [Array<Hash>] Node execution data
    # @return [String, nil] Found markdown content or nil
    def find_markdown_from_node_executions(node_executions)
      return nil unless node_executions.is_a?(Array)

      # Look for markdown/format nodes first
      node_exec = node_executions.find do |n|
        n[:node_name]&.include?("Markdown") || n[:node_name]&.include?("Format")
      end

      # Fall back to last AI agent node
      node_exec ||= node_executions.reverse.find { |n| n[:node_type] == "ai_agent" }

      return nil unless node_exec

      extract_content_from_output(node_exec[:output_data])
    end

    # Recursively extract content from output data
    # @param output_data [Hash, String, nil] Output data to search
    # @param depth [Integer] Current recursion depth
    # @return [String, nil] Found content or nil
    def extract_content_from_output(output_data, depth = 0)
      return nil if depth > 10 || output_data.blank?
      return output_data if output_data.is_a?(String)
      return nil unless output_data.is_a?(Hash)

      # Try common content keys
      %w[markdown final_markdown output result content data response].each do |key|
        result = extract_content_from_output(output_data[key], depth + 1)
        return result if result.present?
      end

      nil
    end

    # Build fallback markdown when no content found
    # @param download_data [Hash] Download data
    # @param exec [Hash] Workflow execution data
    # @return [String] Basic markdown representation
    def build_fallback_markdown(download_data, exec)
      lines = [
        "# #{download_data[:workflow][:name]}",
        "",
        "**Run ID:** `#{exec[:run_id]}`",
        "**Status:** #{exec[:status]}"
      ]

      lines << "**Duration:** #{(exec[:duration_ms] / 1000.0).round(1)} seconds" if exec[:duration_ms]

      lines.concat([
        "",
        "## Workflow completed successfully",
        "",
        "No markdown output was found. The workflow may not have produced formatted content."
      ])

      lines.join("\n")
    end

    # Build static workflow template definitions
    # @return [Array<Hash>] Array of template definitions
    def build_workflow_templates
      [
        {
          id: "content-generation",
          name: "Content Generation Pipeline",
          description: "Sequential workflow for research, writing, and review",
          category: "content",
          execution_mode: "sequential",
          difficulty: "beginner",
          estimated_duration: "5-10 minutes",
          tags: %w[content research writing]
        },
        {
          id: "data-analysis",
          name: "Parallel Data Analysis",
          description: "Analyze data from multiple perspectives simultaneously",
          category: "analytics",
          execution_mode: "parallel",
          difficulty: "intermediate",
          estimated_duration: "10-15 minutes",
          tags: %w[analytics data statistics]
        },
        {
          id: "conditional-processing",
          name: "Smart Conditional Workflow",
          description: "Adaptive workflow with conditional execution",
          category: "automation",
          execution_mode: "conditional",
          difficulty: "advanced",
          estimated_duration: "15-20 minutes",
          tags: %w[automation conditional smart-routing]
        }
      ]
    end
  end
end
