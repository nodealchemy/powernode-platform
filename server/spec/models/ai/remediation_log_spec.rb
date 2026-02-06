# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::RemediationLog, type: :model do
  # ==========================================
  # Associations
  # ==========================================
  describe 'associations' do
    it { should belong_to(:account) }
  end

  # ==========================================
  # Validations
  # ==========================================
  describe 'validations' do
    subject { build(:ai_remediation_log) }

    it { should validate_presence_of(:trigger_source) }
    it { should validate_presence_of(:trigger_event) }
    it { should validate_presence_of(:action_type) }
    it { should validate_presence_of(:result) }
    it { should validate_presence_of(:executed_at) }

    it { should validate_inclusion_of(:action_type).in_array(Ai::RemediationLog::ACTION_TYPES) }
    it { should validate_inclusion_of(:result).in_array(Ai::RemediationLog::RESULTS) }

    it 'rejects an invalid action_type' do
      log = build(:ai_remediation_log, action_type: 'invalid_action')
      expect(log).not_to be_valid
      expect(log.errors[:action_type]).to be_present
    end

    it 'rejects an invalid result' do
      log = build(:ai_remediation_log, result: 'invalid_result')
      expect(log).not_to be_valid
      expect(log.errors[:result]).to be_present
    end
  end

  # ==========================================
  # Constants
  # ==========================================
  describe 'constants' do
    it 'defines valid RESULTS' do
      expect(Ai::RemediationLog::RESULTS).to eq(%w[success failure skipped rate_limited])
    end

    it 'defines valid ACTION_TYPES' do
      expect(Ai::RemediationLog::ACTION_TYPES).to eq(%w[provider_failover workflow_retry alert_escalation])
    end
  end

  # ==========================================
  # Scopes
  # ==========================================
  describe 'scopes' do
    let(:account) { create(:account) }

    describe '.recent' do
      let!(:old_log) { create(:ai_remediation_log, account: account, executed_at: 2.days.ago) }
      let!(:new_log) { create(:ai_remediation_log, account: account, executed_at: 1.minute.ago) }

      it 'returns logs ordered by executed_at desc' do
        results = described_class.recent
        expect(results.first).to eq(new_log)
      end

      it 'defaults to 50 records' do
        expect(described_class.recent.limit_value).to eq(50)
      end

      it 'accepts a custom limit' do
        expect(described_class.recent(5).limit_value).to eq(5)
      end
    end

    describe '.successful' do
      let!(:success_log) { create(:ai_remediation_log, account: account, result: 'success') }
      let!(:failure_log) { create(:ai_remediation_log, account: account, result: 'failure') }

      it 'returns only successful logs' do
        expect(described_class.successful).to include(success_log)
        expect(described_class.successful).not_to include(failure_log)
      end
    end

    describe '.failed' do
      let!(:success_log) { create(:ai_remediation_log, account: account, result: 'success') }
      let!(:failure_log) { create(:ai_remediation_log, account: account, result: 'failure') }

      it 'returns only failed logs' do
        expect(described_class.failed).to include(failure_log)
        expect(described_class.failed).not_to include(success_log)
      end
    end

    describe '.by_action_type' do
      let!(:failover_log) { create(:ai_remediation_log, account: account, action_type: 'provider_failover') }
      let!(:retry_log) { create(:ai_remediation_log, account: account, action_type: 'workflow_retry') }

      it 'returns logs with the specified action type' do
        expect(described_class.by_action_type('provider_failover')).to include(failover_log)
        expect(described_class.by_action_type('provider_failover')).not_to include(retry_log)
      end
    end

    describe '.in_last_hour' do
      let!(:recent_log) { create(:ai_remediation_log, account: account, executed_at: 30.minutes.ago) }
      let!(:old_log) { create(:ai_remediation_log, account: account, executed_at: 2.hours.ago) }

      it 'returns only logs from the last hour' do
        expect(described_class.in_last_hour).to include(recent_log)
        expect(described_class.in_last_hour).not_to include(old_log)
      end
    end

    describe '.by_account' do
      let(:other_account) { create(:account) }
      let!(:log_a) { create(:ai_remediation_log, account: account) }
      let!(:log_b) { create(:ai_remediation_log, account: other_account) }

      it 'returns logs for the specified account' do
        expect(described_class.by_account(account.id)).to include(log_a)
        expect(described_class.by_account(account.id)).not_to include(log_b)
      end
    end
  end

  # ==========================================
  # Class Methods
  # ==========================================
  describe '.hourly_count' do
    let(:account) { create(:account) }

    before do
      create_list(:ai_remediation_log, 3, account: account, executed_at: 30.minutes.ago)
      create(:ai_remediation_log, account: account, executed_at: 2.hours.ago)
    end

    it 'returns the count of remediation logs in the last hour for the given account' do
      expect(described_class.hourly_count(account.id)).to eq(3)
    end

    it 'returns 0 when no logs exist in the last hour' do
      other_account = create(:account)
      expect(described_class.hourly_count(other_account.id)).to eq(0)
    end
  end

  # ==========================================
  # Factories
  # ==========================================
  describe 'factories' do
    it 'has a valid default factory' do
      expect(build(:ai_remediation_log)).to be_valid
    end
  end
end
