# frozen_string_literal: true

module Compliance
  # Job for processing GDPR data export requests
  class DataExportJob < BaseJob
    queue_as :compliance

    def execute(export_request_id)
      log_info "Processing data export request: #{export_request_id}"

      # Fetch export request from API
      response = api_client.get("/api/v1/internal/data_export_requests/#{export_request_id}")

      unless response[:success]
        raise "Failed to fetch export request: #{response[:error]}"
      end

      export_request = response[:data]

      # Skip if not pending
      unless export_request['status'] == 'pending'
        log_info "Export request #{export_request_id} is not pending, skipping"
        return
      end

      # Update status to processing
      api_client.patch(
        "/api/v1/internal/data_export_requests/#{export_request_id}",
        { status: 'processing', processing_started_at: Time.current.iso8601 }
      )

      begin
        # Gather data
        export_data = gather_export_data(export_request)

        # Write export file
        file_path, file_size = write_export_file(export_request, export_data)

        # Generate download token
        download_token = SecureRandom.urlsafe_base64(32)

        # Complete the request
        api_client.patch(
          "/api/v1/internal/data_export_requests/#{export_request_id}",
          {
            status: 'completed',
            file_path: file_path,
            file_size_bytes: file_size,
            download_token: download_token,
            download_token_expires_at: 7.days.from_now.iso8601,
            completed_at: Time.current.iso8601,
            expires_at: 30.days.from_now.iso8601
          }
        )

        log_info "Data export #{export_request_id} completed successfully"

        # Send notification to user
        notify_user_export_ready(export_request, download_token)
      rescue => e
        log_error "Data export failed: #{e.message}"

        api_client.patch(
          "/api/v1/internal/data_export_requests/#{export_request_id}",
          {
            status: 'failed',
            error_message: e.message,
            completed_at: Time.current.iso8601
          }
        )

        raise
      end
    end

    private

    def gather_export_data(export_request)
      user_id = export_request['user_id']
      account_id = export_request['account_id']
      data_types = export_request['include_data_types'] || []
      excluded = export_request['exclude_data_types'] || []

      export_data = {
        export_info: {
          generated_at: Time.current.iso8601,
          user_id: user_id,
          account_id: account_id,
          format: export_request['format']
        }
      }

      (data_types - excluded).each do |data_type|
        export_data[data_type] = fetch_data_type(data_type, user_id, account_id)
      end

      export_data
    end

    def fetch_data_type(data_type, user_id, account_id)
      case data_type
      when 'profile'
        api_client.get("/api/v1/internal/users/#{user_id}/export/profile")[:data]
      when 'activity'
        api_client.get("/api/v1/internal/users/#{user_id}/export/activity")[:data]
      when 'audit_logs'
        api_client.get("/api/v1/internal/users/#{user_id}/export/audit_logs")[:data]
      when 'payments'
        api_client.get("/api/v1/internal/accounts/#{account_id}/export/payments")[:data]
      when 'invoices'
        api_client.get("/api/v1/internal/accounts/#{account_id}/export/invoices")[:data]
      when 'subscriptions'
        api_client.get("/api/v1/internal/accounts/#{account_id}/export/subscriptions")[:data]
      when 'files'
        api_client.get("/api/v1/internal/accounts/#{account_id}/export/files")[:data]
      when 'consents'
        api_client.get("/api/v1/internal/users/#{user_id}/export/consents")[:data]
      else
        { note: "Data type '#{data_type}' not supported" }
      end
    rescue => e
      log_warn "Failed to fetch #{data_type}: #{e.message}"
      { error: "Failed to fetch #{data_type}" }
    end

    def write_export_file(export_request, data)
      export_dir = File.join(Dir.tmpdir, 'powernode_exports')
      FileUtils.mkdir_p(export_dir)

      timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
      user_id = export_request['user_id']
      filename = "export_#{user_id}_#{timestamp}"

      case export_request['format']
      when 'json'
        file_path = File.join(export_dir, "#{filename}.json")
        File.write(file_path, JSON.pretty_generate(data))
      when 'csv'
        file_path = write_csv_export(export_dir, filename, data)
      when 'zip'
        file_path = write_zip_export(export_dir, filename, data)
      else
        file_path = File.join(export_dir, "#{filename}.json")
        File.write(file_path, JSON.pretty_generate(data))
      end

      [file_path, File.size(file_path)]
    end

    def write_csv_export(export_dir, filename, data)
      require 'csv'
      require 'zip'

      csv_dir = File.join(export_dir, filename)
      FileUtils.mkdir_p(csv_dir)

      data.each do |key, value|
        next unless value.is_a?(Array) && value.any? && value.first.is_a?(Hash)

        csv_path = File.join(csv_dir, "#{key}.csv")
        CSV.open(csv_path, 'w') do |csv|
          csv << value.first.keys
          value.each { |row| csv << row.values }
        end
      end

      # Create zip
      zip_path = File.join(export_dir, "#{filename}.zip")
      Zip::File.open(zip_path, Zip::File::CREATE) do |zipfile|
        Dir[File.join(csv_dir, '*.csv')].each do |file|
          zipfile.add(File.basename(file), file)
        end
      end

      FileUtils.rm_rf(csv_dir)
      zip_path
    end

    def write_zip_export(export_dir, filename, data)
      require 'zip'

      json_path = File.join(export_dir, "#{filename}.json")
      File.write(json_path, JSON.pretty_generate(data))

      zip_path = File.join(export_dir, "#{filename}.zip")
      Zip::File.open(zip_path, Zip::File::CREATE) do |zipfile|
        zipfile.add("#{filename}.json", json_path)
      end

      FileUtils.rm(json_path)
      zip_path
    end

    def notify_user_export_ready(export_request, download_token)
      api_client.post(
        '/api/v1/internal/notifications/send',
        {
          user_id: export_request['user_id'],
          type: 'data_export_ready',
          data: {
            export_id: export_request['id'],
            download_token: download_token,
            expires_at: 7.days.from_now.iso8601
          }
        }
      )
    rescue => e
      log_warn "Failed to send export notification: #{e.message}"
    end
  end
end
