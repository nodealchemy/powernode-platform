# frozen_string_literal: true

module Api
  module V1
    module Marketplace
      class TemplatesController < ApplicationController
        before_action :set_template, only: [:show, :submit, :withdraw, :approve, :reject]

        # POST /api/v1/marketplace/templates/from_workflow/:id
        # Create a template from an existing workflow
        def create_from_workflow
          workflow = current_account.ai_workflows.find(params[:id])

          creator = ::Marketplace::TemplateCreator.new(current_user)
          template = creator.create_from_workflow(workflow, template_params)

          render_success(
            serialize_template(template),
            message: "Workflow template created successfully"
          )
        rescue ::Marketplace::TemplateCreatorError => e
          render_error(e.message, status: :unprocessable_entity)
        end

        # POST /api/v1/marketplace/templates/from_pipeline/:id
        # Create a template from an existing pipeline
        def create_from_pipeline
          pipeline = current_account.ci_cd_pipelines.find(params[:id])

          creator = ::Marketplace::TemplateCreator.new(current_user)
          template = creator.create_from_pipeline(pipeline, template_params)

          render_success(
            serialize_template(template),
            message: "Pipeline template created successfully"
          )
        rescue ::Marketplace::TemplateCreatorError => e
          render_error(e.message, status: :unprocessable_entity)
        end

        # POST /api/v1/marketplace/templates/from_integration/:id
        # Create a template from an existing integration template
        def create_from_integration
          integration = Integration::Template.find(params[:id])

          creator = ::Marketplace::TemplateCreator.new(current_user)
          template = creator.create_from_integration(integration, template_params)

          render_success(
            serialize_template(template),
            message: "Integration template created successfully"
          )
        rescue ::Marketplace::TemplateCreatorError => e
          render_error(e.message, status: :unprocessable_entity)
        end

        # POST /api/v1/marketplace/templates/from_prompt/:id
        # Create a template from an existing prompt template
        def create_from_prompt
          prompt = current_account.shared_prompt_templates.find(params[:id])

          creator = ::Marketplace::TemplateCreator.new(current_user)
          template = creator.create_from_prompt(prompt, template_params)

          render_success(
            serialize_template(template),
            message: "Prompt template created successfully"
          )
        rescue ::Marketplace::TemplateCreatorError => e
          render_error(e.message, status: :unprocessable_entity)
        end

        # POST /api/v1/marketplace/templates/:type/:id/submit
        # Submit template for marketplace review
        def submit
          authorize_publish!

          @template.submit_to_marketplace!(current_user)

          render_success(
            serialize_template(@template),
            message: "Template submitted for review"
          )
        rescue MarketplacePublishError => e
          render_error(e.message, status: :unprocessable_entity)
        end

        # POST /api/v1/marketplace/templates/:type/:id/withdraw
        # Withdraw template from marketplace
        def withdraw
          authorize_owner!

          @template.withdraw_from_marketplace!

          render_success(
            serialize_template(@template),
            message: "Template withdrawn from marketplace"
          )
        end

        # POST /api/v1/marketplace/templates/:type/:id/approve
        # Admin: Approve template for marketplace
        def approve
          authorize_admin!

          @template.approve_for_marketplace!(approved_by: current_user)

          render_success(
            serialize_template(@template),
            message: "Template approved for marketplace"
          )
        rescue MarketplacePublishError => e
          render_error(e.message, status: :unprocessable_entity)
        end

        # POST /api/v1/marketplace/templates/:type/:id/reject
        # Admin: Reject template from marketplace
        def reject
          authorize_admin!

          reason = params[:reason] || "No reason provided"
          @template.reject_from_marketplace!(reason, rejected_by: current_user)

          render_success(
            serialize_template(@template),
            message: "Template rejected from marketplace"
          )
        rescue MarketplacePublishError => e
          render_error(e.message, status: :unprocessable_entity)
        end

        # GET /api/v1/marketplace/templates/my_published
        # List user's published templates
        def my_published
          templates = []

          # Gather templates from all publishable types
          templates += current_account.ai_workflows
                        .joins("INNER JOIN ai_workflow_templates ON ai_workflow_templates.source_workflow_id = ai_workflows.id")
                        .where(ai_workflow_templates: { account_id: current_account.id })
                        .map { |_w| Ai::WorkflowTemplate.where(account_id: current_account.id) }
                        .flatten

          # Get directly owned templates
          templates += Ai::WorkflowTemplate.where(account_id: current_account.id).to_a
          templates += CiCd::PipelineTemplate.where(account_id: current_account.id).to_a
          templates += Integration::Template.where(account_id: current_account.id).to_a
          templates += Shared::PromptTemplate.where(account_id: current_account.id, is_system: false).to_a

          # Remove duplicates and serialize
          templates = templates.uniq(&:id)

          render_success(
            templates.map { |t| serialize_template(t) },
            meta: {
              total_count: templates.count,
              counts_by_type: {
                workflow_template: templates.count { |t| t.is_a?(Ai::WorkflowTemplate) },
                pipeline_template: templates.count { |t| t.is_a?(CiCd::PipelineTemplate) },
                integration_template: templates.count { |t| t.is_a?(Integration::Template) },
                prompt_template: templates.count { |t| t.is_a?(Shared::PromptTemplate) }
              }
            }
          )
        end

        # GET /api/v1/marketplace/templates/pending_review
        # Admin: List templates pending review
        def pending_review
          authorize_admin!

          templates = []
          templates += Ai::WorkflowTemplate.marketplace_pending.to_a
          templates += CiCd::PipelineTemplate.marketplace_pending.to_a
          templates += Integration::Template.marketplace_pending.to_a
          templates += Shared::PromptTemplate.marketplace_pending.to_a

          render_success(
            templates.map { |t| serialize_template(t) },
            meta: { total_count: templates.count }
          )
        end

        # POST /api/v1/marketplace/templates/:type/:id/create_instance
        # Create a feature instance from a subscribed template
        def create_instance
          set_template

          creator = ::Marketplace::InstanceCreator.new(current_user)

          instance = case params[:type]
                     when "workflow_template"
                       creator.create_from_workflow_template(@template, instance_params)
                     when "pipeline_template"
                       creator.create_from_pipeline_template(@template, instance_params)
                     when "integration_template"
                       creator.create_from_integration_template(@template, instance_params)
                     else
                       render_error("Cannot create instance from this template type", status: :unprocessable_entity)
                       return
                     end

          render_success(
            { id: instance.id, name: instance.name, type: params[:type].sub("_template", "") },
            message: "Instance created from template"
          )
        rescue ::Marketplace::InstanceCreatorError => e
          render_error(e.message, status: :unprocessable_entity)
        end

        private

        def set_template
          @template = case params[:type]
                      when "workflow_template"
                        Ai::WorkflowTemplate.find(params[:id])
                      when "pipeline_template"
                        CiCd::PipelineTemplate.find(params[:id])
                      when "integration_template"
                        Integration::Template.find(params[:id])
                      when "prompt_template"
                        Shared::PromptTemplate.find(params[:id])
                      else
                        render_error("Invalid template type", status: :bad_request)
                        nil
                      end
        end

        def template_params
          params.permit(:name, :description, :category, :difficulty_level, tags: [])
        end

        def instance_params
          params.permit(:name, :description, variables: {}, configuration: {}, triggers: {})
        end

        def authorize_publish!
          return if current_user.has_permission?("marketplace.publish")
          render_forbidden("You don't have permission to publish templates")
        end

        def authorize_owner!
          return if @template.account_id == current_account.id
          render_forbidden("You can only manage your own templates")
        end

        def authorize_admin!
          return if current_user.has_permission?("admin.marketplace.templates.review")
          render_forbidden("You don't have permission to review templates")
        end

        def serialize_template(template)
          {
            id: template.id,
            type: template.marketplace_template_type,
            name: template.name,
            slug: template.slug,
            description: template.description,
            category: template.respond_to?(:category) ? template.category : nil,
            difficulty_level: template.respond_to?(:difficulty_level) ? template.difficulty_level : nil,
            version: template.version,
            tags: template.respond_to?(:tags) ? template.tags : [],
            rating: template.respond_to?(:rating) ? template.rating : 0,
            rating_count: template.respond_to?(:rating_count) ? template.rating_count : 0,
            usage_count: template.respond_to?(:usage_count) ? template.usage_count : 0,
            is_public: template.respond_to?(:is_public) ? template.is_public : false,
            is_featured: template.respond_to?(:is_featured) ? template.is_featured : false,
            is_marketplace_published: template.is_marketplace_published,
            marketplace_status: template.marketplace_status,
            marketplace_submitted_at: template.marketplace_submitted_at,
            marketplace_approved_at: template.marketplace_approved_at,
            created_at: template.created_at,
            updated_at: template.updated_at,
            publisher: serialize_publisher(template)
          }
        end

        def serialize_publisher(template)
          account = template.respond_to?(:account) && template.account
          return nil unless account

          {
            id: account.id,
            display_name: account.publisher_display_name || account.name,
            bio: account.publisher_bio,
            website: account.publisher_website,
            logo_url: account.publisher_logo_url,
            verified: false # Could be determined by checking if account has verified status
          }
        end
      end
    end
  end
end
