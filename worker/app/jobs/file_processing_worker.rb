# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

# Base class for all file processing worker jobs
# Provides common functionality for handling FileProcessingJob records and file operations
class FileProcessingWorker < BaseJob
  sidekiq_options queue: 'file_processing',
                  retry: 3,
                  dead: true

  protected

  # Load file processing job from backend
  def load_processing_job(processing_job_id)
    job_data = api_client.get_file_processing_job(processing_job_id)

    unless job_data && job_data['id']
      raise "FileProcessingJob #{processing_job_id} not found"
    end

    job_data
  rescue BackendApiClient::ApiError => e
    log_error("Failed to load FileProcessingJob #{processing_job_id}", e)
    raise
  end

  # Load file object from backend
  def load_file_object(file_object_id)
    file_data = api_client.get_file_object(file_object_id)

    unless file_data && file_data['id']
      raise "FileObject #{file_object_id} not found"
    end

    file_data
  rescue BackendApiClient::ApiError => e
    log_error("Failed to load FileObject #{file_object_id}", e)
    raise
  end

  # Mark processing job as started
  def start_processing_job!(processing_job_id)
    api_client.update_file_processing_job(processing_job_id, { status: 'processing' })
    log_info("Started processing job", job_id: processing_job_id)
  rescue BackendApiClient::ApiError => e
    log_error("Failed to start processing job #{processing_job_id}", e)
    raise
  end

  # Mark processing job as completed
  def complete_processing_job!(processing_job_id, result_data = {})
    api_client.complete_file_processing_job(processing_job_id, result_data)
    log_info("Completed processing job", job_id: processing_job_id)
  rescue BackendApiClient::ApiError => e
    log_error("Failed to complete processing job #{processing_job_id}", e)
    raise
  end

  # Mark processing job as failed
  def fail_processing_job!(processing_job_id, error_message, error_data = {})
    api_client.fail_file_processing_job(processing_job_id, error_message, error_data)
    log_error("Failed processing job", job_id: processing_job_id, error: error_message)
  rescue BackendApiClient::ApiError => e
    log_error("Failed to update processing job status #{processing_job_id}", e)
    # Don't raise here - we're already handling a failure
  end

  # Download file content to temporary file
  def download_file_content(file_object_id)
    temp_file = Tempfile.new(['file', File.extname(file_object_id)], binmode: true)

    begin
      content = api_client.download_file_content(file_object_id)
      temp_file.write(content)
      temp_file.rewind

      log_info("Downloaded file", file_id: file_object_id, size: content.bytesize)

      temp_file
    rescue StandardError => e
      temp_file.close
      temp_file.unlink
      raise
    end
  rescue BackendApiClient::ApiError => e
    log_error("Failed to download file #{file_object_id}", e)
    raise
  end

  # Upload processed file result
  def upload_processed_file(file_object_id, file_path, metadata = {})
    file_content = File.binread(file_path)

    api_client.upload_processed_file(file_object_id, file_content, metadata)

    log_info("Uploaded processed file", file_id: file_object_id, size: file_content.bytesize)
  rescue BackendApiClient::ApiError => e
    log_error("Failed to upload processed file for #{file_object_id}", e)
    raise
  end

  # Update file object metadata
  def update_file_metadata(file_object_id, metadata_updates)
    api_client.update_file_object(file_object_id, { metadata: metadata_updates })
    log_info("Updated file metadata", file_id: file_object_id)
  rescue BackendApiClient::ApiError => e
    log_error("Failed to update file metadata for #{file_object_id}", e)
    raise
  end

  # Update file object processing status
  def update_file_processing_status(file_object_id, status)
    api_client.update_file_object(file_object_id, { processing_status: status })
    log_info("Updated file processing status", file_id: file_object_id, status: status)
  rescue BackendApiClient::ApiError => e
    log_error("Failed to update file processing status for #{file_object_id}", e)
    raise
  end

  # Helper to create a working directory for processing
  def with_working_directory
    dir = Dir.mktmpdir('file_processing_')

    begin
      yield dir
    ensure
      FileUtils.rm_rf(dir) if Dir.exist?(dir)
    end
  end

  # Helper to safely close and delete temp files
  def cleanup_temp_file(temp_file)
    return unless temp_file

    temp_file.close unless temp_file.closed?
    temp_file.unlink if File.exist?(temp_file.path)
  rescue StandardError => e
    log_warn("Failed to cleanup temp file: #{e.message}")
  end

  # Get file processing service
  def processing_service
    @processing_service ||= FileProcessingService.new
  end
end
