# frozen_string_literal: true

module Api
  module V1
    module System
      class NodeScriptsController < BaseController
        before_action :set_account
        before_action :set_script, only: [:show, :update, :destroy]

        def index
          authorize_permission!("system.scripts.read")
          scripts = @account.system_node_scripts
          scripts = apply_filters(scripts)
          scripts = paginate(scripts)
          render_success(node_scripts: serialize_collection(scripts), meta: pagination_meta)
        end

        def show
          authorize_permission!("system.scripts.read")
          render_success(node_script: serialize_script(@script))
        end

        def create
          authorize_permission!("system.scripts.create")
          script = @account.system_node_scripts.build(script_params)

          if script.save
            render_success(node_script: serialize_script(script), status: :created)
          else
            render_validation_error(script)
          end
        end

        def update
          authorize_permission!("system.scripts.update")

          if @script.update(script_params)
            render_success(node_script: serialize_script(@script))
          else
            render_validation_error(@script)
          end
        end

        def destroy
          authorize_permission!("system.scripts.delete")

          if @script.destroy
            render_success(message: "Script deleted successfully")
          else
            render_error("Failed to delete script", status: :unprocessable_entity)
          end
        end

        private

        def set_script
          @script = @account.system_node_scripts.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Node Script")
        end

        def script_params
          params.require(:node_script).permit(
            :name, :description, :enabled, :public, :variety, :data
          )
        end

        def apply_filters(scope)
          scope = scope.enabled if params[:enabled] == "true"
          scope = scope.disabled if params[:enabled] == "false"
          scope = scope.public_access if params[:public] == "true"
          scope = scope.where(variety: params[:variety]) if params[:variety].present?
          scope.ordered
        end

        def serialize_script(script)
          ::System::NodeScriptSerializer.new(script).as_json
        end

        def serialize_collection(scripts)
          scripts.map { |s| serialize_script(s) }
        end
      end
    end
  end
end
