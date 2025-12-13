# frozen_string_literal: true

require 'socket'
require 'timeout'

# ClamAV antivirus scanning service
# Communicates with clamd daemon via Unix socket or TCP
class ClamavService
  class ClamavError < StandardError; end
  class ConfigurationError < ClamavError; end
  class ConnectionError < ClamavError; end
  class ScanError < ClamavError; end
  class InfectedFileError < ClamavError
    attr_reader :virus_name, :file_path

    def initialize(message, virus_name: nil, file_path: nil)
      super(message)
      @virus_name = virus_name
      @file_path = file_path
    end
  end

  # Maximum file size to scan (default 100MB)
  MAX_FILE_SIZE = ENV.fetch('CLAMAV_MAX_FILE_SIZE', 100 * 1024 * 1024).to_i

  # Timeout for scan operations (default 5 minutes)
  SCAN_TIMEOUT = ENV.fetch('CLAMAV_SCAN_TIMEOUT', 300).to_i

  # Connection timeout (default 10 seconds)
  CONNECTION_TIMEOUT = ENV.fetch('CLAMAV_CONNECTION_TIMEOUT', 10).to_i

  def initialize
    @logger = PowernodeWorker.logger
    validate_configuration!
  end

  # Check if ClamAV daemon is available and running
  # @return [Boolean] true if daemon is responsive
  def available?
    ping
  rescue StandardError
    false
  end

  # Ping the ClamAV daemon
  # @return [Boolean] true if PONG received
  def ping
    response = send_command('PING')
    response.strip == 'PONG'
  end

  # Get ClamAV version information
  # @return [Hash] version details
  def version
    response = send_command('VERSION')
    parse_version(response)
  end

  # Scan a file for viruses
  # @param file_path [String] Path to file to scan
  # @return [Hash] Scan result with :clean, :virus_name, :raw_response
  def scan_file(file_path)
    validate_file!(file_path)

    @logger.info "[ClamavService] Scanning file: #{File.basename(file_path)}"

    response = Timeout.timeout(SCAN_TIMEOUT) do
      send_command("SCAN #{file_path}")
    end

    parse_scan_result(response, file_path)
  rescue Timeout::Error
    @logger.error "[ClamavService] Scan timeout for #{File.basename(file_path)}"
    raise ScanError, "Scan timed out after #{SCAN_TIMEOUT} seconds"
  end

  # Scan file content via stream (INSTREAM command)
  # More secure as clamd doesn't need file system access
  # @param io [IO] IO object containing file content
  # @param filename [String] Original filename for logging
  # @return [Hash] Scan result
  def scan_stream(io, filename: 'unknown')
    @logger.info "[ClamavService] Scanning stream: #{filename}"

    socket = connect

    begin
      # Send INSTREAM command
      socket.write("zINSTREAM\0")

      # Send file content in chunks
      chunk_size = 2048
      while (chunk = io.read(chunk_size))
        # Send chunk size as 4-byte network-order integer
        socket.write([chunk.bytesize].pack('N'))
        socket.write(chunk)
      end

      # Send zero-length chunk to indicate end
      socket.write([0].pack('N'))

      # Read response
      response = socket.gets
      raise ScanError, 'No response from ClamAV daemon' unless response

      parse_scan_result(response, filename)
    ensure
      socket.close
    end
  rescue Timeout::Error
    @logger.error "[ClamavService] Stream scan timeout for #{filename}"
    raise ScanError, "Stream scan timed out after #{SCAN_TIMEOUT} seconds"
  end

  # Scan file content directly (convenience method)
  # @param content [String] File content to scan
  # @param filename [String] Original filename for logging
  # @return [Hash] Scan result
  def scan_content(content, filename: 'unknown')
    validate_content_size!(content)
    io = StringIO.new(content)
    scan_stream(io, filename: filename)
  end

  # Reload virus database
  # @return [Boolean] true if successful
  def reload
    response = send_command('RELOAD')
    response.strip == 'RELOADING'
  end

  # Get daemon statistics
  # @return [Hash] Statistics
  def stats
    response = send_command('STATS')
    parse_stats(response)
  end

  private

  def connection_type
    @connection_type ||= ENV.fetch('CLAMAV_CONNECTION_TYPE', 'unix')
  end

  def unix_socket_path
    @unix_socket_path ||= ENV.fetch('CLAMAV_SOCKET_PATH', '/var/run/clamav/clamd.ctl')
  end

  def tcp_host
    @tcp_host ||= ENV.fetch('CLAMAV_TCP_HOST', 'localhost')
  end

  def tcp_port
    @tcp_port ||= ENV.fetch('CLAMAV_TCP_PORT', '3310').to_i
  end

  def validate_configuration!
    case connection_type
    when 'unix'
      unless unix_socket_path.present?
        raise ConfigurationError, 'CLAMAV_SOCKET_PATH not configured'
      end
    when 'tcp'
      unless tcp_host.present? && tcp_port.positive?
        raise ConfigurationError, 'CLAMAV_TCP_HOST and CLAMAV_TCP_PORT must be configured'
      end
    else
      raise ConfigurationError, "Invalid CLAMAV_CONNECTION_TYPE: #{connection_type}. Use 'unix' or 'tcp'"
    end
  end

  def connect
    Timeout.timeout(CONNECTION_TIMEOUT) do
      case connection_type
      when 'unix'
        UNIXSocket.new(unix_socket_path)
      when 'tcp'
        TCPSocket.new(tcp_host, tcp_port)
      end
    end
  rescue Errno::ENOENT
    raise ConnectionError, "ClamAV socket not found: #{unix_socket_path}"
  rescue Errno::ECONNREFUSED
    raise ConnectionError, "ClamAV daemon not running or connection refused"
  rescue Timeout::Error
    raise ConnectionError, "Connection to ClamAV daemon timed out"
  end

  def send_command(command)
    socket = connect

    begin
      socket.write("n#{command}\n")
      response = socket.read
      response || ''
    ensure
      socket.close
    end
  rescue StandardError => e
    @logger.error "[ClamavService] Command failed: #{e.message}"
    raise ConnectionError, "Failed to communicate with ClamAV: #{e.message}"
  end

  def validate_file!(file_path)
    unless File.exist?(file_path)
      raise ScanError, "File not found: #{file_path}"
    end

    unless File.readable?(file_path)
      raise ScanError, "File not readable: #{file_path}"
    end

    file_size = File.size(file_path)
    if file_size > MAX_FILE_SIZE
      raise ScanError, "File too large: #{file_size} bytes (max: #{MAX_FILE_SIZE})"
    end

    if file_size.zero?
      @logger.warn "[ClamavService] Empty file: #{file_path}"
    end
  end

  def validate_content_size!(content)
    if content.bytesize > MAX_FILE_SIZE
      raise ScanError, "Content too large: #{content.bytesize} bytes (max: #{MAX_FILE_SIZE})"
    end
  end

  def parse_scan_result(response, file_identifier)
    response = response.to_s.strip

    # Response format: "path: status"
    # Clean file: "/path/to/file: OK"
    # Infected: "/path/to/file: VirusName FOUND"
    # Error: "/path/to/file: Error message ERROR"

    if response.end_with?('OK')
      @logger.info "[ClamavService] File clean: #{File.basename(file_identifier)}"
      {
        clean: true,
        virus_name: nil,
        raw_response: response,
        scanned_at: Time.now.iso8601
      }
    elsif response.include?('FOUND')
      # Extract virus name from response
      match = response.match(/:\s*(.+)\s+FOUND/)
      virus_name = match ? match[1].strip : 'Unknown'

      @logger.warn "[ClamavService] Virus detected: #{virus_name} in #{File.basename(file_identifier)}"
      {
        clean: false,
        virus_name: virus_name,
        raw_response: response,
        scanned_at: Time.now.iso8601
      }
    elsif response.include?('ERROR')
      error_match = response.match(/:\s*(.+)\s+ERROR/)
      error_message = error_match ? error_match[1].strip : response

      @logger.error "[ClamavService] Scan error: #{error_message}"
      raise ScanError, "ClamAV scan error: #{error_message}"
    else
      @logger.warn "[ClamavService] Unknown response: #{response}"
      raise ScanError, "Unknown ClamAV response: #{response}"
    end
  end

  def parse_version(response)
    # Response format: "ClamAV 0.103.6/26423/Wed Feb 28 08:00:29 2024"
    parts = response.strip.split('/')
    {
      version: parts[0]&.strip,
      database_version: parts[1]&.to_i,
      database_date: parts[2]&.strip,
      raw: response.strip
    }
  end

  def parse_stats(response)
    stats = {}
    response.each_line do |line|
      if line.include?(':')
        key, value = line.split(':', 2)
        stats[key.strip.downcase.gsub(' ', '_').to_sym] = value.strip
      end
    end
    stats
  end
end
