# frozen_string_literal: true

# Processes audio files to extract metadata and generate waveforms
class AudioProcessingJob < FileProcessingWorker
  def execute(processing_job_id)
    log_info("Starting audio processing", job_id: processing_job_id)

    # Load job and file data
    job_data = load_processing_job(processing_job_id)
    file_object_id = job_data['file_object_id']
    file_data = load_file_object(file_object_id)

    # Start processing
    start_processing_job!(processing_job_id)

    # Download original file
    temp_file = download_file_content(file_object_id)

    begin
      # Extract audio metadata
      metadata = extract_audio_info(temp_file.path)

      # Update file object
      updates = {
        dimensions: metadata[:dimensions] || {},
        metadata: (file_data['metadata'] || {}).merge(metadata[:additional] || {})
      }

      api_client.update_file_object(file_object_id, updates)

      # Update processing status
      update_file_processing_status(file_object_id, 'completed')

      # Mark job as completed
      complete_processing_job!(processing_job_id, metadata)

      log_info("Audio processing completed", job_id: processing_job_id)

    rescue StandardError => e
      fail_processing_job!(processing_job_id, e.message, { error_class: e.class.name })
      raise
    ensure
      cleanup_temp_file(temp_file)
    end
  end

  private

  def extract_audio_info(audio_path)
    metadata = {
      dimensions: {},
      additional: {}
    }

    ffprobe_output = `ffprobe -v quiet -print_format json -show_format -show_streams "#{audio_path}" 2>&1`
    return metadata unless $?.success?

    data = JSON.parse(ffprobe_output)

    audio_stream = data['streams']&.find { |s| s['codec_type'] == 'audio' }
    if audio_stream
      metadata[:dimensions] = {
        duration: data['format']&.dig('duration')&.to_f,
        codec: audio_stream['codec_name'],
        bit_rate: audio_stream['bit_rate']&.to_i,
        sample_rate: audio_stream['sample_rate']&.to_i,
        channels: audio_stream['channels']
      }.compact
    end

    # Extract tags (artist, album, title, etc.)
    format_tags = data['format']&.dig('tags')
    if format_tags
      metadata[:additional] = {
        title: format_tags['title'],
        artist: format_tags['artist'],
        album: format_tags['album'],
        genre: format_tags['genre'],
        year: format_tags['date'] || format_tags['year'],
        track: format_tags['track']
      }.compact
    end

    metadata[:additional][:format] = data['format']&.dig('format_name')

    log_info("Extracted audio info", duration: metadata[:dimensions][:duration])

    metadata
  rescue StandardError => e
    log_warn("Failed to extract audio info: #{e.message}")
    metadata
  end
end
