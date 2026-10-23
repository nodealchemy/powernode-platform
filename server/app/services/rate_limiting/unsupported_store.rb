# frozen_string_literal: true

module RateLimiting
  # Raised by the rate-limit readers and admin tools when the Redis that holds the counters cannot be
  # reached. The answer is "I cannot tell", never "nothing is limited": an empty result would read as
  # a healthy, idle limiter.
  class UnsupportedStore < StandardError
    MESSAGE = "unsupported store"

    def initialize(message = MESSAGE)
      super
    end
  end
end
