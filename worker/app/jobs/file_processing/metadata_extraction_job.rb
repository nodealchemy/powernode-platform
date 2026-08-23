# frozen_string_literal: true

require 'tmpdir'

module FileProcessing
  # Extracts intrinsic metadata from an uploaded file and records it on the
  # FileManagement::Object.
  #
  # Dispatched by the server for ProcessingJob type "metadata_extract" (image and
  # document uploads). The single argument is the FileManagement::ProcessingJob id.
  #
  # The extractor is chosen from the file's content_type, and only the branch
  # actually taken requires its tool:
  #   image/*            -> ImageMagick identify (dimensions, colorspace, depth)
  #   video/*, audio/*   -> ffprobe (format + streams)
  #   everything else    -> byte size and extension only, NO external tool
  #
  # That last branch matters: documents are the largest caller of this job and
  # they need no binary at all, so metadata extraction still works on a worker
  # with no media tools installed. Only the image/video/audio branches fail with
  # reason "tool_unavailable" there.
  class MetadataExtractionJob < BaseJob
    include ProcessingJobFlow

    sidekiq_options queue: 'file_processing', retry: 2

    def execute(processing_job_id)
      run_processing_job(processing_job_id) do |_record, file_object_id, file_object|
        service = FileProcessingService.new
        content_type = file_object['content_type'].to_s
        filename = file_object['filename'].to_s

        kind = media_kind(content_type, filename)
        require_media_tool!(service, kind)

        extracted = nil
        Dir.mktmpdir('metadata') do |dir|
          path = File.join(dir, File.basename(filename.empty? ? 'file' : filename))
          File.binwrite(path, api_client.download_file_content(file_object_id))

          extracted = case kind
                      when :image then image_metadata(service, path)
                      when :media then media_metadata(service, path)
                      else basic_metadata(service, path)
                      end
        end

        update = { metadata: { 'extracted' => extracted, 'extracted_at' => Time.current.iso8601 } }
        dimensions = extracted['dimensions']
        update[:dimensions] = dimensions if dimensions.is_a?(Hash) && dimensions.any?
        api_client.update_file_object(file_object_id, update)

        log_info('Extracted file metadata',
                 processing_job_id: processing_job_id,
                 file_object_id: file_object_id,
                 kind: kind)

        {
          'file_object_id' => file_object_id,
          'kind' => kind.to_s,
          'metadata' => extracted
        }
      end
    end

    private

    # :image (ImageMagick), :media (ffprobe) or :basic (no external tool).
    # content_type is authoritative; the extension is only a fallback for
    # uploads that arrived as application/octet-stream.
    def media_kind(content_type, filename)
      return :image if content_type.start_with?('image/')
      return :media if content_type.start_with?('video/', 'audio/')

      ext = File.extname(filename).downcase.delete('.')
      return :image if %w[jpg jpeg png gif webp bmp tiff].include?(ext)
      return :media if %w[mp4 avi mov mkv webm flv wmv m4v mp3 wav flac aac ogg m4a wma].include?(ext)

      :basic
    end

    def require_media_tool!(service, kind)
      case kind
      when :image then require_tools!(service, :imagemagick_available?)
      when :media then require_tools!(service, :ffprobe_available?)
      end
    end

    def image_metadata(service, path)
      identified = service.identify_image(path)

      {
        'format' => identified['format'],
        'colorspace' => identified['colorspace'],
        'bit_depth' => identified['bit_depth'],
        'byte_size' => service.file_size(path),
        'dimensions' => { 'width' => identified['width'], 'height' => identified['height'] }
      }
    end

    def media_metadata(service, path)
      probe = service.probe_metadata(path)
      format = probe['format'] || {}
      video_stream = Array(probe['streams']).find { |s| s['codec_type'] == 'video' } || {}

      dimensions = {}
      dimensions['width'] = video_stream['width'].to_i if video_stream['width']
      dimensions['height'] = video_stream['height'].to_i if video_stream['height']
      dimensions['duration'] = format['duration'].to_f if format['duration']

      {
        'format_name' => format['format_name'],
        'duration' => format['duration']&.to_f,
        'bit_rate' => format['bit_rate']&.to_i,
        'byte_size' => service.file_size(path),
        'streams' => Array(probe['streams']).map { |s| s.slice('codec_type', 'codec_name') },
        'dimensions' => dimensions
      }
    end

    def basic_metadata(service, path)
      {
        'format' => service.file_format(path),
        'byte_size' => service.file_size(path),
        'dimensions' => {}
      }
    end
  end
end
