# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class ScanInstancesController < BaseController
        before_action :set_scan_instance, only: [:show, :update, :destroy, :execute, :executions]

        # GET /api/v1/supply_chain/scan_instances
        def index
          @instances = current_account.supply_chain_scan_instances
                                      .includes(:scan_template, :created_by)
                                      .order(created_at: :desc)

          @instances = @instances.where(is_active: true) if params[:active_only] == "true"

          @instances = paginate(@instances)

          render_success(
            scan_instances: @instances.map { |i| serialize_instance(i) },
            meta: pagination_meta(@instances)
          )
        end

        # GET /api/v1/supply_chain/scan_instances/:id
        def show
          render_success(scan_instance: serialize_instance(@instance, include_details: true))
        end

        # POST /api/v1/supply_chain/scan_instances
        def create
          @instance = current_account.supply_chain_scan_instances.build(instance_params)
          @instance.created_by = current_user

          if @instance.save
            render_success(scan_instance: serialize_instance(@instance), status: :created)
          else
            render_error(@instance.errors.full_messages.join(", "), status: :unprocessable_entity)
          end
        end

        # PATCH/PUT /api/v1/supply_chain/scan_instances/:id
        def update
          if @instance.update(instance_params)
            render_success(scan_instance: serialize_instance(@instance))
          else
            render_error(@instance.errors.full_messages.join(", "), status: :unprocessable_entity)
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
            render_error("target_type and target_id are required", status: :unprocessable_entity)
            return
          end

          execution = @instance.scan_executions.create!(
            account: current_account,
            target_type: target_type,
            target_id: target_id,
            triggered_by: current_user,
            status: "pending",
            configuration: @instance.merged_configuration
          )

          # Queue the execution
          ::SupplyChain::ScanExecutionJob.perform_later(execution.id)

          render_success(
            scan_execution: serialize_execution(execution),
            message: "Scan execution queued"
          )
        rescue StandardError => e
          render_error("Failed to execute scan: #{e.message}", status: :unprocessable_entity)
        end

        # GET /api/v1/supply_chain/scan_instances/:id/executions
        def executions
          @executions = @instance.scan_executions
                                 .order(created_at: :desc)

          @executions = @executions.where(status: params[:status]) if params[:status].present?

          @executions = paginate(@executions)

          render_success(
            scan_executions: @executions.map { |e| serialize_execution(e) },
            meta: pagination_meta(@executions)
          )
        end

        private

        def set_scan_instance
          @instance = current_account.supply_chain_scan_instances.find(params[:id])
        end

        def instance_params
          params.require(:scan_instance).permit(
            :name, :description, :scan_template_id, :is_active,
            :schedule_cron, :auto_remediate,
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
            is_active: instance.is_active,
            schedule_cron: instance.schedule_cron,
            last_run_at: instance.last_run_at,
            next_run_at: instance.next_run_at,
            execution_count: instance.scan_executions.count,
            created_at: instance.created_at
          }

          if include_details
            data[:configuration] = instance.configuration
            data[:auto_remediate] = instance.auto_remediate
            data[:recent_executions] = instance.scan_executions.order(created_at: :desc).limit(5).map { |e| serialize_execution(e) }
            data[:metadata] = instance.metadata
          end

          data
        end

        def serialize_execution(execution)
          {
            id: execution.id,
            status: execution.status,
            target_type: execution.target_type,
            target_id: execution.target_id,
            started_at: execution.started_at,
            completed_at: execution.completed_at,
            duration_seconds: execution.duration_seconds,
            findings_count: execution.findings_count,
            error_message: execution.error_message,
            created_at: execution.created_at
          }
        end
      end
    end
  end
end
