# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Compliance::DataExportJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'
  it_behaves_like 'a job with retry logic'
  it_behaves_like 'a job with logging'

  let(:export_request_id) { 'export-req-123' }
  let(:user_id) { 'user-456' }
  let(:account_id) { 'account-789' }
  let(:job_args) { export_request_id }

  let(:export_request_data) do
    {
      'id' => export_request_id,
      'user_id' => user_id,
      'account_id' => account_id,
      'status' => 'pending',
      'format' => 'json',
      'include_data_types' => %w[profile files payments],
      'exclude_data_types' => []
    }
  end

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  after do
    Sidekiq::Worker.clear_all
  end

  describe 'job configuration' do
    it 'is configured with compliance queue' do
      expect(described_class.sidekiq_options['queue'].to_s).to eq('compliance')
    end
  end

  describe '#execute' do
    let(:job) { described_class.new }
    let(:api_client) { instance_double(BackendApiClient) }

    before do
      allow(job).to receive(:api_client).and_return(api_client)
      allow(job).to receive(:log_info)
      allow(job).to receive(:log_error)
      allow(job).to receive(:log_warn)
      allow(SecureRandom).to receive(:urlsafe_base64).and_return('test_download_token')
    end

    context 'when export request is pending' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_export_requests/#{export_request_id}")
          .and_return('success' => true, 'data' => export_request_data)
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/users/#{user_id}/export/profile", {})
          .and_return('success' => true, 'data' => { 'name' => 'Test User', 'email' => 'test@example.com' })
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/accounts/#{account_id}/export/files", { user_id: user_id })
          .and_return('success' => true,
                      'data' => [{ 'id' => 'f1', 'filename' => 'a.pdf' }, { 'id' => 'f2', 'filename' => 'b.pdf' }],
                      'meta' => { 'count' => 2 })
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/accounts/#{account_id}/export/payments", {})
          .and_return('success' => true, 'data' => [{ 'amount' => 99.99, 'date' => '2024-01-01' }])
        allow(api_client).to receive(:patch).and_return(success: true)
        allow(api_client).to receive(:post).and_return(success: true)
      end

      it 'fetches the export request from API' do
        expect(api_client).to receive(:get)
          .with("/api/v1/internal/data_export_requests/#{export_request_id}")

        job.execute(export_request_id)
      end

      it 'updates status to processing' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_export_requests/#{export_request_id}",
            hash_including(status: 'processing')
          )

        job.execute(export_request_id)
      end

      it 'gathers data for requested data types' do
        expect(api_client).to receive(:get)
          .with("/api/v1/internal/users/#{user_id}/export/profile", {})
        expect(api_client).to receive(:get)
          .with("/api/v1/internal/accounts/#{account_id}/export/files", { user_id: user_id })
        expect(api_client).to receive(:get)
          .with("/api/v1/internal/accounts/#{account_id}/export/payments", {})

        job.execute(export_request_id)
      end

      it 'marks request as completed with file info' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_export_requests/#{export_request_id}",
            hash_including(
              status: 'completed',
              download_token: 'test_download_token'
            )
          )

        job.execute(export_request_id)
      end

      it 'gathers the actual string-keyed body for each data type, not nil' do
        # Regression guard for IMP-7046f6e448d6 review finding: fetch_data_type
        # used to read `api_client.get(...)[:data]` (symbol key) against a
        # string-keyed BackendApiClient body, so every gathered section was
        # nil and the job silently produced an empty GDPR export.
        expect(job).to receive(:write_export_file) do |_export_request, export_data|
          expect(export_data['profile']).to eq('name' => 'Test User', 'email' => 'test@example.com')
          expect(export_data['files'].map { |f| f['id'] }).to eq(%w[f1 f2])
          expect(export_data['payments']).to eq([{ 'amount' => 99.99, 'date' => '2024-01-01' }])
          ['/tmp/test_export.json', 512]
        end

        job.execute(export_request_id)
      end

      it 'sends notification to user' do
        expect(api_client).to receive(:post)
          .with(
            '/api/v1/internal/notifications/send',
            hash_including(
              user_id: user_id,
              type: 'data_export_ready'
            )
          )

        job.execute(export_request_id)
      end
      # IMP-8aab38f3ad62 — the archive and the log must say what the export
      # actually holds: per-type counts, and a named warning for anything
      # absent, instead of "completed successfully" either way.
      it 'records a manifest with the real per-type counts in the archive' do
        expect(job).to receive(:write_export_file) do |_export_request, export_data|
          manifest = export_data[:export_info][:manifest]
          expect(manifest['files']).to eq(status: 'exported', count: 2)
          expect(manifest['payments']).to eq(status: 'exported', count: 1)
          expect(manifest['profile']).to eq(status: 'exported', count: 1)
          ['/tmp/test_export.json', 512]
        end

        job.execute(export_request_id)
      end

      it 'logs the per-type counts on completion' do
        expect(job).to receive(:log_info).with(/completed: profile=1 files=2 payments=1/)
        expect(job).not_to receive(:log_warn)

        job.execute(export_request_id)
      end
    end

    context 'when a section is absent from the archive' do
      let(:mixed_request) do
        export_request_data.merge('include_data_types' => %w[files invoices activity])
      end

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_export_requests/#{export_request_id}")
          .and_return('success' => true, 'data' => mixed_request)
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/accounts/#{account_id}/export/files", { user_id: user_id })
          .and_return('success' => true, 'data' => [{ 'id' => 'f1' }], 'meta' => { 'count' => 1 })
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/accounts/#{account_id}/export/invoices", {})
          .and_return('success' => true, 'data' => [],
                      'meta' => { 'available' => false, 'reason' => 'no_export_provider_installed' })
        allow(api_client).to receive(:patch).and_return(success: true)
        allow(api_client).to receive(:post).and_return(success: true)
      end

      it 'marks an unavailable provider and a withdrawn type in the manifest, not as empty exports' do
        expect(job).to receive(:write_export_file) do |_export_request, export_data|
          manifest = export_data[:export_info][:manifest]
          expect(manifest['files']).to eq(status: 'exported', count: 1)
          expect(manifest['invoices']).to eq(status: 'unavailable', reason: 'no_export_provider_installed')
          expect(manifest['activity']).to eq(status: 'not_exportable')
          ['/tmp/test_export.json', 512]
        end

        job.execute(export_request_id)
      end

      it 'never requests the withdrawn activity endpoint' do
        expect(api_client).not_to receive(:get).with("/api/v1/internal/users/#{user_id}/export/activity", anything)
        expect(api_client).not_to receive(:get).with("/api/v1/internal/users/#{user_id}/export/activity")

        job.execute(export_request_id)
      end

      it 'names every absent section in a warning' do
        expect(job).to receive(:log_warn).with(/omits invoices \(unavailable\), activity \(not_exportable\)/)

        job.execute(export_request_id)
      end
    end

    context 'when export request is not pending' do
      let(:completed_request) { export_request_data.merge('status' => 'completed') }

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_export_requests/#{export_request_id}")
          .and_return('success' => true, 'data' => completed_request)
      end

      it 'skips processing' do
        expect(api_client).not_to receive(:patch)
        expect(job).to receive(:log_info).with(/not pending/)

        job.execute(export_request_id)
      end
    end

    context 'when API request fails' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_export_requests/#{export_request_id}")
          .and_return('success' => false, 'error' => 'Not found')
      end

      it 'raises an error' do
        expect { job.execute(export_request_id) }
          .to raise_error(/Failed to fetch export request/)
      end
    end

    context 'when data gathering fails' do
      # Use a simpler approach: test with a single data type that will fail
      let(:single_type_request) do
        export_request_data.merge('include_data_types' => ['profile'])
      end

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_export_requests/#{export_request_id}")
          .and_return('success' => true, 'data' => single_type_request)
        allow(api_client).to receive(:patch).and_return(success: true)
        allow(api_client).to receive(:post).and_return(success: true)
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/users/#{user_id}/export/profile", {})
          .and_raise(StandardError, 'API error')
      end

      it 'logs warning and continues with error data' do
        expect(job).to receive(:log_warn).with(/Failed to fetch profile/)

        job.execute(export_request_id)
      end
    end

    context 'when export processing fails' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_export_requests/#{export_request_id}")
          .and_return('success' => true, 'data' => export_request_data)
        allow(api_client).to receive(:patch).and_return(success: true)
        allow(job).to receive(:gather_export_data).and_return({ test: 'data' })
        allow(job).to receive(:write_export_file).and_raise(StandardError, 'Write failed')
      end

      it 'marks request as failed' do
        # First patch is status: processing, second should be status: failed
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_export_requests/#{export_request_id}",
            hash_including(status: 'failed', error_message: 'Write failed')
          )

        expect { job.execute(export_request_id) }.to raise_error(StandardError, 'Write failed')
      end
    end

    context 'with different export formats' do
      let(:csv_request) { export_request_data.merge('format' => 'csv', 'include_data_types' => ['profile']) }

      before do
        # Stub API responses - order matters, specific before general
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_export_requests/#{export_request_id}")
          .and_return('success' => true, 'data' => csv_request)
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/users/#{user_id}/export/profile", {})
          .and_return('success' => true, 'data' => { 'name' => 'Test', 'email' => 'test@example.com' })
        allow(api_client).to receive(:patch).and_return(success: true)
        allow(api_client).to receive(:post).and_return(success: true)
        # Stub file writing to avoid dependency on zip gem
        allow(job).to receive(:write_export_file).and_return(['/tmp/test_export.csv', 1024])
      end

      it 'generates export in CSV format' do
        # Status: processing first, then completed
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_export_requests/#{export_request_id}",
            hash_including(status: 'processing')
          ).ordered
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_export_requests/#{export_request_id}",
            hash_including(status: 'completed')
          ).ordered

        job.execute(export_request_id)
      end
    end

    context 'with excluded data types' do
      let(:request_with_exclusions) do
        export_request_data.merge(
          'include_data_types' => %w[profile files payments],
          'exclude_data_types' => ['payments']
        )
      end

      before do
        # Order matters: RSpec resolves to the LAST matching stub, so the
        # generic `anything` catch-all must be registered first or it
        # shadows the specific data_export_requests stub below (pre-existing
        # ordering issue exposed once the two stub shapes stopped
        # coincidentally agreeing — see IMP-7046f6e448d6).
        allow(api_client).to receive(:get)
          .with(anything)
          .and_return('success' => true, 'data' => {})
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_export_requests/#{export_request_id}")
          .and_return('success' => true, 'data' => request_with_exclusions)
        allow(api_client).to receive(:patch).and_return(success: true)
        allow(api_client).to receive(:post).and_return(success: true)
      end

      it 'excludes specified data types' do
        expect(api_client).to receive(:get)
          .with("/api/v1/internal/users/#{user_id}/export/profile", {})
          .and_return('success' => true, 'data' => { 'name' => 'Test User' })
        expect(api_client).not_to receive(:get)
          .with("/api/v1/internal/accounts/#{account_id}/export/payments", {})

        job.execute(export_request_id)
      end
    end
  end
end
