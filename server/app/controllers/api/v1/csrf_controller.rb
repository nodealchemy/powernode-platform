# frozen_string_literal: true

module Api
  module V1
    class CsrfController < ApplicationController
      # Generate CSRF token for authenticated users
      def token
        unless current_user
          return render_error("Authentication required for CSRF token", status: :unauthorized)
        end

        csrf_token = generate_csrf_token

        render_success({
          csrf_token: csrf_token,
          expires_at: (Time.current + (Rails.configuration.x.csrf_token_expiry || 2.hours)).iso8601,
          header_name: Rails.configuration.x.csrf_token_header_name || "X-CSRF-Token"
        })
      end

      private

      def generate_csrf_token
        token = SecureRandom.base64(32)
        Rails.cache.write(
          "csrf_token_#{current_user.id}",
          token,
          expires_in: Rails.configuration.x.csrf_token_expiry || 2.hours
        )

        # Log token generation for audit purposes
        AuditLog.create!(
          user: current_user,
          account: current_account,
          action: "csrf_token_generated",
          resource_type: "User",
          resource_id: current_user.id,
          source: "api",
          severity: "low",
          risk_level: "low",
          ip_address: request.remote_ip,
          user_agent: request.user_agent&.truncate(255),
          metadata: {
            token_expires_at: (Time.current + (Rails.configuration.x.csrf_token_expiry || 2.hours)).iso8601
          }
        )

        token
      end
    end
  end
end
