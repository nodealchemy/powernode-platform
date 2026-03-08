# frozen_string_literal: true

class TradingChannel < ApplicationCable::Channel
  def subscribed
    account_id = params[:account_id]

    if current_user && authorized_for_account?(account_id)
      stream_from "trading_account_#{account_id}"
      Rails.logger.info "User #{current_user.id} subscribed to trading updates for account #{account_id}"

      transmit({
        type: "subscribed",
        message: "Connected to trading updates",
        timestamp: Time.current.iso8601
      })
    else
      Rails.logger.warn "Unauthorized trading channel subscription attempt by user #{current_user&.id}"
      reject
    end
  end

  def unsubscribed
    Rails.logger.info "User #{current_user&.id} unsubscribed from trading updates"
  end

  class << self
    def broadcast_to_account(account_id, event_type, payload = {})
      data = { type: event_type, timestamp: Time.current.iso8601 }.merge(payload)
      ActionCable.server.broadcast("trading_account_#{account_id}", data)
    end
  end
end
