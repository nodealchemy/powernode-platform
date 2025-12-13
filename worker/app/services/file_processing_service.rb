# frozen_string_literal: true

# Service for file processing operations
# Provides utilities for image manipulation, metadata extraction, and file operations
class FileProcessingService
  attr_reader :logger

  def initialize
    @logger = PowernodeWorker.application.logger
  end

  # Check if ImageMagick is available
  def imagemagick_available?
    system('which convert > /dev/null 2>&1')
  end

  # Check if FFmpeg is available
  def ffmpeg_available?
    system('which ffmpeg > /dev/null 2>&1')
  end

  # Check if FFprobe is available
  def ffprobe_available?
    system('which ffprobe > /dev/null 2>&1')
  end

  # Get file format from path
  def file_format(file_path)
    File.extname(file_path).downcase.delete('.')
  end

  # Get file size in bytes
  def file_size(file_path)
    File.size(file_path)
  end

  # Check if file is an image
  def image_file?(file_path)
    %w[jpg jpeg png gif webp bmp tiff].include?(file_format(file_path))
  end

  # Check if file is a video
  def video_file?(file_path)
    %w[mp4 avi mov mkv webm flv wmv m4v].include?(file_format(file_path))
  end

  # Check if file is audio
  def audio_file?(file_path)
    %w[mp3 wav flac aac ogg m4a wma].include?(file_format(file_path))
  end

  # Log utility methods
  def log_info(message, **metadata)
    if metadata.any?
      logger.info "#{message} | #{metadata.map { |k, v| "#{k}=#{v}" }.join(' ')}"
    else
      logger.info message
    end
  end

  def log_error(message, exception = nil, **metadata)
    error_details = {
      message: message,
      exception: exception&.class&.name,
      exception_message: exception&.message
    }.merge(metadata).compact

    logger.error error_details.map { |k, v| "#{k}=#{v}" }.join(' ')
  end

  def log_warn(message, **metadata)
    if metadata.any?
      logger.warn "#{message} | #{metadata.map { |k, v| "#{k}=#{v}" }.join(' ')}"
    else
      logger.warn message
    end
  end
end
