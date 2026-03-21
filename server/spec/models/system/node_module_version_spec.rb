# frozen_string_literal: true

require 'rails_helper'

RSpec.describe System::NodeModuleVersion, type: :model do
  subject(:version) { build(:system_node_module_version) }

  describe 'associations' do
    it { is_expected.to belong_to(:node_module).class_name('System::NodeModule') }
    it { is_expected.to belong_to(:created_by).class_name('User').optional }
  end

  describe 'validations' do
    # Note: version_number presence is ensured by callback, not validation
    it { is_expected.to validate_presence_of(:node_module) }
    it { is_expected.to validate_numericality_of(:version_number).only_integer.is_greater_than(0) }

    context 'with existing version' do
      let!(:existing_version) { create(:system_node_module_version) }

      it 'validates uniqueness of version_number scoped to node_module' do
        duplicate = build(:system_node_module_version,
                          node_module: existing_version.node_module,
                          version_number: existing_version.version_number)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:version_number]).to include('has already been taken')
      end

      it 'allows same version_number for different modules' do
        other_module = create(:system_node_module)
        other_version = build(:system_node_module_version,
                              node_module: other_module,
                              version_number: existing_version.version_number)
        expect(other_version).to be_valid
      end
    end
  end

  describe 'scopes' do
    let(:node_module) { create(:system_node_module) }
    let!(:version1) { create(:system_node_module_version, node_module: node_module, version_number: 1) }
    let!(:version2) { create(:system_node_module_version, node_module: node_module, version_number: 2) }
    let!(:version3) { create(:system_node_module_version, :with_data_file, node_module: node_module, version_number: 3) }

    describe '.ordered' do
      it 'orders by version_number descending' do
        expect(node_module.versions.ordered.pluck(:version_number)).to eq([3, 2, 1])
      end
    end

    describe '.by_version' do
      it 'orders by version_number ascending' do
        expect(node_module.versions.by_version.pluck(:version_number)).to eq([1, 2, 3])
      end
    end

    describe '.with_data_file' do
      it 'returns only versions with data files' do
        expect(node_module.versions.with_data_file).to contain_exactly(version3)
      end
    end
  end

  describe 'callbacks' do
    describe '#set_version_number' do
      context 'when version_number is not set' do
        let(:node_module) { create(:system_node_module) }

        it 'auto-increments version_number' do
          v1 = create(:system_node_module_version, node_module: node_module, version_number: nil)
          expect(v1.version_number).to eq(1)

          v2 = create(:system_node_module_version, node_module: node_module, version_number: nil)
          expect(v2.version_number).to eq(2)
        end
      end

      context 'when version_number is provided' do
        it 'uses the provided version_number' do
          v = create(:system_node_module_version, version_number: 42)
          expect(v.version_number).to eq(42)
        end
      end
    end
  end

  describe 'instance methods' do
    let(:node_module) { create(:system_node_module) }
    let!(:version1) { create(:system_node_module_version, node_module: node_module, version_number: 1) }
    let!(:version2) { create(:system_node_module_version, node_module: node_module, version_number: 2) }
    let!(:version3) { create(:system_node_module_version, node_module: node_module, version_number: 3) }

    describe '#has_data_file?' do
      it 'returns true when data_file_name is present' do
        version = build(:system_node_module_version, :with_data_file)
        expect(version.has_data_file?).to be true
      end

      it 'returns false when data_file_name is nil' do
        expect(version1.has_data_file?).to be false
      end
    end

    describe '#current?' do
      before { node_module.update!(current_version: version2) }

      it 'returns true for current version' do
        expect(version2.current?).to be true
      end

      it 'returns false for non-current version' do
        expect(version1.current?).to be false
        expect(version3.current?).to be false
      end
    end

    describe '#latest?' do
      it 'returns true for the highest version number' do
        expect(version3.latest?).to be true
      end

      it 'returns false for lower version numbers' do
        expect(version1.latest?).to be false
        expect(version2.latest?).to be false
      end
    end

    describe '#previous_version' do
      it 'returns the previous version' do
        expect(version2.previous_version).to eq(version1)
        expect(version3.previous_version).to eq(version2)
      end

      it 'returns nil for the first version' do
        expect(version1.previous_version).to be_nil
      end
    end

    describe '#next_version' do
      it 'returns the next version' do
        expect(version1.next_version).to eq(version2)
        expect(version2.next_version).to eq(version3)
      end

      it 'returns nil for the latest version' do
        expect(version3.next_version).to be_nil
      end
    end

    describe '#verify_checksum' do
      let(:test_content) { 'test file content' }
      let(:checksum) { Digest::SHA256.hexdigest(test_content) }
      let(:version) { build(:system_node_module_version, data_checksum: checksum) }

      it 'returns true for matching content' do
        expect(version.verify_checksum(test_content)).to be true
      end

      it 'returns false for non-matching content' do
        expect(version.verify_checksum('different content')).to be false
      end

      it 'returns false when no checksum is stored' do
        version.data_checksum = nil
        expect(version.verify_checksum(test_content)).to be false
      end
    end

    describe '#change_summary' do
      it 'returns changelog when present' do
        version = build(:system_node_module_version, changelog: 'Fixed bug', version_number: 5)
        expect(version.change_summary).to eq('Fixed bug')
      end

      it 'returns default text when changelog is nil' do
        version = build(:system_node_module_version, changelog: nil, version_number: 5)
        expect(version.change_summary).to eq('Version 5')
      end
    end
  end

  describe 'table name' do
    it 'uses the correct table name with system_ prefix' do
      expect(described_class.table_name).to eq('system_node_module_versions')
    end
  end
end
