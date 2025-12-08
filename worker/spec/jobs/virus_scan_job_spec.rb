# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VirusScanJob do
  let(:processing_job_id) { SecureRandom.uuid }
  let(:file_object_id) { SecureRandom.uuid }
  let(:mock_api_client) { instance_double(BackendApiClient) }
  let(:mock_clamav_service) { instance_double(ClamavService) }

  let(:job_data) do
    {
      'id' => processing_job_id,
      'file_object_id' => file_object_id,
      'status' => 'pending'
    }
  end

  let(:file_data) do
    {
      'id' => file_object_id,
      'name' => 'test_document.pdf',
      'content_type' => 'application/pdf',
      'size' => 1024
    }
  end

  before do
    mock_powernode_worker_config
    allow_any_instance_of(described_class).to receive(:api_client).and_return(mock_api_client)
    allow(ClamavService).to receive(:new).and_return(mock_clamav_service)

    # Default API responses
    allow(mock_api_client).to receive(:get_file_processing_job).and_return(job_data)
    allow(mock_api_client).to receive(:get_file_object).and_return(file_data)
    allow(mock_api_client).to receive(:update_file_processing_job)
    allow(mock_api_client).to receive(:complete_file_processing_job)
    allow(mock_api_client).to receive(:fail_file_processing_job)
    allow(mock_api_client).to receive(:update_file_object)
    allow(mock_api_client).to receive(:quarantine_file)
    allow(mock_api_client).to receive(:post)

    # Default file download
    allow(mock_api_client).to receive(:download_file_content).and_return('file content')
  end

  describe '#execute' do
    context 'when ClamAV is available' do
      before do
        allow(mock_clamav_service).to receive(:available?).and_return(true)
        allow(mock_clamav_service).to receive(:version).and_return({ version: 'ClamAV 0.103.6' })
      end

      context 'with clean file' do
        before do
          allow(mock_clamav_service).to receive(:scan_stream).and_return({
            clean: true,
            virus_name: nil,
            scanned_at: Time.now.iso8601
          })
        end

        it 'completes job with clean status' do
          expect(mock_api_client).to receive(:complete_file_processing_job).with(
            processing_job_id,
            hash_including(status: 'clean')
          )

          described_class.new.execute(processing_job_id)
        end

        it 'updates file scan status to clean' do
          expect(mock_api_client).to receive(:update_file_object).with(
            file_object_id,
            hash_including(scan_status: 'clean')
          )

          described_class.new.execute(processing_job_id)
        end
      end

      context 'with infected file' do
        before do
          allow(mock_clamav_service).to receive(:scan_stream).and_return({
            clean: false,
            virus_name: 'Eicar-Test-Signature',
            scanned_at: Time.now.iso8601
          })
        end

        it 'completes job with infected status' do
          expect(mock_api_client).to receive(:complete_file_processing_job).with(
            processing_job_id,
            hash_including(status: 'infected', virus_name: 'Eicar-Test-Signature')
          )

          described_class.new.execute(processing_job_id)
        end

        it 'quarantines the file' do
          expect(mock_api_client).to receive(:quarantine_file).with(
            file_object_id,
            hash_including(reason: 'virus_detected', virus_name: 'Eicar-Test-Signature')
          )

          described_class.new.execute(processing_job_id)
        end

        it 'updates file scan status to infected' do
          expect(mock_api_client).to receive(:update_file_object).with(
            file_object_id,
            hash_including(scan_status: 'infected')
          )

          described_class.new.execute(processing_job_id)
        end

        it 'sends security alert notification' do
          expect(mock_api_client).to receive(:post).with(
            '/api/v1/notifications/security_alert',
            hash_including(type: 'infected_file_detected', severity: 'high')
          )

          described_class.new.execute(processing_job_id)
        end
      end

      context 'with scan error' do
        before do
          allow(mock_clamav_service).to receive(:scan_stream)
            .and_raise(ClamavService::ScanError.new('Scan failed'))
        end

        it 'fails the processing job' do
          expect(mock_api_client).to receive(:fail_file_processing_job).with(
            processing_job_id,
            'Scan failed',
            hash_including(recoverable: true)
          )

          expect { described_class.new.execute(processing_job_id) }
            .to raise_error(ClamavService::ScanError)
        end
      end
    end

    context 'when ClamAV is unavailable' do
      before do
        allow(mock_clamav_service).to receive(:available?).and_return(false)
      end

      it 'completes job with skipped status' do
        expect(mock_api_client).to receive(:complete_file_processing_job).with(
          processing_job_id,
          hash_including(status: 'skipped', reason: 'scanner_unavailable')
        )

        described_class.new.execute(processing_job_id)
      end

      it 'updates file scan status to skipped' do
        expect(mock_api_client).to receive(:update_file_object).with(
          file_object_id,
          hash_including(scan_status: 'skipped')
        )

        described_class.new.execute(processing_job_id)
      end
    end
  end
end
