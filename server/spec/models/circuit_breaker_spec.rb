# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Monitoring::CircuitBreaker, type: :model do
  describe 'associations' do
    it { should have_many(:circuit_breaker_events).dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:circuit_breaker) }

    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:service) }
    it { should validate_numericality_of(:failure_threshold).is_greater_than(0) }
    it { should validate_numericality_of(:success_threshold).is_greater_than(0) }
    it { should validate_numericality_of(:timeout_seconds).is_greater_than(0) }
    it { should validate_numericality_of(:reset_timeout_seconds).is_greater_than(0) }

    it 'validates state inclusion' do
      breaker = build(:circuit_breaker, state: 'invalid')
      expect(breaker).not_to be_valid
      expect(breaker.errors[:state]).to include('must be closed, open, or half_open')
    end

    it 'sets default state on create' do
      breaker = Monitoring::CircuitBreaker.new(name: 'test', service: 'test_service')
      breaker.valid?
      expect(breaker.state).to eq('closed')
    end

    context 'name uniqueness' do
      let!(:existing_breaker) { create(:circuit_breaker, name: 'test_breaker', service: 'ai_provider') }

      it 'validates uniqueness of name within service scope' do
        duplicate_breaker = build(:circuit_breaker, name: 'test_breaker', service: 'ai_provider')
        expect(duplicate_breaker).not_to be_valid
        expect(duplicate_breaker.errors[:name]).to include('has already been taken')
      end

      it 'allows same name for different services' do
        different_service = build(:circuit_breaker, name: 'test_breaker', service: 'payment_gateway')
        expect(different_service).to be_valid
      end
    end

    context 'configuration validation' do
      it 'validates configuration is a hash' do
        breaker = build(:circuit_breaker, configuration: 'invalid')
        expect(breaker).not_to be_valid
        expect(breaker.errors[:configuration]).to include('must be a hash')
      end

      it 'accepts valid configuration hash' do
        breaker = build(:circuit_breaker, configuration: { auto_reset: true })
        expect(breaker).to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:closed_breaker) { create(:circuit_breaker, :closed) }
    let!(:open_breaker) { create(:circuit_breaker, :open) }
    let!(:half_open_breaker) { create(:circuit_breaker, :half_open) }

    describe '.closed' do
      it 'returns only closed circuit breakers' do
        expect(Monitoring::CircuitBreaker.closed).to include(closed_breaker)
        expect(Monitoring::CircuitBreaker.closed).not_to include(open_breaker, half_open_breaker)
      end
    end

    describe '.open' do
      it 'returns only open circuit breakers' do
        expect(Monitoring::CircuitBreaker.open).to include(open_breaker)
        expect(Monitoring::CircuitBreaker.open).not_to include(closed_breaker, half_open_breaker)
      end
    end

    describe '.half_open' do
      it 'returns only half-open circuit breakers' do
        expect(Monitoring::CircuitBreaker.half_open).to include(half_open_breaker)
        expect(Monitoring::CircuitBreaker.half_open).not_to include(closed_breaker, open_breaker)
      end
    end

    describe '.for_service' do
      let!(:ai_breaker) { create(:circuit_breaker, service: 'ai_provider') }
      let!(:payment_breaker) { create(:circuit_breaker, service: 'payment_gateway') }

      it 'filters by service name' do
        expect(Monitoring::CircuitBreaker.for_service('ai_provider')).to include(ai_breaker)
        expect(Monitoring::CircuitBreaker.for_service('ai_provider')).not_to include(payment_breaker)
      end
    end

    describe '.healthy' do
      it 'returns closed circuit breakers' do
        expect(Monitoring::CircuitBreaker.healthy).to include(closed_breaker)
        expect(Monitoring::CircuitBreaker.healthy).not_to include(open_breaker, half_open_breaker)
      end
    end

    describe '.unhealthy' do
      it 'returns open and half-open circuit breakers' do
        expect(Monitoring::CircuitBreaker.unhealthy).to include(open_breaker, half_open_breaker)
        expect(Monitoring::CircuitBreaker.unhealthy).not_to include(closed_breaker)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'sets default values on create' do
        breaker = Monitoring::CircuitBreaker.new(name: 'test', service: 'test_service')
        breaker.valid?

        expect(breaker.state).to eq('closed')
        expect(breaker.failure_count).to eq(0)
        expect(breaker.success_count).to eq(0)
        expect(breaker.failure_threshold).to eq(5)
        expect(breaker.success_threshold).to eq(2)
      end
    end
  end

  describe 'state check methods' do
    describe '#closed?' do
      it 'returns true when state is closed' do
        breaker = build(:circuit_breaker, :closed)
        expect(breaker.closed?).to be true
      end

      it 'returns false when state is not closed' do
        breaker = build(:circuit_breaker, :open)
        expect(breaker.closed?).to be false
      end
    end

    describe '#open?' do
      it 'returns true when state is open' do
        breaker = build(:circuit_breaker, :open)
        expect(breaker.open?).to be true
      end
    end

    describe '#half_open?' do
      it 'returns true when state is half_open' do
        breaker = build(:circuit_breaker, :half_open)
        expect(breaker.half_open?).to be true
      end
    end
  end

  describe '#allow_request?' do
    it 'allows requests when circuit is closed' do
      breaker = create(:circuit_breaker, :closed)
      expect(breaker.allow_request?).to be true
    end

    it 'allows requests when circuit is half_open' do
      breaker = create(:circuit_breaker, :half_open)
      expect(breaker.allow_request?).to be true
    end

    it 'blocks requests when circuit is open' do
      breaker = create(:circuit_breaker, :open)
      expect(breaker.allow_request?).to be false
    end
  end

  describe '#record_success' do
    context 'when circuit is closed' do
      let(:breaker) { create(:circuit_breaker, :closed, failure_count: 3) }

      it 'resets failure count' do
        breaker.record_success
        expect(breaker.reload.failure_count).to eq(0)
      end

      it 'increments success count' do
        expect { breaker.record_success }.to change { breaker.reload.success_count }.by(1)
      end

      it 'updates last_success_at' do
        breaker.record_success
        expect(breaker.reload.last_success_at).to be_within(1.second).of(Time.current)
      end
    end

    context 'when circuit is half_open' do
      let(:breaker) { create(:circuit_breaker, :half_open, success_count: 1, success_threshold: 2) }

      it 'transitions to closed after reaching success threshold' do
        breaker.record_success
        expect(breaker.reload.state).to eq('closed')
      end

      it 'resets counters when transitioning to closed' do
        breaker.record_success
        reloaded = breaker.reload
        expect(reloaded.state).to eq('closed')
        expect(reloaded.failure_count).to eq(0)
        expect(reloaded.success_count).to eq(0)
      end
    end

    it 'creates a success event' do
      breaker = create(:circuit_breaker, :closed)
      expect { breaker.record_success(duration_ms: 100) }
        .to change { breaker.circuit_breaker_events.count }.by(1)

      event = breaker.circuit_breaker_events.last
      expect(event.event_type).to eq('success')
      expect(event.duration_ms).to eq(100)
    end
  end

  describe '#record_failure' do
    context 'when circuit is closed' do
      let(:breaker) { create(:circuit_breaker, :closed, failure_count: 4, failure_threshold: 5) }

      it 'opens circuit when failure threshold is reached' do
        breaker.record_failure(error_message: 'Test error')
        expect(breaker.reload.state).to eq('open')
      end

      it 'increments failure count' do
        breaker = create(:circuit_breaker, :closed, failure_count: 2)
        expect { breaker.record_failure }.to change { breaker.reload.failure_count }.by(1)
      end

      it 'updates last_failure_at' do
        breaker.record_failure
        expect(breaker.reload.last_failure_at).to be_within(1.second).of(Time.current)
      end
    end

    context 'when circuit is half_open' do
      let(:breaker) { create(:circuit_breaker, :half_open) }

      it 'reopens circuit on failure' do
        breaker.record_failure
        expect(breaker.reload.state).to eq('open')
      end
    end

    it 'creates a failure event' do
      breaker = create(:circuit_breaker, :closed)
      expect { breaker.record_failure(error_message: 'Test error', duration_ms: 5000) }
        .to change { breaker.circuit_breaker_events.count }.by(1)

      event = breaker.circuit_breaker_events.last
      expect(event.event_type).to eq('failure')
      expect(event.error_message).to eq('Test error')
    end
  end

  describe '#record_timeout' do
    it 'records failure with timeout message' do
      breaker = create(:circuit_breaker, :closed)
      breaker.record_timeout

      event = breaker.circuit_breaker_events.last
      expect(event.error_message).to eq('Request timeout exceeded')
    end
  end

  describe '#reset!' do
    it 'transitions to closed state' do
      breaker = create(:circuit_breaker, :open)
      breaker.reset!

      expect(breaker.reload.state).to eq('closed')
      expect(breaker.failure_count).to eq(0)
      expect(breaker.success_count).to eq(0)
    end
  end

  describe '#health_metrics' do
    let(:breaker) { create(:circuit_breaker, :closed) }

    before do
      create(:circuit_breaker_event, :success, circuit_breaker: breaker, created_at: 30.minutes.ago)
      create(:circuit_breaker_event, :failure, circuit_breaker: breaker, created_at: 20.minutes.ago)
    end

    it 'calculates health metrics' do
      metrics = breaker.health_metrics

      expect(metrics[:state]).to eq('closed')
      expect(metrics[:total_requests]).to eq(2)
      expect(metrics[:success_rate]).to eq(50.0)
      expect(metrics[:failure_rate]).to eq(50.0)
    end

    it 'returns default metrics when no events' do
      new_breaker = create(:circuit_breaker)
      metrics = new_breaker.health_metrics

      expect(metrics[:total_requests]).to eq(0)
      expect(metrics[:success_rate]).to eq(0.0)
    end
  end

  describe '#recent_events' do
    let(:breaker) { create(:circuit_breaker) }

    before do
      create_list(:circuit_breaker_event, 15, circuit_breaker: breaker)
    end

    it 'returns limited number of recent events' do
      events = breaker.recent_events(10)
      expect(events.count).to eq(10)
    end

    it 'orders events by created_at descending' do
      events = breaker.recent_events(5)
      expect(events.first.created_at).to be >= events.last.created_at
    end
  end
end
