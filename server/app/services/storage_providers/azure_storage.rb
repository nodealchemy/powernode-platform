# frozen_string_literal: true

require "faraday"
require "faraday/multipart"
require "openssl"
require "base64"
require "time"
require "cgi"

module StorageProviders
  # Azure Blob Storage provider using REST API with Faraday 2.x
  # Provides cloud storage with block blobs, SAS tokens, and Azure-specific features
  class AzureStorage < Base
    API_VERSION = "2023-11-03"

    attr_reader :container_name

    def initialize(storage_config)
      super
      @container_name = config("container")
      @account_name = config("account_name")
      @account_key = decrypt_config("account_key")
      @connection = build_connection
    end

    # Initialize storage backend
    def initialize_storage
      begin
        get_container_properties
        log_info("Azure container exists: #{@container_name}")
      rescue AzureError => e
        if e.status_code == 404
          log_info("Creating Azure container: #{@container_name}")
          create_container
        else
          raise e
        end
      end

      log_info("Initialized Azure Blob storage: #{@container_name}")
      true
    rescue AzureError => e
      log_error("Failed to initialize Azure storage: #{e.message}")
      false
    end

    # Test connection
    def test_connection
      return { success: false, error: "Container name not configured" } unless @container_name

      get_container_properties

      {
        success: true,
        message: "Azure Blob storage is accessible",
        container: @container_name,
        account: @account_name
      }
    rescue AzureError => e
      if e.status_code == 404
        {
          success: false,
          error: "Container does not exist: #{@container_name}"
        }
      else
        {
          success: false,
          error: "Connection test failed: #{e.message}"
        }
      end
    end

    # Health check
    def health_check
      connection_test = test_connection

      if connection_test[:success]
        {
          status: "healthy",
          details: {
            "container" => @container_name,
            "account" => @account_name,
            "accessible" => true,
            "files_count" => storage_config.files_count,
            "total_size_bytes" => storage_config.total_size_bytes,
            "checked_at" => Time.current.iso8601
          }
        }
      else
        {
          status: "failed",
          details: {
            "error" => connection_test[:error],
            "checked_at" => Time.current.iso8601
          }
        }
      end
    end

    # Upload file
    def upload_file(file_object, file_data, options = {})
      storage_key = file_object.storage_key

      # Handle IO vs String data
      if file_data.respond_to?(:read)
        file_data.rewind if file_data.respond_to?(:rewind)
        content = file_data.read
        file_data.rewind if file_data.respond_to?(:rewind)
      else
        content = file_data
      end

      # Validate file size
      validate_file_size!(content)

      # Build headers
      headers = {
        "x-ms-blob-type" => "BlockBlob"
      }
      headers["Content-Type"] = options[:content_type] if options[:content_type]
      headers["x-ms-blob-cache-control"] = config("cache_control") if config("cache_control")

      # Add metadata as headers
      if options[:metadata]
        options[:metadata].each do |key, value|
          headers["x-ms-meta-#{key}"] = value.to_s
        end
      end

      # Upload as block blob
      make_request(:put, blob_path(storage_key), body: content, headers: headers)

      # Calculate and store checksums
      file_object.update_columns(
        checksum_md5: calculate_checksum(content, algorithm: :md5),
        checksum_sha256: calculate_checksum(content, algorithm: :sha256)
      )

      log_info("Uploaded file to Azure: #{storage_key} (#{file_object.human_file_size})")
      true
    rescue AzureError => e
      log_error("Failed to upload file #{storage_key}: #{e.message}")
      raise e
    end

    # Read file content
    def read_file(file_object)
      response = make_request(:get, blob_path(file_object.storage_key))
      response.body
    rescue AzureError => e
      if e.status_code == 404
        raise "File not found: #{file_object.storage_key}"
      end
      raise e
    end

    # Stream file content
    def stream_file(file_object, &block)
      # Get blob properties first to determine size
      props = get_blob_properties(file_object.storage_key)
      blob_size = props[:content_length]

      chunk_size = 4.megabytes
      offset = 0

      while offset < blob_size
        end_range = [ offset + chunk_size - 1, blob_size - 1 ].min
        headers = { "Range" => "bytes=#{offset}-#{end_range}" }
        response = make_request(:get, blob_path(file_object.storage_key), headers: headers)
        yield response.body
        offset = end_range + 1
      end
    rescue AzureError => e
      if e.status_code == 404
        raise "File not found: #{file_object.storage_key}"
      end
      raise e
    end

    # Delete file
    def delete_file(file_object)
      make_request(:delete, blob_path(file_object.storage_key))

      log_info("Deleted file from Azure: #{file_object.storage_key}")
      true
    rescue AzureError => e
      if e.status_code == 404
        # File doesn't exist, consider it a success
        return true
      end
      log_error("Failed to delete file #{file_object.storage_key}: #{e.message}")
      false
    end

    # Copy file
    def copy_file(source_key, destination_key)
      source_uri = generate_blob_uri(source_key)

      headers = {
        "x-ms-copy-source" => source_uri
      }

      make_request(:put, blob_path(destination_key), headers: headers)

      log_info("Copied file in Azure: #{source_key} -> #{destination_key}")
      true
    rescue AzureError => e
      if e.status_code == 404
        raise "Source file not found: #{source_key}"
      end
      log_error("Failed to copy file #{source_key} to #{destination_key}: #{e.message}")
      false
    end

    # Move file
    def move_file(source_key, destination_key)
      if copy_file(source_key, destination_key)
        make_request(:delete, blob_path(source_key))
        log_info("Moved file in Azure: #{source_key} -> #{destination_key}")
        true
      else
        false
      end
    rescue StandardError => e
      log_error("Failed to move file #{source_key} to #{destination_key}: #{e.message}")
      false
    end

    # Check if file exists
    def file_exists?(file_object)
      get_blob_properties(file_object.storage_key)
      true
    rescue AzureError => e
      return false if e.status_code == 404
      raise e
    end

    # Get file URL
    def file_url(file_object)
      if config("cdn_domain")
        "https://#{config('cdn_domain')}/#{@container_name}/#{file_object.storage_key}"
      else
        generate_blob_uri(file_object.storage_key)
      end
    end

    # Get download URL (SAS token)
    def download_url(file_object, expires_in: 1.hour)
      generate_sas_url(
        file_object.storage_key,
        expires_in: expires_in,
        permissions: "r",
        content_disposition: "attachment; filename=\"#{file_object.filename}\""
      )
    end

    # Get signed URL (SAS token)
    def signed_url(file_object, expires_in: 1.hour, disposition: "inline")
      generate_sas_url(
        file_object.storage_key,
        expires_in: expires_in,
        permissions: "r",
        content_disposition: "#{disposition}; filename=\"#{file_object.filename}\""
      )
    end

    # Get presigned upload URL
    def presigned_upload_url(storage_key, filename:, content_type:, expires_in: 15.minutes)
      generate_sas_url(
        storage_key,
        expires_in: expires_in,
        permissions: "cw", # Create and Write
        content_type: content_type
      )
    end

    # Get file metadata
    def file_metadata(file_object)
      props = get_blob_properties(file_object.storage_key)

      {
        "size" => props[:content_length],
        "content_type" => props[:content_type],
        "etag" => props[:etag],
        "last_modified" => props[:last_modified],
        "content_md5" => props[:content_md5],
        "blob_type" => props[:blob_type],
        "lease_status" => props[:lease_status],
        "metadata" => props[:metadata]
      }
    rescue AzureError => e
      if e.status_code == 404
        raise "File not found: #{file_object.storage_key}"
      end
      raise e
    end

    # List files in container
    def list_files(prefix: nil, options: {})
      params = { "restype" => "container", "comp" => "list" }
      params["prefix"] = prefix if prefix
      params["maxresults"] = options[:max_keys] || 1000

      response = make_request(:get, "/#{@container_name}", params: params)
      parse_blob_list(response.body)
    rescue AzureError => e
      log_error("Failed to list files: #{e.message}")
      []
    end

    # Batch delete
    def batch_delete(file_objects)
      results = { success: [], failed: [] }

      file_objects.each do |file_object|
        begin
          make_request(:delete, blob_path(file_object.storage_key))
          results[:success] << file_object.id
        rescue AzureError => e
          if e.status_code == 404
            # File doesn't exist, consider it a success
            results[:success] << file_object.id
          else
            log_error("Batch delete failed for #{file_object.storage_key}: #{e.message}")
            results[:failed] << file_object.id
          end
        end
      end

      results
    end

    private

    # Custom error class for Azure API errors
    class AzureError < StandardError
      attr_reader :status_code, :error_code

      def initialize(message, status_code: nil, error_code: nil)
        super(message)
        @status_code = status_code
        @error_code = error_code
      end
    end

    def build_connection
      Faraday.new(url: base_url) do |conn|
        conn.request :multipart
        conn.response :raise_error
        conn.adapter Faraday.default_adapter
        conn.options.timeout = 120
        conn.options.open_timeout = 30
      end
    end

    def base_url
      "https://#{@account_name}.blob.core.windows.net"
    end

    def blob_path(storage_key)
      "/#{@container_name}/#{storage_key}"
    end

    def make_request(method, path, body: nil, headers: {}, params: {})
      request_time = Time.now.utc.httpdate
      content_length = body ? body.bytesize : 0

      # Build full URL with params
      uri = path
      if params.any?
        query_string = params.map { |k, v| "#{CGI.escape(k.to_s)}=#{CGI.escape(v.to_s)}" }.join("&")
        uri = "#{path}?#{query_string}"
      end

      # Build request headers
      request_headers = {
        "x-ms-date" => request_time,
        "x-ms-version" => API_VERSION,
        "Content-Length" => content_length.to_s
      }.merge(headers)

      # Generate authorization signature
      request_headers["Authorization"] = generate_authorization(
        method: method.to_s.upcase,
        path: path,
        headers: request_headers,
        params: params,
        content_length: content_length
      )

      response = @connection.run_request(method, uri, body, request_headers)
      response
    rescue Faraday::ClientError, Faraday::ServerError => e
      status = e.response&.dig(:status) || 0
      body = e.response&.dig(:body) || ""
      error_code = extract_error_code(body)
      raise AzureError.new("Azure API error: #{e.message}", status_code: status, error_code: error_code)
    end

    def generate_authorization(method:, path:, headers:, params:, content_length:)
      # Build canonicalized headers
      canonicalized_headers = headers
        .select { |k, _| k.to_s.downcase.start_with?("x-ms-") }
        .sort_by { |k, _| k.to_s.downcase }
        .map { |k, v| "#{k.downcase}:#{v}" }
        .join("\n")

      # Build canonicalized resource
      canonicalized_resource = "/#{@account_name}#{path}"
      if params.any?
        sorted_params = params.sort_by { |k, _| k.to_s.downcase }
        canonicalized_resource += "\n" + sorted_params.map { |k, v| "#{k.downcase}:#{v}" }.join("\n")
      end

      # Build string to sign
      string_to_sign = [
        method,
        headers["Content-Encoding"] || "",
        headers["Content-Language"] || "",
        content_length > 0 ? content_length.to_s : "",
        headers["Content-MD5"] || "",
        headers["Content-Type"] || "",
        "", # Date (empty because we use x-ms-date)
        headers["If-Modified-Since"] || "",
        headers["If-Match"] || "",
        headers["If-None-Match"] || "",
        headers["If-Unmodified-Since"] || "",
        headers["Range"] || "",
        canonicalized_headers,
        canonicalized_resource
      ].join("\n")

      # Generate HMAC-SHA256 signature
      signature = Base64.strict_encode64(
        OpenSSL::HMAC.digest("sha256", Base64.decode64(@account_key), string_to_sign)
      )

      "SharedKey #{@account_name}:#{signature}"
    end

    def get_container_properties
      make_request(:get, "/#{@container_name}", params: { "restype" => "container" })
    end

    def create_container
      make_request(:put, "/#{@container_name}", params: { "restype" => "container" })
    end

    def get_blob_properties(storage_key)
      response = make_request(:head, blob_path(storage_key))

      {
        content_length: response.headers["content-length"]&.to_i || 0,
        content_type: response.headers["content-type"],
        etag: response.headers["etag"],
        last_modified: response.headers["last-modified"],
        content_md5: response.headers["content-md5"],
        blob_type: response.headers["x-ms-blob-type"],
        lease_status: response.headers["x-ms-lease-status"],
        metadata: extract_metadata(response.headers)
      }
    end

    def extract_metadata(headers)
      metadata = {}
      headers.each do |key, value|
        if key.to_s.downcase.start_with?("x-ms-meta-")
          meta_key = key.to_s.sub(/^x-ms-meta-/i, "")
          metadata[meta_key] = value
        end
      end
      metadata
    end

    def generate_blob_uri(storage_key)
      "#{base_url}/#{@container_name}/#{storage_key}"
    end

    def generate_sas_url(storage_key, expires_in:, permissions:, content_disposition: nil, content_type: nil)
      # SAS token parameters
      start_time = (Time.current - 5.minutes).utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      expiry_time = (Time.current + expires_in).utc.strftime("%Y-%m-%dT%H:%M:%SZ")

      # Build parameters for signature
      signed_permissions = permissions
      signed_start = start_time
      signed_expiry = expiry_time
      canonicalized_resource = "/blob/#{@account_name}/#{@container_name}/#{storage_key}"
      signed_identifier = ""
      signed_ip = ""
      signed_protocol = "https"
      signed_version = API_VERSION
      signed_resource = "b" # blob

      # Cache control, content disposition, content encoding, content language, content type
      rscc = "" # cache-control
      rscd = content_disposition || ""
      rsce = "" # content-encoding
      rscl = "" # content-language
      rsct = content_type || ""

      # String to sign for Service SAS
      string_to_sign = [
        signed_permissions,
        signed_start,
        signed_expiry,
        canonicalized_resource,
        signed_identifier,
        signed_ip,
        signed_protocol,
        signed_version,
        signed_resource,
        "", # snapshot time
        "", # encryption scope
        rscc,
        rscd,
        rsce,
        rscl,
        rsct
      ].join("\n")

      signature = Base64.strict_encode64(
        OpenSSL::HMAC.digest("sha256", Base64.decode64(@account_key), string_to_sign)
      )

      # Build SAS query parameters
      sas_params = {
        "sv" => signed_version,
        "sr" => signed_resource,
        "st" => signed_start,
        "se" => signed_expiry,
        "sp" => signed_permissions,
        "spr" => signed_protocol,
        "sig" => signature
      }
      sas_params["rscd"] = rscd unless rscd.empty?
      sas_params["rsct"] = rsct unless rsct.empty?

      query_string = sas_params.map { |k, v| "#{k}=#{CGI.escape(v)}" }.join("&")
      "#{generate_blob_uri(storage_key)}?#{query_string}"
    end

    def parse_blob_list(xml_body)
      files = []

      # Simple XML parsing for blob list
      xml_body.scan(/<Blob>.*?<\/Blob>/m).each do |blob_xml|
        name = blob_xml[/<Name>(.*?)<\/Name>/, 1]
        content_length = blob_xml[/<Content-Length>(.*?)<\/Content-Length>/, 1]&.to_i
        last_modified = blob_xml[/<Last-Modified>(.*?)<\/Last-Modified>/, 1]
        content_type = blob_xml[/<Content-Type>(.*?)<\/Content-Type>/, 1]
        blob_type = blob_xml[/<BlobType>(.*?)<\/BlobType>/, 1]

        files << {
          "key" => name,
          "size" => content_length,
          "modified_at" => last_modified,
          "content_type" => content_type,
          "blob_type" => blob_type
        }
      end

      files
    end

    def extract_error_code(body)
      body[/<Code>(.*?)<\/Code>/, 1] || "UnknownError"
    end
  end
end
