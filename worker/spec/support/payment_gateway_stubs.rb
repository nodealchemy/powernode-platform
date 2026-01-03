# frozen_string_literal: true

# Mock Stripe module for tests when stripe gem is not available
module Stripe
  class StripeError < StandardError; end
  class APIConnectionError < StripeError; end
  class APIError < StripeError; end
  class InvalidRequestError < StripeError; end
  class RateLimitError < StripeError; end
  class AuthenticationError < StripeError; end

  class Charge
    def self.list(_options = {})
      MockStripeCollection.new([])
    end
  end

  class PaymentIntent
    def self.list(_options = {})
      MockStripeCollection.new([])
    end
  end
end

# Mock collection that supports auto_paging_each
class MockStripeCollection
  def initialize(items)
    @items = items
  end

  def auto_paging_each(&block)
    @items.each(&block) if block_given?
    @items.each
  end

  def each(&block)
    @items.each(&block)
  end
end

# Helper methods for setting up Stripe mocks in tests
module StripeTestHelpers
  def stub_stripe_charges(charges_data = [])
    mock_collection = MockStripeCollection.new(
      charges_data.map { |c| OpenStruct.new(c) }
    )
    allow(Stripe::Charge).to receive(:list).and_return(mock_collection)
  end

  def stub_stripe_api_error(error_class = Stripe::APIConnectionError, message = 'Connection failed')
    allow(Stripe::Charge).to receive(:list).and_raise(error_class.new(message))
  end
end

RSpec.configure do |config|
  config.include StripeTestHelpers
end
