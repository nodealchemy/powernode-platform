# frozen_string_literal: true

require "rails_helper"

# IMP 01a163c7-1ed8. Security::RateLimiter writes its counters through Powernode::Redis. The
# RateLimiting::BaseService readers and the admin tools read through Powernode::CacheRedis, which is
# the Redis behind Rails.cache and is nil whenever Rails.cache is not a Redis store (solid_cache in
# production), so in production they reported "nothing limited" about counters that were there.
#
# Real Redis (the lane's DB), no CacheRedis stub: write through the limiter, read back through every
# reader and every admin tool. Rails.cache stays the test memory store, which is the production shape
# as far as these readers are concerned (a cache store with no Redis behind it).
RSpec.describe RateLimiting::BaseService do
  let(:ip) { "203.0.113.77" }
  let(:other_ip) { "203.0.113.78" }
  let(:user_id) { "019f0000-0000-7000-8000-00000000abcd" }
  let(:account_id) { "019f0000-0000-7000-8000-0000000000ac" }
  let(:redis) { Powernode::Redis.pooled }

  def hit(times, category:, key:, account_id: nil)
    times.times do
      Security::RateLimiter.check!(key: key, category: category, account_id: account_id)
    rescue Security::RateLimiter::RateLimitExceeded
      nil
    end
  end

  before do
    expect(Rails.cache).not_to respond_to(:redis) # the production-shaped store: no Redis behind it
  end

  describe "readers over counters Security::RateLimiter wrote" do
    before do
      hit(10, category: :container_execute, key: "ip:#{ip}")       # at its limit of 10
      hit(3, category: :chat_send, key: "ip:#{ip}")                # under its limit of 30
      hit(2, category: :chat_send, key: "ip:#{other_ip}")
      hit(10, category: :container_execute, key: "user:#{user_id}", account_id: account_id)
    end

    it "#rate_limited? sees an IP at its limit, and not one under it" do
      expect(described_class.rate_limited?(ip)).to be(true)
      expect(described_class.rate_limited?(other_ip)).to be(false)
    end

    it "#rate_limited? sees an account-scoped user key" do
      expect(described_class.rate_limited?(user_id)).to be(true)
    end

    it "#get_limit_info reports each counter with its limit, remaining and window" do
      info = described_class.get_limit_info(ip)

      expect(info.keys).to contain_exactly("container_execute", "chat_send")
      expect(info["container_execute"]).to include(current: 10, limit: 10, remaining: 0)
      expect(info["chat_send"]).to include(current: 3, limit: 30, remaining: 27)
      expect(info["chat_send"][:reset_in]).to be_between(1, 60)
    end

    it "#count_current_violations counts the counters at their limit" do
      expect(described_class.send(:count_current_violations)).to eq(2)
    end

    it "#count_active_limits counts every live counter" do
      expect(described_class.send(:count_active_limits)).to eq(4)
    end

    it "#get_statistics carries those counts" do
      stats = described_class.get_statistics

      expect(stats).to include(current_violations: 2, active_limits: 4)
    end

    it "#clear_limits_for deletes exactly that identifier's counters" do
      expect(described_class.clear_limits_for(ip)).to eq(2)

      expect(described_class.get_limit_info(ip)).to eq({})
      expect(described_class.get_limit_info(other_ip).keys).to eq([ "chat_send" ])
    end

    it "#clear_limits_for reaches a user's account-scoped counter" do
      expect(described_class.clear_limits_for(user_id)).to eq(1)
      expect(described_class.rate_limited?(user_id)).to be(false)
    end
  end

  describe "the key shape" do
    it "is built by one builder that the writer uses" do
      Security::RateLimiter.check!(key: "ip:#{ip}", category: :chat_send, account_id: account_id)

      built = Security::RateLimitKey.build(category: :chat_send, key: "ip:#{ip}", account_id: account_id)
      expect(redis.get(built)).to eq("1")
    end

    it "round-trips through parse" do
      built = Security::RateLimitKey.build(category: :chat_send, key: "ip:#{ip}", account_id: account_id)

      expect(Security::RateLimitKey.parse(built)).to eq(category: "chat_send", account_id: account_id, subject: "ip:#{ip}")
    end

    it "refuses an identifier that is not an IP, a numeric id or a UUID" do
      expect { described_class.clear_limits_for("*") }.to raise_error(ArgumentError)
    end
  end

  describe "a store with no Redis" do
    before { allow(Powernode::Redis).to receive(:with).and_raise(Redis::CannotConnectError, "down") }

    it "raises UnsupportedStore from every reader instead of answering empty" do
      expect { described_class.rate_limited?(ip) }.to raise_error(RateLimiting::UnsupportedStore)
      expect { described_class.get_limit_info(ip) }.to raise_error(RateLimiting::UnsupportedStore)
      expect { described_class.clear_limits_for(ip) }.to raise_error(RateLimiting::UnsupportedStore)
      expect { described_class.send(:count_current_violations) }.to raise_error(RateLimiting::UnsupportedStore)
    end

    it "#get_statistics says unsupported store and carries no counts" do
      stats = described_class.get_statistics

      expect(stats).to include(supported: false, error: "unsupported store")
      expect(stats).not_to have_key(:current_violations)
      expect(stats).not_to have_key(:active_limits)
    end
  end

  describe RateLimiting::TieredService do
    it "does not invent a reset time for a counter its store cannot give a TTL for" do
      request = instance_double(ActionDispatch::Request, path: "/api/v1/things", request_method: "GET", ip: ip)
      allow(described_class).to receive(:determine_tier).and_return(:free)
      allow(described_class).to receive(:get_limit).and_return(100)

      info = described_class.remaining_requests(request)

      expect(info[:reset_at]).to be_nil
    end
  end
end

RSpec.describe "Admin rate limiting: violations over real Redis", type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, account: account, permissions: [ "admin.settings.security" ]) }
  let(:headers) { auth_headers_for(admin_user) }

  before do
    allow_any_instance_of(Api::V1::Admin::RateLimiting::RateLimitingController)
      .to receive(:current_account).and_return(account)
  end

  it "lists a counter Security::RateLimiter wrote" do
    10.times { Security::RateLimiter.check!(key: "ip:203.0.113.77", category: :container_execute) }

    get "/api/v1/admin/rate_limiting/violations", headers: headers, as: :json

    expect_success_response
    violations = json_response_data["violations"]
    expect(violations.size).to eq(1)
    expect(violations.first).to include("endpoint" => "container_execute", "identifier" => "ip:203.0.113.77", "count" => 10, "limit" => 10)
  end

  it "says unsupported store when Redis is unreachable" do
    allow(Powernode::Redis).to receive(:with).and_raise(Redis::CannotConnectError, "down")

    get "/api/v1/admin/rate_limiting/violations", headers: headers, as: :json

    expect(response).to have_http_status(:service_unavailable)
    expect(json_response["error"]).to eq("unsupported store")
  end
end
