# frozen_string_literal: true

require 'tmpdir'

module FileProcessing
  # Renders thumbnails for an uploaded image.
  #
  # Dispatched by the server for ProcessingJob type "thumbnail"
  # (FileManagement::Object#queue_processing_jobs on every image upload, and
  # FileStorageService#queue_processing_job). The single argument is the
  # FileManagement::ProcessingJob id; job_parameters carry:
  #   - sizes: names from FileProcessingService::THUMBNAIL_GEOMETRY
  #            (default ["small", "medium", "large"])
  #
  # Flow: fetch job -> mark processing -> download original -> ImageMagick
  # convert per size -> upload each derivative -> record dimensions on the file
  # object -> complete. Requires ImageMagick; without it the row is failed with
  # reason "tool_unavailable" rather than raising ENOENT into the retry set.
  class ThumbnailGenerationJob < BaseJob
    include ProcessingJobFlow

    sidekiq_options queue: 'file_processing', retry: 2

    DEFAULT_SIZES = %w[small medium large].freeze

    def execute(processing_job_id)
      run_processing_job(processing_job_id) do |record, file_object_id, file_object|
        service = FileProcessingService.new
        require_tools!(service, :imagemagick_available?)

        params = record['job_parameters'] || {}
        sizes = Array(params['sizes']).map(&:to_s).reject(&:empty?)
        sizes = DEFAULT_SIZES if sizes.empty?

        generated = []
        source_dimensions = nil

        Dir.mktmpdir('thumbnail') do |dir|
          source = File.join(dir, 'source')
          File.binwrite(source, api_client.download_file_content(file_object_id))

          source_dimensions = service.identify_image(source)

          sizes.each do |size|
            output = File.join(dir, "thumb_#{size}.jpg")
            service.generate_thumbnail(source, output, size)

            bytes = File.binread(output)
            storage_key = "processed/#{file_object_id}/thumbnails/#{size}.jpg"
            api_client.upload_processed_file(file_object_id, bytes, {
              'type' => "thumbnail_#{size}",
              'size' => bytes.bytesize,
              'storage_key' => storage_key,
              'content_type' => 'image/jpeg'
            })

            generated << {
              'size' => size,
              'storage_key' => storage_key,
              'bytes' => bytes.bytesize
            }
          end
        end

        # Record the ORIGINAL's pixel dimensions on the file object — the
        # uploader's width/height come from here (FileManagement::Object#width).
        api_client.update_file_object(file_object_id, {
          dimensions: {
            'width' => source_dimensions['width'],
            'height' => source_dimensions['height']
          },
          metadata: { 'thumbnails' => generated }
        })

        log_info('Generated thumbnails',
                 processing_job_id: processing_job_id,
                 file_object_id: file_object_id,
                 count: generated.length)

        {
          'file_object_id' => file_object_id,
          'thumbnails' => generated,
          'source_dimensions' => source_dimensions,
          'filename' => file_object['filename']
        }
      end
    end
  end
end
