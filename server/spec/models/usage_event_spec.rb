# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UsageEvent, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:usage_meter) }
    it { is_expected.to belong_to(:user).optional }
  end

  describe 'validations' do
    subject { build(:usage_event) }

    # NOTE: event_id and timestamp have defaults set by before_validation callback,
    # which defeats shoulda-matchers validate_presence_of.
    it { is_expected.to validate_uniqueness_of(:event_id).scoped_to(:account_id) }
    it { is_expected.to validate_presence_of(:quantity) }
    it { is_expected.to validate_numericality_of(:quantity).is_greater_than_or_equal_to(0) }
    it do
      is_expected.to validate_inclusion_of(:source)
        .in_array(%w[api webhook system import internal])
        .allow_nil
    end
  end

  describe 'callbacks' do
    describe 'set_defaults' do
      it 'sets timestamp to current time when blank' do
        travel_to(Time.current) do
          event = build(:usage_event, timestamp: nil)
          event.valid?
          expect(event.timestamp).to be_within(1.second).of(Time.current)
        end
      end

      it 'sets event_id when blank' do
        event = build(:usage_event, event_id: nil)
        event.valid?
        expect(event.event_id).to be_present
      end

      it 'does not overwrite an existing timestamp' do
        specific_time = 2.hours.ago
        event = build(:usage_event, timestamp: specific_time)
        event.valid?
        expect(event.timestamp).to be_within(0.001).of(specific_time)
      end
    end
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let(:usage_meter) { create(:usage_meter) }

    describe '.unprocessed' do
      it 'returns only unprocessed events' do
        processed = create(:usage_event, :processed, account: account, usage_meter: usage_meter)
        unprocessed = create(:usage_event, account: account, usage_meter: usage_meter, is_processed: false)

        expect(UsageEvent.unprocessed).to include(unprocessed)
        expect(UsageEvent.unprocessed).not_to include(processed)
      end
    end

    describe '.processed' do
      it 'returns only processed events' do
        processed = create(:usage_event, :processed, account: account, usage_meter: usage_meter)
        unprocessed = create(:usage_event, account: account, usage_meter: usage_meter, is_processed: false)

        expect(UsageEvent.processed).to include(processed)
        expect(UsageEvent.processed).not_to include(unprocessed)
      end
    end

    describe '.for_period' do
      it 'returns events within the specified time period' do
        start_time = 2.days.ago
        end_time = 1.day.ago

        in_range = create(:usage_event, account: account, usage_meter: usage_meter, timestamp: 1.5.days.ago)
        before_range = create(:usage_event, account: account, usage_meter: usage_meter, timestamp: 3.days.ago)
        after_range = create(:usage_event, account: account, usage_meter: usage_meter, timestamp: Time.current)

        results = UsageEvent.for_period(start_time, end_time)

        expect(results).to include(in_range)
        expect(results).not_to include(before_range)
        expect(results).not_to include(after_range)
      end
    end

    describe '.for_meter' do
      it 'returns events for the specified meter' do
        other_meter = create(:usage_meter)
        meter_event = create(:usage_event, account: account, usage_meter: usage_meter)
        other_event = create(:usage_event, account: account, usage_meter: other_meter)

        expect(UsageEvent.for_meter(usage_meter)).to include(meter_event)
        expect(UsageEvent.for_meter(usage_meter)).not_to include(other_event)
      end
    end

    describe '.recent' do
      it 'returns events ordered by timestamp descending' do
        old = create(:usage_event, account: account, usage_meter: usage_meter, timestamp: 2.days.ago)
        recent = create(:usage_event, account: account, usage_meter: usage_meter, timestamp: 1.hour.ago)
        newest = create(:usage_event, account: account, usage_meter: usage_meter, timestamp: Time.current)

        results = UsageEvent.recent

        expect(results.first).to eq(newest)
        expect(results.last).to eq(old)
      end
    end
  end

  describe 'instance methods' do
    let(:usage_event) { create(:usage_event) }

    describe '#processed?' do
      it 'returns true when is_processed is true' do
        usage_event.update!(is_processed: true)
        expect(usage_event.processed?).to be true
      end

      it 'returns false when is_processed is false' do
        usage_event.update!(is_processed: false)
        expect(usage_event.processed?).to be false
      end
    end

    describe '#mark_processed!' do
      it 'sets is_processed to true and updates processed_at' do
        travel_to(Time.current) do
          usage_event.mark_processed!

          expect(usage_event.is_processed).to be true
          expect(usage_event.processed_at).to be_within(1.second).of(Time.current)
        end
      end

      it 'persists the changes to the database' do
        usage_event.mark_processed!
        usage_event.reload

        expect(usage_event.is_processed).to be true
        expect(usage_event.processed_at).not_to be_nil
      end
    end

    describe '#summary' do
      it 'returns a hash with event summary information' do
        summary = usage_event.summary

        expect(summary).to be_a(Hash)
        expect(summary[:id]).to eq(usage_event.id)
        expect(summary[:event_id]).to eq(usage_event.event_id)
        expect(summary[:quantity]).to eq(usage_event.quantity)
        expect(summary[:timestamp]).to eq(usage_event.timestamp)
        expect(summary[:source]).to eq(usage_event.source)
        expect(summary[:is_processed]).to eq(usage_event.is_processed)
        expect(summary[:properties]).to eq(usage_event.properties)
      end
    end
  end
end
