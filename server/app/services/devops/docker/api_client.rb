# frozen_string_literal: true

module Devops
  module Docker
    class ApiClient
      class ApiError < StandardError
        attr_reader :status, :response

        def initialize(message, status = nil, response = nil)
          super(message)
          @status = status
          @response = response
        end
      end

      class ConnectionError < ApiError; end
      class AuthenticationError < ApiError; end
      class NotFoundError < ApiError; end
      class ConflictError < ApiError; end
      class ServerError < ApiError; end

      def initialize(cluster)
        @cluster = cluster
        @base_url = cluster.api_endpoint
        @api_version = cluster.api_version || "v1.45"
        @tls_verify = cluster.respond_to?(:tls_verify) ? cluster.tls_verify : true
        @tls_credentials = parse_tls_credentials
      end

      # System
      def ping
        get("/_ping")
      end

      def info
        get("/info")
      end

      # Swarm
      def swarm_inspect
        get("/swarm")
      end

      # Nodes
      def node_list
        get("/nodes")
      end

      def node_inspect(id)
        get("/nodes/#{id}")
      end

      def node_update(id, version, spec)
        post("/nodes/#{id}/update?version=#{version}", spec)
      end

      def node_delete(id)
        delete("/nodes/#{id}")
      end

      # Services
      def service_list
        get("/services")
      end

      def service_inspect(id)
        get("/services/#{id}")
      end

      def service_create(spec)
        post("/services/create", spec)
      end

      def service_update(id, version, spec)
        post("/services/#{id}/update?version=#{version}", spec)
      end

      def service_delete(id)
        delete("/services/#{id}")
      end

      def service_logs(id, opts = {})
        params = {
          stdout: opts.fetch(:stdout, true),
          stderr: opts.fetch(:stderr, true),
          tail: opts.fetch(:tail, "100"),
          timestamps: opts.fetch(:timestamps, true)
        }
        params[:since] = opts[:since].to_i if opts[:since]
        raw = get_raw("/services/#{id}/logs", params)
        parse_docker_logs(raw)
      end

      # Tasks
      def task_list(filters = {})
        params = {}
        params[:filters] = filters.to_json if filters.present?
        get("/tasks", params)
      end

      def task_inspect(id)
        get("/tasks/#{id}")
      end

      # Secrets
      def secret_list
        get("/secrets")
      end

      def secret_inspect(id)
        get("/secrets/#{id}")
      end

      def secret_create(spec)
        post("/secrets/create", spec)
      end

      def secret_delete(id)
        delete("/secrets/#{id}")
      end

      # Configs
      def config_list
        get("/configs")
      end

      def config_inspect(id)
        get("/configs/#{id}")
      end

      def config_create(spec)
        post("/configs/create", spec)
      end

      def config_delete(id)
        delete("/configs/#{id}")
      end

      # Networks
      def network_list
        get("/networks")
      end

      def network_inspect(id)
        get("/networks/#{id}")
      end

      def network_create(spec)
        post("/networks/create", spec)
      end

      def network_delete(id)
        delete("/networks/#{id}")
      end

      # Volumes
      def volume_list
        get("/volumes")
      end

      def volume_inspect(id)
        get("/volumes/#{id}")
      end

      def volume_create(spec)
        post("/volumes/create", spec)
      end

      def volume_delete(id)
        delete("/volumes/#{id}")
      end

      # Containers
      def container_list(filters = {})
        params = {}
        params[:filters] = filters.to_json if filters.present?
        get("/containers/json", params)
      end

      def container_inspect(id)
        get("/containers/#{id}/json")
      end

      def container_create(name, params)
        response = post("/containers/create?name=#{name}", params)
        response
      end

      def container_start(id)
        post("/containers/#{id}/start")
      end

      def container_stop(id, timeout = 10)
        post("/containers/#{id}/stop?t=#{timeout}")
      end

      def container_restart(id, timeout = 10)
        post("/containers/#{id}/restart?t=#{timeout}")
      end

      def container_remove(id, force: false)
        delete("/containers/#{id}?force=#{force}")
      end

      def container_logs(id, opts = {})
        params = {
          stdout: opts.fetch(:stdout, true),
          stderr: opts.fetch(:stderr, true),
          tail: opts.fetch(:tail, "100"),
          timestamps: opts.fetch(:timestamps, true)
        }
        params[:since] = opts[:since].to_i if opts[:since]
        raw = get_raw("/containers/#{id}/logs", params)
        parse_docker_logs(raw)
      end

      def container_stats(id, stream: false)
        get("/containers/#{id}/stats?stream=#{stream}")
      end

      def container_top(id)
        get("/containers/#{id}/top")
      end

      # Container exec (2-step process: create → start)
      def container_exec_create(container_id, cmd, opts = {})
        body = {
          "AttachStdout" => true,
          "AttachStderr" => true,
          "Cmd" => Array(cmd)
        }
        body["Env"] = opts[:env] if opts[:env]
        body["WorkingDir"] = opts[:working_dir] if opts[:working_dir]
        post("/containers/#{container_id}/exec", body)
      end

      def container_exec_start(exec_id)
        raw = post_raw("/exec/#{exec_id}/start", { "Detach" => false, "Tty" => false })
        parse_docker_logs(raw)
      end

      def container_exec_inspect(exec_id)
        get("/exec/#{exec_id}/json")
      end

      # Images
      def image_list
        get("/images/json")
      end

      def image_inspect(id)
        get("/images/#{id}/json")
      end

      def image_pull(image, tag = "latest", auth_config: nil)
        params = { fromImage: image, tag: tag }
        if auth_config
          post_with_headers("/images/create", params, { "X-Registry-Auth" => auth_config })
        else
          post("/images/create?fromImage=#{image}&tag=#{tag}")
        end
      end

      def image_remove(id, force: false)
        delete("/images/#{id}?force=#{force}")
      end

      def image_tag(id, repo, tag)
        post("/images/#{id}/tag?repo=#{repo}&tag=#{tag}")
      end

      protected

      def connection
        @connection ||= build_connection
      end

      def build_connection
        Faraday.new(url: @base_url) do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/
          conn.headers["Accept"] = "application/json"
          conn.headers["User-Agent"] = "Powernode/1.0"
          conn.options.timeout = 30
          conn.options.open_timeout = 10
          conn.ssl.verify = @tls_verify
          configure_tls(conn) if @tls_credentials
          conn.adapter Faraday.default_adapter
        end
      rescue Faraday::ConnectionFailed, Faraday::SSLError => e
        raise ConnectionError.new("Failed to connect to Docker API at #{@base_url}: #{e.message}")
      rescue OpenSSL::PKey::PKeyError, OpenSSL::X509::CertificateError => e
        raise ConnectionError.new("Invalid TLS credentials: #{e.message}")
      end

      def configure_tls(conn)
        conn.ssl.client_cert = OpenSSL::X509::Certificate.new(@tls_credentials[:client_cert])
        conn.ssl.client_key = OpenSSL::PKey.read(clean_pem_key(@tls_credentials[:client_key]))

        # Write CA cert to tempfile for Faraday SSL verification
        ca_cert = @tls_credentials[:ca_cert]
        if ca_cert.present?
          @ca_tempfile = Tempfile.new(["docker-ca", ".pem"])
          @ca_tempfile.write(ca_cert)
          @ca_tempfile.flush
          conn.ssl.ca_file = @ca_tempfile.path
        end
      end

      def get(path, params = {})
        response = connection.get(versioned_path(path), params)
        handle_response(response)
      rescue Faraday::ConnectionFailed, Faraday::SSLError => e
        raise ConnectionError.new("Connection failed: #{e.message}")
      rescue Faraday::TimeoutError => e
        raise ConnectionError.new("Request timed out: #{e.message}")
      end

      def get_raw(path, params = {})
        response = connection.get(versioned_path(path), params)
        case response.status
        when 200..299
          response.body
        when 404
          raise NotFoundError.new("Resource not found", response.status, response.body)
        else
          error_message = response.body.is_a?(Hash) ? extract_error_message(response.body) : response.body.to_s
          raise ApiError.new("API error (#{response.status}): #{error_message}", response.status, response.body)
        end
      rescue Faraday::ConnectionFailed, Faraday::SSLError => e
        raise ConnectionError.new("Connection failed: #{e.message}")
      rescue Faraday::TimeoutError => e
        raise ConnectionError.new("Request timed out: #{e.message}")
      end

      def post(path, body = {})
        response = connection.post(versioned_path(path), body.to_json)
        handle_response(response)
      rescue Faraday::ConnectionFailed, Faraday::SSLError => e
        raise ConnectionError.new("Connection failed: #{e.message}")
      rescue Faraday::TimeoutError => e
        raise ConnectionError.new("Request timed out: #{e.message}")
      end

      def put(path, body = {})
        response = connection.put(versioned_path(path), body.to_json)
        handle_response(response)
      rescue Faraday::ConnectionFailed, Faraday::SSLError => e
        raise ConnectionError.new("Connection failed: #{e.message}")
      rescue Faraday::TimeoutError => e
        raise ConnectionError.new("Request timed out: #{e.message}")
      end

      def delete(path)
        response = connection.delete(versioned_path(path))
        handle_response(response)
      rescue Faraday::ConnectionFailed, Faraday::SSLError => e
        raise ConnectionError.new("Connection failed: #{e.message}")
      rescue Faraday::TimeoutError => e
        raise ConnectionError.new("Request timed out: #{e.message}")
      end

      def post_raw(path, body = {})
        response = connection.post(versioned_path(path), body.to_json)
        case response.status
        when 200..299
          response.body
        when 404
          raise NotFoundError.new("Resource not found", response.status, response.body)
        else
          error_message = response.body.is_a?(Hash) ? extract_error_message(response.body) : response.body.to_s
          raise ApiError.new("API error (#{response.status}): #{error_message}", response.status, response.body)
        end
      rescue Faraday::ConnectionFailed, Faraday::SSLError => e
        raise ConnectionError.new("Connection failed: #{e.message}")
      rescue Faraday::TimeoutError => e
        raise ConnectionError.new("Request timed out: #{e.message}")
      end

      def post_with_headers(path, params = {}, headers = {})
        response = connection.post(versioned_path(path)) do |req|
          req.params = params
          headers.each { |k, v| req.headers[k] = v }
        end
        handle_response(response)
      rescue Faraday::ConnectionFailed, Faraday::SSLError => e
        raise ConnectionError.new("Connection failed: #{e.message}")
      rescue Faraday::TimeoutError => e
        raise ConnectionError.new("Request timed out: #{e.message}")
      end

      def handle_response(response)
        case response.status
        when 200..299
          response.body
        when 401
          raise AuthenticationError.new("Authentication failed - check TLS credentials", response.status, response.body)
        when 403
          raise AuthenticationError.new("Access forbidden - check TLS certificate permissions", response.status, response.body)
        when 404
          raise NotFoundError.new("Resource not found", response.status, response.body)
        when 409
          error_message = extract_error_message(response.body)
          raise ConflictError.new("Conflict: #{error_message}", response.status, response.body)
        when 500..599
          error_message = extract_error_message(response.body)
          raise ServerError.new("Docker API error (#{response.status}): #{error_message}", response.status, response.body)
        else
          error_message = extract_error_message(response.body)
          raise ApiError.new("Unexpected response (#{response.status}): #{error_message}", response.status, response.body)
        end
      end

      private

      def versioned_path(path)
        # Paths starting with /_ (like /_ping) are unversioned
        return path.sub(/\A\//, "") if path.start_with?("/_")

        "#{@api_version}#{path}".sub(/\A\//, "")
      end

      def parse_tls_credentials
        return nil if @cluster.encrypted_tls_credentials.blank?

        creds = JSON.parse(@cluster.encrypted_tls_credentials)
        {
          ca_cert: creds["ca_cert"],
          client_cert: creds["client_cert"],
          client_key: creds["client_key"]
        }
      rescue JSON::ParserError => e
        Rails.logger.error("Failed to parse TLS credentials for cluster #{@cluster.id}: #{e.message}")
        nil
      end

      # Strip Docker Swarm metadata lines (kek-version, raft-dek, etc.) from PEM keys
      def clean_pem_key(key_pem)
        return key_pem if key_pem.blank?

        key_pem.lines.reject { |line| line.match?(/\A[a-z]+-[a-z]+:/i) || line.strip.empty? }.join
      end

      def extract_error_message(body)
        return body unless body.is_a?(Hash)

        body["message"] || body["error"] || body.to_json
      end

      # Parse Docker multiplexed log stream into structured entries.
      # Docker uses 8-byte headers per frame: [stream_type(1), 0, 0, 0, size(4 bytes big-endian)]
      # Stream types: 0=stdin, 1=stdout, 2=stderr
      def parse_docker_logs(raw_body)
        return [] if raw_body.blank?

        # If response is already parsed as a Hash (error response), return empty
        return [] if raw_body.is_a?(Hash)

        entries = []
        data = raw_body.to_s.dup.force_encoding("BINARY")
        pos = 0
        parsed_any = false

        while pos + 8 <= data.bytesize
          stream_type_byte = data.getbyte(pos)
          break unless [0, 1, 2].include?(stream_type_byte)

          frame_size = data[pos + 4, 4].unpack1("N")
          pos += 8

          break if frame_size <= 0 || frame_size > 1_048_576 || pos + frame_size > data.bytesize

          frame = data[pos, frame_size].force_encoding("UTF-8")
          frame = frame.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
          pos += frame_size
          parsed_any = true

          stream_name = stream_type_byte == 2 ? "stderr" : "stdout"

          frame.split("\n").each do |line|
            next if line.strip.empty?
            entries << parse_log_line(line, stream_name)
          end
        end

        # Fallback: if no multiplexed frames parsed, treat as plain text
        unless parsed_any
          text = raw_body.to_s.dup.force_encoding("UTF-8")
          text = text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
          text.split("\n").each do |line|
            next if line.strip.empty?
            entries << parse_log_line(line, "stdout")
          end
        end

        entries
      end

      def parse_log_line(line, stream)
        stripped = line.strip
        # Docker timestamp format: 2024-01-15T10:30:45.123456789Z
        if stripped.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
          timestamp, message = stripped.split(" ", 2)
          { timestamp: timestamp, message: message || "", stream: stream }
        else
          { timestamp: nil, message: stripped, stream: stream }
        end
      end
    end
  end
end
