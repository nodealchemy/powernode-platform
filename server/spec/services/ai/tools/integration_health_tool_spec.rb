# frozen_string_literal: true

require "rails_helper"

# A8. The audit's finding: `integration_health` is "permanently `{unknown: N}`:
# the column it buckets has one writer with zero call sites". These examples pin
# BOTH arms of that oracle — the verb reports `unknown` while nothing has probed,
# and a NON-unknown bucket once a probe has actually been persisted. A summary
# that could only ever say `unknown` is not a health check.
RSpec.describe Ai::Tools::IntegrationHealthTool, type: :service do
  let(:account) { create(:account) }
  let(:tool) { described_class.new(account: account) }

  def summary
    tool.execute(params: {})[:summary]
  end

  let!(:instance) do
    create(:devops_integration_instance, account: account, status: "active",
                                         health_status: nil, last_health_check_at: nil,
                                         consecutive_failures: 0)
  end

  it "buckets an integration nobody has probed as unknown" do
    expect(summary).to include(total: 1, unknown: 1, healthy: 0, degraded: 0, unhealthy: 0)
  end

  it "reports a healthy bucket once a passing probe is persisted" do
    instance.record_health_probe!(success: true)

    expect(summary).to include(total: 1, healthy: 1, unknown: 0)
  end

  it "reports an unhealthy bucket once the failure streak reaches the threshold" do
    Devops::IntegrationInstance.health_failure_threshold.times do
      instance.record_health_probe!(success: false, error: "connection refused")
    end

    expect(summary).to include(total: 1, unhealthy: 1, unknown: 0)
  end

  it "surfaces the persisted per-integration fields, not just the summary" do
    instance.record_health_probe!(success: false, error: "connection refused")

    row = tool.execute(params: {})[:integrations].first
    expect(row[:health_status]).to eq("degraded")
    expect(row[:last_health_check_at]).to be_present
    expect(row[:last_error]).to eq("connection refused")

    # `consecutive_failures` on this row is the EXECUTION streak, and a probe
    # must not move it (review F3). The probe streak is its own value. The verb
    # reporting the execution counter under a health heading is a pre-existing
    # naming mismatch, recorded as an offer rather than changed here.
    expect(row[:consecutive_failures]).to eq(0)
    expect(instance.reload.probe_failure_streak).to eq(1)
  end
end
