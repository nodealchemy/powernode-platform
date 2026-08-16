# frozen_string_literal: true

require "rails_helper"

# The tools/list page size must stay AHEAD of the advertised catalog.
#
# Why this spec exists (2026-08-16): TOOLS_PAGE_SIZE was set to 250 with a
# comment stating it was "deliberately larger than the current full catalog
# (231 tools for the widest principal) so existing clients that never send a
# cursor keep receiving the complete set in one page with no nextCursor". That
# invariant was true when written and silently stopped being true as the
# catalog grew: by 2026-08-16 the advertised set was 611 (602 platform + 9
# introspection), so a client that never sends a cursor received 250 and
# SILENTLY LOST 361 tools — a well-formed response, no error, no warning, and
# a tool that is implemented, registered and relevance-filtered simply never
# offered. `platform.dev_update_task` was one of them.
#
# A comment cannot hold an invariant. This executes it: it fails the moment the
# catalog approaches the bound, and names both numbers so whoever adds the tool
# that crosses it is told at CI time rather than discovering it later through a
# tool that "does not exist".
RSpec.describe "MCP tools/list page size", type: :request do
  let(:page_size) { Api::V1::Mcp::StreamableHttpController::TOOLS_PAGE_SIZE }

  # Counted the way the controller builds the list, so the guard cannot drift
  # from the thing it guards: platform tool_definitions + introspection tools.
  # Agent tools are deliberately excluded from tools/list by the controller.
  let(:advertised_count) do
    platform = ::Ai::Tools::PlatformApiToolRegistry.tool_definitions.size
    introspection =
      if defined?(::Ai::Introspection::McpToolRegistrar::INTROSPECTION_TOOLS)
        ::Ai::Introspection::McpToolRegistrar::INTROSPECTION_TOOLS.size
      else
        0
      end
    platform + introspection
  end

  it "fits the entire advertised catalog in one page" do
    expect(advertised_count).to be < page_size,
      "tools/list would TRUNCATE: #{advertised_count} advertised tools vs " \
      "TOOLS_PAGE_SIZE #{page_size}. A client that sends no cursor receives " \
      "the first #{page_size} and silently loses #{advertised_count - page_size}. " \
      "Raise TOOLS_PAGE_SIZE above #{advertised_count}, or make every client " \
      "follow nextCursor before lowering it."
  end

  # Separate from the hard failure above so the signal arrives BEFORE the
  # breakage, not with it. A catalog at 90% of the bound is one feature away
  # from silently truncating, and the whole point of this file is that nobody
  # noticed the first time.
  it "keeps meaningful headroom above the catalog" do
    headroom = page_size - advertised_count
    expect(headroom).to be_positive
    expect(advertised_count.to_f / page_size).to be < 0.9,
      "tools/list headroom is nearly gone: #{advertised_count}/#{page_size} " \
      "(#{(advertised_count.to_f / page_size * 100).round}% of the page). " \
      "Raise TOOLS_PAGE_SIZE now — this is the warning before truncation, " \
      "which is silent when it happens."
  end
end
