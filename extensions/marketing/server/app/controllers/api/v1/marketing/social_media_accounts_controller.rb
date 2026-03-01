# frozen_string_literal: true

module Api
  module V1
    module Marketing
      class SocialMediaAccountsController < ApplicationController
        before_action :set_social_account, only: %i[show update destroy test refresh_token]

        # GET /api/v1/marketing/social_accounts
        def index
          authorize_read!

          scope = current_user.account.marketing_social_media_accounts
          scope = scope.by_platform(params[:platform]) if params[:platform].present?
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.order(created_at: :desc)

          render_success(items: scope.map(&:account_summary))
        end

        # GET /api/v1/marketing/social_accounts/:id
        def show
          authorize_read!

          render_success(social_account: @social_account.account_details)
        end

        # POST /api/v1/marketing/social_accounts
        def create
          authorize_manage!

          social_account = current_user.account.marketing_social_media_accounts.build(social_account_params)
          social_account.connected_by = current_user
          social_account.status ||= "connected"

          if social_account.save
            render_success({ social_account: social_account.account_details }, status: :created)
          else
            render_error(social_account.errors.full_messages, status: :unprocessable_content)
          end
        end

        # PATCH/PUT /api/v1/marketing/social_accounts/:id
        def update
          authorize_manage!

          if @social_account.update(social_account_params)
            render_success(social_account: @social_account.account_details)
          else
            render_error(@social_account.errors.full_messages, status: :unprocessable_content)
          end
        end

        # DELETE /api/v1/marketing/social_accounts/:id
        def destroy
          authorize_manage!

          @social_account.destroy!
          render_success(message: "Social media account deleted successfully")
        end

        # POST /api/v1/marketing/social_accounts/:id/test
        def test
          authorize_manage!

          adapter = ::Marketing::SocialMedia::AdapterFactory.for_account(@social_account)
          result = adapter.test_connection

          render_success(
            message: "Connection test successful",
            details: result
          )
        rescue ::Marketing::SocialMedia::BaseAdapter::AdapterError => e
          render_error(e.message, status: :unprocessable_content)
        rescue NotImplementedError => e
          render_error("Connection test not yet implemented for #{@social_account.platform}", status: :not_implemented)
        end

        # POST /api/v1/marketing/social_accounts/:id/refresh_token
        def refresh_token
          authorize_manage!

          adapter = ::Marketing::SocialMedia::AdapterFactory.for_account(@social_account)
          adapter.refresh_token

          render_success(social_account: @social_account.reload.account_details)
        rescue ::Marketing::SocialMedia::BaseAdapter::AdapterError => e
          render_error(e.message, status: :unprocessable_content)
        rescue NotImplementedError => e
          render_error("Token refresh not yet implemented for #{@social_account.platform}", status: :not_implemented)
        end

        private

        def set_social_account
          @social_account = current_user.account.marketing_social_media_accounts.find(params[:id])
        end

        def social_account_params
          params.require(:social_account).permit(
            :platform, :platform_account_id, :platform_username,
            :token_expires_at, :scopes
          )
        end

        def authorize_read!
          return if current_user.has_permission?("marketing.social.read")

          render_error("Insufficient permissions", status: :forbidden)
        end

        def authorize_manage!
          return if current_user.has_permission?("marketing.social.manage")

          render_error("Insufficient permissions", status: :forbidden)
        end
      end
    end
  end
end
