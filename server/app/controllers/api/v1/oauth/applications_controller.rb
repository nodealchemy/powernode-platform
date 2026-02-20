# frozen_string_literal: true

module Api
  module V1
    module Oauth
      class ApplicationsController < ApplicationController
        skip_before_action :authenticate_request, only: [:lookup]
        before_action -> { require_permission("oauth.applications.read") }, only: %i[index show]
        before_action -> { require_permission("oauth.applications.manage") }, only: %i[create update destroy regenerate_secret suspend activate revoke]
        before_action :set_application, only: %i[show update destroy regenerate_secret suspend activate revoke tokens revoke_tokens]

        # GET /api/v1/oauth/applications/lookup?uid=CLIENT_ID
        # Public endpoint for consent page to display app name/scopes
        def lookup
          app = OauthApplication.where(status: "active").find_by(uid: params[:uid])
          if app
            render_success(name: app.name, scopes: app.scopes.to_s.split(" "))
          else
            render_error("Application not found", :not_found)
          end
        end

        # GET /api/v1/oauth/applications
        def index
          applications = base_scope
                         .order(created_at: :desc)
                         .page(params[:page])
                         .per(params[:per_page] || 20)

          render_success(
            applications: applications.map { |app| serialize_application(app) },
            pagination: {
              current_page: applications.current_page,
              total_pages: applications.total_pages,
              total_count: applications.total_count,
              per_page: applications.limit_value
            }
          )
        end

        # GET /api/v1/oauth/applications/:id
        def show
          render_success(application: serialize_application(@application))
        end

        # POST /api/v1/oauth/applications
        def create
          @application = OauthApplication.new(application_params)
          @application.owner = owner_from_params

          if @application.save
            # Log creation
            AuditLog.create!(
              user: current_user,
              account: current_account,
              action: "oauth_application_created",
              resource_type: "OauthApplication",
              resource_id: @application.id,
              source: "api",
              ip_address: request.remote_ip,
              metadata: { application_name: @application.name, scopes: @application.scopes }
            )

            render_success(
              application: serialize_application(@application, include_secret: true),
              message: "OAuth application created successfully. Please save the client secret - it will not be shown again."
            )
          else
            render_validation_error(@application)
          end
        end

        # PUT /api/v1/oauth/applications/:id
        def update
          if @application.update(application_params.except(:uid))
            AuditLog.create!(
              user: current_user,
              account: current_account,
              action: "oauth_application_updated",
              resource_type: "OauthApplication",
              resource_id: @application.id,
              source: "api",
              ip_address: request.remote_ip,
              metadata: { updated_fields: application_params.keys }
            )

            render_success(
              application: serialize_application(@application),
              message: "OAuth application updated successfully"
            )
          else
            render_validation_error(@application)
          end
        end

        # DELETE /api/v1/oauth/applications/:id
        def destroy
          @application.destroy

          AuditLog.create!(
            user: current_user,
            account: current_account,
            action: "oauth_application_deleted",
            resource_type: "OauthApplication",
            resource_id: @application.id,
            source: "api",
            ip_address: request.remote_ip,
            metadata: { application_name: @application.name }
          )

          render_success(message: "OAuth application deleted successfully")
        end

        # POST /api/v1/oauth/applications/:id/regenerate_secret
        def regenerate_secret
          new_secret = @application.regenerate_secret!

          AuditLog.create!(
            user: current_user,
            account: current_account,
            action: "oauth_application_secret_regenerated",
            resource_type: "OauthApplication",
            resource_id: @application.id,
            source: "api",
            ip_address: request.remote_ip,
            severity: "high",
            metadata: { application_name: @application.name }
          )

          render_success(
            secret: new_secret,
            message: "Client secret regenerated. Please save it - it will not be shown again."
          )
        end

        # POST /api/v1/oauth/applications/:id/suspend
        def suspend
          @application.suspend!(reason: params[:reason])

          AuditLog.create!(
            user: current_user,
            account: current_account,
            action: "oauth_application_suspended",
            resource_type: "OauthApplication",
            resource_id: @application.id,
            source: "api",
            ip_address: request.remote_ip,
            severity: "high",
            metadata: { application_name: @application.name, reason: params[:reason] }
          )

          render_success(
            application: serialize_application(@application),
            message: "OAuth application suspended and all tokens revoked"
          )
        end

        # POST /api/v1/oauth/applications/:id/activate
        def activate
          @application.activate!

          AuditLog.create!(
            user: current_user,
            account: current_account,
            action: "oauth_application_activated",
            resource_type: "OauthApplication",
            resource_id: @application.id,
            source: "api",
            ip_address: request.remote_ip,
            metadata: { application_name: @application.name }
          )

          render_success(
            application: serialize_application(@application),
            message: "OAuth application activated"
          )
        end

        # POST /api/v1/oauth/applications/:id/revoke
        def revoke
          @application.revoke!

          AuditLog.create!(
            user: current_user,
            account: current_account,
            action: "oauth_application_revoked",
            resource_type: "OauthApplication",
            resource_id: @application.id,
            source: "api",
            ip_address: request.remote_ip,
            severity: "critical",
            metadata: { application_name: @application.name }
          )

          render_success(
            application: serialize_application(@application),
            message: "OAuth application permanently revoked"
          )
        end

        # GET /api/v1/oauth/applications/:id/tokens
        def tokens
          tokens = @application.access_tokens
                               .order(created_at: :desc)
                               .page(params[:page])
                               .per(params[:per_page] || 20)

          render_success(
            tokens: tokens.map { |t| serialize_token(t) },
            pagination: {
              current_page: tokens.current_page,
              total_pages: tokens.total_pages,
              total_count: tokens.total_count
            }
          )
        end

        # DELETE /api/v1/oauth/applications/:id/tokens
        def revoke_tokens
          count = @application.access_tokens.where(revoked_at: nil).update_all(revoked_at: Time.current)

          AuditLog.create!(
            user: current_user,
            account: current_account,
            action: "oauth_tokens_bulk_revoked",
            resource_type: "OauthApplication",
            resource_id: @application.id,
            source: "api",
            ip_address: request.remote_ip,
            metadata: { application_name: @application.name, tokens_revoked: count }
          )

          render_success(
            revoked_count: count,
            message: "#{count} access tokens revoked"
          )
        end

        private

        def base_scope
          if current_user.has_permission?("admin.oauth.manage")
            OauthApplication.all
          else
            OauthApplication.for_owner(current_account)
          end
        end

        def set_application
          @application = base_scope.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("OAuth application not found", :not_found)
        end

        def owner_from_params
          if params[:owner_type] == "user" && current_user.has_permission?("admin.oauth.manage")
            User.find(params[:owner_id])
          else
            current_account
          end
        end

        def application_params
          params.require(:application).permit(
            :name,
            :description,
            :redirect_uri,
            :scopes,
            :confidential,
            :trusted,
            :machine_client,
            :rate_limit_tier
          )
        end

        def serialize_application(app, include_secret: false)
          app.as_json(include_secret: include_secret).merge(
            owner: app.owner ? { type: app.owner_type, id: app.owner_id, name: app.owner.try(:name) } : nil
          )
        end

        def serialize_token(token)
          owner = token.resource_owner_id ? User.find_by(id: token.resource_owner_id) : nil
          {
            id: token.id,
            scopes: token.scopes.to_s.split(" "),
            created_at: token.created_at,
            expires_at: token.expires_in ? token.created_at + token.expires_in.seconds : nil,
            revoked_at: token.revoked_at,
            active: token.revoked_at.nil? && (token.expires_in.nil? || token.created_at + token.expires_in.seconds > Time.current),
            resource_owner: owner ? {
              id: owner.id,
              email: owner.email
            } : nil
          }
        end
      end
    end
  end
end
