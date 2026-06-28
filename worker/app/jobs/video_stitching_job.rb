# frozen_string_literal: true

require 'tmpdir'

# Concatenates a media asset bundle's ordered scene clips into a single mp4.
#
# The server enqueues this job (WorkerApiClient maps the "video_stitching"
# ProcessingJob type to this class). The single argument is the
# FileManagement::ProcessingJob id; its job_parameters carry:
#   - scene_file_ids: ordered FileManagement::Object ids of the scene clips
#   - output_file_id:  (optional) the FileManagement::Object to receive the result
#
# Flow: fetch job → mark processing → download each scene in order → ffmpeg
# concat → ffprobe metadata → upload the rendered mp4 → report completion. Any
# failure is reported back to the server and re-raised for Sidekiq retry.
class VideoStitchingJob < BaseJob
  sidekiq_options retry: 3, dead: true, queue: 'file_processing'

  def execute(processing_job_id)
    raise ArgumentError, 'processing_job_id is required' if processing_job_id.nil? || processing_job_id.to_s.empty?

    job = api_client.get_file_processing_job(processing_job_id)
    params = (job && (job['job_parameters'] || job[:job_parameters])) || {}
    scene_file_ids = params['scene_file_ids'] || params['scene_ids'] || []
    output_file_id = params['output_file_id'] || params[:output_file_id]

    if scene_file_ids.empty?
      api_client.fail_file_processing_job(processing_job_id, 'no scenes to stitch')
      return { skipped: true }
    end

    api_client.update_file_processing_job(processing_job_id, status: 'processing')

    service = FileProcessingService.new
    result = nil

    Dir.mktmpdir('stitch') do |dir|
      scene_paths = download_scenes(scene_file_ids, dir)
      output_path = File.join(dir, 'stitched.mp4')

      service.stitch_scenes(scene_paths, output_path)
      metadata = service.probe_metadata(output_path)

      if output_file_id
        api_client.upload_processed_file(output_file_id, File.binread(output_path), metadata)
      end

      result = {
        'output_file_id' => output_file_id,
        'scene_count' => scene_file_ids.length,
        'ffprobe' => metadata
      }
      api_client.complete_file_processing_job(processing_job_id, result)
    end

    { success: true, result: result }
  rescue StandardError => e
    log_error('Video stitching failed', e, processing_job_id: processing_job_id)
    safe_report_failure(processing_job_id, e.message)
    raise
  end

  private

  # Download each scene clip to a local temp file, preserving order via a zero-
  # padded index so the concat sequence matches scene_file_ids.
  def download_scenes(scene_file_ids, dir)
    scene_file_ids.each_with_index.map do |file_id, index|
      path = File.join(dir, "scene_#{format('%04d', index)}")
      File.binwrite(path, api_client.download_file_content(file_id))
      path
    end
  end

  def safe_report_failure(processing_job_id, message)
    api_client.fail_file_processing_job(processing_job_id, message)
  rescue StandardError => e
    log_warn('Failed to report stitching failure to server', error: e.message)
  end
end
