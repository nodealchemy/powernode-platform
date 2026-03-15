# frozen_string_literal: true

require 'websocket-client-simple'
require 'json'
require 'securerandom'

# Thread-safe ActionCable WebSocket client for worker → server communication.
# Implements the ActionCable client protocol (subscribe, message, ping)
# with request/response correlation via UUID request_ids.
#
# Usage:
#   client = ActionCableClient.new("ws://localhost:3000/cable", jwt_token)
#   client.connect
#   response = client.send_request("tool_definitions", agent_id: "uuid")
#   client.disconnect
class ActionCableClient
  DEFAULT_TIMEOUT = 30

  def initialize(url, token, channel: "WorkerToolDispatchChannel")
    @url = url
    @token = token
    @channel_identifier = { channel: channel }.to_json
    @pending = {}
    @global_mutex = Mutex.new
    @connected = false
    @subscribed = false
    @welcome_received = false
    @welcome_mutex = Mutex.new
    @welcome_cv = ConditionVariable.new
    @subscribe_mutex = Mutex.new
    @subscribe_cv = ConditionVariable.new
  end

  # Establish WebSocket connection and subscribe to the tool dispatch channel.
  # Blocks until welcome + subscription confirmation or timeout.
  # Returns self for chaining.
  def connect
    ws_url = "#{@url}?token=#{@token}"
    @ws = WebSocket::Client::Simple.connect(ws_url)
    setup_handlers
    wait_for_welcome(timeout: 5)
    subscribe_to_channel
    wait_for_subscription(timeout: 5)
    @connected = true
    self
  rescue StandardError
    @connected = false
    raise
  end

  # Send an action request and block until the response arrives.
  # Returns the parsed response hash (with "success", "data"/"error" keys).
  def send_request(action, params = {}, timeout: DEFAULT_TIMEOUT)
    raise "Not connected" unless connected?

    request_id = SecureRandom.uuid
    entry = { mutex: Mutex.new, cv: ConditionVariable.new, response: nil }
    @global_mutex.synchronize { @pending[request_id] = entry }

    data = { action: action, request_id: request_id }.merge(params).to_json
    message = { command: "message", identifier: @channel_identifier, data: data }.to_json
    @ws.send(message)

    entry[:mutex].synchronize do
      entry[:cv].wait(entry[:mutex], timeout) unless entry[:response]
    end

    @global_mutex.synchronize { @pending.delete(request_id) }
    raise "WebSocket request timeout (#{action})" unless entry[:response]
    entry[:response]
  end

  # Whether the connection is alive and the channel subscription is confirmed.
  def connected?
    @connected && @subscribed
  end

  # Cleanly unsubscribe and close the WebSocket.
  def disconnect
    @connected = false
    @subscribed = false
    if @ws
      unsub = { command: "unsubscribe", identifier: @channel_identifier }.to_json
      @ws.send(unsub) rescue nil
      @ws.close rescue nil
    end
    @ws = nil
  end

  private

  def setup_handlers
    client = self

    @ws.on :message do |msg|
      client.__send__(:handle_message, msg.data)
    end

    @ws.on :close do |e|
      client.__send__(:handle_close, e)
    end

    @ws.on :error do |e|
      client.__send__(:handle_error, e)
    end
  end

  def handle_message(raw_data)
    data = JSON.parse(raw_data)

    case data["type"]
    when "welcome"
      @welcome_mutex.synchronize do
        @welcome_received = true
        @welcome_cv.broadcast
      end
    when "confirm_subscription"
      @subscribe_mutex.synchronize do
        @subscribed = true
        @subscribe_cv.broadcast
      end
    when "reject_subscription"
      @subscribe_mutex.synchronize do
        @subscribed = false
        @subscribe_cv.broadcast
      end
    when "ping"
      # ActionCable server ping — no response needed
    when "disconnect"
      @connected = false
      @subscribed = false
      wake_all_pending
    else
      # Channel message — correlate by request_id
      message = data["message"]
      if message.is_a?(Hash) && message["request_id"]
        deliver_response(message["request_id"], message)
      end
    end
  rescue JSON::ParserError
    # Ignore unparseable frames
  end

  def handle_close(_event)
    @connected = false
    @subscribed = false
    wake_all_pending
  end

  def handle_error(_error)
    # Errors are typically followed by a close event
  end

  def deliver_response(request_id, message)
    @global_mutex.synchronize do
      entry = @pending[request_id]
      return unless entry

      entry[:mutex].synchronize do
        entry[:response] = message
        entry[:cv].broadcast
      end
    end
  end

  def wake_all_pending
    @global_mutex.synchronize do
      @pending.each_value do |entry|
        entry[:mutex].synchronize { entry[:cv].broadcast }
      end
    end
  end

  def wait_for_welcome(timeout: 5)
    @welcome_mutex.synchronize do
      unless @welcome_received
        @welcome_cv.wait(@welcome_mutex, timeout)
      end
    end
    raise "WebSocket welcome timeout" unless @welcome_received
  end

  def subscribe_to_channel
    sub = { command: "subscribe", identifier: @channel_identifier }.to_json
    @ws.send(sub)
  end

  def wait_for_subscription(timeout: 5)
    @subscribe_mutex.synchronize do
      unless @subscribed
        @subscribe_cv.wait(@subscribe_mutex, timeout)
      end
    end
    raise "WebSocket subscription rejected or timed out" unless @subscribed
  end
end
