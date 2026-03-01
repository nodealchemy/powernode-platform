# frozen_string_literal: true

module A2a
  module Skills
    class ContainerSkills
      class << self
        def execute(account:, user:, params:)
          template = Devops::ContainerTemplate.find(params[:template_id])

          # Verify access
          unless template.accessible_by?(account)
            raise SecurityError, "Access denied to container template"
          end

          # Check quotas
          quota_service = Devops::QuotaService.new(account)
          quota_service.check_execution_allowed!

          # Create container instance
          orchestrator = Devops::ContainerOrchestrationService.new(account: account, user: user)
          instance = orchestrator.execute(
            template: template,
            input_parameters: params[:input_parameters],
            timeout_seconds: params[:timeout_seconds]
          )

          {
            execution_id: instance.execution_id,
            status: instance.status
          }
        end

        def get_status(account:, user:, params:)
          instance = Devops::ContainerInstance
                       .where(account: account)
                       .find_by!(execution_id: params[:execution_id])

          {
            status: instance.status,
            output: instance.output_data,
            logs: instance.logs&.truncate(10_000),
            artifacts: instance.artifacts,
            duration_ms: instance.duration_ms,
            exit_code: instance.exit_code,
            error: instance.error_message
          }
        end

        def list_templates(account:, user:, params:)
          templates = Devops::ContainerTemplate.accessible_by(account)

          if params[:visibility].present?
            templates = templates.where(visibility: params[:visibility])
          end

          templates = templates.where(status: "active")

          {
            templates: templates.map(&:template_summary)
          }
        end
      end
    end
  end
end
