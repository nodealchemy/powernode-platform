# frozen_string_literal: true

require 'rails_helper'

# The defect these four jobs exist to remove: the server creates a
# FileManagement::ProcessingJob row as "pending" and then dispatches by
# class-name string. Nothing else moves that row, so any path that ends without
# reporting leaves it pending forever and the uploader is told nothing.
#
# Every example below asserts the TERMINAL outcome (completed or failed), not
# merely that the constant resolves — the server-side contract guard already
# proves resolution and proves nothing about the file being processed.
module FileProcessingTerminalStateContract
  ALL_JOBS = [
    FileProcessing::ThumbnailGenerationJob,
    FileProcessing::MetadataExtractionJob,
    FileProcessing::VideoProcessingJob,
    FileProcessing::AudioProcessingJob
  ].freeze
end

RSpec.describe 'FileProcessing job terminal-state contract', type: :job do
  all_jobs = FileProcessingTerminalStateContract::ALL_JOBS

  let(:api_client) { double('BackendApiClient') }
  let(:service)    { instance_double(FileProcessingService) }

  let(:processing_job_id) { 'pj-1' }
  let(:file_object_id)    { 'fo-1' }

  let(:job_record) do
    {
      'id' => processing_job_id,
      'status' => 'pending',
      'job_type' => 'thumbnail',
      'file_object_id' => file_object_id,
      'job_parameters' => { 'sizes' => %w[small] },
      'file_object' => {
        'id' => file_object_id,
        'filename' => 'photo.jpg',
        'content_type' => 'image/jpeg'
      }
    }
  end

  # The server answers with the render_success envelope; the client hands the
  # raw body back, so the jobs must unwrap "data" themselves.
  let(:envelope) { { 'success' => true, 'data' => job_record } }

  let(:ffprobe_output) do
    {
      'format' => { 'format_name' => 'mov,mp4', 'duration' => '12.5', 'bit_rate' => '900000' },
      'streams' => [
        { 'codec_type' => 'video', 'codec_name' => 'h264', 'width' => 1920, 'height' => 1080 },
        { 'codec_type' => 'audio', 'codec_name' => 'aac', 'sample_rate' => '44100', 'channels' => 2 }
      ]
    }
  end

  def build(klass)
    klass.new.tap do |job|
      allow(job).to receive(:api_client).and_return(api_client)
      allow(job).to receive(:log_info)
      allow(job).to receive(:log_warn)
      allow(job).to receive(:log_error)
    end
  end

  before do
    Sidekiq::Testing.fake!
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
    allow(FileProcessingService).to receive(:new).and_return(service)

    allow(api_client).to receive(:get_file_processing_job).and_return(envelope)
    allow(api_client).to receive(:update_file_processing_job)
    allow(api_client).to receive(:complete_file_processing_job)
    allow(api_client).to receive(:fail_file_processing_job)
    allow(api_client).to receive(:update_file_object)
    allow(api_client).to receive(:upload_processed_file)
    allow(api_client).to receive(:download_file_content).and_return('BYTES')

    allow(service).to receive(:imagemagick_available?).and_return(true)
    allow(service).to receive(:ffmpeg_available?).and_return(true)
    allow(service).to receive(:ffprobe_available?).and_return(true)
    allow(service).to receive(:identify_image).and_return(
      'format' => 'JPEG', 'width' => 3000, 'height' => 2000,
      'colorspace' => 'sRGB', 'depth' => 8, 'bit_depth' => 8
    )
    allow(service).to receive(:generate_thumbnail) { |_src, out, _size| File.binwrite(out, 'THUMB'); out }
    allow(service).to receive(:extract_video_frame) { |_src, out, **| File.binwrite(out, 'POSTER'); out }
    allow(service).to receive(:probe_metadata).and_return(ffprobe_output)
    allow(service).to receive(:file_size).and_return(5)
    allow(service).to receive(:file_format).and_return('pdf')
  end

  after { Sidekiq::Worker.clear_all }

  describe 'enqueueability (mirrors the worker JobsController#valid_job_class? predicates)' do
    all_jobs.each do |klass|
      it "#{klass} is a BaseJob subclass on the file_processing queue" do
        expect(klass).to be < BaseJob
        expect(klass.get_sidekiq_options['queue']).to eq('file_processing')
      end
    end
  end

  describe 'the happy path reaches COMPLETED' do
    all_jobs.each do |klass|
      it "#{klass} marks the row processing and then completes it" do
        build(klass).execute(processing_job_id)

        expect(api_client).to have_received(:update_file_processing_job)
          .with(processing_job_id, status: 'processing')
        expect(api_client).to have_received(:complete_file_processing_job)
          .with(processing_job_id, kind_of(Hash))
        expect(api_client).not_to have_received(:fail_file_processing_job)
      end
    end
  end

  # A worker image with no ffmpeg/ImageMagick is the CURRENT fleet reality (no
  # platform module ships those packages). The job must still leave the row
  # terminal instead of raising ENOENT into the retry set and stranding it.
  describe 'a missing external tool reaches FAILED, not pending, and does not retry' do
    {
      FileProcessing::ThumbnailGenerationJob => :imagemagick_available?,
      FileProcessing::VideoProcessingJob     => :ffprobe_available?,
      FileProcessing::AudioProcessingJob     => :ffprobe_available?
    }.each do |klass, predicate|
      it "#{klass} fails the row when #{predicate} is false" do
        allow(service).to receive(predicate).and_return(false)

        expect { @result = build(klass).execute(processing_job_id) }.not_to raise_error

        expect(api_client).to have_received(:update_file_processing_job)
          .with(processing_job_id, status: 'processing')
        expect(api_client).to have_received(:fail_file_processing_job)
          .with(processing_job_id, /not installed on this worker/, hash_including('reason' => 'tool_unavailable'))
        expect(api_client).not_to have_received(:complete_file_processing_job)
        expect(@result[:reason]).to eq('tool_unavailable')
      end
    end

    it 'MetadataExtractionJob fails an IMAGE when ImageMagick is missing' do
      allow(service).to receive(:imagemagick_available?).and_return(false)

      build(FileProcessing::MetadataExtractionJob).execute(processing_job_id)

      expect(api_client).to have_received(:fail_file_processing_job)
        .with(processing_job_id, anything, hash_including('reason' => 'tool_unavailable'))
    end

    # Documents are the largest caller of metadata extraction and need no
    # binary, so that branch must still COMPLETE on a tool-less worker.
    it 'MetadataExtractionJob still completes a DOCUMENT with no media tools at all' do
      allow(service).to receive(:imagemagick_available?).and_return(false)
      allow(service).to receive(:ffprobe_available?).and_return(false)
      job_record['file_object']['content_type'] = 'application/pdf'
      job_record['file_object']['filename'] = 'report.pdf'

      build(FileProcessing::MetadataExtractionJob).execute(processing_job_id)

      expect(api_client).to have_received(:complete_file_processing_job)
      expect(api_client).not_to have_received(:fail_file_processing_job)
    end
  end

  describe 'a processing error reaches FAILED and re-raises for Sidekiq' do
    all_jobs.each do |klass|
      it "#{klass} reports the failure before re-raising" do
        allow(api_client).to receive(:download_file_content).and_raise(StandardError, 'storage exploded')

        expect { build(klass).execute(processing_job_id) }.to raise_error(StandardError, 'storage exploded')
        expect(api_client).to have_received(:fail_file_processing_job)
          .with(processing_job_id, 'storage exploded', {})
      end
    end
  end

  describe 'a row with no file object still reaches FAILED' do
    all_jobs.each do |klass|
      it "#{klass} fails rather than leaving it pending" do
        job_record.delete('file_object_id')
        job_record['file_object'] = {}

        result = build(klass).execute(processing_job_id)

        expect(result[:reason]).to eq('no_file_object')
        # mark_failed! refuses a pending row, so the job must step it through
        # processing on the way to failed or the report cannot land.
        expect(api_client).to have_received(:update_file_processing_job)
          .with(processing_job_id, status: 'processing')
        expect(api_client).to have_received(:fail_file_processing_job)
          .with(processing_job_id, /no file object/, {})
      end
    end
  end

  # On a Sidekiq RETRY the first attempt already moved the row to processing.
  # ProcessingJob#start_processing! returns false for a non-pending row and the
  # controller renders 422 — re-asserting it would make every retry die at the
  # first API call and the row could never reach terminal.
  describe 'a retry against an already-processing row still completes' do
    all_jobs.each do |klass|
      it "#{klass} does not re-assert the processing transition" do
        job_record['status'] = 'processing'

        build(klass).execute(processing_job_id)

        expect(api_client).not_to have_received(:update_file_processing_job)
          .with(processing_job_id, status: 'processing')
        expect(api_client).to have_received(:complete_file_processing_job)
      end
    end
  end

  describe 'argument validation' do
    all_jobs.each do |klass|
      it "#{klass} rejects a blank processing_job_id" do
        expect { build(klass).execute(nil) }.to raise_error(ArgumentError)
        expect { build(klass).execute('') }.to raise_error(ArgumentError)
      end
    end
  end
end
