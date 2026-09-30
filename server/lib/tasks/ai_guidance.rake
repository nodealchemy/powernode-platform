# frozen_string_literal: true

namespace :ai do
  desc "Seed development-guidance conventions into platform knowledge (idempotent)"
  task seed_guidance: :environment do
    repository = ENV["REPOSITORY"].presence || "powernode-platform"
    Account.find_each do |account|
      result = Ai::Guidance::GuidanceKnowledgeSeeder.new(account: account, repository: repository).call
      Rails.logger.info("[ai:seed_guidance] account=#{account.id} #{result.summary}")
      puts "[ai:seed_guidance] account=#{account.id} #{result.summary}"
    end
  end

  desc "Seed THIS deployment's local operator docs (gitignored docs/operations/local/*.md) into platform knowledge as deployment-<slug> (idempotent)"
  task seed_deployment_knowledge: :environment do
    repository = ENV["REPOSITORY"].presence || "powernode-platform"
    dir = Rails.root.parent.join(*Ai::Guidance::GuidanceKnowledgeSeeder::DEPLOYMENT_DIR)
    unless dir.exist?
      puts "[ai:seed_deployment_knowledge] #{dir} does not exist — nothing to seed (see docs/contributing/conventions/deployment-knowledge.md)"
      next
    end
    Account.find_each do |account|
      result = Ai::Guidance::GuidanceKnowledgeSeeder.for_deployment(account: account, repository: repository).call
      Rails.logger.info("[ai:seed_deployment_knowledge] account=#{account.id} #{result.summary}")
      puts "[ai:seed_deployment_knowledge] account=#{account.id} #{result.summary}"
    end
  end

  desc "Migrate auto-memory notes into account-scoped platform knowledge as memory:<slug>. " \
       "DRY-RUN by default (plans + triage report, writes nothing to the database). " \
       "APPLY=1 ACCOUNT_ID=<id> writes; INCLUDE_SENSITIVE=1 also applies the break-glass/security-gap set (b); " \
       "sets (a) identifiers and (c) private names are never applied. Env: IDENTIFIERS_FILE, MANIFEST_DIR, ALLOW_NO_IDENTIFIERS"
  task :migrate_auto_memory, [ :dir ] => :environment do |_t, args|
    dir = args[:dir].presence
    abort "[ai:migrate_auto_memory] usage: rake 'ai:migrate_auto_memory[<memory dir>]' (dir is required)" unless dir

    flag = ->(name) { ENV[name] == "1" }
    apply = flag.call("APPLY")
    account = nil
    if apply
      abort "[ai:migrate_auto_memory] APPLY=1 requires ACCOUNT_ID=<account id>" if ENV["ACCOUNT_ID"].blank?
      account = Account.find(ENV["ACCOUNT_ID"])
    end

    begin
      report = Ai::Guidance::AutoMemoryMigrator.new(
        dir: dir, account: account, apply: apply,
        include_sensitive: flag.call("INCLUDE_SENSITIVE"),
        identifiers_path: ENV["IDENTIFIERS_FILE"].presence,
        require_identifiers: !flag.call("ALLOW_NO_IDENTIFIERS"),
        manifest_dir: ENV["MANIFEST_DIR"].presence
      ).call
    rescue Ai::Guidance::AutoMemoryMigrator::Error => e
      abort "[ai:migrate_auto_memory] #{e.message}"
    end
    report.lines.each { |line| puts line }
    puts "  (dry run — nothing written to the database; APPLY=1 ACCOUNT_ID=<id> to apply)" unless apply
  end
end
