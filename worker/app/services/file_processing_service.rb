# frozen_string_literal: true

require 'open3'
require 'json'
require 'tempfile'

# Service for file processing operations
# Provides utilities for image manipulation, metadata extraction, and file operations
class FileProcessingService
  class ProcessingError < StandardError; end
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

  # Concatenate ordered scene clips into a single mp4 using ffmpeg's concat
  # demuxer. `scene_paths` is the ordered list of local clip paths; the joined
  # result is written to `output_path` (returned on success).
  #
  # Tries stream-copy first (fast, lossless, when inputs share a codec) and falls
  # back to a re-encode when copy can't concat heterogeneous inputs. Raises
  # ProcessingError when ffmpeg is unavailable, no scenes are given, or ffmpeg
  # exits non-zero on both attempts.
  def stitch_scenes(scene_paths, output_path)
    raise ProcessingError, 'ffmpeg is not available' unless ffmpeg_available?
    raise ProcessingError, 'no scenes to stitch' if scene_paths.nil? || scene_paths.empty?

    list = Tempfile.new(['concat', '.txt'])
    begin
      # concat demuxer format: one `file '<path>'` line per ordered clip.
      # Single quotes in paths are escaped per the demuxer's rules ('\'').
      scene_paths.each { |p| list.puts("file '#{p.to_s.gsub("'", "'\\\\''")}'") }
      list.flush

      stdout, stderr, status = run_ffmpeg_concat(list.path, output_path, copy: true)
      unless status.success?
        log_warn('ffmpeg stream-copy concat failed, retrying with re-encode', stderr: stderr.to_s[0, 500])
        stdout, stderr, status = run_ffmpeg_concat(list.path, output_path, copy: false)
        raise ProcessingError, "ffmpeg stitch failed: #{stderr}" unless status.success?
      end

      output_path
    ensure
      list.close
      list.unlink
    end
  end

  # Extract media metadata (format + streams) for a file via ffprobe, returned as
  # a parsed Hash. Raises ProcessingError when ffprobe is unavailable or fails.
  def probe_metadata(path)
    raise ProcessingError, 'ffprobe is not available' unless ffprobe_available?

    cmd = ['ffprobe', '-v', 'quiet', '-print_format', 'json',
           '-show_format', '-show_streams', path.to_s]
    stdout, stderr, status = Open3.capture3(*cmd)
    raise ProcessingError, "ffprobe failed: #{stderr}" unless status.success?

    JSON.parse(stdout)
  end

  # Build + run the ffmpeg concat-demuxer command. With copy: true uses stream
  # copy (-c copy); otherwise re-encodes to H.264/AAC. Returns [stdout, stderr, status].
  def run_ffmpeg_concat(list_path, output_path, copy:)
    codec_args = copy ? ['-c', 'copy'] : ['-c:v', 'libx264', '-c:a', 'aac']
    cmd = ['ffmpeg', '-y', '-f', 'concat', '-safe', '0', '-i', list_path, *codec_args, output_path.to_s]
    Open3.capture3(*cmd)
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
