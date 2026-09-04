namespace :db do
  namespace :seed do
    desc "Reset database and load all seeds including test data (development/test only)"
    task reset_with_test: :environment do
      if Rails.env.production?
        puts "❌ Cannot run reset_with_test in production environment!"
        exit 1
      end

      puts "⚠️  This will DELETE all data and reload seeds!"
      print "Are you sure? (y/N): "

      input = STDIN.gets.chomp
      unless input.downcase == "y"
        puts "Cancelled."
        exit 0
      end

      puts "\n🔄 Resetting database..."
      Rake::Task["db:drop"].invoke
      Rake::Task["db:create"].invoke
      Rake::Task["db:migrate"].invoke
      Rake::Task["db:seed"].invoke

      puts "\n✨ Database reset and seeded successfully!"
    end

    # IMP-e8513b30152d — the narrow, absence-only remedy for the one baseline
    # row that is PER-ACCOUNT rather than global.
    #
    # `db:seed` is FIRST BOOT ONLY on a deployed install (the hub's
    # rails-start.sh seeds solely while its durable `.db-initialized` marker is
    # absent, and runs `db:migrate` alone on every later boot — the same gap
    # that left nine seeded governance rows unlanded on ops-hub, measured
    # 2026-08-24). So an install upgraded ONTO the Claude Code provider scope
    # has accounts without one, and Ai::ClaudeExport::ExecutionRecorder
    # deliberately no longer mints it on report — it refuses by name and points
    # here. Re-running the WHOLE seed set on an established install to add one
    # row is the wrong shape; this task adds only what is missing.
    #
    # Idempotent and non-destructive: ensure_for! creates absence only and
    # ADOPTS a row the pre-seed on-demand path already minted (backfilling its
    # source key). It never deactivates, re-points or deletes an operator's row.
    desc "Backfill the inactive claude-code Ai::Provider scope for every account (safe to re-run)"
    task claude_code_provider_scopes: :environment do
      seeded = Ai::ClaudeExport::ProviderScopeSeeder.ensure_all!
      puts "✅ claude-code provider scope ensured for #{seeded} account(s)"
    end

    # HIER-P2B-ENG — the same shape, and the same reason, as the backfill
    # above: `db:seed` is FIRST BOOT ONLY on a deployed install, so the
    # `release.build_dispatch` floor that db/seeds/ai_engineering_agents_seed.rb
    # writes never reaches an install that is already up. Without it every MCP
    # build dispatch parks behind the unmatched-category require_approval
    # default, because the principals that dispatch builds (an operator's
    # mcp_client session, a dev-cell instance principal) match no agent-scoped
    # row. Run this once after upgrading onto the release gating.
    #
    # Absence-only and non-destructive: it never rewrites, deactivates or
    # deletes a row an operator retuned. Safe to re-run.
    desc "Backfill the release.build_dispatch auto_approve floor for every account (safe to re-run)"
    task engineering_release_floor: :environment do
      written = Ai::Engineering::ReleaseDispatchFloorSeeder.ensure_all!
      puts "✅ release.build_dispatch floor ensured (#{written} row(s) written)"
    end

    desc "Load minimal production seeds only (no test data)"
    task minimal: :environment do
      # Temporarily set environment to production to skip test data loading
      original_env = Rails.env
      Rails.env = "production"

      begin
        puts "🌱 Loading minimal seed data only..."
        load Rails.root.join("db", "seeds.rb")
        puts "✅ Minimal seed data loaded successfully!"
      ensure
        Rails.env = original_env
      end
    end
  end
end
