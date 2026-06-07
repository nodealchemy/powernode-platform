# frozen_string_literal: true

require 'rails_helper'

# Ai::DataSourceConfigVersion — append-only, CREDENTIAL-FREE config snapshot
# ("manifest") of a data source and its endpoints (Phase 4b-3b onboarding
# portability). Versions are appended monotonically per source. There is no
# factory for this model, so rows are built/created directly; every build must
# supply the required `created_by_type` (presence + inclusion validated) and a
# `version` (no model-level autonumber — the service assigns it via
# `.next_version_for`). Everything is account-scoped.
RSpec.describe Ai::DataSourceConfigVersion, type: :model do
  let(:account) { create(:account) }
  let(:data_source) { create(:ai_data_source, account: account) }

  describe 'associations' do
    it { is_expected.to belong_to(:account) }

    it 'belongs to data_source via ai_data_source_id' do
      assoc = described_class.reflect_on_association(:data_source)
      expect(assoc.macro).to eq(:belongs_to)
      expect(assoc.options[:class_name]).to eq('Ai::DataSource')
      expect(assoc.options[:foreign_key]).to eq('ai_data_source_id')
    end

    it 'resolves the data_source record through the association' do
      version = described_class.create!(
        account: account,
        data_source: data_source,
        version: 1,
        created_by_type: 'manual'
      )

      expect(version.reload.data_source).to eq(data_source)
      expect(version.ai_data_source_id).to eq(data_source.id)
    end
  end

  describe 'manifest jsonb attribute' do
    it 'defaults to an empty hash for a new record' do
      version = described_class.new

      expect(version.manifest).to eq({})
    end

    it 'persists and reloads a structured manifest unchanged' do
      manifest = {
        'source' => { 'name' => 'Weather API', 'protocol' => 'rest' },
        'endpoints' => [{ 'name' => 'observations', 'http_method' => 'GET' }]
      }

      version = described_class.create!(
        account: account,
        data_source: data_source,
        version: 1,
        created_by_type: 'manual',
        manifest: manifest
      )

      expect(version.reload.manifest).to eq(manifest)
    end
  end

  describe 'validations' do
    subject do
      described_class.new(
        account: account,
        data_source: data_source,
        version: 1,
        created_by_type: 'manual'
      )
    end

    it 'is valid with the required attributes' do
      expect(subject).to be_valid
    end

    it { is_expected.to validate_presence_of(:version) }
    it { is_expected.to validate_presence_of(:ai_data_source_id) }
    it { is_expected.to validate_presence_of(:created_by_type) }

    it 'rejects a non-integer version' do
      subject.version = 1.5
      expect(subject).not_to be_valid
      expect(subject.errors[:version]).to be_present
    end

    it 'rejects a zero or negative version' do
      subject.version = 0
      expect(subject).not_to be_valid

      subject.version = -1
      expect(subject).not_to be_valid
    end

    it 'rejects an unknown created_by_type' do
      subject.created_by_type = 'sideways'
      expect(subject).not_to be_valid
      expect(subject.errors[:created_by_type]).to be_present
    end

    it 'accepts each allowed created_by_type' do
      Ai::DataSourceConfigVersion::CREATED_BY_TYPES.each do |type|
        candidate = described_class.new(
          account: account,
          data_source: data_source,
          version: 1,
          created_by_type: type
        )
        expect(candidate).to be_valid, "expected #{type.inspect} to be a valid created_by_type"
      end
    end

    describe 'version uniqueness scoped to the source' do
      before do
        described_class.create!(
          account: account,
          data_source: data_source,
          version: 1,
          created_by_type: 'manual'
        )
      end

      it 'rejects a second version with the same number for the same source' do
        duplicate = described_class.new(
          account: account,
          data_source: data_source,
          version: 1,
          created_by_type: 'auto'
        )

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:version]).to be_present
      end

      it 'allows the same version number for a DIFFERENT source' do
        other_source = create(:ai_data_source, account: account)

        sibling = described_class.new(
          account: account,
          data_source: other_source,
          version: 1,
          created_by_type: 'manual'
        )

        expect(sibling).to be_valid
        expect { sibling.save! }.not_to raise_error
      end

      it 'allows a different version number for the same source' do
        next_one = described_class.new(
          account: account,
          data_source: data_source,
          version: 2,
          created_by_type: 'auto'
        )

        expect(next_one).to be_valid
      end
    end
  end

  describe '.latest_first' do
    it 'orders versions by version descending' do
      v1 = described_class.create!(account: account, data_source: data_source, version: 1, created_by_type: 'manual')
      v3 = described_class.create!(account: account, data_source: data_source, version: 3, created_by_type: 'manual')
      v2 = described_class.create!(account: account, data_source: data_source, version: 2, created_by_type: 'manual')

      expect(described_class.where(data_source: data_source).latest_first.to_a).to eq([v3, v2, v1])
    end
  end

  describe '.next_version_for' do
    it 'returns 1 when the source has no versions yet' do
      expect(described_class.next_version_for(data_source)).to eq(1)
    end

    it 'returns max(version) + 1 when versions exist' do
      described_class.create!(account: account, data_source: data_source, version: 1, created_by_type: 'manual')
      described_class.create!(account: account, data_source: data_source, version: 2, created_by_type: 'manual')

      expect(described_class.next_version_for(data_source)).to eq(3)
    end

    it 'accepts a raw id as well as a model instance' do
      described_class.create!(account: account, data_source: data_source, version: 5, created_by_type: 'manual')

      expect(described_class.next_version_for(data_source)).to eq(6)
      expect(described_class.next_version_for(data_source.id)).to eq(6)
    end

    it 'counts only versions belonging to the given source' do
      other_source = create(:ai_data_source, account: account)
      described_class.create!(account: account, data_source: other_source, version: 9, created_by_type: 'manual')

      # data_source itself still has none, so it starts at 1 regardless of the
      # other source's higher max.
      expect(described_class.next_version_for(data_source)).to eq(1)
      expect(described_class.next_version_for(other_source)).to eq(10)
    end
  end

  describe '.for_data_source' do
    let(:other_source) { create(:ai_data_source, account: account) }

    before do
      described_class.create!(account: account, data_source: data_source, version: 1, created_by_type: 'manual')
      described_class.create!(account: account, data_source: data_source, version: 2, created_by_type: 'manual')
      described_class.create!(account: account, data_source: other_source, version: 1, created_by_type: 'manual')
    end

    it 'returns only versions for the given source (model instance)' do
      result = described_class.for_data_source(data_source)

      expect(result.count).to eq(2)
      expect(result.pluck(:ai_data_source_id).uniq).to eq([data_source.id])
    end

    it 'accepts a raw id and returns the same scoped set' do
      result = described_class.for_data_source(data_source.id)

      expect(result.count).to eq(2)
      expect(result.pluck(:ai_data_source_id).uniq).to eq([data_source.id])
    end
  end

  describe 'account scoping' do
    it 'is scoped to its account' do
      other_account = create(:account)
      other_source = create(:ai_data_source, account: other_account)

      mine = described_class.create!(account: account, data_source: data_source, version: 1, created_by_type: 'manual')
      theirs = described_class.create!(account: other_account, data_source: other_source, version: 1, created_by_type: 'manual')

      expect(described_class.where(account: account)).to include(mine)
      expect(described_class.where(account: account)).not_to include(theirs)
    end
  end
end
