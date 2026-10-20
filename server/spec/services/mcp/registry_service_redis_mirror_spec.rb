# frozen_string_literal: true

require "rails_helper"

# IMP-3fdaa94f6327. Mcp::RegistryService mirrors every registered manifest into
# the `mcp:registry:<account|global>` hash and every health mark into
# `mcp:health:<account|global>`. Both used to be bare HSETs: no TTL, and no
# teardown, so each account's pair outlived the account (the 2026-08-17 leak
# class; see config/initializers/redis.rb) and the global hash only grew.
#
# These run against the lane's real Redis (Powernode::Redis.client), not a
# double: the property under test IS the TTL Redis holds.
RSpec.describe Mcp::RegistryService, "Redis mirror lifetime" do
  let(:redis) { Powernode::Redis.client }
  let(:account) { create(:account) }
  let(:registry_key) { "mcp:registry:#{account.id}" }
  let(:health_key) { "mcp:health:#{account.id}" }

  def manifest(name)
    {
      "name" => name,
      "description" => "ttl fixture",
      "type" => "function",
      "version" => "1.0.0",
      "inputSchema" => { "type" => "object", "properties" => {} },
      "outputSchema" => { "type" => "object", "properties" => {} }
    }
  end

  # Positive first, so a key with no TTL (-1) fails on that, not on the bound.
  def expect_mirror_ttl(key)
    ttl = redis.ttl(key)
    expect(ttl).to be_positive, "#{key} has TTL #{ttl} (-1 = never expires)"
    expect(ttl).to be <= described_class::REDIS_MIRROR_TTL.to_i
  end

  after { redis.del(registry_key, health_key, "mcp:registry:global", "mcp:health:global") }

  describe "a write" do
    it "leaves the account's registry and health hashes with a TTL" do
      described_class.new(account: account).register_tool("ttl_tool_v1_0_0", manifest("ttl-tool"))

      expect(redis.hexists(registry_key, "ttl_tool_v1_0_0")).to be(true)
      expect_mirror_ttl(registry_key)
      expect_mirror_ttl(health_key)
    end

    it "gives the global hashes a TTL too" do
      described_class.new(account: nil).register_tool("ttl_tool_v1_0_0", manifest("ttl-tool"))

      expect_mirror_ttl("mcp:registry:global")
      expect_mirror_ttl("mcp:health:global")
    end

    it "refreshes the TTL of a hash that already exists" do
      redis.hset(registry_key, "older", "{}")
      redis.expire(registry_key, 5)

      described_class.new(account: account).register_tool("ttl_tool_v1_0_0", manifest("ttl-tool"))

      expect(redis.ttl(registry_key)).to be > 5
    end

    it "heals a pre-existing hash that was written with no TTL" do
      redis.hset(health_key, "older", "{}")
      expect(redis.ttl(health_key)).to eq(-1)

      described_class.new(account: account).mark_tool_unhealthy("older", "boom")

      expect_mirror_ttl(health_key)
    end
  end

  describe ".purge_account!" do
    it "deletes both of the account's hashes and leaves other accounts alone" do
      other = create(:account)
      described_class.new(account: account).register_tool("ttl_tool_v1_0_0", manifest("ttl-tool"))
      described_class.new(account: other).register_tool("ttl_tool_v1_0_0", manifest("ttl-tool"))

      described_class.purge_account!(account.id)

      expect(redis.exists?(registry_key, health_key)).to be(false)
      expect(redis.exists?("mcp:registry:#{other.id}")).to be(true)
    ensure
      redis.del("mcp:registry:#{other.id}", "mcp:health:#{other.id}") if other
    end
  end

  describe "account teardown" do
    # The worker completes a termination by PATCHing status "completed" through
    # Api::V1::Internal::AccountTerminationsController (a plain update!), and
    # Account::Termination#complete! reaches the same after_update, so the
    # status change is the one seam both paths cross. The account row is kept
    # (it is cancelled, not destroyed). Account#destroy is not a teardown path
    # in this codebase: nothing in app/ calls it, and it fails even on a bare
    # account (the default Ai::Environment refuses to be destroyed).
    it "removes the account's keys when its termination completes" do
      allow(NotificationService).to receive(:send_email)
      owner = create(:user, account: account)
      described_class.new(account: account).register_tool("ttl_tool_v1_0_0", manifest("ttl-tool"))
      termination = Account::Termination.create!(account: account, requested_by: owner, status: "processing",
                                                 processing_started_at: Time.current)

      termination.update!(status: "completed", completed_at: Time.current)

      expect(redis.exists?(registry_key, health_key)).to be(false)
    end

    it "removes them through Account::Termination#complete! too" do
      allow(NotificationService).to receive(:send_email)
      owner = create(:user, account: account)
      described_class.new(account: account).register_tool("ttl_tool_v1_0_0", manifest("ttl-tool"))
      termination = Account::Termination.create!(account: account, requested_by: owner, status: "processing",
                                                 processing_started_at: Time.current)

      termination.complete!(owner)

      expect(redis.exists?(registry_key, health_key)).to be(false)
    end

    it "leaves them alone on a status change that is not completion" do
      allow(NotificationService).to receive(:send_email)
      owner = create(:user, account: account)
      described_class.new(account: account).register_tool("ttl_tool_v1_0_0", manifest("ttl-tool"))
      termination = Account::Termination.create!(account: account, requested_by: owner, status: "pending")

      termination.update!(status: "grace_period")

      expect(redis.exists?(registry_key)).to be(true)
    end
  end
end
