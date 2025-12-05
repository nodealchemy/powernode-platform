# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CircuitBreakerEvent, type: :model do
  describe 'associations' do
    it { should belong_to(:circuit_breaker) }
  end

  describe 'validations' do
    it { should validate_presence_of(:event_type) }

    it 'validates event_type inclusion' do
      event = build(:circuit_breaker_event, event_type: 'invalid')
      expect(event).not_to be_valid
      expect(event.errors[:event_type]).to include('must be a valid event type')
    end
  end

  describe 'scopes' do
    let(:breaker) { create(:circuit_breaker) }
    let!(:success_event) { create(:circuit_breaker_event, :success, circuit_breaker: breaker) }
    let!(:failure_event) { create(:circuit_breaker_event, :failure, circuit_breaker: breaker) }
    let!(:timeout_event) { create(:circuit_breaker_event, :timeout, circuit_breaker: breaker) }
    let!(:state_change_event) { create(:circuit_breaker_event, :state_change, circuit_breaker: breaker) }

    describe '.successes' do
      it 'returns only success events' do
        expect(CircuitBreakerEvent.successes).to include(success_event)
        expect(CircuitBreakerEvent.successes).not_to include(failure_event, timeout_event)
      end
    end

    describe '.failures' do
      it 'returns only failure events' do
        expect(CircuitBreakerEvent.failures).to include(failure_event)
        expect(CircuitBreakerEvent.failures).not_to include(success_event, timeout_event)
      end
    end

    describe '.timeouts' do
      it 'returns only timeout events' do
        expect(CircuitBreakerEvent.timeouts).to include(timeout_event)
        expect(CircuitBreakerEvent.timeouts).not_to include(success_event, failure_event)
      end
    end

    describe '.state_changes' do
      it 'returns only state change events' do
        expect(CircuitBreakerEvent.state_changes).to include(state_change_event)
        expect(CircuitBreakerEvent.state_changes).not_to include(success_event, failure_event)
      end
    end

    describe '.recent' do
      let!(:old_event) { create(:circuit_breaker_event, circuit_breaker: breaker, created_at: 2.hours.ago) }
      let!(:recent_event) { create(:circuit_breaker_event, circuit_breaker: breaker, created_at: 30.minutes.ago) }

      it 'returns events from specified time period' do
        results = CircuitBreakerEvent.recent(1.hour)
        expect(results).to include(recent_event)
        expect(results).not_to include(old_event)
      end
    end

    describe '.for_circuit_breaker' do
      let(:other_breaker) { create(:circuit_breaker) }
      let!(:other_event) { create(:circuit_breaker_event, circuit_breaker: other_breaker) }

      it 'filters events by circuit breaker' do
        results = CircuitBreakerEvent.for_circuit_breaker(breaker.id)
        expect(results).to include(success_event)
        expect(results).not_to include(other_event)
      end
    end
  end

  describe 'type check methods' do
    describe '#success?' do
      it 'returns true for success events' do
        event = build(:circuit_breaker_event, :success)
        expect(event.success?).to be true
      end

      it 'returns false for non-success events' do
        event = build(:circuit_breaker_event, :failure)
        expect(event.success?).to be false
      end
    end

    describe '#failure?' do
      it 'returns true for failure events' do
        event = build(:circuit_breaker_event, :failure)
        expect(event.failure?).to be true
      end
    end

    describe '#timeout?' do
      it 'returns true for timeout events' do
        event = build(:circuit_breaker_event, :timeout)
        expect(event.timeout?).to be true
      end
    end

    describe '#state_change?' do
      it 'returns true for state change events' do
        event = build(:circuit_breaker_event, :state_change)
        expect(event.state_change?).to be true
      end
    end
  end
end
