# frozen_string_literal: true

module Api
  module V1
    module Mcp
      class TokensController < ApplicationController
        before_action :require_permission

        # GET /api/v1/mcp/tokens
        def index
          tokens = current_user.user_tokens.by_type("mcp").recent

          render_success(tokens.map { |t| serialize_token(t) })
        end

        # POST /api/v1/mcp/tokens
        def create
          name = params[:name] || "MCP Token"
          requested_permissions = params[:permissions]

          # Validate requested permissions are a subset of user's current permissions
          if requested_permissions.present?
            unauthorized = requested_permissions - current_user.permission_names
            if unauthorized.any?
              render_error("Unauthorized permissions: #{unauthorized.join(', ')}", :forbidden)
              return
            end
          end

          token_permissions = requested_permissions.presence || current_user.permission_names

          result = UserToken.create_token_for_user(
            current_user,
            type: "mcp",
            name: name,
            permissions: token_permissions
          )

          user_token = result[:user_token]
          raw_token = result[:token]

          render_success({
            token: "pnmcp_#{raw_token}",
            token_id: user_token.id,
            name: user_token.name,
            permissions: user_token.permissions,
            expires_at: user_token.expires_at.iso8601,
            created_at: user_token.created_at.iso8601
          }, status: :created)
        end

        # DELETE /api/v1/mcp/tokens/:id
        def destroy
          token = current_user.user_tokens.by_type("mcp").find(params[:id])
          token.revoke!(reason: "manual")

          render_success({ id: token.id, revoked: true })
        end

        private

        def require_permission
          unless current_user.has_permission?("ai.agents.read")
            render_error("Permission denied", :forbidden)
          end
        end

        def serialize_token(token)
          {
            id: token.id,
            name: token.display_name,
            masked_token: token.masked_token,
            permissions: token.permissions,
            scopes: token.scopes,
            created_at: token.created_at.iso8601,
            last_used_at: token.last_used_at&.iso8601,
            expires_at: token.expires_at.iso8601,
            revoked: token.revoked
          }
        end
      end
    end
  end
end
