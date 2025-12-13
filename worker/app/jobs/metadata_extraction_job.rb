# frozen_string_literal: true

require 'mini_magick'
require 'mini_exiftool'

# Extracts metadata from files (images, documents, videos, audio)
# Stores EXIF data, dimensions, durations, and other file properties
class MetadataExtractionJob < FileProcessingWorker
  def execute(processing_job_id)
    log_info("Starting metadata extraction", job_id: processing_job_id)

    # Load job and file data
    job_data = load_processing_job(processing_job_id)
    file_object_id = job_data['file_object_id']
    file_data = load_file_object(file_object_id)

    # Start processing
    start_processing_job!(processing_job_id)

    # Download original file
    temp_file = download_file_content(file_object_id)

    begin
      metadata = extract_metadata(temp_file.path, file_data['content_type'])

      # Update file object with extracted metadata
      updates = {
        exif_data: metadata[:exif_data] || {},
        dimensions: metadata[:dimensions] || {},
        metadata: (file_data['metadata'] || {}).merge(metadata[:additional] || {})
      }

      api_client.update_file_object(file_object_id, updates)

      # Update file processing status to completed if this is the last job
      update_file_processing_status(file_object_id, 'completed')

      # Mark job as completed
      complete_processing_job!(processing_job_id, metadata)

      log_info("Metadata extraction completed", job_id: processing_job_id)

    rescue StandardError => e
      fail_processing_job!(processing_job_id, e.message, { error_class: e.class.name })
      raise
    ensure
      cleanup_temp_file(temp_file)
    end
  end

  private

  def extract_metadata(file_path, content_type)
    metadata = {
      exif_data: {},
      dimensions: {},
      additional: {}
    }

    case content_type
    when /^image\//
      extract_image_metadata(file_path, metadata)
    when /^video\//
      extract_video_metadata(file_path, metadata)
    when /^audio\//
      extract_audio_metadata(file_path, metadata)
    when 'application/pdf', /word/, /excel/, /powerpoint/
      extract_document_metadata(file_path, metadata)
    else
      extract_basic_metadata(file_path, metadata)
    end

    metadata
  rescue StandardError => e
    log_error("Failed to extract metadata", e)
    raise
  end

  def extract_image_metadata(file_path, metadata)
    # Use MiniMagick for dimensions
    image = MiniMagick::Image.open(file_path)
    metadata[:dimensions] = {
      width: image.width,
      height: image.height,
      format: image.type
    }

    # Use MiniExiftool for EXIF data
    exif = MiniExiftool.new(file_path)
    metadata[:exif_data] = {
      make: exif.make,
      model: exif.model,
      date_time: exif.date_time_original&.iso8601,
      orientation: exif.orientation,
      gps_latitude: exif.gps_latitude,
      gps_longitude: exif.gps_longitude,
      iso: exif.iso,
      exposure_time: exif.exposure_time,
      f_number: exif.f_number,
      focal_length: exif.focal_length
    }.compact

    log_info("Extracted image metadata", width: image.width, height: image.height)
  rescue StandardError => e
    log_warn("Failed to extract image metadata: #{e.message}")
  end

  def extract_video_metadata(file_path, metadata)
    # Use ffprobe to extract video metadata
    ffprobe_output = `ffprobe -v quiet -print_format json -show_format -show_streams "#{file_path}" 2>&1`
    return unless $?.success?

    data = JSON.parse(ffprobe_output)

    video_stream = data['streams']&.find { |s| s['codec_type'] == 'video' }
    if video_stream
      metadata[:dimensions] = {
        width: video_stream['width'],
        height: video_stream['height'],
        duration: data['format']&.dig('duration')&.to_f,
        codec: video_stream['codec_name'],
        bit_rate: video_stream['bit_rate']&.to_i
      }.compact
    end

    metadata[:additional] = {
      format: data['format']&.dig('format_name'),
      size: data['format']&.dig('size')&.to_i
    }.compact

    log_info("Extracted video metadata", duration: metadata[:dimensions][:duration])
  rescue StandardError => e
    log_warn("Failed to extract video metadata: #{e.message}")
  end

  def extract_audio_metadata(file_path, metadata)
    # Use ffprobe to extract audio metadata
    ffprobe_output = `ffprobe -v quiet -print_format json -show_format -show_streams "#{file_path}" 2>&1`
    return unless $?.success?

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

    metadata[:additional] = {
      format: data['format']&.dig('format_name')
    }.compact

    log_info("Extracted audio metadata", duration: metadata[:dimensions][:duration])
  rescue StandardError => e
    log_warn("Failed to extract audio metadata: #{e.message}")
  end

  def extract_document_metadata(file_path, metadata)
    exif = MiniExiftool.new(file_path)

    metadata[:additional] = {
      title: exif.title,
      author: exif.author,
      creator: exif.creator,
      pages: exif.page_count || exif.pages,
      created: exif.create_date&.iso8601,
      modified: exif.modify_date&.iso8601
    }.compact

    log_info("Extracted document metadata", pages: metadata[:additional][:pages])
  rescue StandardError => e
    log_warn("Failed to extract document metadata: #{e.message}")
  end

  def extract_basic_metadata(file_path, metadata)
    # Just extract basic file stats
    file_stat = File.stat(file_path)

    metadata[:additional] = {
      modified_at: file_stat.mtime.iso8601,
      accessed_at: file_stat.atime.iso8601
    }
  end
end
