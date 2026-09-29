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

  # IMP-0310a1351dab BLOCKER: Api::V1::Internal::DataExportRequestsController
  # nests the record under `data.data_export_request` (see
  # DataExportRequestsController#show -> serialize_request, and the matching
  # producer-side contract spec in
  # server/spec/requests/api/v1/internal/data_export_requests_spec.rb). Every
  # `'data' => export_request_data` stub in this file used to be FLAT — the
  # same shape the real job had drifted to reading — so this suite exercised
  # a shape the actual endpoint never returns, and could not have caught the
  # job's own bug. Wrapped via this helper so every stub in the file stays in
  # sync with the one real shape.
  def export_response(data)
    { 'success' => true, 'data' => { 'data_export_request' => data } }
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
    end

    context 'when export request is pending' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_export_requests/#{export_request_id}")
          .and_return(export_response(export_request_data))
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
        # IMP-0310a1351dab: was `success: true` (symbol key) — BackendApiClient
        # returns a STRING-keyed body verbatim, so this job's own
        # `unless start_response['success']` (added by this fix) would have
        # read nil against a symbol-keyed stub and raised on every example in
        # this file, for a reason having nothing to do with what each example
        # actually tests. See account_termination_job_spec.rb's own header
        # note on the identical class of defect.
        allow(api_client).to receive(:patch).and_return('success' => true)
        allow(api_client).to receive(:post).and_return('success' => true)
      end

      it 'fetches the export request from API' do
        expect(api_client).to receive(:get)
          .with("/api/v1/internal/data_export_requests/#{export_request_id}")

        job.execute(export_request_id)
      end

      # IMP-0310a1351dab: was `hash_including(status: 'processing')` — the
      # controller dispatches on `action_type`, not a bare `status:` payload
      # (DataExportRequestsController#update); a bare status write falls
      # through to the generic branch, which only permits `metadata:`.
      it 'starts the export via action_type: start' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_export_requests/#{export_request_id}",
            hash_including(action_type: 'start')
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

      # IMP-0310a1351dab: was `hash_including(status: 'completed',
      # download_token: 'test_download_token')` — action_type: 'complete' is
      # the real dispatch, and complete_export generates its OWN
      # download_token server-side (ignoring any the caller sends), so this
      # job no longer sends one at all.
      it 'marks request as completed with file info via action_type: complete' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_export_requests/#{export_request_id}",
            hash_including(action_type: 'complete', file_path: anything, file_size_bytes: anything)
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
          .and_return(export_response(mixed_request))
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/accounts/#{account_id}/export/files", { user_id: user_id })
          .and_return('success' => true, 'data' => [{ 'id' => 'f1' }], 'meta' => { 'count' => 1 })
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/accounts/#{account_id}/export/invoices", {})
          .and_return('success' => true, 'data' => [],
                      'meta' => { 'available' => false, 'reason' => 'no_export_provider_installed' })
        allow(api_client).to receive(:patch).and_return('success' => true)
        allow(api_client).to receive(:post).and_return('success' => true)
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
          .and_return(export_response(completed_request))
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

    # IMP-0310a1351dab: the fetch succeeding but the record missing at the
    # expected nested path (a malformed/regressed response shape) is a
    # DIFFERENT failure than a non-2xx fetch — must not silently proceed with
    # a nil export_request (NoMethodError on `export_request['status']` deep
    # inside gather_export_data, several stack frames away from the real
    # cause) nor silently skip as if merely "not pending".
    context 'when the response is missing the nested data_export_request' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_export_requests/#{export_request_id}")
          .and_return('success' => true, 'data' => {})
      end

      it 'raises a clear error rather than proceeding with a nil export request' do
        expect { job.execute(export_request_id) }
          .to raise_error(/Malformed response fetching export request/)
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
          .and_return(export_response(single_type_request))
        allow(api_client).to receive(:patch).and_return('success' => true)
        allow(api_client).to receive(:post).and_return('success' => true)
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
          .and_return(export_response(export_request_data))
        allow(api_client).to receive(:patch).and_return('success' => true)
        allow(job).to receive(:gather_export_data).and_return({ test: 'data' })
        allow(job).to receive(:write_export_file).and_raise(StandardError, 'Write failed')
      end

      # IMP-0310a1351dab: was `hash_including(status: 'failed', ...)`.
      it 'marks request as failed via action_type: fail' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_export_requests/#{export_request_id}",
            hash_including(action_type: 'fail', error_message: 'Write failed')
          )

        expect { job.execute(export_request_id) }.to raise_error(StandardError, 'Write failed')
      end
    end

    # The archive is the subject's full personal-data export, written to this
    # host's tmp directory. A run that fails after writing it leaves it on no
    # row, so nothing but the job itself will ever remove it.
    context 'when the run fails after the archive was written' do
      let(:export_root) { Dir.mktmpdir('powernode-exports').tap { |d| File.chmod(0o700, d) } }
      let(:archive_path) { File.join(export_root, "export_#{SecureRandom.hex(4)}.json") }

      before do
        allow(described_class).to receive(:export_dir).and_return(export_root)
        File.write(archive_path, '{}')
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_export_requests/#{export_request_id}")
          .and_return(export_response(export_request_data))
        allow(job).to receive(:gather_export_data).and_return({ test: 'data' })
        allow(job).to receive(:write_export_file).and_return([ archive_path, 2 ])
        allow(api_client).to receive(:patch).and_return('success' => true)
        allow(api_client).to receive(:patch)
          .with(anything, hash_including(action_type: 'complete'))
          .and_return('success' => false, 'error' => 'refused')
      end

      after { FileUtils.rm_rf(export_root) }

      it 'removes the orphaned archive and still marks the request failed' do
        expect(api_client).to receive(:patch)
          .with(anything, hash_including(action_type: 'fail'))

        expect { job.execute(export_request_id) }.to raise_error(/Failed to complete export request/)

        expect(File.exist?(archive_path)).to be false
      end
    end

    describe '.discard_archive' do
      let(:dir) { Dir.mktmpdir('powernode-exports').tap { |d| File.chmod(0o700, d) } }
      let(:path) { File.join(dir, "export_#{SecureRandom.hex(4)}.json") }
      let(:elsewhere) { Dir.mktmpdir('not-the-exports') }

      before { allow(described_class).to receive(:export_dir).and_return(dir) }

      after do
        FileUtils.rm_rf(dir)
        FileUtils.rm_rf(elsewhere)
      end

      it 'removes an archive inside the export directory' do
        File.write(path, '{}')

        expect(described_class.discard_archive(path)).to eq(:removed)
        expect(File.exist?(path)).to be false
      end

      it 'removes an archive in a real subdirectory of the export directory' do
        FileUtils.mkdir_p(File.join(dir, 'sub'))
        nested = File.join(dir, 'sub', 'a.json')
        File.write(nested, '{}')

        expect(described_class.discard_archive(nested)).to eq(:removed)
      end

      it 'answers :missing for a blank path, an archive that is already gone, or an export directory that does not exist' do
        expect(described_class.discard_archive(nil)).to eq(:missing)
        expect(described_class.discard_archive('')).to eq(:missing)
        expect(described_class.discard_archive(path)).to eq(:missing)
        allow(described_class).to receive(:export_dir).and_return(File.join(dir, 'absent'))
        expect(described_class.discard_archive(path)).to eq(:missing)
      end

      it 'never touches a path outside the export directory, including a traversal out of it' do
        outside = File.join(elsewhere, 'victim.json')
        File.write(outside, '{}')

        expect(described_class.discard_archive(outside)).to eq(:outside_export_dir)
        expect(described_class.discard_archive(File.join(dir, '..', File.basename(elsewhere), 'victim.json'))).to eq(:outside_export_dir)
        expect(File.exist?(outside)).to be true
      end

      it 'does not treat a sibling directory sharing the prefix as inside' do
        sibling = "#{dir}_other"
        FileUtils.mkdir_p(sibling)
        file = File.join(sibling, 'x.json')
        File.write(file, '{}')

        expect(described_class.discard_archive(file)).to eq(:outside_export_dir)
        expect(File.exist?(file)).to be true
      ensure
        FileUtils.rm_rf(sibling)
      end

      # expand_path does not resolve a symlink: a linked subdirectory inside the
      # export directory would otherwise carry the delete anywhere on the host.
      it 'refuses a path that goes through a symlinked subdirectory pointing outside' do
        victim = File.join(elsewhere, 'victim.json')
        File.write(victim, '{}')
        File.symlink(elsewhere, File.join(dir, 'sub'))

        expect(described_class.discard_archive(File.join(dir, 'sub', 'victim.json'))).to eq(:outside_export_dir)
        expect(File.exist?(victim)).to be true
      end

      it 'refuses an archive that is itself a symlink, and leaves both the link and its target' do
        victim = File.join(elsewhere, 'victim.json')
        File.write(victim, '{}')
        File.symlink(victim, path)

        expect(described_class.discard_archive(path)).to eq(:symlink)
        expect(File.exist?(victim)).to be true
        expect(File.symlink?(path)).to be true
      end

      it 'deletes nothing when the export directory is itself a symlink' do
        real = Dir.mktmpdir('real-exports').tap { |d| File.chmod(0o700, d) }
        link = File.join(elsewhere, 'exports-link')
        File.symlink(real, link)
        file = File.join(real, 'a.json')
        File.write(file, '{}')
        allow(described_class).to receive(:export_dir).and_return(link)

        expect(described_class.discard_archive(File.join(link, 'a.json'))).to eq(:unsafe_export_dir)
        expect(File.exist?(file)).to be true
      ensure
        FileUtils.rm_rf(real)
      end

      # A shared tmp lets another local user pre-create the directory, or leave
      # it writable, and the worker may be root.
      it 'deletes nothing when the export directory is owned by another uid' do
        File.write(path, '{}')
        allow(Process).to receive(:euid).and_return(File.stat(dir).uid + 1)

        expect(described_class.discard_archive(path)).to eq(:unsafe_export_dir)
        expect(File.exist?(path)).to be true
      end

      [ 0o770, 0o707, 0o777, 0o720 ].each do |mode|
        it "deletes nothing when the export directory mode is #{format('%04o', mode)} (group or other writable)" do
          File.write(path, '{}')
          File.chmod(mode, dir)

          expect(described_class.discard_archive(path)).to eq(:unsafe_export_dir)
          expect(File.exist?(path)).to be true
        end
      end

      it 'accepts an owner-only directory with a group/other read bit' do
        File.write(path, '{}')
        File.chmod(0o750, dir)

        expect(described_class.discard_archive(path)).to eq(:removed)
      end

      it 'answers :failed rather than raising when the file cannot be removed' do
        File.write(path, '{}')
        allow(File).to receive(:delete).and_raise(Errno::EACCES)

        expect(described_class.discard_archive(path)).to eq(:failed)
      end
    end

    describe '.export_dir creation' do
      it 'writes archives into a directory created owner-only' do
        root = File.join(Dir.mktmpdir('exports-parent'), 'powernode_exports')
        allow(described_class).to receive(:export_dir).and_return(root)
        job = described_class.new

        job.send(:write_export_file, { 'user_id' => 'u1', 'format' => 'json' }, { a: 1 })

        expect(File.stat(root).mode & 0o077).to eq(0)
        expect(described_class.trusted_export_dir?(root)).to be true
      ensure
        FileUtils.rm_rf(File.dirname(root))
      end
    end

    context 'with different export formats' do
      let(:csv_request) { export_request_data.merge('format' => 'csv', 'include_data_types' => ['profile']) }

      before do
        # Stub API responses - order matters, specific before general
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_export_requests/#{export_request_id}")
          .and_return(export_response(csv_request))
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/users/#{user_id}/export/profile", {})
          .and_return('success' => true, 'data' => { 'name' => 'Test', 'email' => 'test@example.com' })
        allow(api_client).to receive(:patch).and_return('success' => true)
        allow(api_client).to receive(:post).and_return('success' => true)
        # Stub file writing to avoid dependency on zip gem
        allow(job).to receive(:write_export_file).and_return(['/tmp/test_export.csv', 1024])
      end

      it 'generates export in CSV format' do
        # start, then complete
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_export_requests/#{export_request_id}",
            hash_including(action_type: 'start')
          ).ordered
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_export_requests/#{export_request_id}",
            hash_including(action_type: 'complete')
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
          .and_return(export_response(request_with_exclusions))
        allow(api_client).to receive(:patch).and_return('success' => true)
        allow(api_client).to receive(:post).and_return('success' => true)
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
