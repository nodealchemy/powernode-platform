# frozen_string_literal: true

module A2a
  module Skills
    # DevopsSkills - A2A skill implementations for DevOps operations
    class DevopsSkills
      def initialize(account:, user: nil)
        @account = account
        @user = user
      end

      # List pipelines (CI/CD workflows)
      def list_pipelines(input, task = nil)
        scope = @account.ai_workflows.where(workflow_type: "cicd").order(created_at: :desc)

        scope = scope.where(status: input["status"]) if input["status"].present?

        page = (input["page"] || 1).to_i
        per_page = [ (input["per_page"] || 20).to_i, 100 ].min

        pipelines = scope.offset((page - 1) * per_page).limit(per_page)

        {
          output: {
            pipelines: pipelines.map { |p| pipeline_summary(p) },
            total: scope.count,
            page: page,
            per_page: per_page
          }
        }
      end

      # Execute pipeline
      def execute_pipeline(input, task = nil)
        pipeline = find_pipeline(input["pipeline_id"])

        unless pipeline.can_execute?
          raise ArgumentError, "Pipeline cannot be executed in #{pipeline.status} status"
        end

        run = pipeline.start_run!(
          input_variables: {
            **input["variables"] || {},
            ref: input["ref"]
          }.compact,
          triggered_by_user: @user,
          trigger_type: "api_call"
        )

        {
          output: {
            run_id: run.run_id,
            status: run.status,
            pipeline_id: pipeline.id,
            pipeline_name: pipeline.name
          }
        }
      end

      # Get pipeline logs
      def get_logs(input, task = nil)
        run = find_run(input["run_id"])

        logs = if input["job_name"].present?
                 # Get logs for specific job
                 node_execution = run.node_executions.joins(:node)
                                     .where(ai_workflow_nodes: { name: input["job_name"] })
                                     .first
                 node_execution&.metadata&.dig("logs") || ""
        else
                 # Get all logs
                 run.node_executions.order(:started_at).map do |ne|
                   {
                     job_name: ne.node&.name || ne.node_id,
                     status: ne.status,
                     logs: ne.metadata&.dig("logs") || ne.output_data&.dig("logs") || "",
                     started_at: ne.started_at&.iso8601,
                     completed_at: ne.completed_at&.iso8601
                   }
                 end
        end

        {
          output: {
            run_id: run.run_id,
            logs: logs.is_a?(Array) ? nil : logs,
            job_logs: logs.is_a?(Array) ? logs : nil
          }.compact
        }
      end

      # Cancel pipeline run
      def cancel_run(input, task = nil)
        run = find_run(input["run_id"])

        unless run.active?
          raise ArgumentError, "Run cannot be cancelled in #{run.status} status"
        end

        run.cancel!(reason: input["reason"])

        {
          output: {
            success: true,
            run_id: run.run_id,
            status: run.status
          }
        }
      end

      # Get pipeline run status
      def get_run_status(input, task = nil)
        run = find_run(input["run_id"])

        {
          output: {
            run_id: run.run_id,
            status: run.status,
            total_nodes: run.total_nodes,
            completed_nodes: run.completed_nodes,
            failed_nodes: run.failed_nodes,
            current_node: run.current_node_id,
            started_at: run.started_at&.iso8601,
            duration_ms: run.duration_ms
          }
        }
      end

      private

      def find_pipeline(id)
        @account.ai_workflows.where(workflow_type: "cicd").find(id)
      end

      def find_run(run_id)
        @account.ai_workflow_runs.find_by!(run_id: run_id)
      end

      def pipeline_summary(pipeline)
        {
          id: pipeline.id,
          name: pipeline.name,
          description: pipeline.description,
          status: pipeline.status,
          execution_count: pipeline.execution_count,
          last_executed_at: pipeline.last_executed_at&.iso8601,
          created_at: pipeline.created_at.iso8601
        }
      end
    end
  end
end
