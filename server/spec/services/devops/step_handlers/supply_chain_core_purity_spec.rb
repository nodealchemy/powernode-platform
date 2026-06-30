# frozen_string_literal: true

require "spec_helper"

# Core-purity guard (IMP-8b76d67b217f): the supply-chain devops step handlers
# (sbom_generate, vulnerability_scan, sign_artifact, policy_gate) are owned by the
# OPTIONAL public supply-chain extension, which autoloads them and registers them via
# Devops::StepHandlerRegistry at boot. Core must NOT ship duplicate copies: they reference
# the SupplyChain:: namespace and raise NameError in core mode (extension absent), and they
# collide with the extension's canonical definitions of the same constants. The duplicates
# were dead (the constant already resolves to the extension copy). Rails-free file scan.
RSpec.describe "core devops step_handlers supply-chain purity" do
  handlers_dir = File.expand_path("../../../../app/services/devops/step_handlers", __dir__)

  it "ships no core step handler that references the SupplyChain:: extension namespace" do
    leaks = Dir[File.join(handlers_dir, "*.rb")]
            .select { |f| File.read(f).match?(/\bSupplyChain::/) }
            .map { |f| File.basename(f) }

    expect(leaks).to be_empty,
           "supply-chain step handlers belong in the supply-chain extension (it autoloads + " \
           "registers them); core must not duplicate them. Offenders: #{leaks.inspect}"
  end
end
