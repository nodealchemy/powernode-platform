# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Devops::DockerEvent, type: :model do
  subject(:event) { build(:devops_docker_event) }

  describe 'associations' do
    it { is_expected.to belong_to(:docker_host) }
    it { is_expected.to belong_to(:acknowledged_by).optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:event_type) }
    it { is_expected.to validate_presence_of(:severity) }
    it { is_expected.to validate_presence_of(:source_type) }
    it { is_expected.to validate_presence_of(:message) }

    context 'severity inclusion' do
      it 'accepts valid severities' do
        %w[info warning error critical].each do |sev|
          event.severity = sev
          expect(event).to be_valid
        end
      end

      it 'rejects invalid severities' do
        event.severity = 'invalid'
        expect(event).not_to be_valid
        expect(event.errors[:severity]).to be_present
      end
    end

    context 'source_type inclusion' do
      it 'accepts valid source types' do
        %w[host container image network volume].each do |src|
          event.source_type = src
          expect(event).to be_valid
        end
      end

      it 'rejects invalid source types' do
        event.source_type = 'invalid'
        expect(event).not_to be_valid
        expect(event.errors[:source_type]).to be_present
      end
    end
  end

  describe 'scopes' do
    let!(:unacked_event) { create(:devops_docker_event, acknowledged: false) }
    let!(:acked_event) { create(:devops_docker_event, :acknowledged) }
    let!(:critical_event) { create(:devops_docker_event, :critical) }
    let!(:warning_event) { create(:devops_docker_event, :warning) }
    let!(:old_event) { create(:devops_docker_event, created_at: 2.days.ago) }
    let!(:recent_event) { create(:devops_docker_event, created_at: 1.hour.ago) }

    describe '.unacknowledged' do
      it 'returns only unacknowledged events' do
        expect(described_class.unacknowledged).to include(unacked_event)
        expect(described_class.unacknowledged).not_to include(acked_event)
      end
    end

    describe '.by_severity' do
      it 'filters by severity' do
        expect(described_class.by_severity('critical')).to include(critical_event)
        expect(described_class.by_severity('critical')).not_to include(warning_event)
      end
    end

    describe '.critical' do
      it 'returns only critical events' do
        expect(described_class.critical).to include(critical_event)
        expect(described_class.critical).not_to include(warning_event)
      end
    end

    describe '.recent' do
      it 'orders by created_at descending' do
        results = described_class.recent
        expect(results.first.created_at).to be >= results.last.created_at
      end
    end

    describe '.since' do
      it 'returns events since the given time' do
        results = described_class.since(6.hours.ago)
        expect(results).to include(recent_event)
        expect(results).not_to include(old_event)
      end
    end
  end

  describe 'instance methods' do
    describe '#acknowledge!' do
      it 'sets acknowledged, user, and timestamp' do
        event = create(:devops_docker_event)
        user = create(:user)

        event.acknowledge!(user)
        event.reload

        expect(event.acknowledged).to be true
        expect(event.acknowledged_by).to eq(user)
        expect(event.acknowledged_at).to be_within(2.seconds).of(Time.current)
      end
    end

    describe '#critical?' do
      it 'returns true for critical events' do
        event = build(:devops_docker_event, :critical)
        expect(event.critical?).to be true
      end

      it 'returns false for non-critical events' do
        event = build(:devops_docker_event, severity: 'info')
        expect(event.critical?).to be false
      end
    end

    describe '#warning?' do
      it 'returns true for warning events' do
        event = build(:devops_docker_event, :warning)
        expect(event.warning?).to be true
      end

      it 'returns false for non-warning events' do
        event = build(:devops_docker_event, severity: 'info')
        expect(event.warning?).to be false
      end
    end

    describe '#event_summary' do
      it 'returns a hash with summary fields' do
        event = create(:devops_docker_event, :critical)
        summary = event.event_summary

        expect(summary).to include(
          id: event.id,
          event_type: event.event_type,
          severity: 'critical',
          source_type: event.source_type,
          message: event.message,
          acknowledged: false
        )
      end
    end

    describe '#event_details' do
      it 'returns summary merged with detail fields' do
        event = create(:devops_docker_event)
        details = event.event_details

        expect(details).to include(:id, :event_type, :severity, :message)
        expect(details).to include(:source_id, :metadata, :acknowledged_by,
                                   :acknowledged_at, :docker_host_id)
      end
    end
  end
end
