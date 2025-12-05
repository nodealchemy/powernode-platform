# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AudioProcessingJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class

  before { mock_powernode_worker_config }

  let(:processing_job_id) { SecureRandom.uuid }
  let(:file_object_id) { SecureRandom.uuid }

  let(:processing_job_data) do
    {
      'id' => processing_job_id,
      'file_object_id' => file_object_id,
      'job_type' => 'audio_processing',
      'status' => 'pending'
    }
  end

  let(:file_object_data) do
    {
      'id' => file_object_id,
      'filename' => 'test_audio.mp3',
      'content_type' => 'audio/mpeg',
      'size' => 1024000,
      'metadata' => {}
    }
  end

  let(:audio_content) { 'fake audio content' }

  describe '#execute' do
    context 'when audio processing succeeds' do
      before do
        stub_backend_api_success(:get, "/api/v1/file_processing_jobs/#{processing_job_id}", processing_job_data)
        stub_backend_api_success(:get, "/api/v1/file_objects/#{file_object_id}", file_object_data)
        stub_backend_api_success(:patch, "/api/v1/file_processing_jobs/#{processing_job_id}", { 'success' => true })
        stub_backend_api_success(:get, "/api/v1/file_objects/#{file_object_id}/download", audio_content)
        stub_backend_api_success(:patch, "/api/v1/file_objects/#{file_object_id}", { 'success' => true })
        stub_backend_api_success(:post, "/api/v1/file_processing_jobs/#{processing_job_id}/complete", { 'success' => true })

        # Mock ffprobe command
        allow_any_instance_of(described_class).to receive(:`).and_return(ffprobe_json_output)
        allow($?).to receive(:success?).and_return(true)
      end

      let(:ffprobe_json_output) do
        {
          'format' => {
            'duration' => '180.5',
            'format_name' => 'mp3',
            'tags' => {
              'title' => 'Test Song',
              'artist' => 'Test Artist',
              'album' => 'Test Album'
            }
          },
          'streams' => [
            {
              'codec_type' => 'audio',
              'codec_name' => 'mp3',
              'bit_rate' => '320000',
              'sample_rate' => '44100',
              'channels' => 2
            }
          ]
        }.to_json
      end

      it 'loads the processing job' do
        described_class.new.execute(processing_job_id)

        expect_api_request(:get, "/api/v1/file_processing_jobs/#{processing_job_id}")
      end

      it 'loads the file object' do
        described_class.new.execute(processing_job_id)

        expect_api_request(:get, "/api/v1/file_objects/#{file_object_id}")
      end

      it 'updates job status to processing' do
        described_class.new.execute(processing_job_id)

        expect_api_request(:patch, "/api/v1/file_processing_jobs/#{processing_job_id}")
      end

      it 'updates file object with metadata' do
        described_class.new.execute(processing_job_id)

        expect_api_request(:patch, "/api/v1/file_objects/#{file_object_id}")
      end

      it 'marks job as completed' do
        described_class.new.execute(processing_job_id)

        expect_api_request(:post, "/api/v1/file_processing_jobs/#{processing_job_id}/complete")
      end

      it 'logs success message' do
        job = described_class.new
        capture_logs_for(job)

        job.execute(processing_job_id)

        expect_logged(:info, /completed/)
      end
    end

    context 'when processing job not found' do
      before do
        stub_backend_api_error(:get, "/api/v1/file_processing_jobs/#{processing_job_id}", status: 404, error_message: 'Not found')
      end

      it 'raises an error' do
        expect {
          described_class.new.execute(processing_job_id)
        }.to raise_error(BackendApiClient::ApiError)
      end

      it 'logs error' do
        job = described_class.new
        capture_logs_for(job)

        begin
          job.execute(processing_job_id)
        rescue StandardError
          # Expected
        end

        expect_logged(:error, /Failed to load/)
      end
    end

    context 'when file object not found' do
      before do
        stub_backend_api_success(:get, "/api/v1/file_processing_jobs/#{processing_job_id}", processing_job_data)
        stub_backend_api_success(:patch, "/api/v1/file_processing_jobs/#{processing_job_id}", { 'success' => true })
        stub_backend_api_error(:get, "/api/v1/file_objects/#{file_object_id}", status: 404, error_message: 'Not found')
      end

      it 'raises an error' do
        expect {
          described_class.new.execute(processing_job_id)
        }.to raise_error(BackendApiClient::ApiError)
      end
    end

    context 'when ffprobe extraction fails' do
      before do
        stub_backend_api_success(:get, "/api/v1/file_processing_jobs/#{processing_job_id}", processing_job_data)
        stub_backend_api_success(:get, "/api/v1/file_objects/#{file_object_id}", file_object_data)
        stub_backend_api_success(:patch, "/api/v1/file_processing_jobs/#{processing_job_id}", { 'success' => true })
        stub_backend_api_success(:get, "/api/v1/file_objects/#{file_object_id}/download", audio_content)
        stub_backend_api_success(:patch, "/api/v1/file_objects/#{file_object_id}", { 'success' => true })
        stub_backend_api_success(:post, "/api/v1/file_processing_jobs/#{processing_job_id}/complete", { 'success' => true })

        allow_any_instance_of(described_class).to receive(:`).and_return('')
        allow($?).to receive(:success?).and_return(false)
      end

      it 'continues with empty metadata' do
        result = described_class.new.execute(processing_job_id)

        expect_api_request(:post, "/api/v1/file_processing_jobs/#{processing_job_id}/complete")
      end
    end

    context 'when processing fails with exception' do
      before do
        stub_backend_api_success(:get, "/api/v1/file_processing_jobs/#{processing_job_id}", processing_job_data)
        stub_backend_api_success(:get, "/api/v1/file_objects/#{file_object_id}", file_object_data)
        stub_backend_api_success(:patch, "/api/v1/file_processing_jobs/#{processing_job_id}", { 'success' => true })
        stub_backend_api_success(:get, "/api/v1/file_objects/#{file_object_id}/download", audio_content)
        stub_backend_api_success(:post, "/api/v1/file_processing_jobs/#{processing_job_id}/fail", { 'success' => true })

        allow_any_instance_of(described_class).to receive(:extract_audio_info).and_raise(StandardError, 'Processing error')
      end

      it 'marks job as failed' do
        expect {
          described_class.new.execute(processing_job_id)
        }.to raise_error(StandardError, 'Processing error')

        expect_api_request(:post, "/api/v1/file_processing_jobs/#{processing_job_id}/fail")
      end
    end
  end

  describe 'sidekiq options' do
    it 'uses file_processing queue' do
      expect(described_class.sidekiq_options['queue']).to eq('file_processing')
    end

    it 'has retry configured' do
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end
  end

  describe '#extract_audio_info' do
    let(:job) { described_class.new }
    let(:temp_file) { Tempfile.new(['test', '.mp3']) }

    after { temp_file.close! }

    context 'with valid ffprobe output' do
      let(:ffprobe_output) do
        {
          'format' => {
            'duration' => '240.5',
            'format_name' => 'mp3',
            'tags' => {
              'title' => 'My Song',
              'artist' => 'Artist Name',
              'album' => 'Album Title',
              'genre' => 'Rock',
              'date' => '2023'
            }
          },
          'streams' => [
            {
              'codec_type' => 'audio',
              'codec_name' => 'mp3',
              'bit_rate' => '256000',
              'sample_rate' => '48000',
              'channels' => 2
            }
          ]
        }.to_json
      end

      before do
        allow(job).to receive(:`).and_return(ffprobe_output)
        allow($?).to receive(:success?).and_return(true)
      end

      it 'extracts duration' do
        result = job.send(:extract_audio_info, temp_file.path)

        expect(result[:dimensions][:duration]).to eq(240.5)
      end

      it 'extracts codec info' do
        result = job.send(:extract_audio_info, temp_file.path)

        expect(result[:dimensions][:codec]).to eq('mp3')
        expect(result[:dimensions][:bit_rate]).to eq(256_000)
        expect(result[:dimensions][:sample_rate]).to eq(48_000)
        expect(result[:dimensions][:channels]).to eq(2)
      end

      it 'extracts tags' do
        result = job.send(:extract_audio_info, temp_file.path)

        expect(result[:additional][:title]).to eq('My Song')
        expect(result[:additional][:artist]).to eq('Artist Name')
        expect(result[:additional][:album]).to eq('Album Title')
        expect(result[:additional][:genre]).to eq('Rock')
        expect(result[:additional][:year]).to eq('2023')
      end

      it 'extracts format' do
        result = job.send(:extract_audio_info, temp_file.path)

        expect(result[:additional][:format]).to eq('mp3')
      end
    end

    context 'with failed ffprobe' do
      before do
        allow(job).to receive(:`).and_return('')
        allow($?).to receive(:success?).and_return(false)
      end

      it 'returns empty metadata' do
        result = job.send(:extract_audio_info, temp_file.path)

        expect(result[:dimensions]).to eq({})
        expect(result[:additional]).to eq({})
      end
    end

    context 'with invalid JSON output' do
      before do
        allow(job).to receive(:`).and_return('invalid json')
        allow($?).to receive(:success?).and_return(true)
      end

      it 'returns empty metadata and logs warning' do
        capture_logs_for(job)

        result = job.send(:extract_audio_info, temp_file.path)

        expect(result[:dimensions]).to eq({})
        expect_logged(:warn, /Failed to extract/)
      end
    end
  end
end
