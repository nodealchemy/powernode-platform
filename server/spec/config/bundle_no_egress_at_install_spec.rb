# frozen_string_literal: true

require "rails_helper"

# IMP-13aa8e9e2fd4, part of the 2026-09-20 ops-hub outage fix
# (ops-hub-outage-nonroot-rails-four-stacked-defects). `bundle install
# --local` on a deployed node runs with NO egress by design (managed
# children ship their .gem cache in vendor/cache and install offline —
# see rails-start.sh's own comment). A gem whose install step reaches
# out to the network anyway (a native-extension gem that downloads a
# prebuilt binary, rather than compiling one from source) breaks that
# guarantee silently: the gem cache and gemspec still install cleanly,
# but the file the download was supposed to produce is simply absent,
# and bundler only reports it much later as "Could not find X in
# locally installed gems" — which reads like a caching bug, not a
# network one.
#
# skylight was exactly this shape (native agent binary fetched from S3
# at install time) and was also completely unused — never required,
# never configured, referenced nowhere in server/, worker/, or the
# system extension. Removed rather than worked around: no boot-time
# egress dependency to route around if the gem simply is not there.
#
# This spec is a guard against reintroducing that shape, not just a
# check that skylight specifically stays gone:
# BUNDLE_NO_EGRESS_AT_INSTALL_GEMS is a real allowlist-of-forbidden-names
# one line long today, but it's
# the seam for the next gem someone adds that has the same property.
# Re-adding skylight (or anything else with a network-fetching install
# step) needs a deliberate plan for the no-egress fleet first — see this
# task's own acceptance criteria — not a silent Gemfile line.
#
# Gems known to reach the network during `bundle install` (as opposed to
# merely during `require`/runtime, which this spec does not police) —
# typically a native extension that downloads a prebuilt binary instead
# of compiling one from the vendored gem source. Defined at file scope
# (not inside the RSpec.describe block below, where a constant lands on
# Object and a same-named constant in another spec file can clobber it —
# see spec/lib/tasks/mcp_tool_catalog_extension_tools_spec.rb's comment
# on the same rule) and named distinctively for the same reason.
BUNDLE_NO_EGRESS_AT_INSTALL_GEMS = %w[skylight].freeze

RSpec.describe "Bundle has no boot-time-egress-dependent gems" do
  it "does not lock any gem known to fetch a binary over the network at install time" do
    locked_names = Bundler.locked_gems.specs.map(&:name)

    expect(locked_names & BUNDLE_NO_EGRESS_AT_INSTALL_GEMS).to be_empty
  end

  it "does not declare skylight in the Gemfile" do
    gemfile_source = File.read(Bundler.default_gemfile)

    expect(gemfile_source).not_to match(/^\s*gem\s+["']skylight["']/)
  end
end
