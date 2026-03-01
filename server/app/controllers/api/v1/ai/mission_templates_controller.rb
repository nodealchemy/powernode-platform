# frozen_string_literal: true

module Api
  module V1
    module Ai
      class MissionTemplatesController < ApplicationController
        before_action :authorize_read!, only: [:index, :show]
        before_action :authorize_manage!, only: [:create, :update, :destroy]

        # GET /api/v1/ai/mission_templates
        def index
          templates = ::Ai::MissionTemplate.for_account(current_account.id).active

          templates = templates.by_type(params[:mission_type]) if params[:mission_type].present?
          templates = templates.where(template_type: params[:template_type]) if params[:template_type].present?

          render_success(templates: templates.map(&:template_summary))
        end

        # GET /api/v1/ai/mission_templates/:id
        def show
          template = find_template!
          return unless template

          render_success(template: template.template_details)
        end

        # POST /api/v1/ai/mission_templates
        def create
          template = ::Ai::MissionTemplate.new(template_params)
          template.account = current_account
          template.template_type = "account" # Users can only create account templates

          if template.save
            render_success(template: template.template_details, status: :created)
          else
            render_error(template.errors.full_messages.join(", "), :unprocessable_content)
          end
        end

        # PATCH /api/v1/ai/mission_templates/:id
        def update
          template = find_template!
          return unless template

          if template.template_type == "system"
            render_error("System templates cannot be modified", :forbidden)
            return
          end

          if template.update(template_params)
            render_success(template: template.template_details)
          else
            render_error(template.errors.full_messages.join(", "), :unprocessable_content)
          end
        end

        # DELETE /api/v1/ai/mission_templates/:id
        def destroy
          template = find_template!
          return unless template

          if template.template_type == "system"
            render_error("System templates cannot be deleted", :forbidden)
            return
          end

          template.update!(status: "archived")
          render_success(deleted: true)
        end

        private

        def authorize_read!
          render_error("Forbidden", :forbidden) unless has_permission?("ai.missions.read")
        end

        def authorize_manage!
          render_error("Forbidden", :forbidden) unless has_permission?("ai.missions.manage")
        end

        def find_template!
          ::Ai::MissionTemplate.for_account(current_account.id).find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Mission template not found", :not_found)
          nil
        end

        def template_params
          params.permit(
            :name, :description, :mission_type, :status, :is_default,
            phases: [:key, :label, :description, :requires_approval, :job_class,
                     :estimated_duration_minutes, :skip_allowed, :order],
            approval_gates: [],
            rejection_mappings: {},
            skill_compositions: {},
            default_configuration: {}
          )
        end
      end
    end
  end
end
