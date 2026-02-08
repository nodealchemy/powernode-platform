# frozen_string_literal: true

module FileProcessing
  class VirusScanJob < BaseJob
    sidekiq_options queue: "file_processing", retry: 2

    def execute(processing_job_id)
      log_info("Starting virus scan", processing_job_id: processing_job_id)

      # Fetch processing job details from backend
      job_response = api_client.get("/api/v1/internal/file_processing_jobs/#{processing_job_id}")
      job_data = job_response["data"] || job_response

      file_id = job_data["file_id"] || job_data.dig("file", "id")
      unless file_id
        log_error("No file_id found in processing job", processing_job_id: processing_job_id)
        report_result(processing_job_id, "error", "No file ID found")
        return
      end

      # Check if ClamAV is available
      unless clamav_available?
        log_warn("ClamAV not installed, skipping virus scan", processing_job_id: processing_job_id)
        report_result(processing_job_id, "skipped", "ClamAV not available on this system")
        return
      end

      # Download file to temp location
      temp_file = download_file(file_id)
      unless temp_file
        log_error("Failed to download file for scanning", file_id: file_id)
        report_result(processing_job_id, "error", "Failed to download file")
        return
      end

      begin
        # Run ClamAV scan
        result = scan_file(temp_file.path)

        case result[:status]
        when :clean
          log_info("File is clean", file_id: file_id)
          report_result(processing_job_id, "completed", "File is clean", scan_details: result[:output])
        when :infected
          log_warn("INFECTED FILE DETECTED", file_id: file_id, threat: result[:threat])
          report_result(processing_job_id, "completed", "Threat detected: #{result[:threat]}",
                       scan_details: result[:output], infected: true)
          quarantine_file(file_id, result[:threat])
        when :error
          log_error("Scan error", file_id: file_id, error: result[:output])
          report_result(processing_job_id, "error", "Scan failed: #{result[:output]}")
        end
      ensure
        # Clean up temp file
        temp_file.close
        temp_file.unlink
      end
    end

    private

    def clamav_available?
      system("which clamdscan > /dev/null 2>&1") || system("which clamscan > /dev/null 2>&1")
    end

    def scan_file(file_path)
      # Prefer clamdscan (daemon mode, faster) over clamscan (standalone, slower)
      scanner = system("which clamdscan > /dev/null 2>&1") ? "clamdscan" : "clamscan"

      output = `#{scanner} --no-summary "#{file_path}" 2>&1`
      exit_code = $?.exitstatus

      case exit_code
      when 0
        { status: :clean, output: output.strip }
      when 1
        # Extract threat name from output (format: "/path/file: ThreatName FOUND")
        threat = output.match(/:\s*(.+)\s*FOUND/)&.captures&.first || "Unknown threat"
        { status: :infected, output: output.strip, threat: threat.strip }
      else
        { status: :error, output: output.strip }
      end
    end

    def download_file(file_id)
      require "tempfile"

      response = api_client.get("/api/v1/internal/files/#{file_id}/content")

      # The response should contain file content (possibly Base64 encoded)
      content = if response["content"]
                  if response["encoding"] == "base64"
                    Base64.decode64(response["content"])
                  else
                    response["content"]
                  end
                elsif response["data"]
                  response["data"]
                else
                  nil
                end

      return nil unless content

      temp_file = Tempfile.new(["virus_scan_", ".tmp"])
      temp_file.binmode
      temp_file.write(content)
      temp_file.flush
      temp_file
    rescue StandardError => e
      log_error("File download failed", file_id: file_id, error: e.message)
      nil
    end

    def report_result(processing_job_id, status, message, scan_details: nil, infected: false)
      api_client.put("/api/v1/internal/file_processing_jobs/#{processing_job_id}", {
        file_processing_job: {
          status: status,
          result: {
            message: message,
            scan_details: scan_details,
            infected: infected,
            scanned_at: Time.current.iso8601
          }
        }
      })
    rescue StandardError => e
      log_error("Failed to report scan result", processing_job_id: processing_job_id, error: e.message)
    end

    def quarantine_file(file_id, threat)
      api_client.post("/api/v1/internal/files/#{file_id}/quarantine", {
        reason: "Virus detected: #{threat}",
        quarantined_at: Time.current.iso8601
      })
    rescue StandardError => e
      log_error("Failed to quarantine file", file_id: file_id, error: e.message)
    end
  end
end
