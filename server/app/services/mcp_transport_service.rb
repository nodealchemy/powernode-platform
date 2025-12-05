# frozen_string_literal: true

# MCP Transport Service - Handles WebSocket connections and message routing for MCP protocol
class McpTransportService
  include ActiveModel::Model
  include ActiveModel::Attributes

  class TransportError < StandardError; end
  class ConnectionNotFoundError < TransportError; end

  attr_accessor :connection_id

  def initialize(connection_id:)
    @connection_id = connection_id
    @logger = Rails.logger
    @connections = {}
    @message_queue = {}
    @reconnection_attempts = {}
    @health_monitor_thread = nil
    @cleanup_thread = nil
    @shutdown = false

    # Initialize connection pool
    initialize_connection_pool
  end

  # Register a new WebSocket connection
  def register_connection(connection_id, client_info = {})
    @logger.info "[MCP_TRANSPORT] Registering connection: #{connection_id}"

    @connections[connection_id] = {
      id: connection_id,
      client_info: client_info,
      connected_at: Time.current,
      last_ping: Time.current,
      capabilities: {},
      message_queue: [],
      status: 'connected'
    }

    # Initialize message queue for this connection
    @message_queue[connection_id] = []

    @logger.info "[MCP_TRANSPORT] Connection registered: #{connection_id}"
  end

  # Store client capabilities for a connection
  def store_client_capabilities(connection_id, capabilities)
    connection = @connections[connection_id]
    raise ConnectionNotFoundError, "Connection not found: #{connection_id}" unless connection

    connection[:capabilities] = capabilities
    @logger.debug "[MCP_TRANSPORT] Stored capabilities for #{connection_id}: #{capabilities.keys}"
  end

  # Send message to specific connection
  def send_message(connection_id, message)
    connection = @connections[connection_id]
    raise ConnectionNotFoundError, "Connection not found: #{connection_id}" unless connection

    # Add to message queue if connection is not ready
    if connection[:status] != 'connected'
      queue_message(connection_id, message)
      return false
    end

    begin
      # Send via WebSocket channel
      McpChannel.broadcast_to_connection(connection_id, message)
      @logger.debug "[MCP_TRANSPORT] Message sent to #{connection_id}"
      true
    rescue StandardError => e
      @logger.error "[MCP_TRANSPORT] Failed to send message: #{e.message}"
      queue_message(connection_id, message)
      false
    end
  end

  # Broadcast message to all connections
  def broadcast_message(message, filters = {})
    sent_count = 0

    @connections.each do |conn_id, connection|
      next unless connection_matches_filters?(connection, filters)

      if send_message(conn_id, message)
        sent_count += 1
      end
    end

    @logger.info "[MCP_TRANSPORT] Broadcast message to #{sent_count} connections"
    sent_count
  end

  # Handle connection disconnect
  def disconnect_connection(connection_id)
    @logger.info "[MCP_TRANSPORT] Disconnecting connection: #{connection_id}"

    connection = @connections[connection_id]
    return unless connection

    # Mark as disconnected
    connection[:status] = 'disconnected'
    connection[:disconnected_at] = Time.current

    # Store messages for potential reconnection
    preserve_connection_state(connection_id)

    # If this is the last connection, stop background threads
    if @connections.values.count { |c| c[:status] == 'connected' } == 0
      stop_background_threads
    end

    @logger.info "[MCP_TRANSPORT] Connection disconnected: #{connection_id}"
  end

  # Remove connection completely
  def remove_connection(connection_id)
    @logger.info "[MCP_TRANSPORT] Removing connection: #{connection_id}"

    @connections.delete(connection_id)
    @message_queue.delete(connection_id)
    @reconnection_attempts.delete(connection_id)

    @logger.info "[MCP_TRANSPORT] Connection removed: #{connection_id}"
  end

  # Handle connection reconnection
  def reconnect_connection(connection_id, client_info = {})
    @logger.info "[MCP_TRANSPORT] Reconnecting connection: #{connection_id}"

    existing_connection = @connections[connection_id]

    if existing_connection
      # Update existing connection
      existing_connection[:status] = 'connected'
      existing_connection[:reconnected_at] = Time.current
      existing_connection[:client_info].merge!(client_info)

      # Send queued messages
      send_queued_messages(connection_id)
    else
      # Create new connection
      register_connection(connection_id, client_info)
    end

    # Reset reconnection attempts
    @reconnection_attempts[connection_id] = 0

    @logger.info "[MCP_TRANSPORT] Connection reconnected: #{connection_id}"
  end

  # Get connection status
  def connection_status(connection_id)
    connection = @connections[connection_id]
    return nil unless connection

    {
      id: connection_id,
      status: connection[:status],
      connected_at: connection[:connected_at],
      last_ping: connection[:last_ping],
      client_info: connection[:client_info],
      capabilities: connection[:capabilities],
      queued_messages: @message_queue[connection_id]&.size || 0
    }
  end

  # List all active connections
  def list_connections(filters = {})
    connections = @connections.values

    # Apply filters
    if filters[:status]
      connections = connections.select { |conn| conn[:status] == filters[:status] }
    end

    if filters[:capability]
      connections = connections.select do |conn|
        conn[:capabilities].key?(filters[:capability])
      end
    end

    connections.map { |conn| connection_status(conn[:id]) }
  end

  # Handle ping from client
  def handle_ping(connection_id)
    connection = @connections[connection_id]
    return unless connection

    connection[:last_ping] = Time.current

    # Send pong response
    send_message(connection_id, {
      jsonrpc: '2.0',
      method: 'pong',
      params: { timestamp: Time.current.iso8601 }
    })
  end

  # Monitor connection health
  def monitor_connection_health
    # Only log when taking action, not on every check
    stale_count = 0
    dead_count = 0

    @connections.each do |connection_id, connection|
      next unless connection[:status] == 'connected'

      # Check if connection is stale (no ping in last 60 seconds)
      if connection[:last_ping] < 60.seconds.ago
        @logger.warn "[MCP_TRANSPORT] Stale connection detected: #{connection_id}"
        stale_count += 1

        # Send ping to check if connection is alive
        send_ping(connection_id)
      end

      # Check for dead connections (no ping in last 5 minutes)
      if connection[:last_ping] < 5.minutes.ago
        @logger.warn "[MCP_TRANSPORT] Dead connection detected: #{connection_id}"
        dead_count += 1
        disconnect_connection(connection_id)
      end
    end

    # Only log summary if issues found
    if stale_count > 0 || dead_count > 0
      @logger.info "[MCP_TRANSPORT] Health check: #{stale_count} stale, #{dead_count} dead connections"
    end
  end

  # Get transport statistics
  def transport_stats
    connected_count = @connections.count { |_, conn| conn[:status] == 'connected' }
    disconnected_count = @connections.count { |_, conn| conn[:status] == 'disconnected' }
    total_queued_messages = @message_queue.values.sum(&:size)

    {
      total_connections: @connections.size,
      connected_connections: connected_count,
      disconnected_connections: disconnected_count,
      total_queued_messages: total_queued_messages,
      average_queue_size: @connections.size > 0 ? total_queued_messages.to_f / @connections.size : 0
    }
  end

  # Cleanup method to be called when service instance is no longer needed
  def cleanup
    @logger.info "[MCP_TRANSPORT] Cleaning up service instance"
    stop_background_threads
    @connections.clear
    @message_queue.clear
    @reconnection_attempts.clear
  end

  private

  def initialize_connection_pool
    @logger.info "[MCP_TRANSPORT] Initializing connection pool"

    # Start health monitoring background task
    start_health_monitoring

    # Initialize message cleanup task
    start_message_cleanup
  end

  def queue_message(connection_id, message)
    @message_queue[connection_id] ||= []
    @message_queue[connection_id] << {
      message: message,
      queued_at: Time.current,
      attempts: 0
    }

    # Limit queue size to prevent memory issues
    max_queue_size = 1000
    if @message_queue[connection_id].size > max_queue_size
      @message_queue[connection_id].shift # Remove oldest message
    end

    @logger.debug "[MCP_TRANSPORT] Message queued for #{connection_id}"
  end

  def send_queued_messages(connection_id)
    messages = @message_queue[connection_id] || []
    return if messages.empty?

    @logger.info "[MCP_TRANSPORT] Sending #{messages.size} queued messages to #{connection_id}"

    sent_messages = []
    messages.each do |queued_msg|
      if send_message(connection_id, queued_msg[:message])
        sent_messages << queued_msg
      else
        # Update attempt count
        queued_msg[:attempts] += 1

        # Remove message if too many attempts
        if queued_msg[:attempts] > 3
          sent_messages << queued_msg
          @logger.warn "[MCP_TRANSPORT] Dropping message after 3 attempts for #{connection_id}"
        end
      end
    end

    # Remove sent messages from queue
    @message_queue[connection_id] -= sent_messages
  end

  def preserve_connection_state(connection_id)
    # Keep connection state for potential reconnection (up to 24 hours)
    # In a production environment, this might be stored in Redis
    connection = @connections[connection_id]
    return unless connection

    connection[:preserved_until] = 24.hours.from_now
  end

  def connection_matches_filters?(connection, filters)
    return true if filters.empty?

    # Filter by account
    if filters[:account_id]
      client_account = connection[:client_info][:account_id]
      return false unless client_account == filters[:account_id]
    end

    # Filter by capability
    if filters[:capability]
      return false unless connection[:capabilities].key?(filters[:capability])
    end

    # Filter by connection status
    if filters[:status]
      return false unless connection[:status] == filters[:status]
    end

    true
  end

  def send_ping(connection_id)
    ping_message = {
      jsonrpc: '2.0',
      method: 'ping',
      params: { timestamp: Time.current.iso8601 }
    }

    send_message(connection_id, ping_message)
  end

  def start_health_monitoring
    # Store thread reference for cleanup
    @health_monitor_thread = Thread.new do
      loop do
        break if @shutdown

        begin
          monitor_connection_health
        rescue StandardError => e
          @logger.error "[MCP_TRANSPORT] Health monitoring error: #{e.message}"
        end

        # Sleep in small increments to allow quick shutdown
        6.times do
          break if @shutdown
          sleep 5
        end
      end
      @logger.info "[MCP_TRANSPORT] Health monitoring thread stopped"
    end
  end

  def start_message_cleanup
    # Store thread reference for cleanup
    @cleanup_thread = Thread.new do
      loop do
        break if @shutdown

        begin
          cleanup_expired_connections
          cleanup_old_messages
        rescue StandardError => e
          @logger.error "[MCP_TRANSPORT] Cleanup error: #{e.message}"
        end

        # Sleep in small increments to allow quick shutdown
        60.times do
          break if @shutdown
          sleep 5
        end
      end
      @logger.info "[MCP_TRANSPORT] Cleanup thread stopped"
    end
  end

  def stop_background_threads
    @logger.info "[MCP_TRANSPORT] Stopping background threads"
    @shutdown = true

    # Wait for threads to finish (with timeout)
    [@health_monitor_thread, @cleanup_thread].compact.each do |thread|
      thread.join(10) # Wait max 10 seconds
      thread.kill if thread.alive? # Force kill if still running
    end

    @health_monitor_thread = nil
    @cleanup_thread = nil
    @logger.info "[MCP_TRANSPORT] Background threads stopped"
  end

  def cleanup_expired_connections
    expired_connections = @connections.select do |_, connection|
      connection[:status] == 'disconnected' &&
      connection[:preserved_until] &&
      connection[:preserved_until] < Time.current
    end

    expired_connections.each do |connection_id, _|
      remove_connection(connection_id)
      @logger.info "[MCP_TRANSPORT] Removed expired connection: #{connection_id}"
    end
  end

  def cleanup_old_messages
    @message_queue.each do |connection_id, messages|
      # Remove messages older than 1 hour
      old_messages = messages.select { |msg| msg[:queued_at] < 1.hour.ago }

      if old_messages.any?
        @message_queue[connection_id] -= old_messages
        @logger.info "[MCP_TRANSPORT] Cleaned up #{old_messages.size} old messages for #{connection_id}"
      end
    end
  end
end