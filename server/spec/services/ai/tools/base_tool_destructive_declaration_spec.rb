# frozen_string_literal: true

require "rails_helper"

# Increment E2 — the `destructive:` option on Ai::Tools::BaseTool.declare_action.
#
# It is the ground truth Mcp::ToolCatalog publishes as `destructiveHint`, and
# it is a DECLARATION rather than a name glob for the reason stated at
# .declare_action: the field it replaces was a name-shaped guess, and deriving
# the new one from Mcp::Principal::DESTRUCTIVE_TOOL_PATTERNS would repeat that
# mistake one field over.
RSpec.describe Ai::Tools::BaseTool, ".declare_action(destructive:)" do
  def tool_class(&block)
    Class.new(described_class, &block)
  end

  it "defaults to false so every existing declaration keeps its meaning" do
    klass = tool_class { declare_action "plain", mutating: true }

    expect(klass.declared_action("plain")[:destructive]).to be(false)
  end

  it "records a destructive declaration" do
    klass = tool_class { declare_action "wipe", mutating: true, destructive: true }

    expect(klass.declared_action("wipe")[:destructive]).to be(true)
    expect(klass.declared_action("wipe")[:mutating]).to be(true)
  end

  it "records it on a read-only declaration as false, not nil" do
    klass = tool_class { declare_action "peek", mutating: false }

    expect(klass.declared_action("peek")).to include(destructive: false)
  end

  # THE VALIDATION. Per the MCP spec `destructiveHint` is meaningful only when
  # `readOnlyHint` is false, so a read-only destructive declaration is not a
  # stricter statement — it is an incoherent one that would publish a hint no
  # client can act on. Raised at DECLARATION time, i.e. class load, so it can
  # never reach a running catalog.
  it "refuses destructive: true on a read-only action" do
    expect {
      tool_class { declare_action "impossible", mutating: false, destructive: true }
    }.to raise_error(ArgumentError, /destructive: true implies mutating: true/)
  end

  it "names the offending action in the refusal" do
    expect {
      tool_class { declare_action "impossible", mutating: false, destructive: true }
    }.to raise_error(ArgumentError, /"impossible"/)
  end

  # The other arm of the validation: it refuses the incoherent pair and
  # nothing else. A guard that raised on every declaration would look
  # identical from the example above alone.
  it "accepts every coherent combination" do
    expect {
      tool_class do
        declare_action "a", mutating: false
        declare_action "b", mutating: true
        declare_action "c", mutating: true, destructive: false
        declare_action "d", mutating: true, destructive: true
      end
    }.not_to raise_error
  end

  it "is inherited by a subclass that does not redeclare" do
    parent = tool_class { declare_action "wipe", mutating: true, destructive: true }
    child = Class.new(parent)

    expect(child.declared_action("wipe")[:destructive]).to be(true)
  end

  # FOOTGUN, pinned so it is documented behaviour rather than a surprise. It is
  # the same shape .declare_action already records for `audit:`: the option
  # defaults to false and .declared_action resolves child-before-parent, so a
  # subclass that re-declares an action without repeating `destructive: true`
  # silently downgrades the published hint.
  it "is LOST when a subclass redeclares the action without repeating it" do
    parent = tool_class { declare_action "wipe", mutating: true, destructive: true }
    child = Class.new(parent) { declare_action "wipe", mutating: true }

    expect(child.declared_action("wipe")[:destructive]).to be(false)
  end
end
