# frozen_string_literal: true

require 'websocket-client-simple'
require 'json'
require 'securerandom'
require 'openssl'
require_relative 'worker_cert_manager'

# Thread-safe ActionCable WebSocket client for worker → server communication.
# Implements the ActionCable client protocol (subscribe, message, ping)
# with request/response correlation via UUID request_ids.
#
# Auth is mTLS at the TLS handshake — the worker's client cert is
# presented via WorkerCertManager + the websocket-client-simple monkey
# patch (`config/initializers/websocket_client_simple_mtls.rb`). The
# previous `?token=#{jwt}` URL-param JWT path is gone.
#
# Usage:
#   client = ActionCableClient.new("wss://<platform-host>:443/cable")
#   client.connect
#   response = client.send_request("tool_definitions", agent_id: "uuid")
#   client.disconnect
class ActionCableClient
  DEFAULT_TIMEOUT = 30

  def initialize(url, channel: "WorkerToolDispatchChannel")
    @url = url
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
    options = {}
    options[:ssl_context] = build_ssl_context if @url.start_with?("wss://")
    @ws = WebSocket::Client::Simple.connect(@url, options)
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
  # Auto-reconnects once if the connection was lost since the last call.
  # Returns the parsed response hash (with "success", "data"/"error" keys).
  def send_request(action, params = {}, timeout: DEFAULT_TIMEOUT)
    reconnect! if !connected? && @url && @token

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

  # Attempt to re-establish a dropped connection.
  # Called automatically by send_request when the connection is down.
  def reconnect!
    disconnect rescue nil
    @welcome_received = false
    @subscribed = false
    connect
    logger&.info("[ActionCableClient] Reconnected to #{@url}")
  rescue StandardError => e
    logger&.warn("[ActionCableClient] Reconnect failed: #{e.message}")
    raise "Not connected"
  end

  private

  # Builds an OpenSSL::SSL::SSLContext carrying the worker's mTLS client
  # cert (read fresh from disk on each connect so post-rotation reconnects
  # pick up new material atomically). Server cert verification uses the
  # system trust store unless WORKER_TLS_VERIFY=false (dev override).
  def build_ssl_context
    opts = WorkerCertManager.instance.ssl_options
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.cert = opts[:client_cert] if opts[:client_cert]
    ctx.key  = opts[:client_key]  if opts[:client_key]
    ctx.verify_mode = opts[:verify] == false ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER
    ctx.cert_store = OpenSSL::X509::Store.new.tap(&:set_default_paths)
    ctx
  end

  def logger
    @logger ||= defined?(PowernodeWorker) ? PowernodeWorker.application.logger : Logger.new($stdout)
  end

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
