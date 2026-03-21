# frozen_string_literal: true

module Api
  module V1
    module System
      class ModuleDependenciesController < BaseController
        before_action :set_node_module
        before_action :set_dependency, only: [:show, :update, :destroy]

        # GET /api/v1/system/node_modules/:node_module_id/dependencies
        def index
          authorize_permission!('system.modules.read')

          dependencies = @node_module.module_dependencies
          dependencies = apply_filters(dependencies)
          dependencies = paginate(dependencies.includes(:dependency))

          render_success(
            dependencies: dependencies.map { |d| ::System::ModuleDependencySerializer.new(d).as_json },
            meta: pagination_meta
          )
        end

        # GET /api/v1/system/node_modules/:node_module_id/dependencies/:id
        def show
          authorize_permission!('system.modules.read')
          render_success(dependency: ::System::ModuleDependencySerializer.new(@dependency).as_json)
        end

        # POST /api/v1/system/node_modules/:node_module_id/dependencies
        def create
          authorize_permission!('system.modules.update')

          dependency = @node_module.module_dependencies.build(dependency_params)

          if dependency.save
            render_success(dependency: ::System::ModuleDependencySerializer.new(dependency).as_json, status: :created)
          else
            render_validation_error(dependency)
          end
        end

        # PATCH/PUT /api/v1/system/node_modules/:node_module_id/dependencies/:id
        def update
          authorize_permission!('system.modules.update')

          if @dependency.update(dependency_params)
            render_success(dependency: ::System::ModuleDependencySerializer.new(@dependency).as_json)
          else
            render_validation_error(@dependency)
          end
        end

        # DELETE /api/v1/system/node_modules/:node_module_id/dependencies/:id
        def destroy
          authorize_permission!('system.modules.update')

          @dependency.destroy
          render_success(message: 'Dependency removed successfully')
        end

        private

        def set_node_module
          @node_module = current_account.system_node_modules.find(params[:node_module_id])
        end

        def set_dependency
          @dependency = @node_module.module_dependencies.find(params[:id])
        end

        def dependency_params
          params.require(:dependency).permit(:dependency_id, :dependency_type, :required, :version_constraint)
        end

        def apply_filters(dependencies)
          dependencies = dependencies.by_type(params[:type]) if params[:type].present?
          dependencies = dependencies.required if params[:required] == 'true'
          dependencies = dependencies.optional if params[:required] == 'false'
          dependencies
        end
      end
    end
  end
end
