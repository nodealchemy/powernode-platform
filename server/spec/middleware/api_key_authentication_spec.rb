# frozen_string_literal: true

require "rails_helper"

# Regression guard: the ApiKeyAuthentication middleware (app/middleware/api_key_authentication.rb)
# was dead AND broken — it was never wired into the Rack stack (referenced nowhere) and was
# coded against an obsolete ApiKey shape: it called ApiKey.find_by_token (no such finder / no
# token column) and api_key.ip_restrictions / .rate_limit / .user, none of which exist on the
# model (which has find_by_key, allowed_ips, rate_limits, created_by). The live API-key auth
# path lives in the controllers via key_digest. Guard against the dead middleware returning.
RSpec.describe "Legacy ApiKeyAuthentication middleware removal" do
  it "does not define the dead, unwired ApiKeyAuthentication middleware" do
    expect { ApiKeyAuthentication }.to raise_error(NameError)
  end
end
