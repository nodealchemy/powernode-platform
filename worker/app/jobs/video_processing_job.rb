# frozen_string_literal: true

# Processes video files to generate thumbnails and extract metadata
class VideoProcessingJob < FileProcessingWorker
  def execute(processing_job_id)
    log_info("Starting video processing", job_id: processing_job_id)

    # Load job and file data
    job_data = load_processing_job(processing_job_id)
    file_object_id = job_data['file_object_id']
    file_data = load_file_object(file_object_id)

    # Start processing
    start_processing_job!(processing_job_id)

    # Download original file
    temp_file = download_file_content(file_object_id)

    begin
      with_working_directory do |work_dir|
        # Extract video poster frame (thumbnail)
        poster_path = generate_video_poster(temp_file.path, work_dir)

        # Upload poster frame if generated
        if poster_path && File.exist?(poster_path)
          upload_processed_file(
            file_object_id,
            poster_path,
            {
              type: 'video_poster',
              storage_key: "posters/#{file_object_id}/poster.jpg"
            }
          )
        end

        # Extract video metadata
        metadata = extract_video_info(temp_file.path)

        # Update file object
        updates = {
          dimensions: metadata[:dimensions] || {},
          metadata: (file_data['metadata'] || {}).merge(metadata[:additional] || {})
        }

        if poster_path
          updates[:metadata][:poster_url] = "posters/#{file_object_id}/poster.jpg"
        end

        api_client.update_file_object(file_object_id, updates)

        # Update processing status
        update_file_processing_status(file_object_id, 'completed')

        # Mark job as completed
        complete_processing_job!(processing_job_id, metadata)

        log_info("Video processing completed", job_id: processing_job_id)
      end

    rescue StandardError => e
      fail_processing_job!(processing_job_id, e.message, { error_class: e.class.name })
      raise
    ensure
      cleanup_temp_file(temp_file)
    end
  end

  private

  def generate_video_poster(video_path, work_dir)
    output_path = File.join(work_dir, 'poster.jpg')

    # Extract frame at 2 seconds (or 10% of duration, whichever is earlier)
    command = "ffmpeg -i \"#{video_path}\" -ss 2 -vframes 1 -vf \"scale=600:-1\" -q:v 2 \"#{output_path}\" 2>&1"
    output = `#{command}`

    if $?.success? && File.exist?(output_path)
      log_info("Generated video poster")
      output_path
    else
      log_warn("Failed to generate video poster: #{output}")
      nil
    end
  rescue StandardError => e
    log_warn("Failed to generate video poster: #{e.message}")
    nil
  end

  def extract_video_info(video_path)
    metadata = {
      dimensions: {},
      additional: {}
    }

    ffprobe_output = `ffprobe -v quiet -print_format json -show_format -show_streams "#{video_path}" 2>&1`
    return metadata unless $?.success?

    data = JSON.parse(ffprobe_output)

    video_stream = data['streams']&.find { |s| s['codec_type'] == 'video' }
    if video_stream
      metadata[:dimensions] = {
        width: video_stream['width'],
        height: video_stream['height'],
        duration: data['format']&.dig('duration')&.to_f,
        codec: video_stream['codec_name'],
        bit_rate: video_stream['bit_rate']&.to_i,
        frame_rate: video_stream['r_frame_rate']
      }.compact
    end

    audio_stream = data['streams']&.find { |s| s['codec_type'] == 'audio' }
    if audio_stream
      metadata[:additional][:audio_codec] = audio_stream['codec_name']
      metadata[:additional][:audio_channels] = audio_stream['channels']
    end

    metadata[:additional][:format] = data['format']&.dig('format_name')

    log_info("Extracted video info", duration: metadata[:dimensions][:duration])

    metadata
  rescue StandardError => e
    log_warn("Failed to extract video info: #{e.message}")
    metadata
  end
end
