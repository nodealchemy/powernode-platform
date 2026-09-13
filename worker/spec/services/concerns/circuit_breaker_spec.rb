# frozen_string_literal: true

require 'rails_helper'

# D1 re-verify: the shared backend_api breaker wraps every call in its own
# Timeout.timeout, so a caller's longer per-request timeout was cut short at the
# breaker's default. The per-call override is pinned on both arms: it lifts the
# bound for the one call that asks, and every other call keeps the default.
RSpec.describe CircuitBreaker::CircuitBreakerService do
  let(:breaker) { described_class.new('spec_breaker', timeout: 1) }

  it 'cuts a call off at its own bound when no override is given' do
    expect { breaker.call { sleep 1.5 } }.to raise_error(Timeout::Error)
  end

  it 'lets one call run past the default bound when it passes a longer timeout' do
    expect(breaker.call(timeout: 3) { sleep 1.5; :finished }).to eq(:finished)
  end

  it 'still bounds an overridden call by the override' do
    expect { breaker.call(timeout: 1) { sleep 1.5 } }.to raise_error(Timeout::Error)
  end
end
