# frozen_string_literal: true

# Operator tasks for the package catalog's embedding pipeline.
#
# Embeddings are normally generated incrementally — PackageRepositorySyncService
# enqueues SystemPackageEmbeddingJob after every sync that upserts ≥1 row.
# The tasks below are for one-off operator interventions:
#
#   - backfill_embeddings: run against the existing catalog after first
#     enabling the embedding pipeline. Idempotent — packages already
#     embedded are skipped unless `FORCE=true` is set.
#
#   - embedding_coverage:  observability — prints per-repository coverage so
#     operators can see which catalogs are still pending.
namespace :system do
  namespace :packages do
    desc "Enqueue SystemPackageEmbeddingJob for every enabled PackageRepository. Set FORCE=true to re-embed everything."
    task backfill_embeddings: :environment do
      force = ENV["FORCE"] == "true"
      enabled = ::System::PackageRepository.enabled.order(:name)
      if enabled.empty?
        puts "No enabled package repositories — nothing to enqueue."
        next
      end

      enabled.find_each do |repo|
        jid = ::System::WorkerJobEnqueuer.enqueue(
          job_class: "SystemPackageEmbeddingJob",
          args:      [repo.id, { "force" => force }],
          queue:     "system"
        )
        marker = jid ? "[jid=#{jid[0..7]}]" : "[ENQUEUE FAILED]"
        puts "  #{marker} #{repo.name.ljust(40)} kind=#{repo.kind.ljust(4)} pkgs=#{repo.package_count} force=#{force}"
      end
      puts "Done — #{enabled.size} repositories enqueued."
    end

    desc "Report embedding coverage per PackageRepository (pending / embedded / percent)."
    task embedding_coverage: :environment do
      repos = ::System::PackageRepository.order(:name)
      if repos.empty?
        puts "No package repositories."
        next
      end

      header = ["repository".ljust(40), "kind".ljust(4), "live", "embedded", "pending", "%"]
      puts header.join("  ")
      repos.each do |repo|
        live = ::System::Package.live.where(package_repository_id: repo.id)
        total = live.count
        embedded = live.with_embedding.count
        pending = total - embedded
        pct = total.positive? ? ((embedded.to_f / total) * 100).round(1) : 0.0
        puts [
          repo.name.ljust(40),
          repo.kind.ljust(4),
          total.to_s.rjust(6),
          embedded.to_s.rjust(8),
          pending.to_s.rjust(7),
          "#{pct}%".rjust(6)
        ].join("  ")
      end
    end
  end
end
