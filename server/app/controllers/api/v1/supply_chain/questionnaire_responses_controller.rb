# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class QuestionnaireResponsesController < BaseController
        skip_before_action :authenticate_request, only: [:show_by_token, :submit_by_token]
        before_action :require_read_permission, only: [:index, :show]
        before_action :require_write_permission, only: [:update, :submit, :review, :send_reminder, :approve, :reject, :request_changes]
        before_action :set_response, only: [:show, :update, :submit, :review, :send_reminder, :approve, :reject, :request_changes]
        before_action :set_response_by_token, only: [:show_by_token, :submit_by_token]

        # GET /api/v1/supply_chain/questionnaire_responses
        def index
          @responses = ::SupplyChain::QuestionnaireResponse
                         .joins(:vendor)
                         .where(supply_chain_vendors: { account_id: current_account.id })
                         .includes(:template, :vendor)
                         .order(created_at: :desc)

          @responses = @responses.where(status: params[:status]) if params[:status].present?
          @responses = @responses.where(vendor_id: params[:vendor_id]) if params[:vendor_id].present?

          @responses = paginate(@responses)

          render_success(
            { questionnaire_responses: @responses.map { |r| serialize_response(r) } },
            meta: pagination_meta
          )
        end

        # GET /api/v1/supply_chain/questionnaire_responses/:id
        def show
          render_success({ questionnaire_response: serialize_response(@response, include_details: true) })
        end

        # GET /api/v1/supply_chain/questionnaire_responses/token/:token
        def show_by_token
          render_success({
            questionnaire_response: serialize_response_for_vendor(@response),
            template: serialize_template_for_vendor(@response.template)
          })
        end

        # POST /api/v1/supply_chain/questionnaire_responses/token/:token/submit
        def submit_by_token
          if @response.submitted?
            render_error("Questionnaire already submitted", status: :unprocessable_content)
            return
          end

          @response.assign_attributes(
            responses: params[:responses],
            submitted_at: Time.current,
            status: "submitted"
          )

          if @response.save
            # Calculate scores
            @response.calculate_scores!

            # Notify account of submission
            SupplyChainChannel.broadcast_questionnaire_submitted(@response)

            render_success({
              overall_score: @response.overall_score
            }, message: "Questionnaire submitted successfully")
          else
            render_error(@response.errors.full_messages.join(", "), status: :unprocessable_content)
          end
        end

        # PATCH/PUT /api/v1/supply_chain/questionnaire_responses/:id
        def update
          if @response.update(response_params)
            render_success({ questionnaire_response: serialize_response(@response) })
          else
            render_error(@response.errors.full_messages.join(", "), status: :unprocessable_content)
          end
        end

        # POST /api/v1/supply_chain/questionnaire_responses/:id/submit
        def submit
          if @response.submitted?
            render_error("Questionnaire already submitted", status: :unprocessable_content)
            return
          end

          if @response.submit!
            render_success(
              { questionnaire_response: serialize_response(@response) },
              message: "Questionnaire submitted successfully"
            )
          else
            render_error("Failed to submit questionnaire", status: :unprocessable_content)
          end
        rescue StandardError => e
          render_error("Failed to submit: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/supply_chain/questionnaire_responses/:id/review
        def review
          @response.review!(current_user, notes: params[:notes])

          render_success(
            { questionnaire_response: serialize_response(@response) },
            message: "Questionnaire reviewed"
          )
        rescue StandardError => e
          render_error("Failed to review: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/supply_chain/questionnaire_responses/:id/send_reminder
        def send_reminder
          vendor = @response.vendor

          # Send reminder email to vendor
          if vendor&.contact_email.present?
            NotificationService.send_email(
              template: "supply_chain_questionnaire_reminder",
              email: vendor.contact_email,
              data: {
                vendor_name: vendor.name,
                template_name: @response.template&.name,
                access_url: questionnaire_access_url_for_response(@response),
                due_at: @response.expires_at&.iso8601,
                days_remaining: @response.expires_at ? ((@response.expires_at - Time.current) / 1.day).ceil : nil,
                account_name: current_account.name
              }
            )
          end

          @response.touch(:sent_at)

          render_success(
            { questionnaire_response: serialize_response(@response) },
            message: "Reminder sent"
          )
        rescue StandardError => e
          render_error("Failed to send reminder: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/supply_chain/questionnaire_responses/:id/approve
        def approve
          @response.approve!(approved_by: current_user, notes: params[:notes])

          # Update vendor risk assessment based on scores
          @response.vendor.update_risk_from_questionnaire(@response)

          render_success(
            { questionnaire_response: serialize_response(@response) },
            message: "Questionnaire approved"
          )
        rescue StandardError => e
          render_error("Failed to approve: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/supply_chain/questionnaire_responses/:id/reject
        def reject
          reason = params[:reason]
          if reason.blank?
            render_error("Rejection reason is required", status: :unprocessable_content)
            return
          end

          @response.reject!(rejected_by: current_user, reason: reason)

          render_success(
            { questionnaire_response: serialize_response(@response) },
            message: "Questionnaire rejected"
          )
        rescue StandardError => e
          render_error("Failed to reject: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/supply_chain/questionnaire_responses/:id/request_changes
        def request_changes
          feedback = params[:feedback]
          if feedback.blank?
            render_error("Feedback is required", status: :unprocessable_content)
            return
          end

          @response.request_changes!(requested_by: current_user, feedback: feedback)

          # Send notification to vendor
          vendor = @response.vendor
          if vendor&.contact_email.present?
            NotificationService.send_email(
              template: "supply_chain_questionnaire_changes_requested",
              email: vendor.contact_email,
              data: {
                vendor_name: vendor.name,
                template_name: @response.template&.name,
                access_url: questionnaire_access_url_for_response(@response),
                feedback: feedback,
                requested_by: current_user.name,
                account_name: current_account.name
              }
            )
          end

          render_success(
            { questionnaire_response: serialize_response(@response) },
            message: "Changes requested"
          )
        rescue StandardError => e
          render_error("Failed to request changes: #{e.message}", status: :unprocessable_content)
        end

        private

        def set_response
          @response = ::SupplyChain::QuestionnaireResponse
                        .joins(:vendor)
                        .where(supply_chain_vendors: { account_id: current_account.id })
                        .find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Questionnaire response not found", status: :not_found)
        end

        def set_response_by_token
          @response = ::SupplyChain::QuestionnaireResponse.find_by!(access_token: params[:token])

          if @response.expired?
            render_error("This questionnaire link has expired", status: :gone)
            nil
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Invalid questionnaire link", status: :not_found)
        end

        def response_params
          params.require(:questionnaire_response).permit(:review_notes, metadata: {})
        end

        def serialize_response(response, include_details: false)
          data = {
            id: response.id,
            vendor_id: response.vendor_id,
            vendor_name: response.vendor&.name,
            template_id: response.template_id,
            template_name: response.template&.name,
            status: response.status,
            overall_score: response.overall_score,
            sent_at: response.sent_at,
            due_at: response.expires_at,
            submitted_at: response.submitted_at,
            reviewed_at: response.reviewed_at,
            created_at: response.created_at
          }

          if include_details
            data[:responses] = response.responses
            data[:section_scores] = response.section_scores
            data[:reviewer_notes] = response.review_notes
            data[:feedback] = response.metadata["feedback"]
            data[:metadata] = response.metadata
          end

          data
        end

        def serialize_response_for_vendor(response)
          {
            id: response.id,
            template_name: response.template&.name,
            status: response.status,
            due_at: response.expires_at,
            responses: response.responses,
            feedback: response.metadata["feedback"]
          }
        end

        def serialize_template_for_vendor(template)
          {
            name: template.name,
            description: template.description,
            sections: template.sections,
            questions: template.questions
          }
        end

        def questionnaire_access_url_for_response(response)
          "#{Rails.application.config.frontend_url}/vendor-questionnaire/#{response.access_token}"
        end
      end
    end
  end
end
