# frozen_string_literal: true

# IMP-3c9a6dc8f0a9 — predicate-scoped bulk archive/hard-delete for shared
# knowledge (`delete_knowledge` takes one id per call; this is the predicate
# path — report-platform.md §8/§10).
#
# DRY-RUN IS THE DEFAULT on both tasks. Set EXECUTE=true to actually mutate —
# one deliberate env var, not a flag a copy-pasted invocation carries forward
# by accident. Every invocation prints each account's count and a
# first-3/last-1 sample before anything happens.
#
# ACCOUNT_ID IS REQUIRED FOR EXECUTE=true. A dry run may omit it to survey
# every account; a mutating run must name exactly one. Without this, looping
# every account (which a bare `Account.find_each` would do) defeats
# Ai::BulkPredicateMutation::MAX_BULK_PER_CALL by construction: the ceiling
# bounds ONE account's scope, so a hundred accounts each matching 400 rows
# each pass their own check while the invocation destroys 40,000. See
# Ai::BulkPredicateMutation#resolve_accounts_for_rake!/
# #enforce_aggregate_ceiling! for the two-part fix (per-account is not
# enough on its own; the aggregate check backs it up even if the ACCOUNT_ID
# requirement is ever loosened by a future edit).
namespace :ai do
  desc "Predicate-scoped bulk archive of shared knowledge entries. PREDICATE_JSON (env var!): " \
       "{\"source_type\":,\"content_type\":,\"access_level\":,\"tags\":[...],\"imported_from\":,\"created_before\":,\"ids\":[...]}. " \
       "Dry-run by default (sweeps every account); EXECUTE=true to mutate (requires ACCOUNT_ID=<uuid>). " \
       "Soft, reversible (unset provenance.archived to undo)."
  task archive_knowledge_by_predicate: :environment do
    # IMP-3c9a6dc8f0a9 review round (BLOCKER 2) — PREDICATE_JSON used to be
    # a bracketed rake TASK ARG (`[:predicate_json]`), documented in the
    # same breath as EXECUTE/ACCOUNT_ID (both ENV vars) — an operator
    # setting it as an env var like its two neighbours got `args[...] ==
    # nil` -> predicate = {} -> the WIDEST possible scope, silently, with a
    # plausible-looking row count in the output. Worse: Rake splits a
    # bracketed arg string on commas before this task ever sees it, so
    # `rake ai:archive_knowledge_by_predicate['{"a":1,"b":2}']` was DOA for
    # any predicate with more than one key. ENV, matching EXECUTE/
    # ACCOUNT_ID, removes both failure modes — there is no bracket for Rake
    # to split, and one consistent invocation style for all three.
    predicate = ENV["PREDICATE_JSON"].presence ? JSON.parse(ENV["PREDICATE_JSON"]).symbolize_keys : {}
    dry_run = ENV["EXECUTE"] != "true"
    accounts = Ai::BulkPredicateMutation.resolve_accounts_for_rake!(account_id: ENV["ACCOUNT_ID"].presence, dry_run: dry_run)

    previews = accounts.filter_map do |account|
      preview = Ai::Memory::SharedKnowledgeService.new(account: account).archive_by_predicate!(predicate: predicate, dry_run: true)
      [ account, preview ] if preview[:count].to_i.positive?
    end

    previews.each do |account, preview|
      puts "[ai:archive_knowledge_by_predicate] account=#{account.id} predicted_count=#{preview[:count]} sample=#{preview[:sample]}"
    end

    Ai::BulkPredicateMutation.enforce_aggregate_ceiling!(previews, dry_run: dry_run)

    if dry_run
      puts "Dry run — no rows mutated. Re-run with EXECUTE=true and ACCOUNT_ID=<uuid> to archive."
      next
    end

    previews.each do |account, _preview|
      result = Ai::Memory::SharedKnowledgeService.new(account: account).archive_by_predicate!(predicate: predicate, dry_run: false)

      Rails.logger.info("[ai:archive_knowledge_by_predicate] account=#{account.id} #{result}")
      puts "[ai:archive_knowledge_by_predicate] account=#{account.id} count=#{result[:count]} " \
           "sample=#{result[:sample]} #{result[:success] ? '' : "ERROR: #{result[:error]}"}"
    end
  end

  # Irreversible half — only ever touches rows ALREADY provenance.archived=true
  # (see SharedKnowledgeService#hard_delete_archived!'s own comment); the
  # predicate can only narrow that fixed base, never widen past it. Run
  # #archive_knowledge_by_predicate first; this is a deliberate second,
  # separate step.
  desc "Hard-delete shared knowledge entries already archived, optionally narrowed by PREDICATE_JSON " \
       "(env var! same keys as archive_knowledge_by_predicate, plus :archived_before). Dry-run by default " \
       "(sweeps every account); EXECUTE=true to mutate (requires ACCOUNT_ID=<uuid>). IRREVERSIBLE."
  task hard_delete_archived_knowledge: :environment do
    predicate = ENV["PREDICATE_JSON"].presence ? JSON.parse(ENV["PREDICATE_JSON"]).symbolize_keys : {}
    dry_run = ENV["EXECUTE"] != "true"
    accounts = Ai::BulkPredicateMutation.resolve_accounts_for_rake!(account_id: ENV["ACCOUNT_ID"].presence, dry_run: dry_run)

    previews = accounts.filter_map do |account|
      preview = Ai::Memory::SharedKnowledgeService.new(account: account).hard_delete_archived!(predicate: predicate, dry_run: true)
      [ account, preview ] if preview[:count].to_i.positive?
    end

    previews.each do |account, preview|
      puts "[ai:hard_delete_archived_knowledge] account=#{account.id} predicted_count=#{preview[:count]} sample=#{preview[:sample]}"
    end

    Ai::BulkPredicateMutation.enforce_aggregate_ceiling!(previews, dry_run: dry_run)

    if dry_run
      puts "Dry run — no rows mutated. Re-run with EXECUTE=true and ACCOUNT_ID=<uuid> to hard-delete."
      next
    end

    previews.each do |account, _preview|
      result = Ai::Memory::SharedKnowledgeService.new(account: account).hard_delete_archived!(predicate: predicate, dry_run: false)

      Rails.logger.info("[ai:hard_delete_archived_knowledge] account=#{account.id} #{result}")
      puts "[ai:hard_delete_archived_knowledge] account=#{account.id} count=#{result[:count]} " \
           "sample=#{result[:sample]} #{result[:success] ? '' : "ERROR: #{result[:error]}"}"
    end
  end
end
