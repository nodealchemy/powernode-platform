# frozen_string_literal: true

module Api
  module V1
    module System
      class NodeTemplatesController < BaseController
        before_action :set_account
        before_action :set_template, only: [:show, :update, :destroy]

        def index
          authorize_permission!("system.templates.read")
          templates = @account.system_node_templates.includes(:node_platform)
          templates = apply_filters(templates)
          templates = paginate(templates)
          render_success(node_templates: serialize_collection(templates), meta: pagination_meta)
        end

        def show
          authorize_permission!("system.templates.read")
          render_success(node_template: serialize_template(@template))
        end

        def create
          authorize_permission!("system.templates.create")
          template = @account.system_node_templates.build(template_params)

          if template.save
            render_success(node_template: serialize_template(template), status: :created)
          else
            render_validation_error(template)
          end
        end

        def update
          authorize_permission!("system.templates.update")

          if @template.update(template_params)
            render_success(node_template: serialize_template(@template))
          else
            render_validation_error(@template)
          end
        end

        def destroy
          authorize_permission!("system.templates.delete")

          if @template.destroy
            render_success(message: "Template deleted successfully")
          else
            render_error("Failed to delete template", status: :unprocessable_entity)
          end
        end

        private

        def set_template
          @template = @account.system_node_templates.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Node Template")
        end

        def template_params
          params.require(:node_template).permit(
            :name, :description, :enabled, :public, :node_platform_id, :admin_user,
            config: {}
          )
        end

        def apply_filters(scope)
          scope = scope.enabled if params[:enabled] == "true"
          scope = scope.disabled if params[:enabled] == "false"
          scope = scope.public_access if params[:public] == "true"
          scope = scope.where(node_platform_id: params[:platform_id]) if params[:platform_id].present?
          scope.ordered
        end

        def serialize_template(template)
          ::System::NodeTemplateSerializer.new(template).as_json
        end

        def serialize_collection(templates)
          templates.map { |t| serialize_template(t) }
        end
      end
    end
  end
end
