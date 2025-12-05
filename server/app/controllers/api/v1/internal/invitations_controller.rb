# frozen_string_literal: true

module Api
  module V1
    module Internal
      class InvitationsController < ApplicationController
        skip_before_action :authenticate_request
        before_action :authenticate_worker

        def show
          invitation = Invitation.find(params[:id])

          render_success({
            id: invitation.id,
            email: invitation.email,
            first_name: invitation.first_name,
            last_name: invitation.last_name,
            role_names: invitation.role_names,
            expires_at: invitation.expires_at,
            account_name: invitation.account.name,
            inviter_first_name: invitation.inviter.first_name,
            inviter_last_name: invitation.inviter.last_name
          })
        rescue ActiveRecord::RecordNotFound
          render_not_found('Invitation')
        end

        private

        def authenticate_worker
          token = request.headers['Authorization']&.sub(/^Bearer /, '')
          worker_token = Rails.application.config.worker_token

          unless token.present? && worker_token.present? && token == worker_token
            render_unauthorized('Invalid worker authentication')
          end
        end
      end
    end
  end
end
