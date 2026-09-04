# frozen_string_literal: true

require "spec_helper"
require "find"

# IMP-cf4f8bcd02c3 — extension isolation (gate #9), core side. A core spec is
# published with core and must run in a clone where no private extension
# exists, so it must never name a private extension's namespace (`Billing::`,
# `BaaS::`, `Marketplace::`): such a constant in server/spec is a dependency on
# code that is absent from every public clone, whether it hides under a
# `defined?` guard or not. The blessed
# route is core's generic Powernode::BillingBridge seam — stub THAT
# (`allow(::Powernode::BillingBridge).to receive(:check_provisioning_quota)`),
# never the private class behind it. The extension-side twin lives at
# extensions/system/server/spec/lint/billing_namespace_seam_spec.rb.
#
# The core-purity hook does not enforce model namespaces (its header records
# why: a blocking text gate cannot tell a `defined?` guard from a dependency),
# so this file is the ratchet — and because server/spec already carried these
# lines when it was written, it is a ratchet with a BASELINE rather than an
# absence assertion. The oracle is EQUALITY, not <=: every grandfathered file
# must carry exactly the count recorded below. A new file, or a rise in a
# listed one, is a regression; a DROP is progress that must be recorded here in
# the same change, so the ledger can never sit above what the tree contains —
# a ceiling nobody re-tightens is not a ratchet. Entries are per FILE and by
# COUNT, so a line shift elsewhere in the file does not disturb them.
#
# Rails-free, byte-oriented scan over server/spec: comments count (a comment is
# how the last stale copy of a claim survives) and so does every file type.
# This file is the one exclusion — it must spell the tokens it forbids. The
# exclusion is by path RELATIVE to spec_root, so a checkout reached through a
# symlink (where __FILE__ and a realpath-resolved root disagree) cannot
# silently stop matching and fail this file on its own text.
RSpec.describe "core spec private-extension namespace ratchet" do
  spec_root = File.expand_path("..", __dir__)
  self_rel = "lint/extension_namespace_ratchet_spec.rb"

  # Namespace tokens owned by private extensions. Namespaces are domain-top-level
  # by convention (docs/concepts/core-business-boundary.md), so the token is the
  # namespace, never an extension SLUG: a slug-shaped token (the camelized
  # directory name under extensions/private/) may not be written in a public
  # file at all — that is the leak core-purity-check.sh blocks, and the derived
  # scan at extensions/system/server/spec/integration/private_extension_isolation_spec.rb
  # covers those without naming them. What is left for this ratchet is exactly
  # the set the hook's header records as deliberately out of its reach: the
  # private extension's OWN Ruby namespaces. All three are enforced; the two
  # added after Billing:: start at a baseline of zero, so any first reference
  # fails here.
  private_namespace = /\b(?:Billing|BaaS|Marketplace)::\w+/

  # Grandfathered `defined?(Billing::X)` skip guards and business-mode
  # assertions, counted per file on 2026-09-04 (BaaS:: and Marketplace:: appear
  # nowhere in server/spec, so every file below is a Billing:: count). Lower a
  # count when you remove a line; delete the entry when a file reaches zero.
  # Never raise one.
  baseline = {
    "controllers/api/v1/users_controller_spec.rb" => 2,
    "lib/tasks/powernode_setup_purity_spec.rb" => 1,
    "models/account_spec.rb" => 4,
    "models/audit_log_spec.rb" => 4,
    "models/webhook_event_spec.rb" => 1,
    "requests/api/v1/accounts_spec.rb" => 1,
    "requests/api/v1/auth/registrations_spec.rb" => 4,
    "requests/api/v1/internal/accounts_spec.rb" => 1,
    "requests/api/v1/internal/data_exports_spec.rb" => 2,
    "services/usage_limit_service_spec.rb" => 1
  }.freeze

  scan = lambda do
    counts = Hash.new(0)
    Find.find(spec_root) do |path|
      next unless File.file?(path)

      rel = path.delete_prefix("#{spec_root}/")
      next if rel == self_rel

      File.read(path, mode: "rb").force_encoding(Encoding::BINARY).each_line do |line|
        counts[rel] += 1 if line.match?(private_namespace)
      end
    end
    counts
  end

  it "names a private-extension namespace in exactly the grandfathered files, at exactly the recorded counts" do
    actual = scan.call

    regressions = actual.reject { |file, count| baseline.fetch(file, 0) >= count }
                        .map { |file, count| "#{file}: #{count} (baseline #{baseline.fetch(file, 0)})" }
    tightenings = baseline.select { |file, count| actual.fetch(file, 0) < count }
                          .map { |file, count| "#{file}: #{actual.fetch(file, 0)} (baseline #{count})" }

    expect(regressions).to be_empty,
      "a core spec must not name a private-extension namespace (Billing::, BaaS::, Marketplace::) — " \
      "route through the matching core seam and stub THAT instead. New or grown references:\n  " \
      "#{regressions.join("\n  ")}"
    expect(tightenings).to be_empty,
      "references dropped below the recorded baseline — lower these entries (or delete them at zero) " \
      "in #{File.basename(self_rel)} so the ratchet keeps its bite:\n  #{tightenings.join("\n  ")}"
  end
end
