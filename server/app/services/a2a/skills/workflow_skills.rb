# frozen_string_literal: true

module A2a
  module Skills
    # WorkflowSkills - A2A skill implementations for workflow operations
    class WorkflowSkills
      def initialize(account:, user: nil)
        @account = account
        @user = user
      end

      # List workflows
      def list(input, task = nil)
        scope = @account.ai_workflows.order(created_at: :desc)

        scope = scope.where(status: input["status"]) if input["status"].present?
        scope = scope.where(workflow_type: input["workflow_type"]) if input["workflow_type"].present?

        page = (input["page"] || 1).to_i
        per_page = [(input["per_page"] || 20).to_i, 100].min

        workflows = scope.offset((page - 1) * per_page).limit(per_page)

        {
          output: {
            workflows: workflows.map { |w| workflow_summary(w) },
            total: scope.count,
            page: page,
            per_page: per_page
          }
        }
      end

      # Get workflow details
      def get(input, task = nil)
        workflow = find_workflow(input["workflow_id"])

        {
          output: {
            workflow: workflow_details(workflow)
          }
        }
      end

      # Execute workflow
      def execute(input, task = nil)
        workflow = find_workflow(input["workflow_id"])

        unless workflow.can_execute?
          raise ArgumentError, "Workflow cannot be executed in #{workflow.status} status"
        end

        run = workflow.start_run!(
          input_variables: input["input_variables"] || {},
          triggered_by_user: @user,
          trigger_type: "api_call"
        )

        if input["async"] == false
          # Wait for completion
          deadline = Time.current + 300
          loop do
            run.reload
            break if run.finished? || Time.current > deadline
            sleep 1
          end
        end

        {
          output: {
            run_id: run.run_id,
            status: run.status,
            output: run.output_variables
          }
        }
      end

      # Create workflow
      def create(input, task = nil)
        workflow = @account.ai_workflows.create!(
          name: input["name"],
          description: input["description"],
          workflow_type: input["workflow_type"] || "ai",
          status: "draft",
          creator: @user
        )

        # Add nodes if provided
        if input["nodes"].present?
          input["nodes"].each do |node_data|
            workflow.workflow_nodes.create!(node_data.symbolize_keys)
          end
        end

        # Add edges if provided
        if input["edges"].present?
          input["edges"].each do |edge_data|
            workflow.workflow_edges.create!(edge_data.symbolize_keys)
          end
        end

        {
          output: {
            workflow: workflow_details(workflow)
          }
        }
      end

      # List workflow runs
      def list_runs(input, task = nil)
        scope = @account.ai_workflow_runs.order(created_at: :desc)

        scope = scope.for_workflow(input["workflow_id"]) if input["workflow_id"].present?
        scope = scope.where(status: input["status"]) if input["status"].present?

        page = (input["page"] || 1).to_i
        per_page = [(input["per_page"] || 20).to_i, 100].min

        runs = scope.offset((page - 1) * per_page).limit(per_page)

        {
          output: {
            runs: runs.map { |r| run_summary(r) },
            total: scope.count,
            page: page,
            per_page: per_page
          }
        }
      end

      # Get workflow run
      def get_run(input, task = nil)
        run = find_run(input["run_id"])

        {
          output: {
            run: run_details(run)
          }
        }
      end

      # Cancel workflow run
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

      private

      def find_workflow(id)
        @account.ai_workflows.find(id)
      end

      def find_run(run_id)
        @account.ai_workflow_runs.find_by!(run_id: run_id)
      end

      def workflow_summary(workflow)
        {
          id: workflow.id,
          name: workflow.name,
          description: workflow.description,
          status: workflow.status,
          workflow_type: workflow.workflow_type,
          execution_count: workflow.execution_count,
          created_at: workflow.created_at.iso8601
        }
      end

      def workflow_details(workflow)
        workflow_summary(workflow).merge(
          nodes: workflow.workflow_nodes.map { |n| { id: n.id, node_id: n.node_id, node_type: n.node_type, name: n.name } },
          edges: workflow.workflow_edges.count,
          variables: workflow.workflow_variables.count,
          last_executed_at: workflow.last_executed_at&.iso8601
        )
      end

      def run_summary(run)
        {
          run_id: run.run_id,
          workflow_id: run.ai_workflow_id,
          status: run.status,
          trigger_type: run.trigger_type,
          started_at: run.started_at&.iso8601,
          completed_at: run.completed_at&.iso8601,
          duration_ms: run.duration_ms
        }
      end

      def run_details(run)
        run_summary(run).merge(
          input_variables: run.input_variables,
          output_variables: run.output_variables,
          total_nodes: run.total_nodes,
          completed_nodes: run.completed_nodes,
          failed_nodes: run.failed_nodes,
          total_cost: run.total_cost
        )
      end
    end
  end
end
