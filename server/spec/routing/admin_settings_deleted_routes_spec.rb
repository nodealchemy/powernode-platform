# frozen_string_literal: true

require "rails_helper"

# fc-45 — the Admin Settings "Development" tab was a second enable/disable
# surface for the extensions the Extensions tab already manages (GET
# /admin_settings/extensions, PUT /admin_settings/extensions/:slug/toggle).
# The tab and its GET/PUT /admin_settings/development endpoints were deleted.
RSpec.describe "Deleted admin settings routes", type: :routing do
  it "does not route GET or PUT /api/v1/admin_settings/development" do
    expect(get: "/api/v1/admin_settings/development").not_to be_routable
    expect(put: "/api/v1/admin_settings/development").not_to be_routable
  end

  # fc-45 — GET /admin_settings/metrics and /admin_settings/health routed to
  # actions that never existed; their only callers were two client methods
  # nothing called, deleted with the overview's metrics-only rewrite.
  it "does not route GET /api/v1/admin_settings/metrics or /health" do
    expect(get: "/api/v1/admin_settings/metrics").not_to be_routable
    expect(get: "/api/v1/admin_settings/health").not_to be_routable
  end

  it "still routes the Extensions tab's endpoints" do
    expect(get: "/api/v1/admin_settings/extensions").to route_to("api/v1/admin_settings#extensions")
    expect(put: "/api/v1/admin_settings/extensions/foo/toggle")
      .to route_to("api/v1/admin_settings#toggle_extension", slug: "foo")
  end
end
