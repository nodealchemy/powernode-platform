# frozen_string_literal: true

module Api
  module V1
    module Devops
      class IntegrationInstancesController < ApplicationController
        before_action :authenticate_request
        before_action :set_instance, only: [ :show, :update, :destroy, :activate, :deactivate, :test, :execute ]

        # GET /api/v1/devops/integration_instances
        def index
          authorize_action!("devops.integrations.read")

          instances = ::Devops::RegistryService.list_instances(
            account: current_account,
            filters: instance_filters,
            **pagination_params
          )

          render_success({
            instances: instances.map(&:instance_summary),
            pagination: pagination_meta(instances)
          })
        end

        # GET /api/v1/devops/integration_instances/:id
        def show
          authorize_action!("devops.integrations.read")

          render_success({ instance: @instance.instance_details })
        end

        # POST /api/v1/devops/integration_instances
        def create
          authorize_action!("devops.integrations.create")

          instance = ::Devops::RegistryService.install_template(
            account: current_account,
            template_identifier: params[:template_id],
            attributes: instance_params,
            created_by: current_user
          )

          render_success({ instance: instance.instance_details }, status: :created)
        rescue ::Devops::RegistryService::TemplateNotFoundError
          render_not_found("Template")
        rescue ::Devops::RegistryService::ValidationError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # PATCH /api/v1/devops/integration_instances/:id
        def update
          authorize_action!("devops.integrations.update")

          instance = ::Devops::RegistryService.update_instance(
            account: current_account,
            instance_id: @instance.id,
            attributes: instance_params
          )

          render_success({ instance: instance.instance_details })
        rescue ::Devops::RegistryService::ValidationError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # DELETE /api/v1/devops/integration_instances/:id
        def destroy
          authorize_action!("devops.integrations.delete")

          ::Devops::RegistryService.uninstall_instance(
            account: current_account,
            instance_id: @instance.id
          )

          render_success(message: "Integration uninstalled")
        end

        # POST /api/v1/devops/integration_instances/:id/activate
        def activate
          authorize_action!("devops.integrations.update")

          instance = ::Devops::RegistryService.activate_instance(
            account: current_account,
            instance_id: @instance.id
          )

          render_success({ instance: instance.instance_details })
        rescue ::Devops::RegistryService::ValidationError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/devops/integration_instances/:id/deactivate
        def deactivate
          authorize_action!("devops.integrations.update")

          instance = ::Devops::RegistryService.deactivate_instance(
            account: current_account,
            instance_id: @instance.id
          )

          render_success({ instance: instance.instance_details })
        end

        # POST /api/v1/devops/integration_instances/:id/test
        def test
          authorize_action!("devops.integrations.execute")

          result = ::Devops::ExecutionService.test_connection(instance: @instance)

          render_success({ result: result })
        end

        # POST /api/v1/devops/integration_instances/:id/execute
        def execute
          authorize_action!("devops.integrations.execute")

          unless @instance.status == "active"
            return render_error("Integration is not active", status: :unprocessable_content)
          end

          result = ::Devops::ExecutionService.execute(
            instance: @instance,
            input: execution_input,
            triggered_by: current_user,
            context: { request_id: request.request_id }
          )

          if result[:success]
            render_success({ result: result })
          else
            render_error(result[:error], status: :unprocessable_content, data: { execution_id: result[:execution_id] })
          end
        end

        # GET /api/v1/devops/integration_instances/:id/health
        def health
          authorize_action!("devops.integrations.read")

          health = ::Devops::ExecutionService.health_check(instance: @instance)

          render_success({ health: health })
        end

        # GET /api/v1/devops/integration_instances/:id/stats
        def stats
          authorize_action!("devops.integrations.read")

          stats = ::Devops::ExecutionService.execution_stats(
            instance: @instance,
            period: (params[:period] || 30).to_i.days
          )

          render_success({ stats: stats })
        end

        private

        def set_instance
          @instance = ::Devops::RegistryService.find_instance(
            account: current_account,
            instance_id: params[:id]
          )
        rescue ::Devops::RegistryService::InstanceNotFoundError
          render_not_found("Integration instance")
        end

        def instance_params
          params.require(:instance).permit(
            :name, :slug, :credential_id,
            configuration: {}
          )
        end

        def instance_filters
          {
            status: params[:status],
            type: params[:type]
          }.compact
        end

        def execution_input
          params.permit(:method, :path, :workflow_id, :ref, :tool,
                        body: {}, headers: {}, query_params: {}, inputs: {}, arguments: {})
                .to_h
        end

        def authorize_action!(permission)
          unless current_user.has_permission?(permission)
            render_forbidden("You don't have permission to perform this action")
          end
        end

        def pagination_meta(collection)
          {
            current_page: collection.current_page,
            total_pages: collection.total_pages,
            total_count: collection.total_count,
            per_page: collection.limit_value
          }
        end
      end
    end
  end
end
