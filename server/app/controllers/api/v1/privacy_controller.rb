# frozen_string_literal: true

module Api
  module V1
    # Privacy dashboard and GDPR compliance endpoints
    class PrivacyController < ApplicationController
      before_action :authenticate_request

      # GET /api/v1/privacy/dashboard
      def dashboard
        render_success(
          consents: ConsentManagementService.get_consents(current_user),
          export_requests: current_user_export_requests,
          deletion_requests: current_user_deletion_requests,
          terms_status: terms_acceptance_status,
          data_retention_info: data_retention_summary
        )
      end

      # GET /api/v1/privacy/consents
      def consents
        render_success(
          consents: ConsentManagementService.get_consents(current_user),
          consent_types: ConsentManagementService::CONSENT_TYPES
        )
      end

      # PUT /api/v1/privacy/consents
      def update_consents
        results = ConsentManagementService.update_consents(
          user: current_user,
          consents: consent_params,
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )

        render_success(
          message: "Consent preferences updated",
          consents: ConsentManagementService.get_consents(current_user)
        )
      end

      # POST /api/v1/privacy/export
      def request_export
        # Rate limit: max 1 export per week
        recent_request = DataManagement::ExportRequest.where(user: current_user)
                                          .where("created_at > ?", 1.week.ago)
                                          .exists?

        if recent_request
          return render_error("You can only request one data export per week", status: :too_many_requests)
        end

        export_request = DataManagement::ExportRequest.create!(
          user: current_user,
          account: current_user.account,
          format: export_params[:format] || "json",
          export_type: export_params[:export_type] || "full",
          include_data_types: export_params[:include_data_types]
        )

        # Note: Data export processing is handled by the admin during GDPR request fulfillment

        render_success(
          message: "Data export request submitted",
          request: serialize_export_request(export_request),
          status: :created
        )
      end

      # GET /api/v1/privacy/exports
      def export_requests
        requests = DataManagement::ExportRequest.where(user: current_user)
                                    .recent
                                    .limit(10)
                                    .map { |r| serialize_export_request(r) }

        render_success(requests: requests)
      end

      # GET /api/v1/privacy/exports/:id/download
      def download_export
        export_request = DataManagement::ExportRequest.find_by!(
          id: params[:id],
          user: current_user,
          download_token: params[:token]
        )

        unless export_request.downloadable?
          return render_error("Export is not available for download", status: :gone)
        end

        export_request.record_download!

        # Security: Validate file path is within allowed exports directory
        exports_base = Rails.root.join("tmp", "data_exports").to_s
        expanded_path = File.expand_path(export_request.file_path)
        unless expanded_path.start_with?(exports_base)
          Rails.logger.error "Attempted access to file outside exports directory: #{export_request.file_path}"
          return render_error("Invalid export file path", status: :forbidden)
        end

        send_file(
          export_request.file_path,
          filename: "powernode_data_export.#{export_request.format}",
          type: content_type_for(export_request.format)
        )
      end

      # POST /api/v1/privacy/deletion
      def request_deletion
        # Check for existing active request
        existing = DataManagement::DeletionRequest.active.find_by(user: current_user)

        if existing
          return render_error("You already have an active deletion request", status: :conflict)
        end

        deletion_request = DataManagement::DeletionRequest.create!(
          user: current_user,
          account: current_user.account,
          deletion_type: deletion_params[:deletion_type] || "full",
          reason: deletion_params[:reason],
          data_types_to_delete: deletion_params[:data_types_to_delete]
        )

        render_success(
          message: "Data deletion request submitted",
          request: serialize_deletion_request(deletion_request),
          grace_period_days: DataManagement::DeletionRequest::GRACE_PERIOD_DAYS,
          status: :created
        )
      end

      # GET /api/v1/privacy/deletion
      def deletion_request_status
        request = DataManagement::DeletionRequest.where(user: current_user)
                                     .order(created_at: :desc)
                                     .first

        if request
          render_success(request: serialize_deletion_request(request))
        else
          render_success(request: nil)
        end
      end

      # DELETE /api/v1/privacy/deletion/:id
      def cancel_deletion
        request = DataManagement::DeletionRequest.find_by!(id: params[:id], user: current_user)

        unless request.can_be_cancelled?
          return render_error("This deletion request cannot be cancelled", status: :unprocessable_content)
        end

        request.cancel!(current_user, params[:reason])

        render_success(
          message: "Deletion request cancelled",
          request: serialize_deletion_request(request)
        )
      end

      # GET /api/v1/privacy/terms
      def terms_status
        render_success(
          current_versions: TermsAcceptance::CURRENT_VERSIONS,
          accepted: accepted_terms,
          missing: TermsAcceptance.missing_acceptances(current_user)
        )
      end

      # POST /api/v1/privacy/terms/:document_type/accept
      def accept_terms
        document_type = params[:document_type]

        unless TermsAcceptance::CURRENT_VERSIONS.key?(document_type)
          return render_error("Invalid document type", status: :bad_request)
        end

        acceptance = TermsAcceptance.record_acceptance(
          user: current_user,
          document_type: document_type,
          version: params[:version],
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )

        render_success(
          message: "#{document_type.humanize} accepted",
          acceptance: serialize_terms_acceptance(acceptance)
        )
      end

      # GET /api/v1/privacy/cookies
      def cookie_preferences
        consent = CookieConsent.find_by(user: current_user) if current_user

        render_success(
          preferences: consent ? serialize_cookie_consent(consent) : default_cookie_preferences
        )
      end

      # PUT /api/v1/privacy/cookies
      def update_cookie_preferences
        consent = CookieConsent.find_or_initialize_by(user: current_user)

        consent.assign_attributes(
          necessary: true, # Always required
          functional: cookie_params[:functional] || false,
          analytics: cookie_params[:analytics] || false,
          marketing: cookie_params[:marketing] || false,
          ip_address: request.remote_ip,
          user_agent: request.user_agent,
          consented_at: Time.current
        )

        consent.save!

        render_success(
          message: "Cookie preferences updated",
          preferences: serialize_cookie_consent(consent)
        )
      end

      private

      def consent_params
        params.permit(
          :marketing, :analytics, :cookies, :data_sharing,
          :third_party, :communications, :newsletter, :promotional
        ).to_h.transform_values { |v| ActiveModel::Type::Boolean.new.cast(v) }
      end

      def export_params
        params.permit(:format, :export_type, include_data_types: [])
      end

      def deletion_params
        params.permit(:deletion_type, :reason, data_types_to_delete: [])
      end

      def cookie_params
        params.permit(:functional, :analytics, :marketing)
      end

      def current_user_export_requests
        DataManagement::ExportRequest.where(user: current_user)
                         .recent
                         .limit(5)
                         .map { |r| serialize_export_request(r) }
      end

      def current_user_deletion_requests
        DataManagement::DeletionRequest.where(user: current_user)
                           .recent
                           .limit(5)
                           .map { |r| serialize_deletion_request(r) }
      end

      def terms_acceptance_status
        {
          needs_review: TermsAcceptance.needs_acceptance?(current_user),
          missing: TermsAcceptance.missing_acceptances(current_user)
        }
      end

      def data_retention_summary
        DataManagement::RetentionPolicy.data_types.map do |type|
          policy = DataManagement::RetentionPolicy.policy_for(type, current_user.account)
          {
            data_type: type,
            retention_days: policy&.retention_days,
            action: policy&.action
          }
        end
      end

      def accepted_terms
        TermsAcceptance::CURRENT_VERSIONS.map do |doc_type, version|
          acceptance = TermsAcceptance.current_acceptance(current_user, doc_type)
          {
            document_type: doc_type,
            current_version: version,
            accepted: acceptance.present?,
            accepted_version: acceptance&.document_version,
            accepted_at: acceptance&.accepted_at
          }
        end
      end

      def serialize_export_request(request)
        {
          id: request.id,
          status: request.status,
          format: request.format,
          export_type: request.export_type,
          file_size_bytes: request.file_size_bytes,
          downloadable: request.downloadable?,
          download_token: request.download_token,
          download_token_expires_at: request.download_token_expires_at,
          created_at: request.created_at,
          completed_at: request.completed_at,
          expires_at: request.expires_at
        }
      end

      def serialize_deletion_request(request)
        {
          id: request.id,
          status: request.status,
          deletion_type: request.deletion_type,
          reason: request.reason,
          can_be_cancelled: request.can_be_cancelled?,
          in_grace_period: request.in_grace_period?,
          days_until_deletion: request.days_until_deletion,
          grace_period_ends_at: request.grace_period_ends_at,
          created_at: request.created_at,
          completed_at: request.completed_at
        }
      end

      def serialize_terms_acceptance(acceptance)
        {
          id: acceptance.id,
          document_type: acceptance.document_type,
          document_version: acceptance.document_version,
          accepted_at: acceptance.accepted_at
        }
      end

      def serialize_cookie_consent(consent)
        {
          necessary: consent.necessary,
          functional: consent.functional,
          analytics: consent.analytics,
          marketing: consent.marketing,
          consented_at: consent.consented_at
        }
      end

      def default_cookie_preferences
        {
          necessary: true,
          functional: false,
          analytics: false,
          marketing: false,
          consented_at: nil
        }
      end

      def content_type_for(format)
        case format
        when "json" then "application/json"
        when "csv", "zip" then "application/zip"
        else "application/octet-stream"
        end
      end
    end
  end
end
