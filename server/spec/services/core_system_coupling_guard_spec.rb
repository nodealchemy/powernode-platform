# frozen_string_literal: true

require "rails_helper"

# IMP-f5b4cb4eeb20 — core must not name the System (fleet-substrate) extension. Previously
# worker_api_client.rb hardcoded System::*Job dispatch strings and plan_snapshot_service.rb
# referenced ::System::Provider* models (defined?-guarded). Both now route through generic seams:
# the System extension enqueues its own jobs via the slug-agnostic WorkerApiClient#queue_job
# primitive, and provision-step label resolution goes through
# Powernode::ExtensionRegistry.provider(:provision_label_resolver). This guard fails if either
# core file regains a literal System:: reference (the "no extension code in core" lens).
RSpec.describe "core ↛ System extension coupling" do
  core_files = [
    "app/services/worker_api_client.rb",
    "app/services/ai/provisioning/plan_snapshot_service.rb"
  ]

  core_files.each do |rel|
    it "#{rel} names no System:: extension constant" do
      path = Rails.root.join(rel)
      offending = File.readlines(path).each_with_index
                      .select { |line, _idx| line.include?("System::") }
                      .map { |line, idx| "L#{idx + 1}: #{line.strip}" }
      expect(offending).to be_empty,
        "#{rel} references the System:: extension (route through a generic seam instead):\n#{offending.join("\n")}"
    end
  end
end
