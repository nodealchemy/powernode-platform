# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VideoStitchingJob, type: :job do
  let(:job_instance)      { described_class.new }
  let(:api_client_double) { double('BackendApiClient') }
  let(:service_double)    { instance_double(FileProcessingService) }

  let(:processing_job_id) { 'pj-uuid-1' }
  let(:scene_ids)         { %w[scene-a scene-b scene-c] }
  let(:output_file_id)    { 'out-file-1' }
  let(:ffprobe_meta)      { { 'format' => { 'duration' => '30.0' } } }

  let(:job_record) do
    {
      'id' => processing_job_id,
      'job_type' => 'video_stitching',
      'job_parameters' => { 'scene_file_ids' => scene_ids, 'output_file_id' => output_file_id }
    }
  end

  before do
    Sidekiq::Testing.fake!
    allow(job_instance).to receive(:api_client).and_return(api_client_double)
    allow(job_instance).to receive(:log_error)
    allow(job_instance).to receive(:log_warn)
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)

    allow(FileProcessingService).to receive(:new).and_return(service_double)
    # stitch writes the output so File.binread succeeds; probe returns metadata.
    allow(service_double).to receive(:stitch_scenes) { |_paths, out| File.binwrite(out, 'MP4'); out }
    allow(service_double).to receive(:probe_metadata).and_return(ffprobe_meta)

    allow(api_client_double).to receive(:get_file_processing_job).and_return(job_record)
    allow(api_client_double).to receive(:update_file_processing_job)
    allow(api_client_double).to receive(:download_file_content) { |id| "bytes-#{id}" }
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
    it 'marks the job processing before working' do
      job_instance.execute(processing_job_id)
      expect(api_client_double).to have_received(:update_file_processing_job)
        .with(processing_job_id, status: 'processing')
    end

    it 'downloads every scene clip in order' do
      job_instance.execute(processing_job_id)
      scene_ids.each { |id| expect(api_client_double).to have_received(:download_file_content).with(id) }
    end

    it 'stitches the downloaded scenes (one local path per scene)' do
      captured_paths = nil
      allow(service_double).to receive(:stitch_scenes) do |paths, out|
        captured_paths = paths
        File.binwrite(out, 'MP4'); out
      end

      job_instance.execute(processing_job_id)
      expect(captured_paths.length).to eq(scene_ids.length)
    end

    it 'uploads the rendered mp4 to the output file with ffprobe metadata' do
      job_instance.execute(processing_job_id)
      expect(api_client_double).to have_received(:upload_processed_file)
        .with(output_file_id, anything, ffprobe_meta)
    end

    it 'reports completion with scene_count + ffprobe metadata' do
      job_instance.execute(processing_job_id)
      expect(api_client_double).to have_received(:complete_file_processing_job).with(
        processing_job_id,
        hash_including('scene_count' => scene_ids.length, 'ffprobe' => ffprobe_meta, 'output_file_id' => output_file_id)
      )
    end

    context 'when there are no scenes' do
      let(:job_record) { { 'id' => processing_job_id, 'job_parameters' => { 'scene_file_ids' => [] } } }

      it 'fails the job and skips without stitching' do
        result = job_instance.execute(processing_job_id)
        expect(api_client_double).to have_received(:fail_file_processing_job).with(processing_job_id, /no scenes/)
        expect(service_double).not_to have_received(:stitch_scenes)
        expect(result).to eq(skipped: true)
      end
    end

    context 'when stitching raises' do
      before do
        allow(service_double).to receive(:stitch_scenes).and_raise(FileProcessingService::ProcessingError, 'ffmpeg boom')
      end

      it 'reports failure to the server and re-raises' do
        expect { job_instance.execute(processing_job_id) }.to raise_error(FileProcessingService::ProcessingError)
        expect(api_client_double).to have_received(:fail_file_processing_job).with(processing_job_id, 'ffmpeg boom')
      end
    end

    it 'raises when processing_job_id is blank' do
      expect { job_instance.execute(nil) }.to raise_error(ArgumentError)
    end
  end
end
