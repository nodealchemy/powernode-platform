# frozen_string_literal: true

# Job for scanning uploaded files for viruses using ClamAV
# Integrates with the file processing pipeline to detect malicious files
class VirusScanJob < FileProcessingWorker
  sidekiq_options queue: 'file_processing',
                  retry: 3

  # Scan result actions
  ACTIONS = {
    clean: 'allow',         # File is clean, proceed with processing
    infected: 'quarantine', # File is infected, move to quarantine
    error: 'retry'          # Scan error, retry the job
  }.freeze

  def execute(processing_job_id)
    log_info("Starting virus scan", job_id: processing_job_id)

    # Load job and file data
    job_data = load_processing_job(processing_job_id)
    file_object_id = job_data['file_object_id']
    file_data = load_file_object(file_object_id)

    # Check if ClamAV is available
    unless clamav_service.available?
      handle_scanner_unavailable(processing_job_id, file_object_id)
      return
    end

    # Start processing
    start_processing_job!(processing_job_id)

    # Download file for scanning
    temp_file = download_file_content(file_object_id)

    begin
      scan_result = perform_scan(temp_file, file_data)
      handle_scan_result(processing_job_id, file_object_id, file_data, scan_result)

    rescue ClamavService::InfectedFileError => e
      handle_infected_file(processing_job_id, file_object_id, e)
    rescue ClamavService::ScanError => e
      handle_scan_error(processing_job_id, e)
    ensure
      cleanup_temp_file(temp_file)
    end
  end

  private

  def clamav_service
    @clamav_service ||= ClamavService.new
  end

  def perform_scan(temp_file, file_data)
    filename = file_data['name'] || file_data['filename'] || 'unknown'
    content_type = file_data['content_type']

    # Log scan initiation
    log_info("Scanning file",
             filename: filename,
             content_type: content_type,
             size: File.size(temp_file.path))

    # Use stream scanning for better isolation
    temp_file.rewind
    clamav_service.scan_stream(temp_file, filename: filename)
  end

  def handle_scan_result(processing_job_id, file_object_id, file_data, result)
    if result[:clean]
      # File is clean - update status and complete job
      update_file_scan_status(file_object_id, 'clean', result)

      complete_processing_job!(processing_job_id, {
        status: 'clean',
        scanned_at: result[:scanned_at],
        scanner_version: get_scanner_version
      })

      log_info("Virus scan completed - file clean",
               file_id: file_object_id,
               filename: file_data['name'])
    else
      # File is infected - quarantine it
      raise ClamavService::InfectedFileError.new(
        "Virus detected: #{result[:virus_name]}",
        virus_name: result[:virus_name],
        file_path: file_object_id
      )
    end
  end

  def handle_infected_file(processing_job_id, file_object_id, error)
    log_warn("Virus detected",
             file_id: file_object_id,
             virus_name: error.virus_name)

    # Update file status to quarantined
    update_file_scan_status(file_object_id, 'infected', {
      virus_name: error.virus_name,
      scanned_at: Time.now.iso8601,
      action_taken: 'quarantined'
    })

    # Mark the file as quarantined in backend
    quarantine_file(file_object_id, error.virus_name)

    # Complete the job (not failed - scan completed successfully, file was infected)
    complete_processing_job!(processing_job_id, {
      status: 'infected',
      virus_name: error.virus_name,
      action_taken: 'quarantined',
      scanned_at: Time.now.iso8601
    })

    # Notify about infected file
    notify_infected_file(file_object_id, error.virus_name)
  end

  def handle_scan_error(processing_job_id, error)
    log_error("Virus scan failed", error)

    fail_processing_job!(processing_job_id, error.message, {
      error_type: error.class.name,
      recoverable: true
    })

    # Re-raise to allow retry
    raise error
  end

  def handle_scanner_unavailable(processing_job_id, file_object_id)
    log_warn("ClamAV scanner unavailable, skipping scan")

    # Update file with scan skipped status
    update_file_scan_status(file_object_id, 'skipped', {
      reason: 'scanner_unavailable',
      scanned_at: Time.now.iso8601
    })

    # Complete job with skip status
    complete_processing_job!(processing_job_id, {
      status: 'skipped',
      reason: 'scanner_unavailable',
      scanned_at: Time.now.iso8601
    })
  end

  def update_file_scan_status(file_object_id, status, scan_data)
    api_client.update_file_object(file_object_id, {
      scan_status: status,
      scan_result: scan_data,
      scanned_at: scan_data[:scanned_at] || Time.now.iso8601
    })
  rescue BackendApiClient::ApiError => e
    log_error("Failed to update file scan status for #{file_object_id}", e)
  end

  def quarantine_file(file_object_id, virus_name)
    api_client.quarantine_file(file_object_id, {
      reason: 'virus_detected',
      virus_name: virus_name,
      quarantined_at: Time.now.iso8601
    })
  rescue BackendApiClient::ApiError => e
    log_error("Failed to quarantine file #{file_object_id}", e)
    # Continue - file is already marked as infected
  end

  def notify_infected_file(file_object_id, virus_name)
    # Notify via backend API (which can trigger email/notification)
    api_client.post('/api/v1/notifications/security_alert', {
      type: 'infected_file_detected',
      severity: 'high',
      file_object_id: file_object_id,
      virus_name: virus_name,
      detected_at: Time.now.iso8601
    })
  rescue BackendApiClient::ApiError => e
    log_warn("Failed to send infected file notification: #{e.message}")
    # Non-critical - continue
  end

  def get_scanner_version
    clamav_service.version
  rescue StandardError => e
    log_warn("Failed to get scanner version: #{e.message}")
    { version: 'unknown' }
  end
end
