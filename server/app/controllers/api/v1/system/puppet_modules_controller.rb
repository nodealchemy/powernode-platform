# frozen_string_literal: true

module Api
  module V1
    module System
      class PuppetModulesController < BaseController
        before_action :set_puppet_module, only: [:show, :update, :destroy, :resources, :assignments]

        # GET /api/v1/system/puppet_modules
        def index
          authorize_permission!('system.puppet.read')

          modules = current_account.system_puppet_modules
          modules = apply_filters(modules)
          modules = paginate(modules.includes(:puppet_resources).order(name: :asc))

          render_success(
            puppet_modules: modules.map { |m| ::System::PuppetModuleSerializer.new(m).as_json },
            meta: pagination_meta
          )
        end

        # GET /api/v1/system/puppet_modules/:id
        def show
          authorize_permission!('system.puppet.read')
          render_success(puppet_module: ::System::PuppetModuleSerializer.new(@puppet_module).as_json)
        end

        # POST /api/v1/system/puppet_modules
        def create
          authorize_permission!('system.puppet.create')

          puppet_module = current_account.system_puppet_modules.build(puppet_module_params)

          if puppet_module.save
            render_success(puppet_module: ::System::PuppetModuleSerializer.new(puppet_module).as_json, status: :created)
          else
            render_validation_error(puppet_module)
          end
        end

        # PATCH/PUT /api/v1/system/puppet_modules/:id
        def update
          authorize_permission!('system.puppet.update')

          if @puppet_module.update(puppet_module_params)
            render_success(puppet_module: ::System::PuppetModuleSerializer.new(@puppet_module).as_json)
          else
            render_validation_error(@puppet_module)
          end
        end

        # DELETE /api/v1/system/puppet_modules/:id
        def destroy
          authorize_permission!('system.puppet.delete')

          if @puppet_module.module_puppet_assignments.exists?
            render_error('Cannot delete puppet module that is assigned to node modules', status: :unprocessable_entity)
          else
            @puppet_module.destroy
            render_success(message: 'Puppet module deleted successfully')
          end
        end

        # GET /api/v1/system/puppet_modules/:id/resources
        def resources
          authorize_permission!('system.puppet.read')

          resources = @puppet_module.puppet_resources
          resources = resources.enabled if params[:enabled] == 'true'
          resources = resources.by_type(params[:resource_type]) if params[:resource_type].present?
          resources = resources.search(params[:search]) if params[:search].present?

          render_success(
            puppet_resources: resources.map { |r| ::System::PuppetResourceSerializer.new(r).as_json }
          )
        end

        # GET /api/v1/system/puppet_modules/:id/assignments
        def assignments
          authorize_permission!('system.puppet.read')

          assignments = @puppet_module.module_puppet_assignments
                                       .includes(:node_module)
                                       .by_priority

          render_success(
            assignments: assignments.map { |a| ::System::ModulePuppetAssignmentSerializer.new(a).as_json }
          )
        end

        private

        def set_puppet_module
          @puppet_module = current_account.system_puppet_modules.find(params[:id])
        end

        def puppet_module_params
          params.require(:puppet_module).permit(
            :name, :description, :enabled, :public, :version, :author, :license,
            :source_url, :project_url, :forge_name,
            dependencies: [:name, :version_requirement],
            config: {},
            metadata: {}
          )
        end

        def apply_filters(modules)
          modules = modules.enabled if params[:enabled] == 'true'
          modules = modules.disabled if params[:enabled] == 'false'
          modules = modules.public_modules if params[:public] == 'true'
          modules = modules.private_modules if params[:public] == 'false'
          modules = modules.from_forge if params[:from_forge] == 'true'
          modules = modules.by_author(params[:author]) if params[:author].present?
          modules = modules.search(params[:search]) if params[:search].present?
          modules
        end
      end
    end
  end
end
