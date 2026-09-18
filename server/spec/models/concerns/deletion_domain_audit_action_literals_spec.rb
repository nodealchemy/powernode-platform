# frozen_string_literal: true

require "rails_helper"
require "open3"

# Derived guard (IMP-26a95cba1d43), sibling to
# spec/models/concerns/audit_action_literals_spec.rb (IMP-b95b8c5b6c40) — same
# extraction technique, applied to the GDPR/CCPA deletion and account-
# anonymization cluster that spec's own comment named as filed-but-out-of-scope
# for that task. Every writer in this cluster used a
# log_internal_audit("literal", ...) call whose action string was never
# registered in AuditActions — AuditLog's inclusion validation rejected every
# row and log_internal_audit's rescue dropped it silently (see the swallowed-
# write fix in internal_base_controller.rb), so the platform believed it was
# auditing irreversible personal-data destruction and anonymization while
# writing nothing.
#
# SCOPE, stated precisely so a future reader does not assume more coverage
# than this spec provides:
#
#   - Unlike audit_action_literals_spec.rb, this domain has no dedicated
#     subdirectory (its writers sit in app/controllers/api/v1/internal/
#     alongside ~30 unrelated controllers — maintenance, reports, mcp,
#     webhooks, ...), so scanning that whole directory would pull in other
#     domains' defects (e.g. maintenance_controller.rb's unregistered
#     "backup.create" — a real, separate, already-filed bug, IMP-01a0b2f5 —
#     out of scope here). Instead this guard scopes by LITERAL PREFIX
#     (account./user./data_deletion.) rather than by file identity: it
#     globs every *.rb directly under app/controllers/api/v1/internal/ (a
#     REAL, self-updating directory scope — a fourth file dropped into that
#     directory enters this scan automatically) and keeps only the files
#     whose log_internal_audit literals carry one of this domain's prefixes.
#     This is deliberately NOT the same thing as "scoped to exactly three
#     files": a hardcoded file allowlist cannot discover a new writer, and a
#     bare `git grep -l` over those same three paths cannot either (its
#     result is a subset of its own input by construction, i.e. circular).
#     Both the scan (Ruby, File.read + regex) and the second example's
#     cross-check (git grep, an independent extraction mechanism) are
#     derived from the SAME real directory + the SAME prefix set, so a
#     divergence between them is a genuine finding, not a tautology.
#   - Recognizes only the log_internal_audit("literal", ...) call shape,
#     which is the only shape any writer in this cluster uses.
#   - user.delete (UsersController#destroy) is included in the extraction and
#     in AuditActions' registration, but that controller action has NO route
#     (confirmed via `bin/rails routes`) — it is unreachable over HTTP today,
#     a separate, pre-existing defect (dead controller code) out of scope for
#     this task. This spec still guards its literal because AuditActions
#     validates by string, not by reachability, and the action returning to
#     life via a future routing fix must not silently regress this guard.
RSpec.describe "deletion/anonymization domain audit action literals are registered" do
  domain_prefixes = %w[account. user. data_deletion.].freeze
  literal_pattern = /\blog_internal_audit\(\s*["']([\w.]+)["']/

  # Real directory scope (non-recursive: this domain's writers sit directly
  # in this directory, not a subdirectory of it), filtered to files that
  # contain at least one literal in this domain's namespace. Computed once,
  # at describe-body eval time, and reused by both examples below so they
  # are checking the same set, not two independently-drifting ones.
  candidate_files = Dir.glob(Rails.root.join("app", "controllers", "api", "v1", "internal", "*.rb")).sort

  scan_roots = candidate_files.select do |path|
    literals = File.read(path).scan(literal_pattern).flatten
    literals.any? { |literal| domain_prefixes.any? { |prefix| literal.start_with?(prefix) } }
  end.freeze

  it "scopes to the three known deletion-domain files (sanity check on the derivation above)" do
    # Not the guard itself (see the two examples below) — just a trip-wire so
    # a change to domain_prefixes or the controller set that silently grows
    # or shrinks this list is visible here first, with an explicit list to
    # diff against, rather than only as an obscure count-floor failure.
    expect(scan_roots.map { |p| p.sub("#{Rails.root}/", "") }).to contain_exactly(
      "app/controllers/api/v1/internal/accounts_controller.rb",
      "app/controllers/api/v1/internal/users_controller.rb",
      "app/controllers/api/v1/internal/data_deletion_requests_controller.rb"
    )
  end

  it "does not write an action string that AuditActions.valid_action? rejects" do
    offenders = {}
    total_literal_occurrences = 0

    scan_roots.each do |path|
      content = File.read(path)
      literals = content.scan(literal_pattern).flatten
      domain_literals = literals.select { |l| domain_prefixes.any? { |prefix| l.start_with?(prefix) } }
      total_literal_occurrences += domain_literals.size

      domain_literals.uniq.each do |literal|
        next if AuditActions.valid_action?(literal)

        (offenders[path.to_s.sub("#{Rails.root}/", "")] ||= []) << literal
      end
    end

    expect(offenders).to be_empty,
      "Unregistered audit action literal(s) found in the deletion/anonymization " \
      "domain — AuditLog's inclusion validation rejects these and " \
      "log_internal_audit's rescue silently drops the row:\n" +
      offenders.map { |file, actions| "  #{file}: #{actions.sort.join(', ')}" }.join("\n")

    # Positive floor, same reasoning as audit_action_literals_spec.rb's F1:
    # `offenders` reads empty both when every literal is registered AND when
    # the extraction matched nothing — 18 is the actual raw literal count
    # across these three files as of this task (7 account.* + 7 user.* + 4
    # data_deletion.*); verified by temporarily excluding one file, which
    # drops the count below this floor and fails the example.
    expect(total_literal_occurrences).to be >= 15
  end

  it "covers every log_internal_audit writer under app/controllers/api/v1/internal/*.rb whose literal " \
     "falls in this domain (guards the scan derivation itself, via an independent extraction mechanism)" do
    # git grep, not Ruby File.read + regex — a genuinely separate mechanism
    # from `scan_roots` above, scanning the SAME real directory glob rather
    # than the three files it is meant to check, so a fourth deletion-domain
    # writer dropped anywhere in this directory would surface here as a
    # divergence instead of being silently invisible to both sides at once.
    grep_files, status = Open3.capture2(
      "git", "-C", Rails.root.to_s, "grep", "-l", "-E",
      "-e", 'log_internal_audit\([[:space:]]*["\'](account\.|user\.|data_deletion\.)',
      "--", "app/controllers/api/v1/internal/*.rb"
    )
    raise "git grep failed: #{grep_files}" unless status.success? || status.exitstatus == 1

    expected = grep_files.lines.map(&:chomp).map { |f| Rails.root.join(f).to_s }.sort
    expect(scan_roots).to eq(expected)
  end
end
