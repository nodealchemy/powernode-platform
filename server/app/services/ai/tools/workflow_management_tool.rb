# frozen_string_literal: true

module Ai
  module Tools
    class WorkflowManagementTool < BaseTool
      REQUIRED_PERMISSION = "ai.workflows.execute"

      def self.definition
        {
          name: "workflow_management",
          description: "Create, list, get, update, or execute AI workflows",
          parameters: {
            action: { type: "string", required: true, description: "Action: create_workflow, list_workflows, get_workflow, update_workflow, execute_workflow" },
            workflow_id: { type: "string", required: false },
            name: { type: "string", required: false },
            description: { type: "string", required: false },
            input: { type: "object", required: false },
            status: { type: "string", required: false, description: "Workflow status (for update)" }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "create_workflow" then create_workflow(params)
        when "execute_workflow" then execute_workflow(params)
        when "list_workflows" then list_workflows
        when "get_workflow" then get_workflow(params)
        when "update_workflow" then update_workflow(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      end

      private

      def create_workflow(params)
        workflow = account.ai_workflows.create!(
          name: params[:name],
          description: params[:description],
          status: "active",
          version: "1.0.0",
          slug: params[:name]&.parameterize
        )
        { success: true, workflow_id: workflow.id, name: workflow.name }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end

      def execute_workflow(params)
        workflow = account.ai_workflows.find(params[:workflow_id])
        { success: true, workflow_id: workflow.id, status: "execution_queued" }
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Workflow not found" }
      end

      def list_workflows
        workflows = account.ai_workflows.where(status: "active").limit(50)
        { success: true, workflows: workflows.map { |w| { id: w.id, name: w.name, status: w.status } } }
      end

      def get_workflow(params)
        workflow = account.ai_workflows.find(params[:workflow_id])
        {
          success: true,
          workflow: {
            id: workflow.id,
            name: workflow.name,
            slug: workflow.slug,
            description: workflow.description,
            status: workflow.status,
            version: workflow.version,
            created_at: workflow.created_at&.iso8601,
            updated_at: workflow.updated_at&.iso8601
          }
        }
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Workflow not found" }
      end

      def update_workflow(params)
        workflow = account.ai_workflows.find(params[:workflow_id])
        attrs = {}
        attrs[:name] = params[:name] if params[:name].present?
        attrs[:description] = params[:description] if params[:description].present?
        attrs[:status] = params[:status] if params[:status].present?
        workflow.update!(attrs)
        { success: true, workflow_id: workflow.id, name: workflow.name }
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Workflow not found" }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end
    end
  end
end
