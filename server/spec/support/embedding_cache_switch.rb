# frozen_string_literal: true

# Test-env switch for Ai::Memory::EmbeddingService's Redis cache (`ai:embeddings:<account>:<sha>`,
# CACHE_TTL 7 days). Every example creates its own account, so the key never repeats and is
# never read back, yet each write is ~32 KB: a 16-process run held 112 MB in one lane and
# peaked the test Redis at 1.51 GB of a 2 GB noeviction maxmemory. Specs therefore SKIP the
# cache read and write by default (same shape as AccountBootstrapSwitch).
#
# Opt in where a spec exercises the caching:
#   it "...", :embedding_cache do               # one example (wraps its let!/before too)
#   describe "...", :embedding_cache do         # a group, incl. its before_all
#   with_embedding_cache { service.generate("x") } # just the calls in the block
#
# Scope: test env only. app/services/ai/memory/embedding_service.rb is unchanged; the gate is
# prepended from here, so production caching and TTL are untouched. Explicit
# `use_cache: false` is still honoured; the gate can only turn caching off, never on.
# The gate wraps the Redis client (GET misses, SETEX dropped) instead of prepending #generate, because
# RSpec's allow_any_instance_of cannot stub a method defined on a prepended module.
#
# Thread safety: a per-process, mutex-guarded depth counter (parallel_tests = one process per
# lane). Process-wide on purpose so helper threads inside a tagged example also cache. Every
# enable is paired with a disable in an ensure / after hook; an unbalanced disable raises.
module EmbeddingCacheSwitch
  MUTEX = Mutex.new
  @depth = 0

  class << self
    def enabled?
      @depth.positive?
    end

    def enable!
      MUTEX.synchronize { @depth += 1 }
    end

    def disable!
      MUTEX.synchronize do
        raise "EmbeddingCacheSwitch.disable! without a matching enable! (unbalanced switch)" unless @depth.positive?

        @depth -= 1
      end
    end

    def with_cache
      enable!
      yield
    ensure
      disable!
    end
  end

  # Wraps the service's Redis client. While the switch is off, the cache read (GET) misses and the
  # cache write (SETEX) is dropped; everything else (del, scan_each, ...) is forwarded untouched.
  # Gating the client rather than #generate / #generate_batch keeps those methods un-prepended,
  # so `allow_any_instance_of(EmbeddingService).to receive(:generate)` keeps working.
  class GatedRedis < BasicObject
    def initialize(client)
      @client = client
    end

    def get(*args, **kwargs, &)
      return nil unless ::EmbeddingCacheSwitch.enabled?

      @client.get(*args, **kwargs, &)
    end

    def setex(*args, **kwargs, &)
      return "OK" unless ::EmbeddingCacheSwitch.enabled?

      @client.setex(*args, **kwargs, &)
    end

    def method_missing(name, *args, **kwargs, &)
      @client.__send__(name, *args, **kwargs, &)
    end

    def respond_to_missing?(name, include_private = false) # rubocop:disable Style/OptionalBooleanParameter
      @client.respond_to?(name, include_private)
    end
  end

  # Prepended into Ai::Memory::EmbeddingService; swaps @redis for the gated wrapper.
  module Gate
    def initialize(*, **)
      super
      @redis = GatedRedis.new(@redis)
    end
  end

  module Helpers
    def with_embedding_cache(&)
      EmbeddingCacheSwitch.with_cache(&)
    end
  end
end

Ai::Memory::EmbeddingService.prepend(EmbeddingCacheSwitch::Gate)

RSpec.configure do |config|
  config.include EmbeddingCacheSwitch::Helpers

  config.around(:example, embedding_cache: true) do |example|
    EmbeddingCacheSwitch.with_cache { example.run }
  end

  config.before(:context, embedding_cache: true) { EmbeddingCacheSwitch.enable! }
  config.after(:context, embedding_cache: true) { EmbeddingCacheSwitch.disable! }
end
