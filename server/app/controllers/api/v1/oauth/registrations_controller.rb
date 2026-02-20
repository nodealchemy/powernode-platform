# frozen_string_literal: true

module Api
  module V1
    module Oauth
      # RFC 7591 Dynamic Client Registration for MCP OAuth 2.1.
      # Public endpoint — no authentication required.
      # MCP clients call this to register themselves before starting the OAuth flow.
      class RegistrationsController < ActionController::API
        ALLOWED_SCOPES = %w[read write workflows files].freeze
        LOOPBACK_HOSTS = %w[127.0.0.1 localhost ::1 [::1]].freeze

        # POST /api/v1/oauth/register
        def create
          client_name = params[:client_name].presence || "MCP Client"
          redirect_uris = Array(params[:redirect_uris])
          raw_scopes = params[:scope].presence || params[:scopes].presence
          requested_scopes = if raw_scopes.is_a?(String)
            raw_scopes.split
          elsif raw_scopes.is_a?(Array)
            raw_scopes.flat_map { |s| s.split }
          else
            ALLOWED_SCOPES.dup
          end

          # Validate redirect URIs
          if redirect_uris.blank?
            render json: { error: "redirect_uris is required" }, status: :bad_request
            return
          end

          unless redirect_uris.all? { |uri| loopback_uri?(uri) }
            render json: {
              error: "invalid_redirect_uri",
              error_description: "Only loopback redirect URIs are allowed (127.0.0.1, localhost, ::1)"
            }, status: :bad_request
            return
          end

          # Restrict scopes
          scopes = requested_scopes & ALLOWED_SCOPES
          if scopes.empty?
            render json: {
              error: "invalid_scope",
              error_description: "Requested scopes not allowed. Supported: #{ALLOWED_SCOPES.join(', ')}"
            }, status: :bad_request
            return
          end

          # Create public OAuth application
          app = OauthApplication.create!(
            name: client_name,
            redirect_uri: redirect_uris.join("\n"),
            scopes: scopes.join(" "),
            confidential: false,
            trusted: false,
            status: "active",
            metadata: { registered_via: "mcp_dynamic_registration", registered_at: Time.current.iso8601 }
          )

          render json: {
            client_id: app.uid,
            client_name: app.name,
            redirect_uris: redirect_uris,
            grant_types: %w[authorization_code refresh_token],
            response_types: ["code"],
            token_endpoint_auth_method: "none",
            scope: scopes.join(" ")
          }, status: :created
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: "registration_failed", error_description: e.message }, status: :unprocessable_entity
        end

        private

        def loopback_uri?(uri_string)
          parsed = URI.parse(uri_string)
          LOOPBACK_HOSTS.include?(parsed.host)
        rescue URI::InvalidURIError
          false
        end
      end
    end
  end
end
