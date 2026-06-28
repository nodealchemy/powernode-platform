# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DocumentGenerationJob, type: :job do
  let(:job_instance)      { described_class.new }
  let(:api_client_double) { double('BackendApiClient') }
  let(:service_double)    { instance_double(DocumentPdfService) }

  let(:processing_job_id) { 'pj-doc-1' }
  let(:output_file_id)    { 'out-doc-1' }
  let(:sections)          { [{ 'heading' => 'A', 'body' => 'x' }, { 'heading' => 'B', 'body' => 'y' }] }
  let(:pdf_bytes)         { "%PDF-1.4\nfake" }

  let(:job_record) do
    {
      'id' => processing_job_id,
      'job_type' => 'document_generation',
      'job_parameters' => { 'title' => 'My Doc', 'sections' => sections, 'output_file_id' => output_file_id }
    }
  end

  before do
    Sidekiq::Testing.fake!
    allow(job_instance).to receive(:api_client).and_return(api_client_double)
    allow(job_instance).to receive(:log_error)
    allow(job_instance).to receive(:log_warn)
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)

    allow(DocumentPdfService).to receive(:new).and_return(service_double)
    allow(service_double).to receive(:render).and_return(pdf_bytes)

    allow(api_client_double).to receive(:get_file_processing_job).and_return(job_record)
    allow(api_client_double).to receive(:update_file_processing_job)
    allow(api_client_double).to receive(:upload_processed_file)
    allow(api_client_double).to receive(:complete_file_processing_job)
    allow(api_client_double).to receive(:fail_file_processing_job)
  end

  after { Sidekiq::Worker.clear_all }

  describe 'job configuration' do
    it 'uses the file_processing queue' do
      expect(described_class.get_sidekiq_options['queue']).to eq('file_processing')
    end
  end

  describe '#execute' do
    it 'marks the job processing' do
      job_instance.execute(processing_job_id)
      expect(api_client_double).to have_received(:update_file_processing_job).with(processing_job_id, status: 'processing')
    end

    it 'renders the PDF from the title + sections' do
      job_instance.execute(processing_job_id)
      expect(service_double).to have_received(:render).with(title: 'My Doc', sections: sections)
    end

    it 'uploads the rendered PDF to the output file as application/pdf' do
      job_instance.execute(processing_job_id)
      expect(api_client_double).to have_received(:upload_processed_file)
        .with(output_file_id, pdf_bytes, hash_including('content_type' => 'application/pdf', 'page_count' => 3))
    end

    it 'reports completion with page_count + section_count' do
      job_instance.execute(processing_job_id)
      expect(api_client_double).to have_received(:complete_file_processing_job)
        .with(processing_job_id, hash_including('page_count' => 3, 'section_count' => 2, 'output_file_id' => output_file_id))
    end

    context 'when rendering raises' do
      before { allow(service_double).to receive(:render).and_raise(StandardError, 'prawn boom') }

      it 'reports failure and re-raises' do
        expect { job_instance.execute(processing_job_id) }.to raise_error(StandardError, 'prawn boom')
        expect(api_client_double).to have_received(:fail_file_processing_job).with(processing_job_id, 'prawn boom')
      end
    end

    it 'raises when processing_job_id is blank' do
      expect { job_instance.execute('') }.to raise_error(ArgumentError)
    end
  end
end
