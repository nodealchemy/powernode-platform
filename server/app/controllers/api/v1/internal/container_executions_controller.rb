# frozen_string_literal: true

module Api
  module V1
    module Internal
      class ContainerExecutionsController < ApplicationController
        # Worker service authentication
        skip_before_action :authenticate_request
        before_action :authenticate_worker!

        # POST /api/v1/internal/container_executions/:execution_id/complete
        # Callback from Gitea workflow when container execution completes
        def complete
          instance = find_instance

          service = ::Devops::ContainerOrchestrationService.new(
            account: instance.account,
            user: instance.triggered_by
          )

          service.handle_completion(
            params[:execution_id],
            {
              status: params[:status],
              exit_code: params[:exit_code],
              output: params[:output],
              logs: params[:logs],
              artifacts: params[:artifacts],
              error: params[:error]
            }
          )

          render_success({ status: "ok" })
        rescue ActiveRecord::RecordNotFound
          render_error("Execution not found", status: :not_found)
        rescue StandardError => e
          Rails.logger.error "Container execution callback error: #{e.message}"
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/internal/container_executions/:execution_id/status
        # Update execution status (from Gitea workflow)
        def status
          instance = find_instance

          case params[:status]
          when "running"
            instance.start_running!
          when "provisioning"
            instance.start_provisioning!
          end

          render_success({ status: "ok", instance_status: instance.status })
        rescue ActiveRecord::RecordNotFound
          render_error("Execution not found", status: :not_found)
        end

        # POST /api/v1/internal/container_executions/:execution_id/logs
        # Append logs to execution (streaming logs from Gitea workflow)
        def logs
          instance = find_instance
          instance.append_logs(params[:logs]) if params[:logs].present?

          render_success({ status: "ok" })
        rescue ActiveRecord::RecordNotFound
          render_error("Execution not found", status: :not_found)
        end

        # POST /api/v1/internal/container_executions/:execution_id/resource_usage
        # Record resource usage metrics
        def resource_usage
          instance = find_instance

          instance.record_resource_usage(
            memory_mb: params[:memory_mb]&.to_i,
            cpu_millicores: params[:cpu_millicores]&.to_i,
            storage_bytes: params[:storage_bytes]&.to_i,
            network_in: params[:network_bytes_in]&.to_i,
            network_out: params[:network_bytes_out]&.to_i
          )

          render_success({ status: "ok" })
        rescue ActiveRecord::RecordNotFound
          render_error("Execution not found", status: :not_found)
        end

        # POST /api/v1/internal/container_executions/:execution_id/security_violation
        # Record security violation detected during execution
        def security_violation
          instance = find_instance

          instance.record_security_violation!(
            type: params[:violation_type],
            description: params[:description],
            severity: params[:severity],
            details: params[:details]&.to_unsafe_h || {}
          )

          # If critical violation, cancel the execution
          if params[:severity] == "critical"
            instance.fail!("Critical security violation: #{params[:violation_type]}")
            ::Devops::QuotaService.new(instance.account).decrement_running!
          end

          render_success({ status: "ok" })
        rescue ActiveRecord::RecordNotFound
          render_error("Execution not found", status: :not_found)
        end

        # GET /api/v1/internal/container_executions/:execution_id
        # Get execution details (for Gitea workflow to fetch configuration)
        def show
          instance = find_instance

          render_success({
            execution_id: instance.execution_id,
            image_name: instance.image_name,
            image_tag: instance.image_tag,
            timeout_seconds: instance.timeout_seconds,
            environment_variables: instance.environment_variables,
            input_parameters: instance.input_parameters,
            sandbox_enabled: instance.sandbox_enabled,
            runner_labels: instance.runner_labels
          })
        rescue ActiveRecord::RecordNotFound
          render_error("Execution not found", status: :not_found)
        end

        private

        def find_instance
          ::Devops::ContainerInstance.find_by!(execution_id: params[:execution_id])
        end

        def authenticate_worker!
          token = request.headers["Authorization"]&.split(" ")&.last
          return render_error("Unauthorized", status: :unauthorized) unless token

          begin
            payload = Security::JwtService.decode(token)
            worker = Worker.find_by(id: payload[:sub]) if payload[:type] == "worker"
          rescue StandardError
            worker = nil
          end

          unless worker&.active?
            render_error("Unauthorized", status: :unauthorized)
          end
        end
      end
    end
  end
end
