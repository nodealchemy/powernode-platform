# frozen_string_literal: true

require "rails_helper"

# IMP-affa1c163adc — core must not name the OPTIONAL public supply-chain extension.
# Previously Devops::GitRepository declared `has_many :sboms, class_name: "SupplyChain::Sbom"`
# and Api::V1::FilesController#find_attachable hardcoded a case over SupplyChain::Sbom/
# Attestation/ContainerImage/Vendor — both NameError in core mode (extension absent). The
# SBOM association now lives in the supply-chain GitRepository decorator, and attachable
# resolution routes through the generic Powernode::AttachableRegistry seam. This guard fails
# if any core source file (server/app, server/lib) regains a literal SupplyChain:: reference.
RSpec.describe "core ↛ supply-chain extension coupling" do
  scan_roots = %w[app lib].map { |d| Rails.root.join(d) }

  it "no core source file names the SupplyChain:: extension namespace" do
    offenders = scan_roots.flat_map do |root|
      Dir[root.join("**", "*.rb")].select { |f| File.read(f).match?(/\bSupplyChain::/) }
    end.map { |f| Pathname.new(f).relative_path_from(Rails.root).to_s }

    expect(offenders).to be_empty,
      "core must not reference the supply-chain extension; route through a generic seam " \
      "(Powernode::AttachableRegistry / model decorator). Offenders:\n#{offenders.join("\n")}"
  end
end
