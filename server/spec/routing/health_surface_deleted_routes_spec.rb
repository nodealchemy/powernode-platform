# frozen_string_literal: true

require "rails_helper"

# fc-47 — platform health lives on /app/status (Platform::Status contributors,
# core_service among them). Observability's System Health tab was the only
# caller of GET /ai/monitoring/health; the tab and the endpoint were deleted.
# The MCP health tool reads Ai::MonitoringHealthService directly, not this route.
RSpec.describe "Deleted health surface routes", type: :routing do
  it "does not route GET /api/v1/ai/monitoring/health" do
    expect(get: "/api/v1/ai/monitoring/health").not_to be_routable
  end

  it "still routes the detailed and connectivity health checks" do
    expect(get: "/api/v1/ai/monitoring/health/detailed")
      .to route_to("api/v1/ai/monitoring#health_detailed")
    expect(get: "/api/v1/ai/monitoring/health/connectivity")
      .to route_to("api/v1/ai/monitoring#health_connectivity")
  end
end
