# frozen_string_literal: true

namespace :ai do
  namespace :roster do
    desc "Move runs and skill-usage rows off the GLOBAL roster canonicals onto each account's shadow. " \
         "Dry run by default (count, first 3, last 1); APPLY=1 applies with a ledger row per move; " \
         "ROLLBACK=<run_id> reverses a run from its ledger. Idempotent."
    task repair_shadows: :environment do
      Ai::Roster::ShadowRepair.operator_run
    end
  end
end
