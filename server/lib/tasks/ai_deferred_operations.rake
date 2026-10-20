# frozen_string_literal: true

namespace :ai do
  desc "Seal/mask secret-bearing params on pre-existing deferred operations (DRY_RUN=false to write)"
  task backfill_deferred_operation_params: :environment do
    dry_run = ENV["DRY_RUN"] != "false"
    counts = Ai::DeferredOperation.backfill_params_seal(dry_run: dry_run)
    puts "deferred operations: sealed=#{counts[:sealed]} masked=#{counts[:masked]} " \
         "skipped=#{counts[:skipped]} #{dry_run ? '(dry run; DRY_RUN=false to apply)' : '(applied)'}"
  end
end
