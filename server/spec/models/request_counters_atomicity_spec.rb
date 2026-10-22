# frozen_string_literal: true

require "rails_helper"

# Three more plain request counters used read-then-write (read the count,
# write count + 1 with a fresh expires_in): concurrent requests lost
# increments on a shared store, and every request restarted the window, so a
# steady caller never aged out. Each now uses Rails.cache.increment with
# expires_in, which keeps an existing entry's expiry (a fixed window).
RSpec.describe "request counters are atomic with a fixed window" do
  let(:store) { ActiveSupport::Cache::MemoryStore.new }

  before { allow(Rails).to receive(:cache).and_return(store) }

  # Count once at t0 and once just before the window ends; just after the
  # window the counter must be gone (read-then-write had reset it to a full
  # window at the second count).
  def expect_fixed_window(window)
    yield
    travel(window - 10.seconds) { yield }
    travel(window + 1.second) { expect(Rails.cache.read_counter(@key).to_i).to eq(0) }
  end

  it "FederationPartner#increment_request_count!" do
    partner = create(:federation_partner, :active)
    @key = partner.rate_limit_key

    expect_fixed_window(1.hour) { partner.increment_request_count! }
  end

  it "Chat::Channel#increment_rate_counter!" do
    channel = create(:chat_channel)
    @key = channel.rate_limit_key

    expect_fixed_window(1.minute) { channel.increment_rate_counter! }
  end

  it "Audit::LoggingService rate limiting" do
    service = Audit::LoggingService.instance
    allow(Rails.env).to receive(:test?).and_return(false)
    @key = "audit_log:login:198.51.100.5"

    expect_fixed_window(1.hour) { service.send(:should_rate_limit?, "login", nil, "198.51.100.5") }
  end

  it "Audit::LoggingService still allows exactly the limit, then limits" do
    service = Audit::LoggingService.instance
    allow(Rails.env).to receive(:test?).and_return(false)

    results = Array.new(6) { service.send(:should_rate_limit?, "admin_delete", nil, "198.51.100.6") }

    expect(results).to eq([ false, false, false, false, false, true ])
  end
end
