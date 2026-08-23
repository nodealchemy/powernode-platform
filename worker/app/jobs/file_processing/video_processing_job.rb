# frozen_string_literal: true

require 'tmpdir'

module FileProcessing
  # Probes an uploaded video and renders a poster frame for it.
  #
  # Dispatched by the server for ProcessingJob type "video_processing"
  # (FileManagement::Object#queue_processing_jobs on every video upload). The
  # single argument is the FileManagement::ProcessingJob id; job_parameters carry:
  #   - poster_offset_seconds: where to grab the poster frame (default 1)
  #   - poster: false to skip the poster frame entirely
  #
  # Requires ffprobe, and ffmpeg as well when a poster frame is wanted. Without
  # them the row is failed with reason "tool_unavailable" — never an ENOENT into
  # the retry set.
  class VideoProcessingJob < BaseJob
    include ProcessingJobFlow

    sidekiq_options queue: 'file_processing', retry: 2

    DEFAULT_POSTER_OFFSET = 1

    def execute(processing_job_id)
      run_processing_job(processing_job_id) do |record, file_object_id, file_object|
        service = FileProcessingService.new
        params = record['job_parameters'] || {}
        want_poster = params['poster'] != false

        # Check every tool up front so a missing ffmpeg is reported before the
        # file is downloaded and probed, not halfway through.
        tools = [:ffprobe_available?]
        tools << :ffmpeg_available? if want_poster
        require_tools!(service, *tools)

        probe = nil
        poster = nil

        Dir.mktmpdir('video') do |dir|
          source = File.join(dir, 'source')
          File.binwrite(source, api_client.download_file_content(file_object_id))

          probe = service.probe_metadata(source)

          if want_poster
            offset = params['poster_offset_seconds'] || DEFAULT_POSTER_OFFSET
            output = File.join(dir, 'poster.jpg')
            service.extract_video_frame(source, output, offset_seconds: offset)

            bytes = File.binread(output)
            storage_key = "processed/#{file_object_id}/poster.jpg"
            api_client.upload_processed_file(file_object_id, bytes, {
              'type' => 'video_poster',
              'size' => bytes.bytesize,
              'storage_key' => storage_key,
              'content_type' => 'image/jpeg'
            })

            poster = { 'storage_key' => storage_key, 'bytes' => bytes.bytesize, 'offset_seconds' => offset }
          end
        end

        format = probe['format'] || {}
        video_stream = Array(probe['streams']).find { |s| s['codec_type'] == 'video' } || {}
        audio_stream = Array(probe['streams']).find { |s| s['codec_type'] == 'audio' } || {}

        dimensions = {
          'width' => video_stream['width'].to_i,
          'height' => video_stream['height'].to_i,
          'duration' => format['duration'].to_f
        }

        api_client.update_file_object(file_object_id, {
          dimensions: dimensions,
          metadata: {
            'video' => {
              'format_name' => format['format_name'],
              'duration' => format['duration']&.to_f,
              'bit_rate' => format['bit_rate']&.to_i,
              'video_codec' => video_stream['codec_name'],
              'audio_codec' => audio_stream['codec_name'],
              'frame_rate' => video_stream['r_frame_rate'],
              'poster' => poster
            }.compact
          }
        })

        log_info('Processed video',
                 processing_job_id: processing_job_id,
                 file_object_id: file_object_id,
                 duration: format['duration'])

        {
          'file_object_id' => file_object_id,
          'filename' => file_object['filename'],
          'dimensions' => dimensions,
          'poster' => poster,
          'ffprobe' => probe
        }
      end
    end
  end
end
