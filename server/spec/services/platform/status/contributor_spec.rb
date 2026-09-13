# frozen_string_literal: true

require "rails_helper"

# The contributor contract's optional hooks (design §4.4).
#
# `signal_resolver` was deleted unused: no contributor in core or any extension
# ever overrode it, and the design that consumed it (a per-contributor
# row-mapping hook) would have filtered every recent FleetEvent in memory.
# Per-component signals bind by the FleetEvent's TYPED entity column, filtered
# at the extension's own endpoint, and core never reads FleetEvent (design §6).
# This pins the deletion so the dead hook is not re-added as a second channel.
RSpec.describe Platform::Status::Contributor do
  subject(:contributor) { described_class.new }

  it "no longer declares a signal_resolver hook" do
    expect(contributor).not_to respond_to(:signal_resolver)
  end

  # The other arm: the sibling optional hooks are still on the contract, so the
  # absence above is about that one method, not a contract that answers nothing.
  it "still declares the other optional hooks with nil defaults" do
    expect(contributor.runbook_key).to be_nil
    expect(contributor.owner_agent_slug).to be_nil
    expect(contributor.escalates?).to be(true)
  end
end
