# frozen_string_literal: true

module Ai
  module Analytics
    # Service for generating and managing AI analytics reports
    #
    # Provides report generation including:
    # - Scheduled report generation
    # - Custom report building
    # - Report export (JSON, CSV, PDF)
    # - Report storage and retrieval
    #
    # Usage:
    #   service = Ai::Analytics::ReportService.new(account: current_account, user: current_user)
    #   report = service.generate(type: :executive_summary, time_range: 30.days)
    #
    class ReportService
      attr_reader :account, :user, :time_range

      REPORT_TYPES = %w[
        executive_summary
        cost_analysis
        performance_analysis
        workflow_analysis
        agent_analysis
        custom
      ].freeze

      def initialize(account:, user:, time_range: 30.days)
        @account = account
        @user = user
        @time_range = time_range
      end

      # Generate a report
      # @param type [String, Symbol] Report type
      # @param options [Hash] Report options
      # @return [Hash] Generated report
      def generate(type:, options: {})
        validate_report_type!(type)

        report_data = case type.to_s
        when "executive_summary" then generate_executive_summary(options)
        when "cost_analysis" then generate_cost_report(options)
        when "performance_analysis" then generate_performance_report(options)
        when "workflow_analysis" then generate_workflow_report(options)
        when "agent_analysis" then generate_agent_report(options)
        when "custom" then generate_custom_report(options)
        else raise ArgumentError, "Unknown report type: #{type}"
        end

        {
          report_type: type.to_s,
          generated_at: Time.current.iso8601,
          generated_by: user.email,
          account_id: account.id,
          time_range: {
            start: time_range.ago.iso8601,
            end: Time.current.iso8601,
            period: format_time_range
          },
          data: report_data
        }
      end

      # Export report to specific format
      # @param report [Hash] Report data
      # @param format [Symbol] Export format (:json, :csv, :pdf)
      # @return [String] Exported content
      def export(report:, format:)
        case format.to_sym
        when :json then export_json(report)
        when :csv then export_csv(report)
        when :pdf then export_pdf(report)
        else raise ArgumentError, "Unknown export format: #{format}"
        end
      end

      # Schedule a recurring report
      # @param type [String] Report type
      # @param schedule [String] Cron expression
      # @param recipients [Array<String>] Email recipients
      # @param options [Hash] Report options
      # @return [Hash] Schedule confirmation
      def schedule(type:, schedule:, recipients:, options: {})
        {
          scheduled: true,
          report_type: type,
          schedule: schedule,
          recipients: recipients,
          options: options,
          next_run: calculate_next_run(schedule)
        }
      end

      # List available report types
      # @return [Array<Hash>] Available report types
      def available_reports
        REPORT_TYPES.map do |type|
          {
            type: type,
            name: type.titleize,
            description: report_description(type),
            estimated_generation_time: estimate_generation_time(type)
          }
        end
      end

      private

      # =============================================================================
      # REPORT GENERATORS
      # =============================================================================

      def generate_executive_summary(options)
        dashboard = DashboardService.new(account: account, time_range: time_range).generate
        cost = CostAnalysisService.new(account: account, time_range: time_range).calculate_total_cost
        performance = PerformanceAnalysisService.new(account: account, time_range: time_range)

        {
          title: "Executive Summary Report",
          highlights: [
            "Total AI Executions: #{dashboard[:summary][:workflows][:executions]}",
            "Success Rate: #{(dashboard[:summary][:workflows][:success_rate] || 0) * 100}%",
            "Total Cost: $#{cost[:total]}",
            "Active Workflows: #{dashboard[:summary][:workflows][:active]}"
          ],
          kpis: {
            executions: dashboard[:summary][:workflows][:executions],
            success_rate: dashboard[:summary][:workflows][:success_rate],
            total_cost: cost[:total],
            active_workflows: dashboard[:summary][:workflows][:active],
            active_agents: dashboard[:summary][:agents][:active]
          },
          trends: dashboard[:trends],
          cost_summary: {
            total: cost[:total],
            trend: CostAnalysisService.new(account: account, time_range: time_range).calculate_cost_trend
          },
          performance_summary: {
            response_times: performance.analyze_response_times.slice(:avg_ms, :p95_ms),
            success_rates: performance.analyze_success_rates.slice(:success_rate, :failure_rate)
          },
          top_workflows: dashboard[:highlights][:top_workflows],
          recent_issues: dashboard[:highlights][:recent_failures]
        }
      end

      def generate_cost_report(options)
        cost_service = CostAnalysisService.new(account: account, time_range: time_range)

        {
          title: "Cost Analysis Report",
          total_cost: cost_service.calculate_total_cost,
          cost_trend: cost_service.calculate_cost_trend,
          cost_by_provider: cost_service.cost_breakdown_by_provider,
          cost_by_workflow: cost_service.cost_breakdown_by_workflow,
          cost_by_model: cost_service.cost_breakdown_by_model,
          daily_costs: cost_service.daily_cost_breakdown,
          budget_status: cost_service.budget_analysis,
          optimization_opportunities: cost_service.estimate_cost_savings,
          forecast: cost_service.generate_budget_forecast,
          anomalies: cost_service.detect_cost_anomalies
        }
      end

      def generate_performance_report(options)
        performance_service = PerformanceAnalysisService.new(account: account, time_range: time_range)

        {
          title: "Performance Analysis Report",
          response_times: performance_service.analyze_response_times,
          success_rates: performance_service.analyze_success_rates,
          throughput: performance_service.analyze_throughput,
          error_rates: performance_service.analyze_error_rates,
          bottlenecks: performance_service.identify_bottlenecks,
          sla_compliance: performance_service.analyze_sla_compliance,
          trends: performance_service.analyze_performance_trends
        }
      end

      def generate_workflow_report(options)
        metrics_service = MetricsService.new(account: account, time_range: time_range)
        workflow_metrics = metrics_service.workflow_metrics

        specific_workflows = if options[:workflow_ids].present?
                               options[:workflow_ids].map do |id|
                                 workflow = account.ai_workflows.find_by(id: id)
                                 next nil unless workflow

                                 metrics_service.workflow_specific_metrics(workflow)
                               end.compact
        else
                               []
        end

        {
          title: "Workflow Analysis Report",
          summary: workflow_metrics,
          top_performers: find_top_performing_workflows,
          needs_attention: find_workflows_needing_attention,
          execution_trends: workflow_execution_trends,
          workflow_details: specific_workflows
        }
      end

      def generate_agent_report(options)
        metrics_service = MetricsService.new(account: account, time_range: time_range)
        agent_metrics = metrics_service.agent_metrics

        specific_agents = if options[:agent_ids].present?
                            options[:agent_ids].map do |id|
                              agent = account.ai_agents.find_by(id: id)
                              next nil unless agent

                              metrics_service.agent_specific_metrics(agent)
                            end.compact
        else
                            []
        end

        {
          title: "Agent Analysis Report",
          summary: agent_metrics,
          agent_performance: analyze_agent_performance,
          agent_details: specific_agents
        }
      end

      def generate_custom_report(options)
        sections = options[:sections] || []

        {
          title: options[:title] || "Custom Report",
          sections: sections.map do |section|
            case section.to_s
            when "cost" then { name: "Cost Analysis", data: generate_cost_report({}) }
            when "performance" then { name: "Performance", data: generate_performance_report({}) }
            when "workflows" then { name: "Workflows", data: generate_workflow_report({}) }
            when "agents" then { name: "Agents", data: generate_agent_report({}) }
            else { name: section.to_s, data: {} }
            end
          end
        }
      end

      # =============================================================================
      # EXPORT FORMATTERS
      # =============================================================================

      def export_json(report)
        JSON.pretty_generate(report)
      end

      def export_csv(report)
        csv_data = []

        # Convert report data to flat CSV format
        csv_data << [ "Report Type", report[:report_type] ]
        csv_data << [ "Generated At", report[:generated_at] ]
        csv_data << [ "Period", "#{report[:time_range][:start]} to #{report[:time_range][:end]}" ]
        csv_data << []

        # Add data sections
        flatten_to_csv(report[:data], csv_data)

        csv_data.map { |row| row.join(",") }.join("\n")
      end

      def export_pdf(report)
        require "prawn"
        require "prawn/table"

        pdf = Prawn::Document.new(page_size: "A4", margin: 50)

        # Title page
        pdf.move_down 100
        pdf.text report[:report_type].to_s.titleize, size: 28, style: :bold, align: :center
        pdf.move_down 20
        pdf.text "Generated: #{report[:generated_at]}", size: 12, align: :center, color: "666666"
        pdf.text "By: #{report[:generated_by]}", size: 12, align: :center, color: "666666"
        if report[:time_range]
          pdf.text "Period: #{report[:time_range][:period]}", size: 12, align: :center, color: "666666"
        end

        pdf.start_new_page

        # Render data sections
        render_pdf_section(pdf, report[:data]) if report[:data].is_a?(Hash)

        # Footer on each page
        pdf.number_pages "Page <page> of <total>", at: [pdf.bounds.right - 100, -10], size: 8, color: "999999"

        pdf.render
      end

      def render_pdf_section(pdf, data, depth = 0)
        data.each do |key, value|
          case value
          when Hash
            pdf.move_down 10
            pdf.text key.to_s.titleize, size: 14 - [depth, 4].min, style: :bold
            pdf.move_down 5
            render_pdf_section(pdf, value, depth + 1)
          when Array
            pdf.move_down 10
            pdf.text key.to_s.titleize, size: 14 - [depth, 4].min, style: :bold
            pdf.move_down 5
            render_pdf_array(pdf, value)
          else
            pdf.text "#{key.to_s.titleize}: #{value}", size: 10
            pdf.move_down 3
          end
        end
      end

      def render_pdf_array(pdf, array)
        return if array.empty?

        if array.first.is_a?(Hash)
          headers = array.first.keys.map { |k| k.to_s.titleize }
          rows = array.map { |item| item.values.map { |v| v.to_s.truncate(50) } }
          table_data = [headers] + rows

          pdf.table(table_data, width: pdf.bounds.width) do |t|
            t.row(0).font_style = :bold
            t.row(0).background_color = "F0F0F0"
            t.cells.padding = [5, 8]
            t.cells.border_width = 0.5
            t.cells.border_color = "DDDDDD"
            t.cells.size = 9
          end
        else
          array.each do |item|
            pdf.text "• #{item}", size: 10
            pdf.move_down 2
          end
        end
      rescue Prawn::Errors::CannotFit
        # Table too wide, render as list instead
        array.each do |item|
          pdf.text "• #{item.is_a?(Hash) ? item.values.join(' | ') : item}", size: 9
          pdf.move_down 2
        end
      end

      def flatten_to_csv(data, csv_data, prefix = "")
        case data
        when Hash
          data.each do |key, value|
            new_prefix = prefix.empty? ? key.to_s : "#{prefix}.#{key}"
            flatten_to_csv(value, csv_data, new_prefix)
          end
        when Array
          data.each_with_index do |item, index|
            flatten_to_csv(item, csv_data, "#{prefix}[#{index}]")
          end
        else
          csv_data << [ prefix, data.to_s ]
        end
      end

      # =============================================================================
      # HELPER METHODS
      # =============================================================================

      def validate_report_type!(type)
        unless REPORT_TYPES.include?(type.to_s)
          raise ArgumentError, "Invalid report type: #{type}. Valid types: #{REPORT_TYPES.join(', ')}"
        end
      end

      def format_time_range
        days = time_range.to_i / 86400
        case days
        when 1 then "1 day"
        when 7 then "1 week"
        when 30 then "30 days"
        when 90 then "90 days"
        else "#{days} days"
        end
      end

      def report_description(type)
        case type
        when "executive_summary" then "High-level overview of AI operations with key metrics and trends"
        when "cost_analysis" then "Detailed cost breakdown and optimization recommendations"
        when "performance_analysis" then "Performance metrics, SLA compliance, and bottleneck analysis"
        when "workflow_analysis" then "Workflow execution statistics and performance analysis"
        when "agent_analysis" then "Agent performance and utilization analysis"
        when "custom" then "Customizable report with selected sections"
        else "Report"
        end
      end

      def estimate_generation_time(type)
        case type
        when "executive_summary" then "~5 seconds"
        when "cost_analysis" then "~10 seconds"
        when "performance_analysis" then "~15 seconds"
        when "workflow_analysis" then "~20 seconds"
        when "agent_analysis" then "~10 seconds"
        when "custom" then "Varies"
        else "Unknown"
        end
      end

      def calculate_next_run(cron_expression)
        # Simplified - would use a cron parser
        Time.current + 1.day
      end

      def find_top_performing_workflows
        start_time = time_range.ago

        account.ai_workflows.map do |workflow|
          runs = workflow.runs.where("ai_workflow_runs.created_at >= ?", start_time)
                        .where.not(status: %w[running initializing pending])

          total = runs.count
          next nil if total < 5

          completed = runs.where(status: "completed").count
          success_rate = (completed.to_f / total * 100).round(2)

          {
            id: workflow.id,
            name: workflow.name,
            executions: total,
            success_rate: success_rate
          }
        end.compact.select { |w| w[:success_rate] >= 95 }.sort_by { |w| -w[:executions] }.first(5)
      end

      def find_workflows_needing_attention
        start_time = time_range.ago

        account.ai_workflows.map do |workflow|
          runs = workflow.runs.where("ai_workflow_runs.created_at >= ?", start_time)
                        .where.not(status: %w[running initializing pending])

          total = runs.count
          next nil if total < 3

          failed = runs.where(status: "failed").count
          failure_rate = (failed.to_f / total * 100).round(2)

          next nil if failure_rate < 10

          {
            id: workflow.id,
            name: workflow.name,
            executions: total,
            failure_rate: failure_rate,
            recent_errors: runs.where(status: "failed").order(created_at: :desc).limit(3).pluck(:error_details)
          }
        end.compact.sort_by { |w| -w[:failure_rate] }.first(5)
      end

      def workflow_execution_trends
        start_time = time_range.ago

        ::Ai::WorkflowRun.joins(:workflow)
                        .where(ai_workflows: { account_id: account.id })
                        .where("ai_workflow_runs.created_at >= ?", start_time)
                        .group("DATE(ai_workflow_runs.created_at)")
                        .count
                        .transform_keys(&:to_s)
      end

      def analyze_agent_performance
        start_time = time_range.ago

        account.ai_agents.map do |agent|
          node_executions = ::Ai::WorkflowNodeExecution.joins(:node, workflow_run: :workflow)
                                              .where(ai_workflows: { account_id: account.id })
                                              .where("ai_workflow_nodes.configuration->>'agent_id' = ?", agent.id.to_s)
                                              .where("ai_node_executions.created_at >= ?", start_time)

          total = node_executions.count
          next nil if total.zero?

          completed = node_executions.where(status: "completed").count

          {
            id: agent.id,
            name: agent.name,
            agent_type: agent.agent_type,
            total_executions: total,
            success_rate: (completed.to_f / total * 100).round(2),
            avg_response_time_ms: node_executions.where(status: "completed").average(:execution_time_ms)&.to_f&.round(2)
          }
        end.compact.sort_by { |a| -a[:total_executions] }
      end
    end
  end
end
