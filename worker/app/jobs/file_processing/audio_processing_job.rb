# frozen_string_literal: true

require 'tmpdir'

module FileProcessing
  # Probes an uploaded audio file and records its stream properties.
  #
  # Dispatched by the server for ProcessingJob type "audio_processing"
  # (FileManagement::Object#queue_processing_jobs on every audio upload). The
  # single argument is the FileManagement::ProcessingJob id.
  #
  # Audio needs no rendered derivative, so this job produces no uploaded artifact
  # — it probes with ffprobe and writes duration/codec/bitrate/channel data onto
  # the file object. Without ffprobe the row is failed with reason
  # "tool_unavailable" rather than raising ENOENT into the retry set.
  class AudioProcessingJob < BaseJob
    include ProcessingJobFlow

    sidekiq_options queue: 'file_processing', retry: 2

    def execute(processing_job_id)
      run_processing_job(processing_job_id) do |_record, file_object_id, file_object|
        service = FileProcessingService.new
        require_tools!(service, :ffprobe_available?)

        probe = nil
        Dir.mktmpdir('audio') do |dir|
          source = File.join(dir, 'source')
          File.binwrite(source, api_client.download_file_content(file_object_id))
          probe = service.probe_metadata(source)
        end

        format = probe['format'] || {}
        stream = Array(probe['streams']).find { |s| s['codec_type'] == 'audio' } || {}

        audio = {
          'format_name' => format['format_name'],
          'duration' => format['duration']&.to_f,
          'bit_rate' => format['bit_rate']&.to_i,
          'codec' => stream['codec_name'],
          'sample_rate' => stream['sample_rate']&.to_i,
          'channels' => stream['channels'],
          'channel_layout' => stream['channel_layout']
        }.compact

        # duration lives in dimensions because that is where the server reads it
        # from (FileManagement::Object#duration -> dimensions["duration"]).
        api_client.update_file_object(file_object_id, {
          dimensions: { 'duration' => format['duration'].to_f },
          metadata: { 'audio' => audio }
        })

        log_info('Processed audio',
                 processing_job_id: processing_job_id,
                 file_object_id: file_object_id,
                 duration: format['duration'])

        {
          'file_object_id' => file_object_id,
          'filename' => file_object['filename'],
          'audio' => audio,
          'ffprobe' => probe
        }
      end
    end
  end
end
