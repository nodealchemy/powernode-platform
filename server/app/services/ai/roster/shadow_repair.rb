# frozen_string_literal: true

module Ai
  module Roster
    # Repairs the rows that landed on a GLOBAL roster canonical before runtime
    # writers resolved through the account's shadow (6 Claude Code runs hit the
    # global platform-engineer). For every account holding such rows it mints the
    # shadows (Ai::Agents::AccountPrincipalResolver.for, creator the account owner,
    # or CREATOR=<email>) and re-points Ai::AgentExecution and
    # Ai::SkillUsageRecord from the global canonical to the account's shadow,
    # writing one Ai::RosterMigrationRun ledger row per move.
    #
    # Dry run by default (count, first 3, last 1); APPLY=1 applies; ROLLBACK=<run_id>
    # reverses a run from its ledger. Idempotent: once nothing sits on a global
    # canonical there is nothing to move and nothing is written. Rollback restores
    # the re-pointed rows (only those still on the shadow it moved them to); it
    # leaves minted shadows in place, since a shadow may already carry state.
    class ShadowRepair
      KIND = "shadow_repair"
      MOVED_TABLES = { "ai_agent_executions" => "Ai::AgentExecution", "ai_skill_usage_records" => "Ai::SkillUsageRecord" }.freeze
      MINT_TABLE = "ai_agents"

      class UnknownRun < StandardError; end

      # Rake entry point. ENV: APPLY=1, ROLLBACK=<run_id>.
      def self.operator_run(env: ENV, out: $stdout)
        repair = new(out: out, creator_email: env["CREATOR"])
        if env["ROLLBACK"].present?
          repair.rollback!(env["ROLLBACK"])
        elsif env["APPLY"] == "1"
          repair.apply!
        else
          repair.dry_run
        end
      end

      # @param creator_email [String, nil] a deliberate choice of shadow creator (CREATOR=<email>);
      #   it must be a user of each account it is applied to. Without it the creator is the
      #   account owner, and nobody else: a shadow's tool permissions are scoped to its creator,
      #   so an arbitrary user is never chosen.
      def initialize(out: $stdout, creator_email: nil)
        @out = out
        @creator_email = creator_email.presence
      end

      # Prints what APPLY would move; changes nothing.
      def dry_run
        rows = candidates
        if rows.empty?
          say "Nothing to repair: no execution or skill-usage row sits on a global roster canonical."
          return nil
        end

        say "This will affect #{rows.size} rows (#{rows.count { |r| r[:table] == 'ai_agent_executions' } } executions, " \
            "#{rows.count { |r| r[:table] == 'ai_skill_usage_records' } } skill usage records) across " \
            "#{rows.map { |r| r[:account_id] }.uniq.size} account(s). Dry run: nothing changed. APPLY=1 applies."
        rows.first(3).each_with_index { |r, i| say "  first #{i + 1}: #{describe(r)}" }
        say "  last #{rows.size}: #{describe(rows.last)}" if rows.size > 3
        say "  last #{rows.size}: (same as the rows above)" if rows.size <= 3
        rows.size
      end

      # @return [String, nil] the run id, nil when there was nothing to move
      def apply!
        rows = candidates
        if rows.empty?
          say "Nothing to repair."
          return nil
        end

        run_id = SecureRandom.uuid
        moved = 0
        rows.group_by { |r| r[:account_id] }.each do |account_id, account_rows|
          moved += repair_account(run_id, account_id, account_rows)
        end
        say "Applied: moved #{moved} of #{rows.size} rows. run_id=#{run_id}  (reverse with ROLLBACK=#{run_id})"
        run_id
      end

      # @raise [UnknownRun] when the ledger holds no row for the run
      def rollback!(run_id)
        ledger = Ai::RosterMigrationRun.for_run(KIND, run_id).where(table_name: MOVED_TABLES.keys).order(:created_at, :id).to_a
        if ledger.empty?
          raise UnknownRun, "No #{KIND} ledger rows for run #{run_id}" unless Ai::RosterMigrationRun.for_run(KIND, run_id).exists?
        end

        restored = 0
        ledger.group_by(&:table_name).each do |table, entries|
          model = MOVED_TABLES.fetch(table).constantize
          entries.each do |entry|
            restored += model.where(id: entry.record_id, ai_agent_id: entry.to_id).update_all(ai_agent_id: entry.from_id)
          end
        end
        say "Rolled back run #{run_id}: restored #{restored} of #{ledger.size} rows (minted shadows are left in place)."
        restored
      end

      private

      def say(line) = @out.puts(line)

      def roster_globals
        @roster_globals ||= ::Ai::Agent.global.where(slug: ::Ai::Agents::CanonicalRoster.slugs).pluck(:id, :slug).to_h
      end

      # Rows on a global roster canonical, oldest first. Ordered the same way each run.
      def candidates
        ids = roster_globals.keys
        return [] if ids.empty?

        MOVED_TABLES.flat_map do |table, model_name|
          model_name.constantize.where(ai_agent_id: ids).order(:created_at, :id).pluck(:id, :account_id, :ai_agent_id).map do |id, account_id, agent_id|
            { table: table, id: id, account_id: account_id, from: agent_id, slug: roster_globals[agent_id] }
          end
        end
      end

      def describe(row)
        "#{row[:table]} #{row[:id]} account=#{row[:account_id]} #{row[:slug]} (#{row[:from]}) -> shadow"
      end

      def repair_account(run_id, account_id, account_rows)
        account = ::Account.find_by(id: account_id)
        if account && @creator_email
          creator = account.users.find_by(email: @creator_email.downcase)
          unless creator
            say "  skipped account #{account_id}: creator_not_in_account (CREATOR=#{@creator_email} is not a user of it); " \
                "#{account_rows.size} rows left"
            return 0
          end
        else
          creator = account&.owner
        end
        unless account && creator
          say "  skipped account #{account_id}: no_mintable_principal (the account has no owner to own a shadow; " \
              "pass CREATOR=<email> to choose one); #{account_rows.size} rows left"
          return 0
        end

        moved = 0
        ::Ai::Agent.transaction do
          shadows = {}
          roster_globals.each_value do |slug|
            existed = ::Ai::Agent.owned_by_account(account.id).exists?(slug: slug)
            shadow = ::Ai::Agents::AccountPrincipalResolver.for(canonical_slug: slug, account: account, user: creator)
            shadows[slug] = shadow
            next if existed || shadow.nil?

            ledger(run_id, account.id, MINT_TABLE, shadow.id, nil, shadow.id, "minted" => true, "canonical_slug" => slug)
          end

          needed = account_rows.map { |r| r[:slug] }.uniq
          missing = needed.select { |slug| shadows[slug].nil? || shadows[slug].global? }
          if missing.any?
            say "  skipped account #{account.id}: no_mintable_principal for #{missing.join(', ')} (no active provider?); #{account_rows.size} rows left"
            raise ActiveRecord::Rollback
          end

          account_rows.each do |row|
            shadow = shadows.fetch(row[:slug])
            model = MOVED_TABLES.fetch(row[:table]).constantize
            next unless model.where(id: row[:id], ai_agent_id: row[:from]).update_all(ai_agent_id: shadow.id) == 1

            ledger(run_id, account.id, row[:table], row[:id], row[:from], shadow.id, "canonical_slug" => row[:slug])
            moved += 1
          end
        end
        moved
      end

      def ledger(run_id, account_id, table, record_id, from_id, to_id, metadata)
        ::Ai::RosterMigrationRun.create!(
          kind: KIND, run_id: run_id, account_id: account_id, table_name: table,
          record_id: record_id, from_id: from_id, to_id: to_id, metadata: metadata
        )
      end
    end
  end
end
