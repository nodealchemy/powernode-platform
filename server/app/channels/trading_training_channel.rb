# frozen_string_literal: true

class TradingTrainingChannel < ApplicationCable::Channel
  def subscribed
    session_id = params[:session_id]
    account_id = params[:account_id]

    if current_user && authorized_for_account?(account_id)
      if session_id.present?
        stream_from "trading_training_#{session_id}"
        Rails.logger.info "User #{current_user.id} subscribed to training session #{session_id}"
      else
        stream_from "trading_training_account_#{account_id}"
        Rails.logger.info "User #{current_user.id} subscribed to all training updates for account #{account_id}"
      end

      transmit({
        type: "subscribed",
        message: "Connected to training session updates",
        session_id: session_id,
        timestamp: Time.current.iso8601
      })
    else
      Rails.logger.warn "Unauthorized training channel subscription attempt by user #{current_user&.id}"
      reject
    end
  end

  def unsubscribed
    Rails.logger.info "User #{current_user&.id} unsubscribed from training updates"
  end

  class << self
    def broadcast_tick_update(session)
      data = {
        type: "tick_update",
        session_id: session.id,
        completed_ticks: session.completed_ticks,
        total_ticks: session.total_ticks,
        progress_pct: session.progress_pct,
        metrics: session.metrics,
        timeline: session.timeline,
        status: session.status,
        timestamp: Time.current.iso8601
      }

      broadcast_to_session(session, data)
      broadcast_to_account(session.account_id, data)
    end

    def broadcast_completed(session)
      data = {
        type: "completed",
        session_id: session.id,
        status: session.status,
        results: session.results,
        completed_at: session.completed_at&.iso8601,
        timestamp: Time.current.iso8601
      }

      broadcast_to_session(session, data)
      broadcast_to_account(session.account_id, data)
    end

    def broadcast_failed(session)
      data = {
        type: "failed",
        session_id: session.id,
        status: session.status,
        error_message: session.error_message,
        timestamp: Time.current.iso8601
      }

      broadcast_to_session(session, data)
      broadcast_to_account(session.account_id, data)
    end

    private

    def broadcast_to_session(session, data)
      ActionCable.server.broadcast("trading_training_#{session.id}", data)
    end

    def broadcast_to_account(account_id, data)
      ActionCable.server.broadcast("trading_training_account_#{account_id}", data)
    end
  end
end
