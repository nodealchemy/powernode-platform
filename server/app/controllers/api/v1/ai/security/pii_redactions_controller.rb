# frozen_string_literal: true

module Api
  module V1
    module Ai
      module Security
        class PiiRedactionsController < ApplicationController
          before_action :validate_permissions

          # POST /api/v1/ai/security/pii_redaction/scan
          def scan
            result = service.scan(text: params[:content])

            render_success(data: result)
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # POST /api/v1/ai/security/pii_redaction/redact
          def redact
            result = service.redact(text: params[:content])

            render_success(data: result)
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # POST /api/v1/ai/security/pii_redaction/apply_policy
          def apply_policy
            result = service.apply_policy(
              text: params[:content],
              classification_level: params[:classification_level] || "internal"
            )

            render_success(data: result)
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # POST /api/v1/ai/security/pii_redaction/check_output
          def check_output
            result = service.safe_to_output?(
              text: params[:content],
              max_confidence: params[:max_confidence]&.to_f || 0.7
            )

            render_success(data: { safe: result })
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          # POST /api/v1/ai/security/pii_redaction/batch_scan
          def batch_scan
            texts = params[:contents] || []
            result = service.batch_scan(texts: texts)

            render_success(data: result)
          rescue StandardError => e
            render_error(e.message, status: :unprocessable_content)
          end

          private

          def validate_permissions
            return if current_worker || current_service

            require_permission("ai.security.manage")
          end

          def service
            @service ||= ::Ai::Security::PiiRedactionService.new(account: current_account)
          end
        end
      end
    end
  end
end
