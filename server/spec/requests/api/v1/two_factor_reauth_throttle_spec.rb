# frozen_string_literal: true

require "rails_helper"

# IMP-99e8e4701150 review M1 — pins the two_factor_reauth_by_ip and
# two_factor_reauth_by_user throttles (config/initializers/rack_attack.rb).
# Same enable/reset pattern as
# extensions/system/.../claim_throttle_spec.rb: these two throttles are
# registered OUTSIDE the `unless Rails.env.test?` guard specifically so they
# are directly testable, but stay a no-op for every OTHER request spec
# because rate_limiting_enabled? is false by default in test.
RSpec.describe "Rack::Attack throttling for 2FA re-auth", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(user) }

  around do |example|
    original_store = Rack::Attack.cache.store
    original_enabled = Rack::Attack.enabled
    Rack::Attack.enabled = true
    # Test Rails.cache may be a NullStore, which would never accumulate
    # throttle counters — use a real in-memory store for these examples.
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rack::Attack.cache.store = original_store
    Rack::Attack.enabled = original_enabled
  end

  before do
    allow(Rack::Attack).to receive(:rate_limiting_enabled?).and_return(true)
  end

  describe "DELETE /api/v1/two_factor/disable" do
    before { user.enable_two_factor! }

    it "throttles after 5 wrong codes from one IP within the window" do
      5.times do
        delete "/api/v1/two_factor/disable", params: { code: "000000" }, headers: headers, as: :json
        expect(response).to have_http_status(:unprocessable_content)
      end

      delete "/api/v1/two_factor/disable", params: { code: "000000" }, headers: headers, as: :json

      expect(response).to have_http_status(:too_many_requests)
    end

    it "throttles by user even across different-looking requests to the same account" do
      5.times do
        delete "/api/v1/two_factor/disable", params: { code: "000000" }, headers: headers, as: :json
      end

      delete "/api/v1/two_factor/disable", params: { code: "000000" }, headers: headers, as: :json

      expect(response).to have_http_status(:too_many_requests)
      # Confirmed 2FA survives — the throttle blocked the request before it
      # ever reached the controller's own wrong-code check.
      expect(user.reload.two_factor_enabled?).to be true
    end
  end

  describe "POST /api/v1/two_factor/regenerate_backup_codes" do
    before { user.enable_two_factor! }

    it "throttles after 5 wrong codes from one IP within the window" do
      5.times do
        post "/api/v1/two_factor/regenerate_backup_codes", params: { code: "000000" }, headers: headers, as: :json
        expect(response).to have_http_status(:unprocessable_content)
      end

      post "/api/v1/two_factor/regenerate_backup_codes", params: { code: "000000" }, headers: headers, as: :json

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  it "does not throttle unrelated 2FA endpoints (status)" do
    user.enable_two_factor!

    6.times do
      get "/api/v1/two_factor/status", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end
  end
end
