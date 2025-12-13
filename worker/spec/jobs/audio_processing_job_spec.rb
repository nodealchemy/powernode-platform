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
    let(:mock_api_client) { instance_double(BackendApiClient) }

    before do
      allow_any_instance_of(described_class).to receive(:api_client).and_return(mock_api_client)
    end

    context 'when audio processing succeeds' do
      let(:temp_file) { Tempfile.new(['audio', '.mp3']) }

      before do
        # Mock API client methods
        allow(mock_api_client).to receive(:get_file_processing_job).with(processing_job_id).and_return(processing_job_data)
        allow(mock_api_client).to receive(:get_file_object).with(file_object_id).and_return(file_object_data)
        allow(mock_api_client).to receive(:update_file_processing_job).and_return({ 'success' => true })
        allow(mock_api_client).to receive(:download_file_content).with(file_object_id).and_return(audio_content)
        allow(mock_api_client).to receive(:update_file_object).and_return({ 'success' => true })
        allow(mock_api_client).to receive(:complete_file_processing_job).and_return({ 'success' => true })

        # Mock temp file download
        allow_any_instance_of(described_class).to receive(:download_file_content).and_return(temp_file)
        allow_any_instance_of(described_class).to receive(:cleanup_temp_file)

        # Mock ffprobe command - use block form to run a successful command that sets $?
        allow_any_instance_of(described_class).to receive(:`) do |_instance, _cmd|
          `true` # Run a simple successful command to set $? to success
          ffprobe_json_output
        end
      end

      after do
        temp_file.close
        temp_file.unlink rescue nil
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

        expect(mock_api_client).to have_received(:get_file_processing_job).with(processing_job_id)
      end

      it 'loads the file object' do
        described_class.new.execute(processing_job_id)

        expect(mock_api_client).to have_received(:get_file_object).with(file_object_id)
      end

      it 'updates job status to processing' do
        described_class.new.execute(processing_job_id)

        expect(mock_api_client).to have_received(:update_file_processing_job).with(processing_job_id, hash_including(status: 'processing'))
      end

      it 'updates file object with metadata' do
        described_class.new.execute(processing_job_id)

        # Called twice: once for metadata update, once for processing_status update
        expect(mock_api_client).to have_received(:update_file_object).with(file_object_id, anything).at_least(:once)
      end

      it 'marks job as completed' do
        described_class.new.execute(processing_job_id)

        expect(mock_api_client).to have_received(:complete_file_processing_job).with(processing_job_id, anything)
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
        allow(mock_api_client).to receive(:get_file_processing_job).and_raise(
          BackendApiClient::ApiError.new('Not found', 404)
        )
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
        allow(mock_api_client).to receive(:get_file_processing_job).with(processing_job_id).and_return(processing_job_data)
        allow(mock_api_client).to receive(:update_file_processing_job).and_return({ 'success' => true })
        allow(mock_api_client).to receive(:get_file_object).and_raise(
          BackendApiClient::ApiError.new('Not found', 404)
        )
      end

      it 'raises an error' do
        expect {
          described_class.new.execute(processing_job_id)
        }.to raise_error(BackendApiClient::ApiError)
      end
    end

    context 'when ffprobe extraction fails' do
      let(:temp_file) { Tempfile.new(['audio', '.mp3']) }

      before do
        allow(mock_api_client).to receive(:get_file_processing_job).with(processing_job_id).and_return(processing_job_data)
        allow(mock_api_client).to receive(:get_file_object).with(file_object_id).and_return(file_object_data)
        allow(mock_api_client).to receive(:update_file_processing_job).and_return({ 'success' => true })
        allow(mock_api_client).to receive(:download_file_content).with(file_object_id).and_return(audio_content)
        allow(mock_api_client).to receive(:update_file_object).and_return({ 'success' => true })
        allow(mock_api_client).to receive(:complete_file_processing_job).and_return({ 'success' => true })

        # Mock temp file download
        allow_any_instance_of(described_class).to receive(:download_file_content).and_return(temp_file)
        allow_any_instance_of(described_class).to receive(:cleanup_temp_file)

        # Mock ffprobe command - use block form to run a failing command that sets $?
        allow_any_instance_of(described_class).to receive(:`) do |_instance, _cmd|
          `false` # Run a failing command to set $? to failure
          ''
        end
      end

      after do
        temp_file.close
        temp_file.unlink rescue nil
      end

      it 'continues with empty metadata' do
        described_class.new.execute(processing_job_id)

        expect(mock_api_client).to have_received(:complete_file_processing_job).with(processing_job_id, anything)
      end
    end

    context 'when processing fails with exception' do
      let(:temp_file) { Tempfile.new(['audio', '.mp3']) }

      before do
        allow(mock_api_client).to receive(:get_file_processing_job).with(processing_job_id).and_return(processing_job_data)
        allow(mock_api_client).to receive(:get_file_object).with(file_object_id).and_return(file_object_data)
        allow(mock_api_client).to receive(:update_file_processing_job).and_return({ 'success' => true })
        allow(mock_api_client).to receive(:download_file_content).with(file_object_id).and_return(audio_content)
        allow(mock_api_client).to receive(:fail_file_processing_job).and_return({ 'success' => true })

        # Mock temp file download
        allow_any_instance_of(described_class).to receive(:download_file_content).and_return(temp_file)
        allow_any_instance_of(described_class).to receive(:cleanup_temp_file)

        allow_any_instance_of(described_class).to receive(:extract_audio_info).and_raise(StandardError, 'Processing error')
      end

      after do
        temp_file.close
        temp_file.unlink rescue nil
      end

      it 'marks job as failed' do
        expect {
          described_class.new.execute(processing_job_id)
        }.to raise_error(StandardError, 'Processing error')

        expect(mock_api_client).to have_received(:fail_file_processing_job).with(processing_job_id, 'Processing error', anything)
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
        allow(job).to receive(:`) do |_cmd|
          `true` # Set $? to success
          ffprobe_output
        end
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
        allow(job).to receive(:`) do |_cmd|
          `false` # Set $? to failure
          ''
        end
      end

      it 'returns empty metadata' do
        result = job.send(:extract_audio_info, temp_file.path)

        expect(result[:dimensions]).to eq({})
        expect(result[:additional]).to eq({})
      end
    end

    context 'with invalid JSON output' do
      before do
        allow(job).to receive(:`) do |_cmd|
          `true` # Set $? to success
          'invalid json'
        end
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
