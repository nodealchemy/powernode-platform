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
    def broadcast_session_created(session)
      data = {
        type: "session_created",
        session_id: session.id,
        name: session.name,
        status: session.status,
        timestamp: Time.current.iso8601
      }

      broadcast_to_account(session.account_id, data)
    end

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
      publish_worker_event(session, "failed")
    end

    def broadcast_cancelled(session)
      data = {
        type: "cancelled",
        session_id: session.id,
        status: session.status,
        timestamp: Time.current.iso8601
      }

      broadcast_to_session(session, data)
      broadcast_to_account(session.account_id, data)
      publish_worker_event(session, "cancelled")
    end

    def broadcast_paused(session)
      data = {
        type: "paused",
        session_id: session.id,
        status: session.status,
        timestamp: Time.current.iso8601
      }

      broadcast_to_session(session, data)
      broadcast_to_account(session.account_id, data)
      publish_worker_event(session, "paused")
    end

    def broadcast_config_updated(session, changes: {})
      data = {
        type: "config_updated",
        session_id: session.id,
        changes: changes,
        timestamp: Time.current.iso8601
      }

      broadcast_to_session(session, data)
      broadcast_to_account(session.account_id, data)
      publish_worker_event(session, "config_updated", changes: changes)
    end

    def broadcast_emergency_halt(session)
      data = {
        type: "emergency_halt",
        session_id: session.id,
        status: session.status,
        timestamp: Time.current.iso8601
      }

      broadcast_to_session(session, data)
      broadcast_to_account(session.account_id, data)
      publish_worker_event(session, "emergency_halt")
    end

    def broadcast_resumed(session)
      data = {
        type: "resumed",
        session_id: session.id,
        status: session.status,
        timestamp: Time.current.iso8601
      }

      broadcast_to_session(session, data)
      broadcast_to_account(session.account_id, data)
    end

    def broadcast_rebalance(session, epoch_data)
      data = {
        type: "rebalance",
        session_id: session.id,
        epoch_id: epoch_data[:epoch_id],
        strategies_promoted: epoch_data[:promoted],
        strategies_demoted: epoch_data[:demoted],
        strategies_decommissioned: epoch_data[:decommissioned],
        capital_movements: epoch_data[:capital_movements],
        smoothing_factor: epoch_data[:smoothing_factor],
        timestamp: Time.current.iso8601
      }

      broadcast_to_session(session, data)
      broadcast_to_account(session.account_id, data)
    end

    private

    # Push lifecycle events to the worker via Redis pub/sub.
    # The worker's SessionEventListener subscribes to this channel at
    # session start. Pub/sub is cross-database so this reaches workers on DB 1.
    def publish_worker_event(session, event, **extra)
      payload = { session_id: session.id, event: event, timestamp: Time.current.iso8601 }
      payload.merge!(extra) if extra.any?
      Powernode::Redis.client.publish("training_session_events", payload.to_json)
    rescue StandardError => e
      Rails.logger.warn("[TradingTrainingChannel] Failed to publish #{event} event: #{e.message}")
    end

    def broadcast_to_session(session, data)
      ActionCable.server.broadcast("trading_training_#{session.id}", data)
    end

    def broadcast_to_account(account_id, data)
      ActionCable.server.broadcast("trading_training_account_#{account_id}", data)
    end
  end
end
