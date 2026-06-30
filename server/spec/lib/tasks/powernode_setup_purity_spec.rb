# frozen_string_literal: true

require "spec_helper"

# Core-purity guard (IMP-ac0873c03dd0, gate #9): the core setup rake must not name
# business-extension models directly. powernode_setup.rake previously called
# Billing::Plan.find_or_create_by! and guarded on defined?(Billing::Subscription);
# it now routes through the generic Powernode::BillingBridge seam
# (plan_model / subscription_model), so core embeds no business-domain class names.
# Rails-free file scan keeps it fast.
RSpec.describe "core powernode_setup.rake billing-namespace purity" do
  rake_path = File.expand_path("../../../lib/tasks/powernode_setup.rake", __dir__)

  it "names no business-extension Billing:: model directly (routes through Powernode::BillingBridge)" do
    leaks = File.read(rake_path).scan(/\bBilling::\w+/).uniq
    expect(leaks).to be_empty,
           "core setup rake must not reference business-extension Billing:: models directly; " \
           "found #{leaks.inspect} — route through Powernode::BillingBridge instead"
  end
end
