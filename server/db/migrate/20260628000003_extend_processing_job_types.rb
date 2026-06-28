# frozen_string_literal: true

# Extend file_processing_jobs.job_type to allow the media types the system already
# dispatches: video_processing / audio_processing (FileManagement::Object queues
# these on create + WorkerApiClient routes them, but the enum never allowed them,
# so creating a video/audio object raised) and the new video_stitching type that
# concatenates a bundle's ordered scene clips into one mp4 (worker ffmpeg wrapper).
class ExtendProcessingJobTypes < ActiveRecord::Migration[8.0]
  OLD_TYPES = %w[thumbnail resize convert scan ocr metadata_extract compress watermark transform].freeze
  NEW_TYPES = (OLD_TYPES + %w[video_processing audio_processing video_stitching]).freeze
  CONSTRAINT = "file_processing_jobs_job_type_check"

  def up
    swap_job_type_constraint(NEW_TYPES)
  end

  def down
    swap_job_type_constraint(OLD_TYPES)
  end

  private

  def swap_job_type_constraint(types)
    remove_check_constraint :file_processing_jobs, name: CONSTRAINT
    add_check_constraint :file_processing_jobs, job_type_expression(types), name: CONSTRAINT
  end

  def job_type_expression(types)
    list = types.map { |t| "'#{t}'::character varying::text" }.join(", ")
    "job_type::text = ANY (ARRAY[#{list}])"
  end
end
