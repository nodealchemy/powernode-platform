# frozen_string_literal: true

# Read-only checks for capability skills. The gate and eval tasks write no row;
# their only side effect is the embeddings they compute (cached per account by the
# embedding service). Owners are "core" or "extensions/<slug>" (loaded only).
#
#   rails "skills:gate:check[core,provider]"
#   rails "skills:gate:check[extensions/<slug>,provider,<account-id>]"   (an extension's seed batch)
#   rails "skills:eval:discovery[provider,<account-id>]"          (legacy rows compete)
#   rails "skills:eval:discovery[provider,<account-id>,false]"    (post-retirement view)
#
# embedder: provider (the account's embedding provider; no fallback — fails if
# any text cannot be embedded), lexical, or auto. account: defaults to the
# first account.
namespace :skills do
  account_for = lambda do |id|
    next Account.first if id.blank?

    Account.find_by(id: id) || abort("skills: no account #{id}")
  end

  pct = ->(n, d) { d.zero? ? "n/a" : "#{(100.0 * n / d).round(1)}%" }
  mark_for = lambda do |row|
    if row.expected
      return "HIT1" if row.hit1

      row.hit3 ? "HIT3" : "MISS"
    elsif row.false_first
      "FALSE-FIRST"
    else
      row.false_top3 ? "false-top3" : "ok"
    end
  end

  namespace :gate do
    desc "Dry-run the capability skill seed gate for one owner: print same-domain pairs >= 0.6 and every violation; exit 1 on any violation"
    task :check, %i[owner embedder account_id] => :environment do |_task, args|
      owner = args[:owner].presence || Ai::Skills::Contract::CORE_OWNER
      account = account_for.call(args[:account_id])
      # Batches seeded before this owner's (core before any extension) count as
      # relation targets, so an extension dry-runs before core is seeded here.
      sources = Ai::Skills::CapabilitySeeder.data_sources
      earlier = sources.take_while { |o, _| o != owner }.flat_map do |o, dir|
        Ai::Skills::CapabilitySeeder.load_entries(dir).map { |raw| Ai::Skills::CapabilitySeeder.normalize(raw, o) }
      end
      gate = Ai::Skills::SeedGate.new(owner_repo: owner, embedder: args[:embedder].presence || "provider", account: account, pending: earlier)
      entries = Ai::Skills::CapabilitySeeder.load_entries(Ai::Skills::CapabilitySeeder.data_dir_for(owner))
                                            .map { |raw| Ai::Skills::CapabilitySeeder.normalize(raw, owner) }

      begin
        pairs = gate.similarity_report(entries)
        violations = gate.violations(entries)
      rescue Ai::Skills::SkillEmbedder::EmbeddingUnavailable => e
        abort("skills:gate:check — #{e.message}")
      end

      puts "Capability seed gate dry-run: owner=#{owner} skills=#{entries.size} account=#{account&.id || 'none'} " \
           "embedder=#{gate.embedder_mode_used} (writes nothing)"
      puts "\nSame-domain pairs >= #{Ai::Skills::SeedGate::REPORT_FLOOR} (similarity, band, margin to next band, not_for names a->b / b->a):"
      puts "  (none)" if pairs.empty?
      pairs.each do |p|
        puts format("  %-6.4f %-11s margin %-7.4f %s <-> %s [%s] named %s/%s",
                    p[:similarity], p[:band] || "-", p[:margin], p[:a], p[:b], p[:domain],
                    p[:a_names_b] ? "y" : "n", p[:b_names_a] ? "y" : "n")
      end
      warnings = gate.warnings(entries)
      puts "\nWarnings (non-fatal): #{warnings.size}"
      warnings.each { |w| puts "  - #{w}" }
      puts "\nViolations: #{violations.size}"
      violations.each { |v| puts "  - #{v}" }
      exit(violations.empty? ? 0 : 1)
    end
  end

  namespace :eval do
    desc "Record real provider embeddings for each loaded owner's eval corpus into that owner's spec fixture (writes no row)"
    task :record_embeddings, %i[account_id owner] => :environment do |_task, args|
      account = account_for.call(args[:account_id])
      owners = Ai::Skills::CapabilitySeeder.owner_roots
      owners = owners.select { |owner, _| owner == args[:owner] } if args[:owner].present?
      abort("skills:eval:record_embeddings — unknown owner #{args[:owner].inspect}") if owners.empty?

      owners.each do |owner, root|
        texts = Ai::Skills::RecordedEmbeddings.corpus_for(owner, root)
        begin
          fixture = Ai::Skills::RecordedEmbeddings.record(texts, account: account)
        rescue Ai::Skills::SkillEmbedder::EmbeddingUnavailable => e
          abort("skills:eval:record_embeddings (#{owner}) — #{e.message}")
        end
        dir = Ai::Skills::RecordedEmbeddings.fixture_dir(root)
        FileUtils.mkdir_p(dir)
        File.write(dir.join("vectors.json"), "#{JSON.pretty_generate(fixture)}\n")
        puts "#{owner}: recorded #{fixture['vectors'].size} embeddings (#{fixture['format']}) to #{dir.join('vectors.json')}"
      end
    end

    desc "Run every capability skill eval through discovery ranking at the real cut-off; report hit@1, hit@3 and false-firsts"
    task :discovery, %i[embedder account_id legacy] => :environment do |_task, args|
      account = account_for.call(args[:account_id])
      runner = Ai::Skills::DiscoveryEvalRunner.new(embedder: args[:embedder].presence || "provider", account: account,
                                                   legacy: args[:legacy].to_s != "false")
      begin
        runner.run
      rescue Ai::Skills::SkillEmbedder::EmbeddingUnavailable => e
        abort("skills:eval:discovery — #{e.message}")
      end

      runner.rows.each do |row|
        mark = mark_for.call(row)
        facet = row.project_kind ? " [#{row.project_kind}]" : ""
        puts format("%-11s %-30s rank=%-4s %s%s -> %s", mark, row.slug, row.rank || "-", row.task.truncate(70), facet, row.top.join(", "))
      end
      t = runner.totals
      puts "\naccount=#{account&.id || 'none'} embedder=#{t[:embedder]} distance<=#{t[:threshold]} legacy_competition=#{t[:legacy]}"
      puts "positives #{t[:positives]}: hit@1 #{t[:hit1]} (#{pct.call(t[:hit1], t[:positives])}), hit@3 #{t[:hit3]} (#{pct.call(t[:hit3], t[:positives])})"
      puts "negatives #{t[:negatives]}: false-first #{t[:false_first]}, in top 3 #{t[:false_top3]}; empty results #{t[:empty]}"
    end
  end
end
