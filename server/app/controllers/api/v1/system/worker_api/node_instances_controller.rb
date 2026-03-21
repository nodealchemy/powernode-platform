# frozen_string_literal: true

module Api
  module V1
    module System
      module WorkerApi
        # Node instance lifecycle management for infrastructure workers
        # Handles instance CRUD and state transitions
        class NodeInstancesController < BaseController
          before_action :set_instance, only: [:show, :update, :destroy, :start, :stop, :reboot, :sync, :maintenance]

          # GET /api/v1/system/worker_api/node_instances
          # List instances for nodes managed by this worker
          def index
            authorize_worker_permission!("system.node_instances.read")

            instances = ::System::NodeInstance
                        .joins(:node)
                        .where(system_nodes: { worker_id: current_worker.id })
            instances = apply_filters(instances)
            instances = paginate(instances.includes(:node, :provider_region))

            render_success(
              instances: instances.map { |i| serialize_instance(i) },
              meta: pagination_meta
            )
          end

          # GET /api/v1/system/worker_api/node_instances/:id
          def show
            authorize_worker_permission!("system.node_instances.read")
            render_success(instance: serialize_instance_full(@instance))
          end

          # POST /api/v1/system/worker_api/node_instances
          # Create new instance (typically from provisioning job)
          def create
            authorize_worker_permission!("system.node_instances.create")

            node = ::System::Node.where(worker: current_worker).find(params[:node_id])
            instance = node.node_instances.build(instance_params)

            if instance.save
              render_success(instance: serialize_instance(instance), status: :created)
            else
              render_validation_error(instance)
            end
          rescue ActiveRecord::RecordNotFound
            render_record_not_found("Node")
          end

          # PUT /api/v1/system/worker_api/node_instances/:id
          # Update instance (IP addresses, cloud IDs, status)
          def update
            authorize_worker_permission!("system.node_instances.update")

            if @instance.update(instance_update_params)
              render_success(instance: serialize_instance(@instance))
            else
              render_validation_error(@instance)
            end
          end

          # DELETE /api/v1/system/worker_api/node_instances/:id
          def destroy
            authorize_worker_permission!("system.node_instances.delete")

            if @instance.destroy
              render_success(message: "Instance deleted successfully")
            else
              render_error("Failed to delete instance: #{@instance.errors.full_messages.join(', ')}")
            end
          end

          # POST /api/v1/system/worker_api/node_instances/:id/start
          def start
            authorize_worker_permission!("system.node_instances.manage")
            execute_instance_action(:start)
          end

          # POST /api/v1/system/worker_api/node_instances/:id/stop
          def stop
            authorize_worker_permission!("system.node_instances.manage")
            execute_instance_action(:stop)
          end

          # POST /api/v1/system/worker_api/node_instances/:id/reboot
          def reboot
            authorize_worker_permission!("system.node_instances.manage")
            execute_instance_action(:reboot)
          end

          # POST /api/v1/system/worker_api/node_instances/:id/sync
          # Sync instance configuration
          def sync
            authorize_worker_permission!("system.node_instances.manage")
            execute_instance_action(:sync)
          end

          # POST /api/v1/system/worker_api/node_instances/:id/maintenance
          # Run maintenance tasks (sync cloud state)
          def maintenance
            authorize_worker_permission!("system.node_instances.manage")

            service = ::System::InstanceMaintenanceService.new(@instance)
            result = service.perform_maintenance

            if result[:success]
              render_success(
                instance: serialize_instance(@instance.reload),
                maintenance_result: result
              )
            else
              render_error(result[:error] || "Maintenance failed")
            end
          end

          private

          def set_instance
            @instance = ::System::NodeInstance
                        .joins(:node)
                        .where(system_nodes: { worker_id: current_worker.id })
                        .find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_record_not_found("NodeInstance")
          end

          def instance_params
            params.require(:instance).permit(
              :name, :variety, :status,
              :provider_region_id, :provider_instance_type_id,
              :provider_availability_zone_id,
              :private_ip_address, :public_ip_address,
              :cloud_instance_id,
              config: {}
            )
          end

          def instance_update_params
            params.require(:instance).permit(
              :status,
              :private_ip_address, :public_ip_address,
              :cloud_instance_id,
              config: {}
            )
          end

          def apply_filters(scope)
            scope = scope.where(variety: params[:variety]) if params[:variety].present?
            scope = scope.where(status: params[:status]) if params[:status].present?
            scope = scope.where(node_id: params[:node_id]) if params[:node_id].present?
            scope.order(created_at: :desc)
          end

          def execute_instance_action(action)
            service = ::System::InstanceControlService.new(@instance)
            result = service.public_send(action)

            if result[:success]
              render_success(
                instance: serialize_instance(@instance.reload),
                action: action,
                result: result
              )
            else
              render_error(result[:error] || "#{action.to_s.humanize} failed")
            end
          end

          def serialize_instance(instance)
            {
              id: instance.id,
              name: instance.name,
              node_id: instance.node_id,
              variety: instance.variety,
              status: instance.status,
              private_ip_address: instance.private_ip_address,
              public_ip_address: instance.public_ip_address,
              cloud_instance_id: instance.cloud_instance_id,
              provider_region_id: instance.provider_region_id,
              created_at: instance.created_at,
              updated_at: instance.updated_at
            }
          end

          def serialize_instance_full(instance)
            serialize_instance(instance).merge(
              node: {
                id: instance.node.id,
                name: instance.node.name,
                template_id: instance.node.node_template_id
              },
              config: instance.config,
              provider_region: instance.provider_region ? {
                id: instance.provider_region.id,
                name: instance.provider_region.name,
                region_code: instance.provider_region.region_code
              } : nil,
              provider_instance_type: instance.provider_instance_type ? {
                id: instance.provider_instance_type.id,
                name: instance.provider_instance_type.name
              } : nil
            )
          end
        end
      end
    end
  end
end
