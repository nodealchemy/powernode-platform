# frozen_string_literal: true

# Renders a content production's document deliverable as a multi-page PDF (Prawn)
# and uploads it to the target FileManagement::Object.
#
# The server enqueues this job (WorkerApiClient maps the "document_generation"
# ProcessingJob type to this class). The single argument is the
# FileManagement::ProcessingJob id; its job_parameters carry:
#   - title:    document title (string)
#   - sections: ordered [{heading, body}, ...] — one page each
#   - output_file_id: the FileManagement::Object to receive the rendered PDF
#
# Flow: fetch job → mark processing → render PDF → upload → report completion.
# Mirrors the async report-generation pattern (Reports::GenerateReportJob).
class DocumentGenerationJob < BaseJob
  sidekiq_options retry: 3, dead: true, queue: 'file_processing'

  def execute(processing_job_id)
    raise ArgumentError, 'processing_job_id is required' if processing_job_id.nil? || processing_job_id.to_s.empty?

    job = api_client.get_file_processing_job(processing_job_id)
    params = (job && (job['job_parameters'] || job[:job_parameters])) || {}
    title = params['title'] || params[:title] || 'Document'
    sections = params['sections'] || params[:sections] || []
    output_file_id = params['output_file_id'] || params[:output_file_id]

    api_client.update_file_processing_job(processing_job_id, status: 'processing')

    pdf = DocumentPdfService.new.render(title: title, sections: sections)
    page_count = 1 + Array(sections).length

    if output_file_id
      api_client.upload_processed_file(output_file_id, pdf, {
        'content_type' => 'application/pdf',
        'page_count' => page_count,
        'byte_size' => pdf.bytesize
      })
    end

    api_client.complete_file_processing_job(processing_job_id, {
      'output_file_id' => output_file_id,
      'page_count' => page_count,
      'byte_size' => pdf.bytesize,
      'section_count' => Array(sections).length
    })

    { success: true, page_count: page_count }
  rescue StandardError => e
    log_error('Document generation failed', e, processing_job_id: processing_job_id)
    safe_report_failure(processing_job_id, e.message)
    raise
  end

  private

  def safe_report_failure(processing_job_id, message)
    api_client.fail_file_processing_job(processing_job_id, message)
  rescue StandardError => e
    log_warn('Failed to report document generation failure to server', error: e.message)
  end
end
