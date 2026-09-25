# frozen_string_literal: true

require "rails_helper"

# fc-47 review M1: the "resources" component (host cpu/memory by shelling out
# to free/top, plus a database and redis status of its own) fed only the
# Observability System Health tab, which fc-47 deleted. Host and service
# health are read from Platform::Health::CoreChecks, on /app/status.
RSpec.describe Monitoring::UnifiedService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  it "no longer offers a resources component" do
    expect(described_class::COMPONENTS).not_to include("resources")
    expect(service.collect_component_metrics("resources", 1.hour)).to eq({})
  end
end
