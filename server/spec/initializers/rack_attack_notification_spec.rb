# frozen_string_literal: true

require "rails_helper"

# The "rack.attack" subscriber fires ONLY when a rule MATCHES, so a bug in it
# is invisible under normal traffic and surfaces the instant a limit is hit.
#
# It also runs at TOP LEVEL (self == main), unlike the throttle blocks in the
# same file, which are written inside `class Rack::Attack` and therefore close
# over the class. An unqualified `client_ip(request)` there raised
# NoMethodError for main:Object; the error propagated out of
# ActiveSupport::Notifications, through Rack::Attack, into
# ProxySecurityValidator's catch-all rescue, and came back as a generic 500.
# Net effect: every throttle hit answered 500 instead of 429, and every
# blocklist hit 500 instead of 403, with the cause masked.
#
# These publish the notification directly rather than driving real traffic, so
# BOTH branches are covered — a genuine blocklist match is awkward to provoke,
# and it was the branch with no coverage at all.
RSpec.describe "rack.attack notification subscriber" do
  def publish(match_type)
    env = Rack::MockRequest.env_for("/api/v1/auth/login", method: "POST")
    env["rack.attack.matched"]    = "some_rule"
    env["rack.attack.match_type"] = match_type
    env["rack.attack.match_data"] = { count: 11, limit: 10, period: 60 }
    request = Rack::Attack::Request.new(env)

    ActiveSupport::Notifications.instrument("rack.attack", request: request) { nil }
  end

  it "logs a throttle match without raising" do
    expect { publish(:throttle) }.not_to raise_error
  end

  it "logs a blocklist match without raising" do
    expect { publish(:blocklist) }.not_to raise_error
  end

  # The specific regression. Resolving the client IP is the only call in the
  # subscriber that needs an explicit receiver, and getting it wrong is silent
  # until a limit is actually hit.
  it "resolves the client IP through the class, not top-level self" do
    expect(Rack::Attack).to receive(:client_ip).at_least(:once).and_call_original
    publish(:throttle)
  end

  it "does not raise for a match_type it does not handle" do
    expect { publish(:safelist) }.not_to raise_error
  end
end
