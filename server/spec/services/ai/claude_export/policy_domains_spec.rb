# frozen_string_literal: true

require "rails_helper"

# Core-pure seam for "which domain owns this intervention-policy category".
# The exact prefix table is extension-owned (the system extension's
# DOMAIN_PREFIXES); core must not name it, so an extension REGISTERS its map
# here and core falls back to a generic prefix heuristic when nothing is
# registered for a category.
RSpec.describe Ai::ClaudeExport::PolicyDomains do
  after { described_class.reset! }

  it "resolves a registered prefix map first-match, in registration order" do
    described_class.register("topology", %w[system.sdwan_federation_compose])
    described_class.register("sdwan", %w[system.sdwan_ sdwan.])

    expect(described_class.domain_for("system.sdwan_federation_compose")).to eq("topology")
    expect(described_class.domain_for("system.sdwan_create_peer")).to eq("sdwan")
    expect(described_class.domain_for("sdwan.route_policy")).to eq("sdwan")
  end

  it "falls back to the leading family token after the namespace when nothing is registered" do
    expect(described_class.domain_for("system.cve_triage")).to eq("cve")
    expect(described_class.domain_for("system.instance_pool_replenish")).to eq("instance")
    expect(described_class.domain_for("project.create")).to eq("project")
    expect(described_class.domain_for("system.architecture.propose")).to eq("architecture")
  end

  it "dedupes and drops blanks over a category list" do
    expect(described_class.for_categories([ "system.cve_triage", "system.cve_runbook", nil, "" ])).to eq(%w[cve])
  end
end
