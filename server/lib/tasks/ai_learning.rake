# frozen_string_literal: true

namespace :ai do
  # ai:retire_learning_domain was DELETED here 2026-09-20 (IMP-3c9a6dc8f0a9,
  # operator directive: always remove legacy support in favour of
  # standardized platform capabilities). It is fully subsumed by
  # ai:retire_learnings_by_predicate below: PREDICATE_JSON='{"domain":"..."}'
  # retires the identical row set with identical recorded metadata — see
  # "subsumes retire_domain!" in compound_learning_service_spec.rb for the
  # equivalence proof that licensed the deletion, and
  # CompoundLearningService#retire_by_predicate!'s header comment. Grepped
  # for other references before deleting (server/worker/extensions/docs):
  # zero hits outside this file and the (now updated) service comment.
  #
  # IMP-3c9a6dc8f0a9 — dedup_promoted_learnings previously looped every
  # account with NO bound of any kind (`Account.find_each`, always mutating,
  # no dry-run). Same invocation-level hazard as the predicate tasks below,
  # standardized onto the identical ACCOUNT_ID/aggregate-ceiling guard rather
  # than left as the one bulk task in this file without it. This IS a
  # behavior change to an existing operator-run task: it previously always
  # executed; it now defaults to dry-run like every other task here, and a
  # real run requires EXECUTE=true ACCOUNT_ID=<uuid>.
  desc "Collapse duplicate promoted (team/global) compound learnings sharing identical content at the same scope; " \
       "supersedes duplicates, never hard-deletes. Dry-run by default (sweeps every account); EXECUTE=true to " \
       "mutate (requires ACCOUNT_ID=<uuid>)."
  task dedup_promoted_learnings: :environment do
    dry_run = ENV["EXECUTE"] != "true"
    accounts = Ai::BulkPredicateMutation.resolve_accounts_for_rake!(account_id: ENV["ACCOUNT_ID"].presence, dry_run: dry_run)

    previews = accounts.filter_map do |account|
      preview = Ai::Learning::CompoundLearningService.new(account: account).dedup_promoted_copies(dry_run: true)
      [ account, preview ] if preview[:count].to_i.positive?
    end

    previews.each do |account, preview|
      puts "[ai:dedup_promoted_learnings] account=#{account.id} predicted_collapse=#{preview[:count]} groups=#{preview[:groups]}"
    end

    Ai::BulkPredicateMutation.enforce_aggregate_ceiling!(previews, dry_run: dry_run)

    if dry_run
      puts "Dry run — no rows mutated. Re-run with EXECUTE=true and ACCOUNT_ID=<uuid> to collapse duplicates."
      next
    end

    previews.each do |account, _preview|
      result = Ai::Learning::CompoundLearningService.new(account: account).dedup_promoted_copies

      Rails.logger.info("[ai:dedup_promoted_learnings] account=#{account.id} #{result}")
      puts "[ai:dedup_promoted_learnings] account=#{account.id} #{result}"
    end
  end

  # IMP-3c9a6dc8f0a9 — predicate-scoped bulk retire/hard-delete: retire by
  # status/category/extraction_method/min_importance/age/id/domain (see
  # PREDICATE_JSON in the desc below; domain: subsumes the now-deleted
  # ai:retire_learning_domain, see the note above).
  #
  # DRY-RUN IS THE DEFAULT. Set EXECUTE=true to actually mutate — one
  # deliberate env var, not a flag a copy-pasted invocation carries forward
  # by accident. Every invocation prints each account's count and a
  # first-3/last-1 sample before anything happens.
  #
  # ACCOUNT_ID IS REQUIRED FOR EXECUTE=true — see ai_knowledge.rake's header
  # comment for why a bare Account.find_each defeats
  # Ai::BulkPredicateMutation::MAX_BULK_PER_CALL on a multi-account mutating
  # run, and why the aggregate-ceiling check backs up the ACCOUNT_ID
  # requirement rather than replacing it.
  desc "Predicate-scoped bulk retire of compound learnings. PREDICATE_JSON (env var!): " \
       "{\"status\":,\"category\":,\"scope\":,\"min_importance\":,\"team_id\":,\"extraction_method\":,\"domain\":,\"created_before\":,\"ids\":[...]}. " \
       "Dry-run by default (sweeps every account); EXECUTE=true to mutate (requires ACCOUNT_ID=<uuid>). " \
       "REASON (env var, optional) is recorded on each retired row."
  task retire_learnings_by_predicate: :environment do
    # IMP-3c9a6dc8f0a9 review round (BLOCKER 2) — PREDICATE_JSON/REASON
    # moved from bracketed task args to ENV, matching EXECUTE/ACCOUNT_ID —
    # see ai_knowledge.rake's identical note for why (an operator setting a
    # documented-as-neighbouring value the wrong way got the WIDEST
    # possible scope silently; a multi-key JSON predicate was also DOA
    # through Rake's own comma-splitting on a bracketed arg).
    predicate = ENV["PREDICATE_JSON"].presence ? JSON.parse(ENV["PREDICATE_JSON"]).symbolize_keys : {}
    dry_run = ENV["EXECUTE"] != "true"
    reason = ENV["REASON"].presence
    accounts = Ai::BulkPredicateMutation.resolve_accounts_for_rake!(account_id: ENV["ACCOUNT_ID"].presence, dry_run: dry_run)

    previews = accounts.filter_map do |account|
      preview = Ai::Learning::CompoundLearningService.new(account: account).retire_by_predicate!(predicate: predicate, dry_run: true)
      [ account, preview ] if preview[:count].to_i.positive?
    end

    previews.each do |account, preview|
      puts "[ai:retire_learnings_by_predicate] account=#{account.id} predicted_count=#{preview[:count]} sample=#{preview[:sample]}"
    end

    Ai::BulkPredicateMutation.enforce_aggregate_ceiling!(previews, dry_run: dry_run)

    if dry_run
      puts "Dry run — no rows mutated. Re-run with EXECUTE=true and ACCOUNT_ID=<uuid> to retire."
      next
    end

    previews.each do |account, _preview|
      result = Ai::Learning::CompoundLearningService.new(account: account)
                 .retire_by_predicate!(predicate: predicate, dry_run: false, reason: reason)

      Rails.logger.info("[ai:retire_learnings_by_predicate] account=#{account.id} #{result}")
      puts "[ai:retire_learnings_by_predicate] account=#{account.id} count=#{result[:count]} " \
           "sample=#{result[:sample]} #{result[:success] ? '' : "ERROR: #{result[:error]}"}"
    end
  end

  # Irreversible half — only ever touches rows ALREADY status
  # retired/superseded (see CompoundLearningService#hard_delete_retired_or_superseded!'s
  # own comment); the predicate can only narrow that fixed base, never widen
  # past it. Run #retire_learnings_by_predicate first; this is a deliberate
  # second, separate step.
  desc "Hard-delete compound learnings already retired/superseded, optionally narrowed by PREDICATE_JSON " \
       "(env var! same keys as retire_learnings_by_predicate). Dry-run by default (sweeps every account); " \
       "EXECUTE=true to mutate (requires ACCOUNT_ID=<uuid>). IRREVERSIBLE."
  task hard_delete_retired_learnings: :environment do
    predicate = ENV["PREDICATE_JSON"].presence ? JSON.parse(ENV["PREDICATE_JSON"]).symbolize_keys : {}
    dry_run = ENV["EXECUTE"] != "true"
    accounts = Ai::BulkPredicateMutation.resolve_accounts_for_rake!(account_id: ENV["ACCOUNT_ID"].presence, dry_run: dry_run)

    previews = accounts.filter_map do |account|
      preview = Ai::Learning::CompoundLearningService.new(account: account).hard_delete_retired_or_superseded!(predicate: predicate, dry_run: true)
      [ account, preview ] if preview[:count].to_i.positive?
    end

    previews.each do |account, preview|
      puts "[ai:hard_delete_retired_learnings] account=#{account.id} predicted_count=#{preview[:count]} sample=#{preview[:sample]}"
    end

    Ai::BulkPredicateMutation.enforce_aggregate_ceiling!(previews, dry_run: dry_run)

    if dry_run
      puts "Dry run — no rows mutated. Re-run with EXECUTE=true and ACCOUNT_ID=<uuid> to hard-delete."
      next
    end

    previews.each do |account, _preview|
      result = Ai::Learning::CompoundLearningService.new(account: account)
                 .hard_delete_retired_or_superseded!(predicate: predicate, dry_run: false)

      Rails.logger.info("[ai:hard_delete_retired_learnings] account=#{account.id} #{result}")
      puts "[ai:hard_delete_retired_learnings] account=#{account.id} count=#{result[:count]} " \
           "sample=#{result[:sample]} #{result[:success] ? '' : "ERROR: #{result[:error]}"}"
    end
  end
end
