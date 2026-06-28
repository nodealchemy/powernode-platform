# frozen_string_literal: true

# Allow the document_generation ProcessingJob type — the worker renders a
# multi-page PDF (Prawn) for a content production's document deliverable and
# uploads it to the target FileManagement::Object.
class AddDocumentGenerationJobType < ActiveRecord::Migration[8.0]
  WITHOUT = %w[thumbnail resize convert scan ocr metadata_extract compress watermark transform
               video_processing audio_processing video_stitching].freeze
  WITH = (WITHOUT + %w[document_generation]).freeze
  CONSTRAINT = "file_processing_jobs_job_type_check"

  def up
    swap_job_type_constraint(WITH)
  end

  def down
    swap_job_type_constraint(WITHOUT)
  end

  private

  def swap_job_type_constraint(types)
    remove_check_constraint :file_processing_jobs, name: CONSTRAINT
    list = types.map { |t| "'#{t}'::character varying::text" }.join(", ")
    add_check_constraint :file_processing_jobs, "job_type::text = ANY (ARRAY[#{list}])", name: CONSTRAINT
  end
end
