# frozen_string_literal: true

module Api
  module V1
    module System
      class NodePlatformsController < BaseController
        before_action :set_account
        before_action :set_platform, only: [:show, :update, :destroy]

        def index
          authorize_permission!("system.platforms.read")
          platforms = @account.system_node_platforms.includes(:node_architecture)
          platforms = apply_filters(platforms)
          platforms = paginate(platforms)
          render_success(node_platforms: serialize_collection(platforms), meta: pagination_meta)
        end

        def show
          authorize_permission!("system.platforms.read")
          render_success(node_platform: serialize_platform(@platform))
        end

        def create
          authorize_permission!("system.platforms.create")
          platform = @account.system_node_platforms.build(platform_params)

          if platform.save
            render_success(node_platform: serialize_platform(platform), status: :created)
          else
            render_validation_error(platform)
          end
        end

        def update
          authorize_permission!("system.platforms.update")

          if @platform.update(platform_params)
            render_success(node_platform: serialize_platform(@platform))
          else
            render_validation_error(@platform)
          end
        end

        def destroy
          authorize_permission!("system.platforms.delete")

          if @platform.destroy
            render_success(message: "Platform deleted successfully")
          else
            render_error("Failed to delete platform", status: :unprocessable_entity)
          end
        end

        private

        def set_platform
          @platform = @account.system_node_platforms.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Node Platform")
        end

        def platform_params
          params.require(:node_platform).permit(
            :name, :description, :enabled, :public, :node_architecture_id,
            :build_script, :init_script, :sync_script
          )
        end

        def apply_filters(scope)
          scope = scope.enabled if params[:enabled] == "true"
          scope = scope.disabled if params[:enabled] == "false"
          scope = scope.public_access if params[:public] == "true"
          scope = scope.where(node_architecture_id: params[:architecture_id]) if params[:architecture_id].present?
          scope.ordered
        end

        def serialize_platform(platform)
          ::System::NodePlatformSerializer.new(platform).as_json
        end

        def serialize_collection(platforms)
          platforms.map { |p| serialize_platform(p) }
        end
      end
    end
  end
end
