# frozen_string_literal: true

module Api
  module V1
    module System
      class NodeInstancesController < BaseController
        before_action :set_account
        before_action :set_node
        before_action :set_instance, only: [:show, :update, :destroy, :start, :stop, :reboot]

        def index
          authorize_permission!("system.instances.read")
          instances = @node.node_instances
          instances = apply_filters(instances)
          instances = paginate(instances)
          render_success(node_instances: serialize_collection(instances), meta: pagination_meta)
        end

        def show
          authorize_permission!("system.instances.read")
          render_success(node_instance: serialize_instance(@instance))
        end

        def create
          authorize_permission!("system.instances.create")
          instance = @node.node_instances.build(instance_params)

          if instance.save
            render_success(node_instance: serialize_instance(instance), status: :created)
          else
            render_validation_error(instance)
          end
        end

        def update
          authorize_permission!("system.instances.update")

          if @instance.update(instance_params)
            render_success(node_instance: serialize_instance(@instance))
          else
            render_validation_error(@instance)
          end
        end

        def destroy
          authorize_permission!("system.instances.delete")

          if @instance.destroy
            render_success(message: "Instance deleted successfully")
          else
            render_error("Failed to delete instance", status: :unprocessable_entity)
          end
        end

        # POST /api/v1/system/nodes/:node_id/node_instances/:id/start
        def start
          authorize_permission!("system.instances.control")

          if @instance.can_start?
            @instance.update!(status: "starting")
            # Create operation for tracking
            operation = create_instance_operation("start")
            render_success(
              node_instance: serialize_instance(@instance.reload),
              operation: operation ? ::System::OperationSerializer.new(operation).as_json : nil
            )
          else
            render_error("Cannot start instance in current state: #{@instance.status}", status: :unprocessable_entity)
          end
        end

        # POST /api/v1/system/nodes/:node_id/node_instances/:id/stop
        def stop
          authorize_permission!("system.instances.control")

          if @instance.can_stop?
            @instance.update!(status: "stopping")
            operation = create_instance_operation("stop")
            render_success(
              node_instance: serialize_instance(@instance.reload),
              operation: operation ? ::System::OperationSerializer.new(operation).as_json : nil
            )
          else
            render_error("Cannot stop instance in current state: #{@instance.status}", status: :unprocessable_entity)
          end
        end

        # POST /api/v1/system/nodes/:node_id/node_instances/:id/reboot
        def reboot
          authorize_permission!("system.instances.control")

          if @instance.can_reboot?
            @instance.update!(status: "rebooting")
            operation = create_instance_operation("reboot")
            render_success(
              node_instance: serialize_instance(@instance.reload),
              operation: operation ? ::System::OperationSerializer.new(operation).as_json : nil
            )
          else
            render_error("Cannot reboot instance in current state: #{@instance.status}", status: :unprocessable_entity)
          end
        end

        private

        def set_node
          @node = @account.system_nodes.find(params[:node_id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Node")
        end

        def set_instance
          @instance = @node.node_instances.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Node Instance")
        end

        def instance_params
          params.require(:node_instance).permit(
            :name, :description, :variety, :status, :key,
            :private_ip_address, :public_ip_address, :vpn_ip_address,
            config: {}
          )
        end

        def apply_filters(scope)
          scope = scope.where(variety: params[:variety]) if params[:variety].present?
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope
        end

        def serialize_instance(instance)
          ::System::NodeInstanceSerializer.new(instance).as_json
        end

        def serialize_collection(instances)
          instances.map { |i| serialize_instance(i) }
        end

        def create_instance_operation(command)
          return nil unless current_account.respond_to?(:system_operations)

          current_account.system_operations.create(
            command: command,
            description: "#{command.capitalize} node instance: #{@instance.name}",
            operable: @instance,
            initiated_by: current_user,
            status: "pending"
          )
        rescue StandardError => e
          Rails.logger.error "Failed to create operation: #{e.message}"
          nil
        end
      end
    end
  end
end
