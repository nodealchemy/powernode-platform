# frozen_string_literal: true

namespace :powernode do
  namespace :cache do
    desc "One-time: empty solid_cache_entries of entries written before cache encryption. " \
         "Marker-guarded (FORCE=1 re-runs), bounded (BUDGET seconds, default 30), never raises. " \
         "Exits non-zero only when the clear failed, so a caller can retry next boot."
    task clear_legacy_plaintext: :environment do
      outcome = Powernode::LegacyCachePlaintextClear.run_once!(
        time_budget: ENV.fetch("BUDGET", "30").to_f, force: ENV["FORCE"].to_s == "1"
      )
      puts "legacy cache plaintext clear: #{outcome.status}#{" (#{outcome.error_class})" if outcome.error_class}"
      exit(1) if outcome.status == :failed
    end
  end
end
