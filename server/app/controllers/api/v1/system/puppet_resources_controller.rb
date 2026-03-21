# frozen_string_literal: true

module Api
  module V1
    module System
      class PuppetResourcesController < BaseController
        before_action :set_puppet_module
        before_action :set_puppet_resource, only: [:show, :update, :destroy, :puppet_dsl]

        # GET /api/v1/system/puppet_modules/:puppet_module_id/puppet_resources
        def index
          authorize_permission!('system.puppet.read')

          resources = @puppet_module.puppet_resources
          resources = apply_filters(resources)
          resources = paginate(resources.order(resource_type: :asc, name: :asc))

          render_success(
            puppet_resources: resources.map { |r| ::System::PuppetResourceSerializer.new(r).as_json },
            meta: pagination_meta
          )
        end

        # GET /api/v1/system/puppet_modules/:puppet_module_id/puppet_resources/:id
        def show
          authorize_permission!('system.puppet.read')
          render_success(puppet_resource: ::System::PuppetResourceSerializer.new(@puppet_resource).as_json)
        end

        # POST /api/v1/system/puppet_modules/:puppet_module_id/puppet_resources
        def create
          authorize_permission!('system.puppet.create')

          puppet_resource = @puppet_module.puppet_resources.build(puppet_resource_params)

          if puppet_resource.save
            render_success(puppet_resource: ::System::PuppetResourceSerializer.new(puppet_resource).as_json, status: :created)
          else
            render_validation_error(puppet_resource)
          end
        end

        # PATCH/PUT /api/v1/system/puppet_modules/:puppet_module_id/puppet_resources/:id
        def update
          authorize_permission!('system.puppet.update')

          if @puppet_resource.update(puppet_resource_params)
            render_success(puppet_resource: ::System::PuppetResourceSerializer.new(@puppet_resource).as_json)
          else
            render_validation_error(@puppet_resource)
          end
        end

        # DELETE /api/v1/system/puppet_modules/:puppet_module_id/puppet_resources/:id
        def destroy
          authorize_permission!('system.puppet.delete')
          @puppet_resource.destroy
          render_success(message: 'Puppet resource deleted successfully')
        end

        # GET /api/v1/system/puppet_modules/:puppet_module_id/puppet_resources/:id/puppet_dsl
        def puppet_dsl
          authorize_permission!('system.puppet.read')
          render_success(puppet_dsl: @puppet_resource.to_puppet_dsl)
        end

        private

        def set_puppet_module
          @puppet_module = current_account.system_puppet_modules.find(params[:puppet_module_id])
        end

        def set_puppet_resource
          @puppet_resource = @puppet_module.puppet_resources.find(params[:id])
        end

        def puppet_resource_params
          params.require(:puppet_resource).permit(
            :name, :description, :resource_type, :title, :path, :data,
            :enabled, :exported,
            parameters: {},
            config: {}
          )
        end

        def apply_filters(resources)
          resources = resources.enabled if params[:enabled] == 'true'
          resources = resources.disabled if params[:enabled] == 'false'
          resources = resources.exported if params[:exported] == 'true'
          resources = resources.not_exported if params[:exported] == 'false'
          resources = resources.by_type(params[:resource_type]) if params[:resource_type].present?
          resources = resources.search(params[:search]) if params[:search].present?
          resources
        end
      end
    end
  end
end
