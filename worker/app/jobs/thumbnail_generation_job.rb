# frozen_string_literal: true

require 'mini_magick'

# Generates thumbnails for image files
# Creates small (150x150), medium (300x300), and large (600x600) thumbnails
class ThumbnailGenerationJob < FileProcessingWorker
  def execute(processing_job_id)
    log_info("Starting thumbnail generation", job_id: processing_job_id)

    # Load job and file data
    job_data = load_processing_job(processing_job_id)
    file_object_id = job_data['file_object_id']
    file_data = load_file_object(file_object_id)

    # Start processing
    start_processing_job!(processing_job_id)

    # Get thumbnail sizes from job parameters or use defaults
    sizes = job_data['job_parameters']&.dig('sizes') || ['small', 'medium', 'large']

    # Download original file
    temp_file = download_file_content(file_object_id)

    begin
      thumbnails = generate_thumbnails(temp_file.path, sizes)

      # Upload each thumbnail
      thumbnail_urls = {}
      thumbnails.each do |size, thumbnail_path|
        upload_processed_file(
          file_object_id,
          thumbnail_path,
          {
            type: 'thumbnail',
            size: size,
            storage_key: "thumbnails/#{file_object_id}/#{size}.jpg"
          }
        )

        thumbnail_urls[size] = "thumbnails/#{file_object_id}/#{size}.jpg"
      end

      # Update file metadata with thumbnail URLs
      update_file_metadata(file_object_id, { thumbnail_urls: thumbnail_urls })

      # Mark job as completed
      complete_processing_job!(processing_job_id, { thumbnails: thumbnail_urls })

      log_info("Thumbnail generation completed", job_id: processing_job_id, count: thumbnails.size)

    rescue StandardError => e
      fail_processing_job!(processing_job_id, e.message, { error_class: e.class.name })
      raise
    ensure
      cleanup_temp_file(temp_file)
    end
  end

  private

  def generate_thumbnails(source_path, sizes)
    thumbnails = {}

    with_working_directory do |work_dir|
      sizes.each do |size|
        dimension = thumbnail_dimension(size)
        output_path = File.join(work_dir, "#{size}.jpg")

        image = MiniMagick::Image.open(source_path)

        # Resize to fit within dimensions, maintaining aspect ratio
        image.resize "#{dimension}x#{dimension}>"

        # Convert to JPEG with quality 85
        image.format 'jpg'
        image.quality 85

        image.write output_path

        thumbnails[size] = output_path

        log_info("Generated thumbnail", size: size, dimension: dimension)
      end
    end

    thumbnails
  rescue MiniMagick::Error => e
    log_error("Failed to generate thumbnails", e)
    raise StandardError, "Thumbnail generation failed: #{e.message}"
  end

  def thumbnail_dimension(size)
    case size.to_s
    when 'small' then 150
    when 'medium' then 300
    when 'large' then 600
    else 300  # default to medium
    end
  end
end
