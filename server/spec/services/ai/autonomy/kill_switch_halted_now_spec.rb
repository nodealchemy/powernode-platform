# frozen_string_literal: true

require "rails_helper"

# D2 review F2/F4: KillSwitchService.halted_now? is the platform's one halt
# predicate (#halted?, i.e. Account#ai_suspended?) read FRESH, for guards on an
# action already in flight.
RSpec.describe Ai::Autonomy::KillSwitchService, ".halted_now?", type: :service do
  let(:account) { create(:account) }

  it "reads false for a running account" do
    expect(described_class.halted_now?(account.id)).to be(false)
  end

  it "sees a halt thrown through ANOTHER Account instance, which a cached read would miss" do
    cached = Account.find(account.id)
    Account.find(account.id).suspend_ai!

    expect(cached.ai_suspended?).to be(false) # the stale copy an in-flight guard would hold
    expect(described_class.halted_now?(account.id)).to be(true)
  end

  it "reads a missing account as halted (fail closed)" do
    expect(described_class.halted_now?(SecureRandom.uuid)).to be(true)
    expect(described_class.halted_now?(nil)).to be(true)
  end
end
