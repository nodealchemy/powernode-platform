# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::DataSourceEndpoint, type: :model do
  let(:account) { create(:account) }
  let(:data_source) { create(:ai_data_source, account: account) }

  subject(:endpoint) { build(:ai_data_source_endpoint, data_source: data_source) }

  describe 'associations' do
    it { is_expected.to belong_to(:data_source).class_name('Ai::DataSource').with_foreign_key('ai_data_source_id') }

    it 'has many queries that are nullified on destroy' do
      is_expected.to have_many(:queries)
        .class_name('Ai::DataSourceQuery')
        .with_foreign_key('ai_data_source_endpoint_id')
        .dependent(:nullify)
    end
  end

  describe 'validations' do
    it { is_expected.to be_valid }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:http_method) }

    it 'validates name length' do
      endpoint.name = 'a' * 256
      expect(endpoint).not_to be_valid
      expect(endpoint.errors[:name]).to include('is too long (maximum is 255 characters)')
    end

    it 'requires ai_data_source_id' do
      orphan = build(:ai_data_source_endpoint)
      orphan.data_source = nil
      orphan.ai_data_source_id = nil
      expect(orphan).not_to be_valid
      expect(orphan.errors[:ai_data_source_id]).to include("can't be blank")
    end

    it 'validates http_method inclusion' do
      endpoint.http_method = 'CONNECT'
      expect(endpoint).not_to be_valid
      expect(endpoint.errors[:http_method]).to be_present
    end

    it 'accepts every supported HTTP method' do
      described_class::HTTP_METHODS.each do |method|
        candidate = build(:ai_data_source_endpoint, data_source: data_source, http_method: method)
        expect(candidate).to be_valid, "expected #{method} to be a valid http_method"
      end
    end

    it 'validates response_format inclusion but allows nil' do
      endpoint.response_format = 'protobuf'
      expect(endpoint).not_to be_valid
      expect(endpoint.errors[:response_format]).to be_present

      endpoint.response_format = nil
      expect(endpoint).to be_valid
    end

    it 'validates change_detection inclusion but allows nil' do
      endpoint.change_detection = 'magic'
      expect(endpoint).not_to be_valid
      expect(endpoint.errors[:change_detection]).to be_present

      endpoint.change_detection = nil
      expect(endpoint).to be_valid
    end

    it 'rejects a negative cache_ttl_seconds' do
      endpoint.cache_ttl_seconds = -1
      expect(endpoint).not_to be_valid
      expect(endpoint.errors[:cache_ttl_seconds]).to be_present
    end

    it 'allows a nil cache_ttl_seconds' do
      endpoint.cache_ttl_seconds = nil
      expect(endpoint).to be_valid
    end
  end

  describe 'slug auto-generation' do
    it 'derives a parameterized slug from the name on create' do
      ep = create(:ai_data_source_endpoint, data_source: data_source, name: 'Current Observations', slug: nil)
      expect(ep.slug).to eq('current_observations')
    end

    it 'respects an explicitly provided slug' do
      ep = create(:ai_data_source_endpoint, data_source: data_source, name: 'Whatever', slug: 'custom-slug')
      expect(ep.slug).to eq('custom-slug')
    end

    it 'disambiguates duplicate slugs within the same data source' do
      first = create(:ai_data_source_endpoint, data_source: data_source, name: 'Forecast', slug: nil)
      second = create(:ai_data_source_endpoint, data_source: data_source, name: 'Forecast', slug: nil)

      expect(first.slug).to eq('forecast')
      expect(second.slug).to eq('forecast_1')
    end

    it 'allows the same slug across different data sources' do
      other_source = create(:ai_data_source, account: account)
      a = create(:ai_data_source_endpoint, data_source: data_source, name: 'Forecast', slug: nil)
      b = create(:ai_data_source_endpoint, data_source: other_source, name: 'Forecast', slug: nil)

      expect(a.slug).to eq('forecast')
      expect(b.slug).to eq('forecast')
    end

    it 'enforces slug format' do
      endpoint.slug = 'Has Spaces'
      expect(endpoint).not_to be_valid
      expect(endpoint.errors[:slug]).to be_present
    end

    it 'enforces slug uniqueness within the data source at the model layer' do
      create(:ai_data_source_endpoint, data_source: data_source, slug: 'dup')
      dup = build(:ai_data_source_endpoint, data_source: data_source, slug: 'dup')
      expect(dup).not_to be_valid
      expect(dup.errors[:slug]).to include('has already been taken')
    end
  end

  describe 'account delegation' do
    it 'delegates #account to the parent data source' do
      ep = create(:ai_data_source_endpoint, data_source: data_source)
      expect(ep.account).to eq(account)
    end

    it 'returns nil for #account when the data source is absent (allow_nil)' do
      ep = described_class.new
      expect(ep.account).to be_nil
    end
  end

  describe 'JSON column defaults' do
    it 'defaults template/mapping/schema/metadata columns to empty hashes' do
      ep = described_class.new
      expect(ep.query_template).to eq({})
      expect(ep.body_template).to eq({})
      expect(ep.response_mapping).to eq({})
      expect(ep.response_schema).to eq({})
      expect(ep.metadata).to eq({})
    end
  end

  describe '#to_param' do
    it 'returns the slug' do
      ep = create(:ai_data_source_endpoint, data_source: data_source, name: 'Stations', slug: nil)
      expect(ep.to_param).to eq('stations')
    end
  end

  describe 'scopes' do
    describe '.for_data_source' do
      it 'accepts a record and returns its endpoints' do
        mine = create(:ai_data_source_endpoint, data_source: data_source)
        create(:ai_data_source_endpoint, data_source: create(:ai_data_source, account: account))

        expect(described_class.for_data_source(data_source)).to contain_exactly(mine)
      end

      it 'accepts a bare id' do
        mine = create(:ai_data_source_endpoint, data_source: data_source)
        expect(described_class.for_data_source(data_source.id)).to contain_exactly(mine)
      end
    end

    describe '.monitorable' do
      it 'returns only monitorable endpoints' do
        watched = create(:ai_data_source_endpoint, data_source: data_source, monitorable: true)
        create(:ai_data_source_endpoint, data_source: data_source, monitorable: false)

        expect(described_class.monitorable).to contain_exactly(watched)
      end
    end
  end
end
