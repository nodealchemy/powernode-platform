# frozen_string_literal: true

require "open3"

module Ai
  module Deploy
    # Deterministic, conservative pre-deploy gate: does deploying `target_ref` over the
    # currently-deployed `base_ref` introduce DB migrations that can't be cleanly
    # auto-rolled-back? Auto-deploy blocks on irreversible DDL unless allow_irreversible,
    # because the Orchestrator's safety net is auto-rollback on health failure, and an
    # irreversible migration would make that rollback unsafe.
    #
    # Heuristic (errs toward FLAGGING — a false "irreversible" only forces an explicit
    # override; a missed one would be dangerous):
    #   reversible   = an explicit `def down`, OR a `def change` using only clearly
    #                  reversible ops.
    #   irreversible = a `def change` containing drop_table / drop_column / remove_column /
    #                  change_column / execute / remove_reference with NO `def down`,
    #                  OR a `def up` with no matching `def down`.
    class MigrationSafetyChecker
      IRREVERSIBLE_OPS = /\b(drop_table|drop_column|remove_column|change_column(?!_default|_null|_comment)|execute|remove_reference|remove_belongs_to)\b/
      MIGRATE_DIR_HINT = "db/migrate/"
      MIGRATE_GLOBS = ["db/migrate", "server/db/migrate"].freeze

      Report = Struct.new(:safe, :added, :irreversible, :reasons, keyword_init: true) do
        def safe?
          safe
        end

        def to_h
          { safe: safe, added: added, irreversible: irreversible, reasons: reasons }
        end
      end

      def initialize(repository_path:)
        @repo = repository_path
      end

      def check(base_ref:, target_ref:, allow_irreversible: false)
        added = added_migration_files(base_ref, target_ref)
        irreversible = added.select { |path| irreversible?(target_ref, path) }
        reasons = []
        if irreversible.any?
          reasons << "#{irreversible.size} potentially irreversible migration(s): #{irreversible.join(', ')}"
          reasons << "allowed by allow_irreversible override" if allow_irreversible
        end
        Report.new(
          safe: irreversible.empty? || allow_irreversible,
          added: added, irreversible: irreversible, reasons: reasons
        )
      end

      private

      def git(*args)
        out, _err, status = Open3.capture3("git", *args, chdir: @repo)
        status.success? ? out : ""
      end

      # Migration files ADDED between base and target (filter A = added).
      def added_migration_files(base, target)
        pathspecs = MIGRATE_GLOBS.map { |g| "#{g}/*.rb" }
        git("diff", "--name-only", "--diff-filter=A", "#{base}..#{target}", "--", *pathspecs)
          .split("\n").map(&:strip).reject(&:empty?)
          .select { |p| p.include?(MIGRATE_DIR_HINT) }
      end

      def irreversible?(target_ref, path)
        body = git("show", "#{target_ref}:#{path}")
        return false if body.blank?
        return false if body.match?(/def\s+down\b/)   # explicit reversal provided
        return true if body.match?(/def\s+up\b/)      # up with no down

        body.match?(IRREVERSIBLE_OPS)                 # change with an irreversible op
      end
    end
  end
end
