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

  # fc-47 review H1: the Maintenance overview's host metrics section was the
  # only caller of GET /admin/maintenance/metrics. GET /admin/maintenance/health
  # stays: the worker's scheduled task executor reads its overall_status.
  it "does not route GET /api/v1/admin/maintenance/metrics, and still routes /health" do
    expect(get: "/api/v1/admin/maintenance/metrics").not_to be_routable
    expect(get: "/api/v1/admin/maintenance/health").to route_to("api/v1/admin/maintenance/maintenance#health")
  end

  # fc-47 review L-3: GET /admin/maintenance/status had no caller (the Mode
  # tab reads /mode), and GET /admin/maintenance/health/services pointed at a
  # service_health action that never existed.
  it "does not route GET /api/v1/admin/maintenance/status or /health/services" do
    expect(get: "/api/v1/admin/maintenance/status").not_to be_routable
    expect(get: "/api/v1/admin/maintenance/health/services").not_to be_routable
  end

  # fc-47 review M5: the detailed and connectivity checks had no caller left
  # (their client methods were never called, and no MCP tool reads them).
  it "does not route the detailed or connectivity health checks" do
    expect(get: "/api/v1/ai/monitoring/health/detailed").not_to be_routable
    expect(get: "/api/v1/ai/monitoring/health/connectivity").not_to be_routable
  end

  # fc-47: MonitoringApiService.getMetrics was the only caller of GET
  # /ai/monitoring/metrics, and nothing called it. The worker's broadcast is
  # a different route and stays.
  it "does not route GET /api/v1/ai/monitoring/metrics, and still routes the broadcast" do
    expect(get: "/api/v1/ai/monitoring/metrics").not_to be_routable
    expect(post: "/api/v1/ai/monitoring/broadcast").to route_to("api/v1/ai/monitoring#broadcast_metrics")
  end
end
