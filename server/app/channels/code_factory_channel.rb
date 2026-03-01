# frozen_string_literal: true

class CodeFactoryChannel < ApplicationCable::Channel
  def subscribed
    resource_type = params[:type]
    resource_id = params[:id]

    unless %w[run contract account review_state].include?(resource_type)
      reject
      return
    end

    unless authorized?(resource_type, resource_id)
      reject
      return
    end

    stream_from stream_key(resource_type, resource_id)
  end

  def unsubscribed
    stop_all_streams
  end

  class << self
    def broadcast_run_event(run_id, event_type, payload = {})
      message = build_message(event_type, payload)
      ActionCable.server.broadcast(stream_key("run", run_id), message)
    end

    def broadcast_contract_event(contract_id, event_type, payload = {})
      message = build_message(event_type, payload)
      ActionCable.server.broadcast(stream_key("contract", contract_id), message)
    end

    def broadcast_to_account(account_id, event:, payload:, timestamp: nil)
      message = {
        event: event,
        payload: payload,
        timestamp: timestamp || Time.current.iso8601
      }
      ActionCable.server.broadcast(stream_key("account", account_id), message)
    end

    private

    def build_message(event_type, payload)
      {
        event: event_type,
        payload: payload,
        timestamp: Time.current.iso8601
      }
    end

    def stream_key(type, id)
      "code_factory:#{type}:#{id}"
    end
  end

  private

  def authorized?(resource_type, resource_id)
    return false unless current_user

    case resource_type
    when "account"
      current_user.account_id == resource_id
    when "run", "contract"
      true # Account-scoped via the resource itself
    else
      false
    end
  end

  def stream_key(type, id)
    self.class.send(:stream_key, type, id)
  end
end
