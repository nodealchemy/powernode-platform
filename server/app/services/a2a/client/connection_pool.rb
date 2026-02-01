# frozen_string_literal: true

module A2a
  module Client
    # ConnectionPool - Manages HTTP connections to external A2A agents
    # Provides connection reuse and health monitoring
    class ConnectionPool
      include Singleton

      DEFAULT_POOL_SIZE = 5
      CONNECTION_TIMEOUT = 30
      IDLE_TIMEOUT = 60

      def initialize
        @pools = {}
        @mutex = Mutex.new
        @stats = Hash.new { |h, k| h[k] = { requests: 0, errors: 0, avg_time_ms: 0 } }
      end

      # Get or create a connection pool for a host
      def pool_for(host)
        @mutex.synchronize do
          @pools[host] ||= create_pool(host)
        end
      end

      # Execute a request using a pooled connection
      def with_connection(host, &block)
        pool = pool_for(host)

        start_time = Time.current
        result = nil
        error = nil

        begin
          result = pool.with { |conn| block.call(conn) }
          record_request(host, start_time, success: true)
        rescue StandardError => e
          error = e
          record_request(host, start_time, success: false)
          raise
        end

        result
      end

      # Get connection statistics
      def stats
        @mutex.synchronize { @stats.dup }
      end

      # Clear all pools
      def clear!
        @mutex.synchronize do
          @pools.each_value(&:shutdown)
          @pools.clear
          @stats.clear
        end
      end

      # Warm up connections to an agent
      def warm_up(host, count: 2)
        pool = pool_for(host)
        connections = []

        count.times do
          pool.with { |conn| connections << conn }
        end

        Rails.logger.info("A2A connection pool warmed up for #{host} with #{count} connections")
      end

      private

      def create_pool(host)
        uri = URI.parse(host.start_with?("http") ? host : "https://#{host}")

        ConnectionPool::Wrapper.new(size: DEFAULT_POOL_SIZE, timeout: CONNECTION_TIMEOUT) do
          Net::HTTP.new(uri.host, uri.port).tap do |http|
            http.use_ssl = uri.scheme == "https"
            http.open_timeout = 10
            http.read_timeout = 30
            http.keep_alive_timeout = IDLE_TIMEOUT
          end
        end
      end

      def record_request(host, start_time, success:)
        duration_ms = ((Time.current - start_time) * 1000).round(2)

        @mutex.synchronize do
          stats = @stats[host]
          stats[:requests] += 1
          stats[:errors] += 1 unless success

          # Update rolling average
          if stats[:avg_time_ms].zero?
            stats[:avg_time_ms] = duration_ms
          else
            stats[:avg_time_ms] = (stats[:avg_time_ms] * 0.9 + duration_ms * 0.1).round(2)
          end
        end
      end
    end

    # Simple connection pool wrapper (if connection_pool gem not available)
    module ConnectionPool
      class Wrapper
        def initialize(size:, timeout:, &block)
          @size = size
          @timeout = timeout
          @block = block
          @connections = Queue.new
          @mutex = Mutex.new
          @created = 0

          # Pre-create connections
          size.times { @connections << @block.call }
          @created = size
        end

        def with
          conn = checkout
          begin
            yield conn
          ensure
            checkin(conn)
          end
        end

        def shutdown
          until @connections.empty?
            conn = @connections.pop(true) rescue nil
            conn&.finish rescue nil
          end
        end

        private

        def checkout
          @connections.pop(true)
        rescue ThreadError
          @mutex.synchronize do
            if @created < @size
              @created += 1
              @block.call
            else
              @connections.pop
            end
          end
        end

        def checkin(conn)
          @connections << conn
        rescue ThreadError
          conn&.finish rescue nil
        end
      end
    end
  end
end
