# frozen_string_literal: true

require "spec_helper"

# Core-purity guard (IMP-3b7f94ff21cc): McpScannerService resolves hosted MCP servers
# through the ExtensionRegistry provider seam precisely so core never names the
# business-only hosted-server model. It re-leaked that model name as a literal
# (a knowledge-graph target_type); the node type must be derived from the resolved
# object instead. Rails-free file scan keeps it fast.
RSpec.describe "core McpScannerService hosted-server model-name purity" do
  service_path = File.expand_path("../../../../app/services/ai/discovery/mcp_scanner_service.rb", __dir__)

  it "names no business hosted-server model directly (derives the type via the registry seam)" do
    leaks = File.read(service_path).scan(/Mcp::HostedServer/).uniq
    expect(leaks).to be_empty,
           "core McpScannerService must not name the business Mcp::HostedServer model; " \
           "derive the knowledge-graph node type from the resolved object/provider"
  end
end
