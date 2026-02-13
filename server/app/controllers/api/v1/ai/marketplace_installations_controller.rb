# frozen_string_literal: true

module Api
  module V1
    module Ai
      class MarketplaceInstallationsController < ApplicationController
        include AuditLogging

        before_action :authenticate_request
        before_action :set_template, only: [ :install, :rate ]
        before_action :validate_permissions

        # GET /api/v1/ai/marketplace/installations
        def installations_index
          result = installation_service.list_installations(
            page: params[:page]&.to_i || 1,
            per_page: params[:per_page]&.to_i || 25,
            category: params[:category]
          )

          render_success({
            installations: result[:installations],
            pagination: result[:pagination],
            total_count: result[:pagination][:total_count]
          })
        end

        # GET /api/v1/ai/marketplace/installations/:id
        def installation_show
          result = installation_service.get_installation(params[:id])

          if result[:success]
            render_success({ installation: result[:installation] })
          else
            render_error(result[:error], status: :not_found)
          end
        end

        # DELETE /api/v1/ai/marketplace/installations/:id
        def installation_destroy
          result = installation_service.uninstall(
            subscription_id: params[:id],
            delete_workflow: params[:delete_workflow] == "true"
          )

          if result[:success]
            log_audit_event("ai.marketplace.installation_deleted", nil)
            render_success({ message: result[:message] })
          else
            render_error(result[:error], status: :not_found)
          end
        end

        # POST /api/v1/ai/marketplace/templates/:id/install
        def install
          result = installation_service.install(
            template_id: @template.id,
            custom_configuration: params[:custom_configuration] || params[:customizations] || {},
            installation_notes: params[:installation_notes]
          )

          if result[:success]
            log_audit_event("ai.marketplace.template_installed", @template,
              subscription_id: result[:subscription].id,
              workflow_id: result[:workflow].id
            )

            render_success({
              installation: serialize_installation(result[:subscription]),
              workflow: serialize_workflow(result[:workflow]),
              message: result[:message]
            }, status: :created)
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # GET /api/v1/ai/marketplace/updates
        def check_updates
          result = installation_service.check_for_updates

          render_success({ updates_available: result[:updates_available] })
        end

        # POST /api/v1/ai/marketplace/updates/apply
        def apply_updates
          result = installation_service.apply_all_updates(
            preserve_customizations: params[:preserve_customizations] != "false"
          )

          render_success({
            updated: result,
            message: "Updated #{result[:successful]} of #{result[:total_attempted]} templates"
          })
        end

        # POST /api/v1/ai/marketplace/templates/:id/rate
        def rate
          unless params[:rating].present?
            return render_error("Rating is required", status: :bad_request)
          end

          rating_value = params[:rating].to_i
          unless rating_value.between?(1, 5)
            return render_error("Rating must be between 1 and 5", status: :bad_request)
          end

          result = installation_service.rate_template(
            template_id: @template.id,
            rating: rating_value,
            feedback: params[:feedback] || {}
          )

          if result[:success]
            log_audit_event("ai.marketplace.template_rated", @template, rating: rating_value)

            render_success({
              rating: result,
              message: result[:message]
            })
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        private

        def installation_service
          @installation_service ||= ::Ai::Marketplace::InstallationService.new(
            account: current_user.account,
            user: current_user
          )
        end

        def set_template
          @template = ::Ai::WorkflowTemplate
                        .includes(:created_by_user)
                        .accessible_to_account(current_user.account.id)
                        .find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Template not found", status: :not_found)
        end

        def validate_permissions
          return if current_worker

          case action_name
          when "installations_index", "installation_show", "check_updates"
            require_permission("ai.workflows.read")
          when "install"
            require_permission("ai.workflows.create")
          when "rate"
            require_permission("ai.workflows.update")
          when "installation_destroy"
            require_permission("ai.workflows.delete")
          when "apply_updates"
            require_permission("ai.workflows.manage")
          end
        end

        def serialize_installation(subscription)
          {
            id: subscription.id,
            installed_version: subscription.metadata&.dig("template_version"),
            created_at: subscription.subscribed_at&.iso8601 || subscription.created_at.iso8601,
            customizations: subscription.configuration
          }
        end

        def serialize_workflow(workflow)
          return nil unless workflow

          {
            id: workflow.id,
            name: workflow.name,
            description: workflow.description,
            status: workflow.status,
            version: workflow.version,
            created_at: workflow.created_at.iso8601
          }
        end
      end
    end
  end
end
