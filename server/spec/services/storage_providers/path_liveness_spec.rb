# frozen_string_literal: true

require 'rails_helper'

# IMP-593f2b533823 — write_liveness_marker! wrote the nonce file and then did
# a whole-hash update_columns with no lock, so two concurrent initializes could
# leave the disk nonce and the row nonce different (every blob then :dead).
RSpec.describe StorageProviders::PathLiveness, type: :service do
  let(:account) { create(:account) }
  let(:root) { Rails.root.join('tmp', 'test_storage', "liveness-#{account.id}").to_s }
  let(:storage_config) do
    create(:file_storage, account: account, provider_type: 'local',
                          configuration: { 'root_path' => root })
  end

  after { FileUtils.rm_rf(root) }

  it 'merges only the liveness key, keeping other metadata' do
    FileUtils.mkdir_p(root)
    storage_config.update_columns(metadata: { 'keep' => 'me' })
    provider = StorageProviders::LocalStorage.new(storage_config)

    nonce = provider.write_liveness_marker!

    row = FileManagement::Storage.find(storage_config.id)
    expect(row.metadata).to eq('keep' => 'me', 'liveness_marker' => nonce)
    expect(storage_config.metadata['liveness_marker']).to eq(nonce)
  end

  it 'reads the row FOR UPDATE before it writes the marker file, and reflects the merged metadata in memory' do
    FileUtils.mkdir_p(root)
    storage_config.update_columns(metadata: { 'keep' => 'me' })
    provider = StorageProviders::LocalStorage.new(storage_config)
    # Another writer adds a key behind this instance's back.
    FileManagement::Storage.where(id: storage_config.id).update_all("metadata = metadata || '{\"other\":1}'::jsonb")

    events = []
    sub = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      events << :lock if payload[:sql] =~ /FROM "file_storages".*FOR UPDATE/m
    end
    allow(File).to receive(:write).and_wrap_original do |orig, *args, **kw|
      events << :file_write if args.first.to_s.end_with?(StorageProviders::Base::LIVENESS_MARKER)
      orig.call(*args, **kw)
    end
    begin
      provider.write_liveness_marker!
    ensure
      ActiveSupport::Notifications.unsubscribe(sub)
    end

    expect(events.first(2)).to eq(%i[lock file_write])
    expect(storage_config.metadata).to include('keep' => 'me', 'other' => 1)
  end
end

# The threads must hold REAL separate connections, so the rows are committed and
# this group opts out of the wrapping test transaction (a `truncation: true` tag
# set in a before hook comes too late to do that), cleaning up after itself.
RSpec.describe StorageProviders::PathLiveness, 'with concurrent initializes', type: :service do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let(:root) { Rails.root.join('tmp', 'test_storage', "liveness-conc-#{account.id}").to_s }
  let!(:storage_config) do
    create(:file_storage, account: account, provider_type: 'local', configuration: { 'root_path' => root })
  end

  after do
    FileUtils.rm_rf(root)
    FileManagement::Storage.where(id: storage_config.id).delete_all
    Account.where(id: account.id).delete_all
  end

  it 'leaves the store :live when two initializes write the marker concurrently' do
    FileUtils.mkdir_p(root)
    providers = Array.new(2) do
      StorageProviders::LocalStorage.new(FileManagement::Storage.find(storage_config.id))
    end

    # The first writer stalls after its file write, so without serialisation the
    # second writer's file AND row writes land before the first writer's row
    # write: disk and row then disagree.
    first = Concurrent::AtomicBoolean.new(true)
    allow(File).to receive(:write).and_wrap_original do |orig, *args, **kw|
      result = orig.call(*args, **kw)
      sleep 0.3 if args.first.to_s.end_with?(StorageProviders::Base::LIVENESS_MARKER) && first.make_false
      result
    end

    threads = providers.each_with_index.map do |p, i|
      Thread.new do
        sleep 0.05 * i
        ActiveRecord::Base.connection_pool.with_connection { p.write_liveness_marker! }
      end
    end
    threads.each(&:join)

    fresh = StorageProviders::LocalStorage.new(FileManagement::Storage.find(storage_config.id))
    expect(fresh.store_liveness).to eq(:live)
  end
end
