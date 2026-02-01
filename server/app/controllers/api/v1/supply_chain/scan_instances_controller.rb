# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class ScanInstancesController < BaseController
        before_action :require_read_permission, only: [:index, :show, :executions]
        before_action :require_write_permission, only: [:create, :update, :destroy, :execute]
        before_action :set_scan_instance, only: [:show, :update, :destroy, :execute, :executions]

        # GET /api/v1/supply_chain/scan_instances
        def index
          @instances = current_account.supply_chain_scan_instances
                                      .includes(:scan_template, :installed_by)
                                      .order(created_at: :desc)

          @instances = @instances.where(status: "active") if params[:active_only] == "true"

          @instances = paginate(@instances)

          render_success(
            { scan_instances: @instances.map { |i| serialize_instance(i) } },
            meta: pagination_meta
          )
        end

        # GET /api/v1/supply_chain/scan_instances/:id
        def show
          render_success({ scan_instance: serialize_instance(@instance, include_details: true) })
        end

        # POST /api/v1/supply_chain/scan_instances
        def create
          @instance = current_account.supply_chain_scan_instances.build(instance_params)
          @instance.installed_by = current_user

          if @instance.save
            render_success({ scan_instance: serialize_instance(@instance) }, status: :created)
          else
            render_error(@instance.errors.full_messages.join(", "), status: :unprocessable_content)
          end
        end

        # PATCH/PUT /api/v1/supply_chain/scan_instances/:id
        def update
          if @instance.update(instance_params)
            render_success({ scan_instance: serialize_instance(@instance) })
          else
            render_error(@instance.errors.full_messages.join(", "), status: :unprocessable_content)
          end
        end

        # DELETE /api/v1/supply_chain/scan_instances/:id
        def destroy
          @instance.destroy
          render_success(message: "Scan instance deleted")
        end

        # POST /api/v1/supply_chain/scan_instances/:id/execute
        def execute
          target_type = params[:target_type]
          target_id = params[:target_id]

          if target_type.blank? || target_id.blank?
            render_error("target_type and target_id are required", status: :unprocessable_content)
            return
          end

          execution = @instance.executions.create!(
            account: current_account,
            triggered_by: current_user,
            trigger_type: "manual",
            status: "pending",
            input_data: {
              target_type: target_type,
              target_id: target_id,
              configuration: @instance.configuration
            }
          )

          # Queue the execution
          ::SupplyChain::ScanExecutionJob.perform_later(execution.id)

          render_success(
            { scan_execution: serialize_execution(execution) },
            message: "Scan execution queued"
          )
        rescue StandardError => e
          render_error("Failed to execute scan: #{e.message}", status: :unprocessable_content)
        end

        # GET /api/v1/supply_chain/scan_instances/:id/executions
        def executions
          @executions = @instance.executions
                                 .order(created_at: :desc)

          @executions = @executions.where(status: params[:status]) if params[:status].present?

          @executions = paginate(@executions)

          render_success(
            { scan_executions: @executions.map { |e| serialize_execution(e) } },
            meta: pagination_meta
          )
        end

        private

        def set_scan_instance
          @instance = current_account.supply_chain_scan_instances.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Scan instance not found", status: :not_found)
        end

        def instance_params
          params.require(:scan_instance).permit(
            :name, :description, :scan_template_id, :status,
            :schedule_cron,
            configuration: {}, metadata: {}
          )
        end

        def serialize_instance(instance, include_details: false)
          data = {
            id: instance.id,
            name: instance.name,
            description: instance.description,
            scan_template_id: instance.scan_template_id,
            scan_template_name: instance.scan_template&.name,
            status: instance.status,
            schedule_cron: instance.schedule_cron,
            last_execution_at: instance.last_execution_at,
            next_execution_at: instance.next_execution_at,
            execution_count: instance.execution_count,
            success_count: instance.success_count,
            failure_count: instance.failure_count,
            created_at: instance.created_at
          }

          if include_details
            data[:configuration] = instance.configuration
            data[:recent_executions] = instance.executions.order(created_at: :desc).limit(5).map { |e| serialize_execution(e) }
            data[:metadata] = instance.metadata
          end

          data
        end

        def serialize_execution(execution)
          {
            id: execution.id,
            execution_id: execution.execution_id,
            status: execution.status,
            trigger_type: execution.trigger_type,
            target_type: execution.input_data["target_type"],
            target_id: execution.input_data["target_id"],
            started_at: execution.started_at,
            completed_at: execution.completed_at,
            duration_ms: execution.duration_ms,
            error_message: execution.error_message,
            created_at: execution.created_at
          }
        end
      end
    end
  end
end
