# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'System::NodeModule versioning', type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:node_module) { create(:system_node_module, account: account) }

  describe 'versioning associations' do
    it 'has_many versions' do
      v1 = create(:system_node_module_version, node_module: node_module, version_number: 1)
      v2 = create(:system_node_module_version, node_module: node_module, version_number: 2)

      expect(node_module.versions).to contain_exactly(v1, v2)
    end

    it 'belongs_to current_version optionally' do
      expect(node_module.current_version).to be_nil

      version = create(:system_node_module_version, node_module: node_module)
      node_module.update!(current_version: version)

      expect(node_module.reload.current_version).to eq(version)
    end
  end

  describe 'locking behavior' do
    describe '#locked?' do
      it 'returns false by default' do
        expect(node_module.locked?).to be false
      end

      it 'returns true when lock_spec is true' do
        node_module.update!(lock_spec: true)
        expect(node_module.locked?).to be true
      end
    end

    describe '#lock!' do
      it 'sets lock_spec to true' do
        node_module.lock!
        expect(node_module.reload.lock_spec).to be true
      end
    end

    describe '#unlock!' do
      before { node_module.update!(lock_spec: true) }

      it 'sets lock_spec to false' do
        node_module.unlock!
        expect(node_module.reload.lock_spec).to be false
      end
    end
  end

  describe 'versioning scopes' do
    describe '.locked' do
      let!(:locked_module) { create(:system_node_module, :locked, account: account) }
      let!(:unlocked_module) { create(:system_node_module, account: account) }

      it 'returns only locked modules' do
        expect(System::NodeModule.locked).to contain_exactly(locked_module)
      end
    end

    describe '.unlocked' do
      let!(:locked_module) { create(:system_node_module, :locked, account: account) }
      let!(:unlocked_module) { create(:system_node_module, account: account) }

      it 'returns only unlocked modules' do
        expect(System::NodeModule.unlocked).to include(unlocked_module)
        expect(System::NodeModule.unlocked).not_to include(locked_module)
      end
    end

    describe '.versioned' do
      let!(:versioned_module) do
        mod = create(:system_node_module, account: account)
        version = create(:system_node_module_version, node_module: mod)
        mod.update!(current_version: version)
        mod
      end
      let!(:unversioned_module) { create(:system_node_module, account: account) }

      it 'returns only modules with current_version set' do
        expect(System::NodeModule.versioned).to contain_exactly(versioned_module)
      end
    end
  end

  describe 'versioning methods' do
    describe '#versioned?' do
      it 'returns false when no versions exist' do
        expect(node_module.versioned?).to be false
      end

      it 'returns true when versions exist' do
        create(:system_node_module_version, node_module: node_module)
        expect(node_module.versioned?).to be true
      end
    end

    describe '#latest_version' do
      let!(:v1) { create(:system_node_module_version, node_module: node_module, version_number: 1) }
      let!(:v2) { create(:system_node_module_version, node_module: node_module, version_number: 2) }
      let!(:v3) { create(:system_node_module_version, node_module: node_module, version_number: 3) }

      it 'returns the version with highest version_number' do
        expect(node_module.latest_version).to eq(v3)
      end
    end

    describe '#version' do
      let!(:v1) { create(:system_node_module_version, node_module: node_module, version_number: 1) }
      let!(:v2) { create(:system_node_module_version, node_module: node_module, version_number: 2) }

      it 'finds version by number' do
        expect(node_module.version(1)).to eq(v1)
        expect(node_module.version(2)).to eq(v2)
      end

      it 'returns nil for non-existent version' do
        expect(node_module.version(99)).to be_nil
      end
    end

    describe '#create_version!' do
      it 'creates a new version' do
        expect {
          node_module.create_version!(changelog: 'Test version')
        }.to change { node_module.versions.count }.by(1)
      end

      it 'captures current module state' do
        node_module.update!(mask: { 'key' => 'value' }, file_spec: { 'file' => 'spec' })

        version = node_module.create_version!(changelog: 'Captured state')

        expect(version.mask).to eq({ 'key' => 'value' })
        expect(version.file_spec).to eq({ 'file' => 'spec' })
      end

      it 'updates current_version reference' do
        version = node_module.create_version!(changelog: 'New version')

        expect(node_module.reload.current_version).to eq(version)
        expect(node_module.current_version_number).to eq(version.version_number)
      end

      it 'raises error when module is locked' do
        node_module.update!(lock_spec: true)

        expect {
          node_module.create_version!(changelog: 'Should fail')
        }.to raise_error(System::ModuleVersionService::LockError)
      end

      it 'records the user who created the version' do
        version = node_module.create_version!(changelog: 'User version', user: user)

        expect(version.created_by).to eq(user)
      end
    end

    describe '#rollback_to!' do
      let!(:v1) do
        node_module.update!(mask: { 'v1' => true })
        node_module.create_version!(changelog: 'Version 1')
      end
      let!(:v2) do
        node_module.update!(mask: { 'v2' => true })
        node_module.create_version!(changelog: 'Version 2')
      end

      it 'restores module state from version' do
        node_module.update!(mask: { 'v3' => true })
        node_module.rollback_to!(v1)

        expect(node_module.reload.mask).to eq({ 'v1' => true })
      end

      it 'creates a new version for the rollback' do
        expect {
          node_module.rollback_to!(v1)
        }.to change { node_module.versions.count }.by(1)
      end

      it 'raises error when module is locked' do
        node_module.update!(lock_spec: true)

        expect {
          node_module.rollback_to!(v1)
        }.to raise_error(System::ModuleVersionService::LockError)
      end

      it 'raises error for version from different module' do
        other_module = create(:system_node_module, account: account)
        other_version = create(:system_node_module_version, node_module: other_module)

        expect {
          node_module.rollback_to!(other_version)
        }.to raise_error(System::ModuleVersionService::RollbackError)
      end
    end

    describe '#rollback_to_previous!' do
      before do
        node_module.update!(mask: { 'v1' => true })
        node_module.create_version!(changelog: 'Version 1')
        node_module.update!(mask: { 'v2' => true })
        node_module.create_version!(changelog: 'Version 2')
      end

      it 'rolls back to the previous version' do
        node_module.update!(mask: { 'v3' => true })
        node_module.rollback_to_previous!

        # After rollback, mask should be from v2 (the previous current)
        expect(node_module.reload.mask['v2']).to be true
      end

      it 'raises error when no previous version exists' do
        new_module = create(:system_node_module, account: account)
        new_module.create_version!(changelog: 'First version')

        expect {
          new_module.rollback_to_previous!
        }.to raise_error(System::ModuleVersionService::RollbackError)
      end
    end

    describe '#version_history' do
      before do
        3.times do |i|
          node_module.create_version!(changelog: "Version #{i + 1}")
        end
      end

      it 'returns version history with summary information' do
        history = node_module.version_history

        expect(history.length).to eq(3)
        expect(history.first[:version_number]).to eq(3) # ordered by desc
        expect(history.first).to include(:id, :changelog, :created_at, :is_current)
      end

      it 'respects limit parameter' do
        history = node_module.version_history(limit: 2)

        expect(history.length).to eq(2)
      end
    end
  end

  describe 'data file management' do
    describe '#set_data_file' do
      it 'sets file attributes with calculated checksum' do
        content = 'test file content here'
        node_module.set_data_file(filename: 'test.tar.gz', content: content)

        expect(node_module.data_file_name).to eq('test.tar.gz')
        expect(node_module.data_file_size).to eq(content.bytesize)
        expect(node_module.data_checksum).to eq(Digest::SHA256.hexdigest(content))
      end
    end

    describe '#verify_data_file' do
      let(:content) { 'test file content' }

      before do
        node_module.set_data_file(filename: 'test.tar.gz', content: content)
      end

      it 'returns true for matching content' do
        expect(node_module.verify_data_file(content)).to be true
      end

      it 'returns false for non-matching content' do
        expect(node_module.verify_data_file('different content')).to be false
      end
    end
  end
end
