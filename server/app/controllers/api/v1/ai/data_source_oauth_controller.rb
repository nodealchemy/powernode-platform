# frozen_string_literal: true

module Api
  module V1
    module Ai
      # x-com-provider campaign (I1) — provider-agnostic OAuth 2.0 Authorization
      # Code + PKCE connect flow for a data source's credential. Two actions:
      #
      #   #authorize — JWT-authenticated. The operator starts the connect flow;
      #     we mint state + PKCE, stash them server-side, and return the
      #     provider's authorization URL for the browser to navigate to.
      #
      #   #callback — a top-level BROWSER GET (or POST, form_post response_mode)
      #     issued by the PROVIDER's redirect — NOT an API call from our own
      #     frontend. It carries no Authorization header, so JWT auth is skipped
      #     for this action ONLY. Its authorization/CSRF defense is entirely the
      #     `state` value minted by #authorize (see
      #     Ai::DataSources::OauthAuthorizationCodeService): it re-associates the
      #     request to the initiating account/user/data_source and is rejected
      #     if the state is missing, unknown, expired, or disagrees with the
      #     path's data_source_id.
      class DataSourceOauthController < ApplicationController
        include AuditLogging

        skip_before_action :authenticate_request, only: :callback

        before_action :set_data_source, only: :authorize
        before_action :validate_permissions, only: :authorize

        # POST /api/v1/ai/data_sources/:data_source_id/oauth/authorize
        def authorize
          result = oauth_service.build_authorize_request(
            data_source: @data_source,
            user: current_user,
            account: current_user.account,
            credential_id: params[:credential_id]
          )

          render_success(
            authorization_url: result[:authorization_url],
            redirect_uri: result[:redirect_uri],
            state: result[:state]
          )

          log_audit_event("ai.data_sources.oauth.authorize", @data_source)
        rescue ::Ai::DataSources::OauthAuthorizationCodeService::ConfigError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # GET|POST /api/v1/ai/data_sources/:data_source_id/oauth/callback
        # UNAUTHENTICATED — see the class comment. Never trusts the path's
        # :data_source_id over the state; the service itself makes that call.
        def callback
          result = oauth_service.handle_callback(
            path_data_source_id: params[:data_source_id],
            state: params[:state],
            code: params[:code],
            error: params[:error]
          )

          # Best-effort context for audit-log attribution only — NOT an
          # authorization decision. The service already decided success/failure
          # via the state check; this just lets log_audit_event name an account.
          @current_user = ::User.find_by(id: result[:user_id])
          @current_account = ::Account.find_by(id: result[:account_id])

          if result[:success]
            render_success(message: "OAuth connection successful", scopes: result[:scopes])
            log_audit_event("ai.data_sources.oauth.callback", @current_account, outcome: "success")
          else
            render_error(result[:error], status: :unprocessable_content)
            log_audit_event("ai.data_sources.oauth.callback", @current_account,
              outcome: "failed", error_message: result[:error]
            )
          end
        end

        private

        def oauth_service
          ::Ai::DataSources::OauthAuthorizationCodeService.new
        end

        def set_data_source
          @data_source = current_user.account.ai_data_sources.find(params[:data_source_id])
        rescue ActiveRecord::RecordNotFound
          render_error("Data source not found", status: :not_found)
        end

        def validate_permissions
          require_permission("ai.data_sources.update")
        end
      end
    end
  end
end
