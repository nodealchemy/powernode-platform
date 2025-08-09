# frozen_string_literal: true

module ApplicationCable
  class Channel < ActionCable::Channel::Base
    protected

    # Helper method to get current user's account
    def current_account
      @current_account ||= current_user&.account
    end

    # Helper method to check if user can access account data
    def authorized_for_account?(account_id)
      return false unless current_user&.account

      # User can access their own account data
      current_user.account.id == account_id
    end

    # Helper method to broadcast to account-specific stream
    def broadcast_to_account(account, data)
      ActionCable.server.broadcast("account_#{account.id}", data)
    end

    # Helper method to stream from account-specific channel
    def stream_for_account(account)
      stream_from("account_#{account.id}")
    end
  end
end