# frozen_string_literal: true

require "spec_helper"
require "find"

# IMP-63a7d2f99c56 — the mechanical guard the operator direction asked for
# ("a lint or a shared helper, not another comment"). The production default
# cache store (solid_cache; config/environments/production.rb:50) does not
# implement Rails.cache.delete_matched — ActiveSupport::Cache::Store#delete_matched
# raises NotImplementedError, which descends from ScriptError and so is NOT
# caught by `rescue StandardError`. CacheVersioning
# (app/services/concerns/cache_versioning.rb) is the structural replacement
# every call site this task touched now uses.
#
# Same EQUALITY-oracle ratchet shape as
# spec/lint/extension_namespace_ratchet_spec.rb: a baseline with a ceiling
# nobody re-tightens is not a ratchet, so a regression (new/grown site) AND a
# stale entry (dropped below its recorded count) both fail this spec — lower
# or delete an entry in the SAME change that fixes the site.
#
# Scoped to the literal call form `delete_matched(` (receiver + open paren,
# no space), not the bare word — the risk this guard exists for is a CALL
# raising in production, not the method's name appearing in explanatory
# prose. user.rb's baseline entry below is exactly that distinction: prose
# describing why the call was removed, not a live call.
RSpec.describe "Rails.cache.delete_matched call-site ratchet (core)" do
  app_root = File.expand_path("../../app", __dir__)
  pattern = "delete_matched("

  # Grandfathered, per file, counted 2026-09-04 (IMP-63a7d2f99c56). Lower a
  # count (or delete the entry at zero) in the same change that removes a
  # site; never raise one.
  baseline = {
    # Real call. Structurally unfixable within this task's file list: the
    # READ side of its cache key ("ai:monitoring:comprehensive:<account>:<time_range>")
    # lives in ai/monitoring_health_service.rb, which this task does not own,
    # and time_range is an unbounded user-controlled param (0..604800 seconds,
    # api/v1/ai/monitoring_controller.rb#set_time_range) — not enumerable as
    # an explicit key list either. A CacheVersioning fix needs that file too;
    # tracked as a known gap in this task's report rather than left silent.
    "services/ai/monitoring_health_service/health_checks.rb" => 1,
    # Prose, not a call: documents (in the exact syntax) the delete_matched
    # invocation IMP-95e4904258c8 already removed from #clear_permission_cache
    # by making the permission-name cache key structural instead.
    "models/user.rb" => 1
  }.freeze

  scan = lambda do
    counts = Hash.new(0)
    Find.find(app_root) do |path|
      next unless File.file?(path)

      rel = path.delete_prefix("#{app_root}/")
      File.read(path, mode: "rb").force_encoding(Encoding::BINARY).each_line do |line|
        counts[rel] += 1 if line.include?(pattern)
      end
    end
    counts
  end

  it "calls Rails.cache.delete_matched in exactly the grandfathered files, at exactly the recorded counts" do
    actual = scan.call

    regressions = actual.reject { |file, count| baseline.fetch(file, 0) >= count }
                        .map { |file, count| "#{file}: #{count} (baseline #{baseline.fetch(file, 0)})" }
    tightenings = baseline.select { |file, count| actual.fetch(file, 0) < count }
                          .map { |file, count| "#{file}: #{actual.fetch(file, 0)} (baseline #{count})" }

    expect(regressions).to be_empty,
      "a new or grown Rails.cache.delete_matched call site — the production default store " \
      "(solid_cache) does not implement it and NotImplementedError is not a StandardError, so " \
      "`rescue StandardError` will not catch it. Use CacheVersioning " \
      "(app/services/concerns/cache_versioning.rb) instead:\n  #{regressions.join("\n  ")}"
    expect(tightenings).to be_empty,
      "a grandfathered site dropped below its recorded baseline — lower this entry (or delete it " \
      "at zero) in #{File.basename(__FILE__)} so the ratchet keeps its bite:\n  #{tightenings.join("\n  ")}"
  end
end
