# frozen_string_literal: true

module Api
  module V1
    module System
      class NodeArchitecturesController < BaseController
        before_action :set_account
        before_action :set_architecture, only: [:show, :update, :destroy]

        def index
          authorize_permission!("system.architectures.read")
          architectures = @account.system_node_architectures
          architectures = apply_filters(architectures)
          architectures = paginate(architectures)
          render_success(node_architectures: serialize_collection(architectures), meta: pagination_meta)
        end

        def show
          authorize_permission!("system.architectures.read")
          render_success(node_architecture: serialize_architecture(@architecture))
        end

        def create
          authorize_permission!("system.architectures.create")
          architecture = @account.system_node_architectures.build(architecture_params)

          if architecture.save
            render_success(node_architecture: serialize_architecture(architecture), status: :created)
          else
            render_validation_error(architecture)
          end
        end

        def update
          authorize_permission!("system.architectures.update")

          if @architecture.update(architecture_params)
            render_success(node_architecture: serialize_architecture(@architecture))
          else
            render_validation_error(@architecture)
          end
        end

        def destroy
          authorize_permission!("system.architectures.delete")

          if @architecture.destroy
            render_success(message: "Architecture deleted successfully")
          else
            render_error("Failed to delete architecture", status: :unprocessable_entity)
          end
        end

        private

        def set_architecture
          @architecture = @account.system_node_architectures.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Node Architecture")
        end

        def architecture_params
          params.require(:node_architecture).permit(
            :name, :description, :enabled, :public, :kernel_options,
            :kernel_file_object_id, :ramdisk_file_object_id, :image_file_object_id
          )
        end

        def apply_filters(scope)
          scope = scope.enabled if params[:enabled] == "true"
          scope = scope.disabled if params[:enabled] == "false"
          scope = scope.public_access if params[:public] == "true"
          scope.ordered
        end

        def serialize_architecture(architecture)
          ::System::NodeArchitectureSerializer.new(architecture).as_json
        end

        def serialize_collection(architectures)
          architectures.map { |a| serialize_architecture(a) }
        end
      end
    end
  end
end
