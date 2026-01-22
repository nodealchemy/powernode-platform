# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class QuestionnaireTemplatesController < BaseController
        before_action :require_read_permission, only: [:index, :show]
        before_action :require_write_permission, only: [:create, :update, :destroy, :duplicate, :send_to_vendor]
        before_action :set_template, only: [:show, :update, :destroy, :duplicate, :send_to_vendor]

        # GET /api/v1/supply_chain/questionnaire_templates
        def index
          @templates = ::SupplyChain::QuestionnaireTemplate.for_account(current_account)
                                                           .order(created_at: :desc)

          @templates = @templates.active if params[:active_only] == "true"
          @templates = @templates.system_templates if params[:system_only] == "true"
          @templates = @templates.by_type(params[:type]) if params[:type].present?

          @templates = paginate(@templates)

          render_success(
            { questionnaire_templates: @templates.map { |t| serialize_template(t) } },
            meta: pagination_meta
          )
        end

        # GET /api/v1/supply_chain/questionnaire_templates/:id
        def show
          render_success({ questionnaire_template: serialize_template(@template, include_details: true) })
        end

        # POST /api/v1/supply_chain/questionnaire_templates
        def create
          @template = current_account.supply_chain_questionnaire_templates.build(template_params)
          @template.created_by = current_user
          @template.is_system = false

          if @template.save
            render_success({ questionnaire_template: serialize_template(@template) }, status: :created)
          else
            render_error(@template.errors.full_messages.join(", "), status: :unprocessable_entity)
          end
        end

        # PATCH/PUT /api/v1/supply_chain/questionnaire_templates/:id
        def update
          if @template.is_system
            render_error("Cannot modify system templates", status: :forbidden)
            return
          end

          if @template.update(template_params)
            render_success({ questionnaire_template: serialize_template(@template) })
          else
            render_error(@template.errors.full_messages.join(", "), status: :unprocessable_entity)
          end
        end

        # DELETE /api/v1/supply_chain/questionnaire_templates/:id
        def destroy
          if @template.is_system
            render_error("Cannot delete system templates", status: :forbidden)
            return
          end

          if @template.questionnaire_responses.exists?
            render_error("Cannot delete template with existing responses", status: :unprocessable_entity)
            return
          end

          @template.destroy
          render_success(message: "Questionnaire template deleted")
        end

        # POST /api/v1/supply_chain/questionnaire_templates/:id/duplicate
        def duplicate
          new_name = params[:name] || "#{@template.name} (Copy)"
          new_template = @template.duplicate(new_name: new_name, for_account: current_account)

          render_success(
            { questionnaire_template: serialize_template(new_template) },
            message: "Template duplicated"
          )
        rescue StandardError => e
          render_error("Failed to duplicate: #{e.message}", status: :unprocessable_entity)
        end

        # POST /api/v1/supply_chain/questionnaire_templates/:id/send_to_vendor
        def send_to_vendor
          vendor = current_account.supply_chain_vendors.find(params[:vendor_id])

          response = vendor.questionnaire_responses.create!(
            template: @template,
            account: current_account,
            status: "pending",
            sent_at: Time.current,
            requested_by: current_user,
            expires_at: params[:due_at] || 30.days.from_now
          )

          # TODO: Send notification email to vendor

          render_success(
            { questionnaire_response: serialize_response(response) },
            message: "Questionnaire sent to vendor"
          )
        rescue StandardError => e
          render_error("Failed to send questionnaire: #{e.message}", status: :unprocessable_entity)
        end

        private

        def set_template
          @template = ::SupplyChain::QuestionnaireTemplate.for_account(current_account).find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Questionnaire template not found", status: :not_found)
        end

        def template_params
          params.require(:questionnaire_template).permit(
            :name, :description, :template_type, :version, :is_active,
            sections: [:id, :name, :description, :weight, :order],
            questions: [:id, :section_id, :text, :type, :required, :weight, :order, options: []],
            metadata: {}
          )
        end

        def serialize_template(template, include_details: false)
          data = {
            id: template.id,
            name: template.name,
            description: template.description,
            template_type: template.template_type,
            version: template.version,
            is_system: template.is_system,
            is_active: template.is_active,
            section_count: template.section_count,
            question_count: template.question_count,
            created_at: template.created_at
          }

          if include_details
            data[:sections] = template.sections
            data[:questions] = template.questions
            data[:response_count] = template.questionnaire_responses.count
            data[:metadata] = template.metadata
          end

          data
        end

        def serialize_response(response)
          {
            id: response.id,
            vendor_id: response.vendor_id,
            template_id: response.template_id,
            status: response.status,
            sent_at: response.sent_at,
            due_at: response.expires_at,
            access_url: questionnaire_access_url(response)
          }
        end

        def questionnaire_access_url(response)
          # Generate a URL for vendor to access the questionnaire
          "#{Rails.application.config.frontend_url}/vendor-questionnaire/#{response.access_token}"
        end
      end
    end
  end
end
