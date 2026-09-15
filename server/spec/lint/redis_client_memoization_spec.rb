# frozen_string_literal: true

require "rails_helper"

# IMP-1cec0fdb8628. Powernode::Redis.client is already the process-wide memo
# (config/initializers/redis.rb). A service that caches it AGAIN in its own
# `@redis ||=` holds a second copy that nothing else can reach:
#
#   * in the suite, whatever client was stubbed the first time the service was
#     touched stays there for every later example. Ai::Introspection::RateLimiter
#     kept rate_limiter_spec's instance_double(Redis), so the three
#     gitea_actions_tool_mcp_disclosure_spec examples, which reach the limiter
#     through McpPlatformToolRegistrar#guard_call!, failed with "leaked double"
#     in full-suite order and passed in isolation;
#   * in production, Powernode::Redis.reconfigure! closes and drops the shared
#     client, while each private copy keeps the closed one.
RSpec.describe "Powernode::Redis.client is never memoized a second time" do
  let(:app_root) { Rails.root.join("app") }
  let(:memo_pattern) { /@\w+\s*\|\|=\s*(?:::)?Powernode::Redis\.client\b/ }

  it "finds the services that use the shared client, so the scan below cannot pass vacuously" do
    users = Dir.glob(app_root.join("**", "*.rb")).select { |f| File.read(f).include?("Powernode::Redis.client") }

    expect(users.length).to be >= 8
  end

  it "has no app file caching Powernode::Redis.client in its own instance variable" do
    offenders = Dir.glob(app_root.join("**", "*.rb")).flat_map do |file|
      File.readlines(file).each_with_index.filter_map do |line, index|
        "#{Pathname(file).relative_path_from(Rails.root)}:#{index + 1}" if line.match?(memo_pattern)
      end
    end

    expect(offenders).to be_empty,
      "these cache the already-memoized client, so a stub or a reconfigure! never reaches them: " \
      "#{offenders.join(', ')}"
  end

  # The finding's own path, in the order that broke it: one example stubs the
  # client and touches the limiter, the next expects the real client.
  describe Ai::Introspection::RateLimiter, order: :defined do
    it "uses a client stubbed for this example" do
      stubbed = instance_double(Redis)
      allow(Powernode::Redis).to receive(:client).and_return(stubbed)

      expect(described_class.send(:redis)).to equal(stubbed)
    end

    it "does not keep the previous example's stubbed client" do
      expect(described_class.send(:redis)).to equal(Powernode::Redis.client)
    end

    it "follows Powernode::Redis.reconfigure! instead of keeping the closed client" do
      before_reconfigure = described_class.send(:redis)
      Powernode::Redis.reconfigure!

      expect(described_class.send(:redis)).not_to equal(before_reconfigure)
      expect(described_class.send(:redis)).to equal(Powernode::Redis.client)
    end
  end
end
