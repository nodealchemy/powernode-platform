# frozen_string_literal: true

require "rails_helper"

# Rate-limit counters must be atomic and keep a fixed window.
#
# Both counters used read-then-write: read the count, then write count + 1
# with a fresh expires_in. On a store shared by several processes two
# requests that read the same count wrote the same count + 1, so an attempt
# was lost, and every write restarted the window, so a steady trickle of
# attempts never aged out. Rails.cache.increment(key, 1, expires_in:) is
# atomic in every store we run (MemoryStore, SolidCache, Redis) and keeps an
# existing entry's expiry, so the window is fixed from the first attempt.
RSpec.describe "rate-limit counter atomicity" do
  # Holds every read long enough for a second thread to read the same value,
  # which is the interleaving read-then-write loses an update under.
  # Named: ActiveSupport's local cache keys itself on the store class's name.
  let(:slow_read_store) do
    stub_const("SlowReadMemoryStore", Class.new(ActiveSupport::Cache::MemoryStore) do
      def read(*args, **kwargs)
        value = super
        sleep 0.05
        value
      end
    end).new
  end

  let(:store) { ActiveSupport::Cache::MemoryStore.new }

  def read_count(key)
    Rails.cache.read_counter(key).to_i
  end

  describe RateLimiting do
    let(:controller_class) do
      Class.new(ActionController::API) do
        include RateLimiting

        attr_reader :limited

        def render_error(*, **)
          @limited = true
        end

        private

        def should_rate_limit? = true
        def rate_limit_key = "rate_limit:counter_spec:198.51.100.21"
      end
    end

    before { allow(Rails).to receive(:cache).and_return(store) }

    it "loses no attempt when two requests read the same count before either increments" do
      first = controller_class.new
      second = controller_class.new
      first.send(:check_and_increment_rate_limit)
      second.send(:check_and_increment_rate_limit)

      first.send(:increment_rate_limit_count)
      second.send(:increment_rate_limit_count)

      expect(read_count("rate_limit:counter_spec:198.51.100.21")).to eq(2)
    end

    it "keeps a fixed window: a later attempt does not extend the first one's expiry" do
      window = controller_class.new.send(:rate_limit_window_seconds)
      controller = controller_class.new
      controller.send(:check_and_increment_rate_limit)
      controller.send(:increment_rate_limit_count)

      travel(window - 10) do
        later = controller_class.new
        later.send(:check_and_increment_rate_limit)
        later.send(:increment_rate_limit_count)
      end

      travel(window + 1) do
        expect(read_count("rate_limit:counter_spec:198.51.100.21")).to eq(0)
      end
    end
  end

  describe RateLimiting::TieredService do
    let(:key) { "tiered_rate:ip:198.51.100.22:api:minute" }

    it "loses no increment under two concurrent threads" do
      allow(Rails).to receive(:cache).and_return(slow_read_store)

      Array.new(2) { Thread.new { described_class.send(:increment_counter, key, 60) } }.each(&:join)

      expect(described_class.send(:get_counter, key)).to eq(2)
    end

    it "keeps a fixed window from the first increment" do
      allow(Rails).to receive(:cache).and_return(store)
      described_class.send(:increment_counter, key, 60)
      travel(40) { described_class.send(:increment_counter, key, 60) }

      travel(61) { expect(described_class.send(:get_counter, key)).to eq(0) }
    end
  end
end
