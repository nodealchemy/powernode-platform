# frozen_string_literal: true

require 'rails_helper'

RSpec.describe System::ModuleVersionService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:node_module) { create(:system_node_module, account: account) }
  let(:service) { described_class.new(node_module, current_user: user) }

  describe '#initialize' do
    it 'sets node_module and current_user' do
      expect(service.node_module).to eq(node_module)
      expect(service.current_user).to eq(user)
    end
  end

  describe '#create_version' do
    it 'creates a new version' do
      expect {
        service.create_version(changelog: 'Test version')
      }.to change { node_module.versions.count }.by(1)
    end

    it 'captures module state in version' do
      node_module.update!(
        mask: { 'test' => 'mask' },
        file_spec: { 'file' => 'spec' },
        package_spec: { 'package' => 'spec' },
        config: { 'config' => 'value' }
      )

      version = service.create_version(changelog: 'Captured')

      expect(version.mask).to eq({ 'test' => 'mask' })
      expect(version.file_spec).to eq({ 'file' => 'spec' })
      expect(version.package_spec).to eq({ 'package' => 'spec' })
      expect(version.config).to eq({ 'config' => 'value' })
    end

    it 'captures data file information' do
      node_module.update!(
        data_file_name: 'module.tar.gz',
        data_checksum: 'abc123',
        data_file_size: 1024
      )

      version = service.create_version

      expect(version.data_file_name).to eq('module.tar.gz')
      expect(version.data_checksum).to eq('abc123')
      expect(version.data_file_size).to eq(1024)
    end

    it 'updates current_version on module' do
      version = service.create_version

      expect(node_module.reload.current_version).to eq(version)
      expect(node_module.current_version_number).to eq(version.version_number)
    end

    it 'sets created_by from current_user' do
      version = service.create_version

      expect(version.created_by).to eq(user)
    end

    it 'allows explicit user override' do
      other_user = create(:user, account: account)
      version = service.create_version(user: other_user)

      expect(version.created_by).to eq(other_user)
    end

    it 'raises LockError when module is locked' do
      node_module.update!(lock_spec: true)

      expect {
        service.create_version
      }.to raise_error(described_class::LockError, /locked/)
    end
  end

  describe '#create_initial_version' do
    it 'creates initial version for new module' do
      expect {
        service.create_initial_version
      }.to change { node_module.versions.count }.by(1)
    end

    it 'sets changelog to Initial version' do
      version = service.create_initial_version

      expect(version.changelog).to eq('Initial version')
    end

    it 'does nothing if versions already exist' do
      service.create_version(changelog: 'Existing')

      expect {
        service.create_initial_version
      }.not_to change { node_module.versions.count }
    end
  end

  describe '#rollback_to' do
    let!(:v1) do
      node_module.update!(mask: { 'v1' => true }, file_spec: { 'spec1' => true })
      service.create_version(changelog: 'Version 1')
    end
    let!(:v2) do
      node_module.update!(mask: { 'v2' => true }, file_spec: { 'spec2' => true })
      service.create_version(changelog: 'Version 2')
    end

    it 'restores module state from target version' do
      node_module.update!(mask: { 'v3' => true })
      service.rollback_to(v1)

      node_module.reload
      expect(node_module.mask).to eq({ 'v1' => true })
      expect(node_module.file_spec).to eq({ 'spec1' => true })
    end

    it 'creates a new version recording the rollback' do
      expect {
        service.rollback_to(v1)
      }.to change { node_module.versions.count }.by(1)

      latest = node_module.latest_version
      expect(latest.changelog).to include('Rollback')
    end

    it 'allows custom changelog' do
      service.rollback_to(v1, changelog: 'Emergency rollback due to bug')

      latest = node_module.latest_version
      expect(latest.changelog).to eq('Emergency rollback due to bug')
    end

    it 'raises LockError when module is locked' do
      node_module.update!(lock_spec: true)

      expect {
        service.rollback_to(v1)
      }.to raise_error(described_class::LockError)
    end

    it 'raises RollbackError for version from different module' do
      other_module = create(:system_node_module, account: account)
      other_version = create(:system_node_module_version, node_module: other_module)

      expect {
        service.rollback_to(other_version)
      }.to raise_error(described_class::RollbackError, /does not belong/)
    end
  end

  describe '#rollback_to_previous' do
    before do
      node_module.update!(mask: { 'v1' => true })
      service.create_version(changelog: 'V1')
      node_module.update!(mask: { 'v2' => true })
      service.create_version(changelog: 'V2')
    end

    it 'rolls back to the version before current' do
      current_before = node_module.current_version
      previous = current_before.previous_version

      service.rollback_to_previous

      expect(node_module.reload.mask).to eq(previous.mask)
    end

    it 'raises RollbackError when no current version' do
      new_module = create(:system_node_module, account: account)
      new_service = described_class.new(new_module)

      expect {
        new_service.rollback_to_previous
      }.to raise_error(described_class::RollbackError, /No current version/)
    end

    it 'raises RollbackError when no previous version' do
      single_version_module = create(:system_node_module, account: account)
      sv_service = described_class.new(single_version_module)
      sv_service.create_version(changelog: 'Only version')

      expect {
        sv_service.rollback_to_previous
      }.to raise_error(described_class::RollbackError, /No previous version/)
    end
  end

  describe '#lock!' do
    it 'locks the module' do
      service.lock!

      expect(node_module.reload.lock_spec).to be true
    end

    it 'raises LockError if already locked' do
      node_module.update!(lock_spec: true)

      expect {
        service.lock!
      }.to raise_error(described_class::LockError, /already locked/)
    end
  end

  describe '#unlock!' do
    before { node_module.update!(lock_spec: true) }

    it 'unlocks the module' do
      service.unlock!

      expect(node_module.reload.lock_spec).to be false
    end

    it 'raises LockError if not locked' do
      node_module.update!(lock_spec: false)

      expect {
        service.unlock!
      }.to raise_error(described_class::LockError, /not locked/)
    end
  end

  describe '#compare_versions' do
    let(:compare_module) { create(:system_node_module, account: account) }
    let(:compare_service) { described_class.new(compare_module, current_user: user) }
    let!(:v1) do
      compare_module.instance_variable_set(:@skip_auto_version, true)
      compare_module.update!(
        mask: { 'a' => 1, 'b' => 2 },
        file_spec: { 'file' => 'old' },
        package_spec: { 'pkg' => 'v1' },
        config: { 'config' => 'old' },
        data_checksum: 'checksum1'
      )
      compare_module.instance_variable_set(:@skip_auto_version, false)
      compare_service.create_version(changelog: 'V1')
    end
    let!(:v2) do
      compare_module.instance_variable_set(:@skip_auto_version, true)
      compare_module.update!(
        mask: { 'a' => 1, 'c' => 3 },
        file_spec: { 'file' => 'new' },
        package_spec: { 'pkg' => 'v2' },
        config: { 'config' => 'old' },
        data_checksum: 'checksum2'
      )
      compare_module.instance_variable_set(:@skip_auto_version, false)
      compare_service.create_version(changelog: 'V2')
    end

    it 'returns version numbers' do
      diff = compare_service.compare_versions(v1, v2)

      expect(diff[:version_numbers]).to eq([1, 2])
    end

    it 'identifies mask differences' do
      diff = compare_service.compare_versions(v1, v2)

      expect(diff[:mask_diff]).to include('b', 'c')
      expect(diff[:mask_diff]['b']).to eq({ from: 2, to: nil })
      expect(diff[:mask_diff]['c']).to eq({ from: nil, to: 3 })
    end

    it 'identifies file_spec differences' do
      diff = compare_service.compare_versions(v1, v2)

      expect(diff[:file_spec_diff]['file']).to eq({ from: 'old', to: 'new' })
    end

    it 'identifies when config is unchanged' do
      diff = compare_service.compare_versions(v1, v2)

      expect(diff[:config_diff]).to be_empty
    end

    it 'identifies data file changes' do
      diff = compare_service.compare_versions(v1, v2)

      expect(diff[:data_file_changed]).to be true
    end
  end

  describe '#version_history' do
    let(:history_module) { create(:system_node_module, account: account) }
    let(:history_service) { described_class.new(history_module, current_user: user) }

    before do
      3.times do |i|
        history_service.create_version(changelog: "Version #{i + 1}")
      end
    end

    it 'returns array of version summaries' do
      history = history_service.version_history

      expect(history).to be_an(Array)
      expect(history.length).to eq(3)
    end

    it 'orders by version_number descending' do
      history = history_service.version_history

      expect(history.map { |h| h[:version_number] }).to eq([3, 2, 1])
    end

    it 'includes expected fields' do
      history = history_service.version_history

      expect(history.first).to include(
        :id,
        :version_number,
        :changelog,
        :created_by,
        :created_at,
        :is_current,
        :has_data_file
      )
    end

    it 'marks current version' do
      history = history_service.version_history

      current = history.find { |h| h[:is_current] }
      expect(current[:version_number]).to eq(history_module.current_version_number)
    end

    it 'respects limit parameter' do
      history = history_service.version_history(limit: 2)

      expect(history.length).to eq(2)
    end
  end
end
