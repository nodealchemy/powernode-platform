# frozen_string_literal: true

# Ai::ModelTiers memoizes a DB-backed price index in a process-level cache with a
# TTL (cheap classify() in scoring loops). Reset it before every example so a
# pricing row created in one spec can never leak into another via the cache.
RSpec.configure do |config|
  config.before(:each) do
    Ai::ModelTiers.reset_price_cache! if defined?(Ai::ModelTiers)
  end
end
