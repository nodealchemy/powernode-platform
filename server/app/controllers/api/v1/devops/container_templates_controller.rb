# frozen_string_literal: true

module Api
  module V1
    module Devops
      class ContainerTemplatesController < ApplicationController
        include AuditLogging
        include ::Ai::ResourceFiltering

        before_action :set_template, only: %i[show update destroy publish unpublish executions stats trigger_build builds]

        # GET /api/v1/mcp/templates
        def index
          scope = ::Devops::ContainerTemplate.accessible_by(current_user.account)

          # Apply filters
          scope = scope.where(category: params[:category]) if params[:category].present?
          scope = scope.active if params[:active] == "true"
          scope = scope.public_templates if params[:public] == "true"

          # Search
          if params[:query].present?
            scope = scope.where(
              "name ILIKE :q OR description ILIKE :q",
              q: "%#{params[:query]}%"
            )
          end

          # Sorting
          case params[:sort]
          when "popular"
            scope = scope.order(execution_count: :desc)
          when "recent"
            scope = scope.order(created_at: :desc)
          when "name"
            scope = scope.order(name: :asc)
          else
            scope = scope.order(created_at: :desc)
          end

          # Pagination
          scope = apply_pagination(scope)

          render_success(
            items: scope.map(&:template_summary),
            pagination: pagination_data(scope)
          )
          log_audit_event("devops.container_templates.list", current_user.account)
        end

        # GET /api/v1/mcp/templates/:id
        def show
          render_success(template: @template.template_details)
          log_audit_event("devops.container_templates.read", @template)
        end

        # POST /api/v1/mcp/templates
        def create
          template = current_user.account.devops_container_templates.build(template_params)
          template.created_by = current_user

          if template.save
            render_success({ template: template.template_details }, status: :created)
            log_audit_event("devops.container_templates.create", template)
          else
            render_error(template.errors.full_messages, status: :unprocessable_content)
          end
        end

        # PATCH/PUT /api/v1/mcp/templates/:id
        def update
          unless @template.account_id == current_user.account_id
            render_error("You can only update your own templates", status: :forbidden)
            return
          end

          if @template.update(template_params)
            render_success(template: @template.template_details)
            log_audit_event("devops.container_templates.update", @template)
          else
            render_error(@template.errors.full_messages, status: :unprocessable_content)
          end
        end

        # DELETE /api/v1/mcp/templates/:id
        def destroy
          unless @template.account_id == current_user.account_id
            render_error("You can only delete your own templates", status: :forbidden)
            return
          end

          @template.destroy!
          render_success(message: "Template deleted successfully")
          log_audit_event("devops.container_templates.delete", @template)
        end

        # POST /api/v1/mcp/templates/:id/publish
        def publish
          unless @template.account_id == current_user.account_id
            render_error("You can only publish your own templates", status: :forbidden)
            return
          end

          @template.update!(visibility: "public", status: "active")
          render_success(template: @template.template_details)
          log_audit_event("devops.container_templates.publish", @template)
        end

        # POST /api/v1/mcp/templates/:id/unpublish
        def unpublish
          unless @template.account_id == current_user.account_id
            render_error("You can only unpublish your own templates", status: :forbidden)
            return
          end

          @template.update!(visibility: "private")
          render_success(template: @template.template_details)
          log_audit_event("devops.container_templates.unpublish", @template)
        end

        # GET /api/v1/mcp/templates/:id/executions
        def executions
          scope = @template.container_instances

          # Apply filters
          scope = scope.where(status: params[:status]) if params[:status].present?

          # Date range
          if params[:since].present?
            scope = scope.where("created_at >= ?", Time.zone.parse(params[:since]))
          end

          # Sorting and pagination
          scope = scope.order(created_at: :desc)
          scope = apply_pagination(scope)

          render_success(
            items: scope.map(&:instance_summary),
            pagination: pagination_data(scope)
          )
        end

        # GET /api/v1/mcp/templates/:id/stats
        def stats
          instances = @template.container_instances

          render_success(
            stats: {
              total_executions: instances.count,
              successful: instances.successful.count,
              failed: instances.failed.count,
              avg_duration_ms: instances.finished.average(:duration_ms)&.round(2),
              success_rate: instances.finished.count > 0 ?
                (instances.successful.count.to_f / instances.finished.count * 100).round(2) : 0,
              last_execution_at: instances.maximum(:created_at)
            }
          )
        end

        # GET /api/v1/mcp/templates/categories
        def categories
          render_success(
            categories: ::Devops::ContainerTemplate.active
                                                .distinct
                                                .pluck(:category)
                                                .compact
                                                .sort
          )
        end

        # GET /api/v1/mcp/templates/featured
        def featured
          scope = ::Devops::ContainerTemplate.public_templates
                                          .active
                                          .where(featured: true)
                                          .order(execution_count: :desc)
                                          .limit(params[:limit]&.to_i || 10)

          render_success(items: scope.map(&:template_summary))
        end

        # POST /api/v1/devops/container_templates/:id/trigger_build
        def trigger_build
          unless @template.account_id == current_user.account_id
            render_error("You can only build your own templates", status: :forbidden)
            return
          end

          unless @template.gitea_repo_full_name.present?
            render_error("Template has no linked Gitea repository", status: :unprocessable_content)
            return
          end

          build = ::Devops::ContainerImageBuildService
            .new(account: current_user.account)
            .trigger_build(template: @template, trigger_type: "manual")

          render_success({ build: build.build_summary }, status: :created)
          log_audit_event("devops.container_templates.trigger_build", @template)
        rescue ::Devops::ContainerImageBuildService::BuildError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # GET /api/v1/devops/container_templates/:id/builds
        def builds
          scope = @template.image_builds.recent
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = apply_pagination(scope)

          render_success(
            items: scope.map(&:build_summary),
            pagination: pagination_data(scope)
          )
        end

        # POST /api/v1/devops/container_templates/create_image_repo
        def create_image_repo
          repo_params = params.require(:image_repo).permit(:name, :variant_type, :parent_template_id)

          parent_template = nil
          if repo_params[:parent_template_id].present?
            parent_template = ::Devops::ContainerTemplate.find(repo_params[:parent_template_id])
          end

          result = ::Devops::ContainerImageRepoService
            .new(account: current_user.account, user: current_user)
            .create_image_repo(
              name: repo_params[:name],
              variant_type: repo_params[:variant_type],
              parent_template: parent_template
            )

          render_success({
            template: result[:template].template_details,
            repository: result[:repository],
            files_created: result[:files_created]
          }, status: :created)
          log_audit_event("devops.container_templates.create_image_repo", result[:template])
        rescue ::Devops::ContainerImageRepoService::RepoCreationError => e
          render_error(e.message, status: :unprocessable_content)
        end

        private

        def set_template
          @template = ::Devops::ContainerTemplate.accessible_by(current_user.account).find(params[:id])
        end

        def template_params
          params.require(:template).permit(
            :name,
            :description,
            :image_name,
            :image_tag,
            :category,
            :visibility,
            :timeout_seconds,
            :memory_mb,
            :cpu_millicores,
            :sandbox_mode,
            :network_access,
            :featured,
            :parent_template_id,
            :gitea_repo_full_name,
            :auto_update,
            input_schema: {},
            output_schema: {},
            environment_variables: {},
            labels: {},
            allowed_egress_domains: []
          )
        end
      end
    end
  end
end
