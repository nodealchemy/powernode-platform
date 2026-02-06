# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Introspection::RateLimiter do
  let(:mock_redis) { instance_double(Redis) }
  let(:agent_id) { SecureRandom.uuid }

  before do
    allow(Redis).to receive(:new).and_return(mock_redis)
    # Reset memoized redis instance between tests
    described_class.instance_variable_set(:@redis, nil)
  end

  describe "constants" do
    it "has a default max calls of 10" do
      expect(described_class::DEFAULT_MAX_CALLS).to eq(10)
    end

    it "has a default window of 60 seconds" do
      expect(described_class::DEFAULT_WINDOW_SECONDS).to eq(60)
    end

    it "has a redis namespace" do
      expect(described_class::REDIS_NAMESPACE).to eq("introspection_rate_limit")
    end
  end

  describe ".check!" do
    context "when within rate limits" do
      it "returns remaining calls and reset window" do
        allow(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([nil, nil, 5, nil])
        allow(mock_redis).to receive(:zremrangebyscore)
        allow(mock_redis).to receive(:zadd)
        allow(mock_redis).to receive(:zcard)
        allow(mock_redis).to receive(:expire)

        result = described_class.check!(agent_id: agent_id)

        expect(result[:remaining]).to eq(5)
        expect(result[:reset_in]).to eq(60)
      end

      it "accepts custom max_calls and window parameters" do
        allow(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([nil, nil, 3, nil])
        allow(mock_redis).to receive(:zremrangebyscore)
        allow(mock_redis).to receive(:zadd)
        allow(mock_redis).to receive(:zcard)
        allow(mock_redis).to receive(:expire)

        result = described_class.check!(agent_id: agent_id, max_calls: 20, window: 120)

        expect(result[:remaining]).to eq(17)
        expect(result[:reset_in]).to eq(120)
      end

      it "records the call in the sorted set" do
        pipeline = mock_redis
        allow(mock_redis).to receive(:multi).and_yield(pipeline).and_return([nil, nil, 1, nil])

        expect(pipeline).to receive(:zremrangebyscore).with(anything, "-inf", anything)
        expect(pipeline).to receive(:zadd).with(anything, anything, anything)
        expect(pipeline).to receive(:zcard).with(anything)
        expect(pipeline).to receive(:expire).with(anything, 60)

        described_class.check!(agent_id: agent_id)
      end
    end

    context "when exceeding rate limits" do
      it "raises RateLimitExceeded error" do
        allow(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([nil, nil, 11, nil])
        allow(mock_redis).to receive(:zremrangebyscore)
        allow(mock_redis).to receive(:zadd)
        allow(mock_redis).to receive(:zcard)
        allow(mock_redis).to receive(:expire)
        allow(mock_redis).to receive(:zrem)
        allow(mock_redis).to receive(:zrange).and_return([[agent_id, Time.current.to_f - 30]])

        expect {
          described_class.check!(agent_id: agent_id)
        }.to raise_error(Ai::Introspection::RateLimiter::RateLimitExceeded)
      end

      it "includes retry_after in the error" do
        now = Time.current.to_f
        allow(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([nil, nil, 11, nil])
        allow(mock_redis).to receive(:zremrangebyscore)
        allow(mock_redis).to receive(:zadd)
        allow(mock_redis).to receive(:zcard)
        allow(mock_redis).to receive(:expire)
        allow(mock_redis).to receive(:zrem)
        allow(mock_redis).to receive(:zrange).and_return([["entry", now - 30]])

        begin
          described_class.check!(agent_id: agent_id)
          fail "Expected RateLimitExceeded to be raised"
        rescue Ai::Introspection::RateLimiter::RateLimitExceeded => e
          expect(e.retry_after).to be_a(Integer)
          expect(e.retry_after).to be >= 1
        end
      end

      it "removes the speculatively added entry" do
        allow(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([nil, nil, 11, nil])
        allow(mock_redis).to receive(:zremrangebyscore)
        allow(mock_redis).to receive(:zadd)
        allow(mock_redis).to receive(:zcard)
        allow(mock_redis).to receive(:expire)
        allow(mock_redis).to receive(:zrange).and_return([["entry", Time.current.to_f]])

        expect(mock_redis).to receive(:zrem)

        expect {
          described_class.check!(agent_id: agent_id)
        }.to raise_error(Ai::Introspection::RateLimiter::RateLimitExceeded)
      end

      it "defaults retry_after to window when no oldest entry" do
        allow(mock_redis).to receive(:multi).and_yield(mock_redis).and_return([nil, nil, 11, nil])
        allow(mock_redis).to receive(:zremrangebyscore)
        allow(mock_redis).to receive(:zadd)
        allow(mock_redis).to receive(:zcard)
        allow(mock_redis).to receive(:expire)
        allow(mock_redis).to receive(:zrem)
        allow(mock_redis).to receive(:zrange).and_return([])

        begin
          described_class.check!(agent_id: agent_id)
          fail "Expected RateLimitExceeded to be raised"
        rescue Ai::Introspection::RateLimiter::RateLimitExceeded => e
          expect(e.retry_after).to eq(60)
        end
      end
    end

    it "uses the correct redis key" do
      pipeline = mock_redis
      expected_key = "introspection_rate_limit:#{agent_id}"

      allow(mock_redis).to receive(:multi).and_yield(pipeline).and_return([nil, nil, 1, nil])
      expect(pipeline).to receive(:zremrangebyscore).with(expected_key, anything, anything)
      expect(pipeline).to receive(:zadd).with(expected_key, anything, anything)
      expect(pipeline).to receive(:zcard).with(expected_key)
      expect(pipeline).to receive(:expire).with(expected_key, anything)

      described_class.check!(agent_id: agent_id)
    end
  end

  describe ".remaining" do
    it "returns number of remaining calls" do
      allow(mock_redis).to receive(:zremrangebyscore)
      allow(mock_redis).to receive(:zcard).and_return(3)

      result = described_class.remaining(agent_id: agent_id)

      expect(result).to eq(7)
    end

    it "never returns negative remaining" do
      allow(mock_redis).to receive(:zremrangebyscore)
      allow(mock_redis).to receive(:zcard).and_return(15)

      result = described_class.remaining(agent_id: agent_id)

      expect(result).to eq(0)
    end

    it "accepts custom max_calls and window" do
      allow(mock_redis).to receive(:zremrangebyscore)
      allow(mock_redis).to receive(:zcard).and_return(5)

      result = described_class.remaining(agent_id: agent_id, max_calls: 20, window: 120)

      expect(result).to eq(15)
    end

    it "cleans expired entries before counting" do
      expect(mock_redis).to receive(:zremrangebyscore).with(anything, "-inf", anything)
      allow(mock_redis).to receive(:zcard).and_return(0)

      described_class.remaining(agent_id: agent_id)
    end
  end

  describe ".reset!" do
    it "deletes the rate limit key" do
      expected_key = "introspection_rate_limit:#{agent_id}"

      expect(mock_redis).to receive(:del).with(expected_key)

      described_class.reset!(agent_id: agent_id)
    end
  end

  describe Ai::Introspection::RateLimiter::RateLimitExceeded do
    it "includes retry_after in the message" do
      error = described_class.new(retry_after: 30)

      expect(error.message).to include("30 seconds")
      expect(error.retry_after).to eq(30)
    end

    it "is a StandardError" do
      error = described_class.new(retry_after: 10)

      expect(error).to be_a(StandardError)
    end
  end
end
