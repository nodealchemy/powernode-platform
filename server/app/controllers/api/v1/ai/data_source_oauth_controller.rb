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
      #     path's data_source_id. (I5) Because the caller is a real browser, the
      #     default (:html) response REDIRECTS to the frontend's data-sources
      #     route with an `?oauth=success|failed` status so the operator lands
      #     back in the app instead of staring at a raw JSON body; a caller that
      #     explicitly negotiates :json (tests, or a future API client) still
      #     gets the plain success/error envelope.
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

          # Respond BEFORE logging (mirrors #authorize above): AuditLogging#log_audit_event
          # re-raises in test env, and ApiResponse's rescue_from only renders its own
          # error response `unless performed?` — logging first would let an audit-log
          # failure clobber the callback response the operator/provider is waiting on.
          respond_to_callback(result)

          if result[:success]
            log_audit_event("ai.data_sources.oauth.callback", @current_account, outcome: "success")
          else
            log_audit_event("ai.data_sources.oauth.callback", @current_account,
              outcome: "failed", error_message: result[:error]
            )
          end
        end

        private

        # The real caller is always the provider's top-level browser redirect (see
        # the class comment), which negotiates :html by default — so that's the
        # branch that sends the operator back into the app. A caller that explicitly
        # asks for JSON (an API client, or a request spec using `as: :json`) keeps
        # the raw success/error envelope instead, unchanged from I1.
        def respond_to_callback(result)
          if request.format.json?
            if result[:success]
              render_success(message: "OAuth connection successful", scopes: result[:scopes])
            else
              render_error(result[:error], status: :unprocessable_content)
            end
          else
            redirect_to(callback_redirect_url(result), allow_other_host: true)
          end
        end

        # Frontend landing route + status query params for the post-connect UX
        # (I5). data_source_id only travels here when the state itself resolved
        # one (never the untrusted path param) — the frontend uses it to reopen
        # that source's detail view; its absence just means a generic toast.
        def callback_redirect_url(result)
          frontend = ::AdminSetting.frontend_url_for_request(request)
          query = { oauth: result[:success] ? "success" : "failed" }
          query[:data_source_id] = result[:data_source_id] if result[:data_source_id].present?
          query[:error] = result[:error] if result[:error].present?
          "#{frontend}/app/ai/infrastructure/data-sources?#{query.to_query}"
        end

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
