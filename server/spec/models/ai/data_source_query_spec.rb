# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::DataSourceQuery, type: :model do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:data_source) { create(:ai_data_source, account: account) }
  let(:endpoint) { create(:ai_data_source_endpoint, data_source: data_source) }

  # No factory for the query/audit-log row; build rows directly to keep the
  # spec focused on the model's associations, validations, and scopes.
  def build_query(**attrs)
    described_class.new(
      data_source: data_source,
      account_id: account.id,
      **attrs
    )
  end

  def create_query(**attrs)
    build_query(**attrs).tap(&:save!)
  end

  describe 'associations' do
    subject { build_query }

    it { is_expected.to belong_to(:data_source).class_name('Ai::DataSource').with_foreign_key('ai_data_source_id') }

    it 'belongs to an optional endpoint' do
      is_expected.to belong_to(:endpoint)
        .class_name('Ai::DataSourceEndpoint')
        .with_foreign_key('ai_data_source_endpoint_id')
        .optional
    end

    it 'persists with an associated endpoint' do
      query = create_query(endpoint: endpoint, status: 'success')
      expect(query.reload.endpoint).to eq(endpoint)
    end

    it 'persists without an endpoint' do
      query = create_query(status: 'success')
      expect(query.reload.endpoint).to be_nil
    end
  end

  describe 'validations' do
    it 'is valid with a data source' do
      expect(build_query(status: 'success')).to be_valid
    end

    it 'requires ai_data_source_id' do
      query = build_query
      query.data_source = nil
      query.ai_data_source_id = nil
      expect(query).not_to be_valid
      expect(query.errors[:ai_data_source_id]).to include("can't be blank")
    end
  end

  describe 'JSON column defaults' do
    it 'defaults metadata to an empty hash' do
      expect(described_class.new.metadata).to eq({})
    end
  end

  describe 'scopes' do
    describe '.for_data_source' do
      it 'accepts a record' do
        mine = create_query(status: 'success')
        create_query_for(create(:ai_data_source, account: account))

        expect(described_class.for_data_source(data_source)).to contain_exactly(mine)
      end

      it 'accepts a bare id' do
        mine = create_query(status: 'success')
        expect(described_class.for_data_source(data_source.id)).to contain_exactly(mine)
      end
    end

    describe '.for_account' do
      it 'accepts an Account record and scopes by account_id' do
        mine = create_query(status: 'success')
        described_class.create!(data_source: create(:ai_data_source, account: other_account),
                                account_id: other_account.id, status: 'success')

        expect(described_class.for_account(account)).to contain_exactly(mine)
      end

      it 'accepts a bare account id' do
        mine = create_query(status: 'success')
        expect(described_class.for_account(account.id)).to contain_exactly(mine)
      end
    end

    describe '.successful / .failed' do
      it 'partitions rows by success status' do
        ok = create_query(status: 'success')
        err = create_query(status: 'error')
        timed_out = create_query(status: 'timeout')

        expect(described_class.successful).to contain_exactly(ok)
        expect(described_class.failed).to contain_exactly(err, timed_out)
      end
    end

    describe '.cached' do
      it 'returns only rows served from cache' do
        from_cache = create_query(status: 'cached', cached: true)
        create_query(status: 'success', cached: false)

        expect(described_class.cached).to contain_exactly(from_cache)
      end
    end

    describe '.recent' do
      it 'orders by created_at descending' do
        older = create_query(status: 'success')
        older.update_column(:created_at, 2.hours.ago)
        newer = create_query(status: 'success')
        newer.update_column(:created_at, 1.minute.ago)

        expect(described_class.recent.to_a).to eq([newer, older])
      end
    end
  end

  describe 'status constants' do
    it 'exposes the canonical status, served-stage, and policy-decision lists' do
      expect(described_class::STATUSES).to include('success', 'error', 'timeout', 'rate_limited', 'blocked', 'cached')
      expect(described_class::SERVED_STAGES).to include('fresh', 'cache', 'stale_while_revalidate', 'stale_if_error')
      expect(described_class::POLICY_DECISIONS).to include('allow', 'deny', 'mask')
    end
  end

  # Helper that creates a query row for an arbitrary data source (used to prove
  # the for_data_source scope filters correctly).
  def create_query_for(source)
    described_class.create!(data_source: source, account_id: source.account_id, status: 'success')
  end
end
