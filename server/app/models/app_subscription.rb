# frozen_string_literal: true

# Backward compatibility alias for Marketplace::Subscription
require_relative "marketplace/subscription"
AppSubscription = Marketplace::Subscription unless defined?(AppSubscription)
