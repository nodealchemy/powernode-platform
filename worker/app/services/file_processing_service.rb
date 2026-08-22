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

  # Named thumbnail sizes. FileManagement::Object#queue_processing_jobs asks for
  # ["small", "medium", "large"]; the geometry is `>`-suffixed so an image
  # already smaller than the box is never upscaled.
  THUMBNAIL_GEOMETRY = {
    'small' => '150x150>',
    'medium' => '400x400>',
    'large' => '1024x1024>'
  }.freeze

  # Check if ImageMagick is available. ImageMagick 7 ships a single `magick`
  # entrypoint and may omit the v6 `convert`/`identify` shims entirely, so both
  # spellings count.
  #
  # BOTH v6 binaries are required, not just `convert`: this service shells out to
  # `identify` as well, and some slim v6 packagings ship one without the other.
  # Answering true on `convert` alone would move the failure from this guard
  # (terminal, reported) to an ENOENT inside identify_image.
  def imagemagick_available?
    magick_v7? || (on_path?('convert') && on_path?('identify'))
  end

  def magick_v7?
    return @magick_v7 if defined?(@magick_v7)

    @magick_v7 = on_path?('magick')
  end

  # argv prefix for an ImageMagick subcommand ("convert" / "identify"), spelled
  # for whichever major version is installed.
  def imagemagick_argv(subcommand)
    magick_v7? ? ['magick', subcommand] : [subcommand]
  end

  # Memoized PATH lookup — the availability predicates are called once per job
  # AND once per thumbnail size, and each bare `system('which ...')` forks.
  def on_path?(binary)
    @on_path ||= {}
    return @on_path[binary] if @on_path.key?(binary)

    @on_path[binary] = system("which #{binary} > /dev/null 2>&1")
  end

  # Read an image's intrinsic properties with ImageMagick's `identify`. Returns
  # a Hash with string keys; raises ProcessingError when ImageMagick is absent or
  # identify exits non-zero (an unreadable/corrupt file).
  #
  # `[0]` restricts the read to the FIRST frame — a multi-page TIFF or animated
  # GIF would otherwise print one line per frame and the parse below would see
  # only a concatenated mess.
  def identify_image(path)
    raise ProcessingError, 'ImageMagick is not available' unless imagemagick_available?

    fmt = '%m|%w|%h|%[colorspace]|%z|%[bit-depth]'
    cmd = [*imagemagick_argv('identify'), '-format', fmt, "#{path}[0]"]
    stdout, stderr, status = Open3.capture3(*cmd)
    raise ProcessingError, "identify failed: #{stderr}" unless status.success?

    format, width, height, colorspace, depth, bit_depth = stdout.strip.split('|')

    {
      'format' => format,
      'width' => width.to_i,
      'height' => height.to_i,
      'colorspace' => colorspace,
      'depth' => depth.to_i,
      'bit_depth' => bit_depth.to_i
    }
  end

  # Render one thumbnail of `source_path` into `output_path` at the named size
  # (see THUMBNAIL_GEOMETRY) or an explicit ImageMagick geometry string.
  # Returns output_path; raises ProcessingError on an unknown size, a missing
  # ImageMagick, or a non-zero convert.
  def generate_thumbnail(source_path, output_path, size)
    raise ProcessingError, 'ImageMagick is not available' unless imagemagick_available?

    geometry = THUMBNAIL_GEOMETRY[size.to_s] || (size.to_s.match?(/\A\d+x\d+/) ? size.to_s : nil)
    raise ProcessingError, "unknown thumbnail size '#{size}'" unless geometry

    # `[0]` again: take the first frame, never a whole animation.
    # -auto-orient applies the EXIF rotation so portrait phone photos are not
    # thumbnailed sideways. -strip drops EXIF (incl. GPS) from the DERIVATIVE —
    # the original keeps it, and MetadataExtractionJob records it separately.
    cmd = [*imagemagick_argv('convert'), "#{source_path}[0]",
           '-auto-orient', '-thumbnail', geometry, '-strip', output_path.to_s]
    _stdout, stderr, status = Open3.capture3(*cmd)
    raise ProcessingError, "thumbnail generation failed: #{stderr}" unless status.success?

    output_path
  end

  # Extract a single poster frame from a video at `offset_seconds`. Returns
  # output_path; raises ProcessingError when ffmpeg is absent or fails.
  def extract_video_frame(source_path, output_path, offset_seconds: 1)
    raise ProcessingError, 'ffmpeg is not available' unless ffmpeg_available?

    cmd = ['ffmpeg', '-y', '-ss', offset_seconds.to_s, '-i', source_path.to_s,
           '-frames:v', '1', output_path.to_s]
    _stdout, stderr, status = Open3.capture3(*cmd)
    raise ProcessingError, "poster frame extraction failed: #{stderr}" unless status.success?

    output_path
  end

  # Check if FFmpeg is available
  def ffmpeg_available?
    on_path?('ffmpeg')
  end

  # Check if FFprobe is available
  def ffprobe_available?
    on_path?('ffprobe')
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
