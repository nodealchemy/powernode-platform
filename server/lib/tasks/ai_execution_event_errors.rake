# frozen_string_literal: true

namespace :ai do
  desc "IMP-dbabbea6f81c: scrub historical approval_execution error text in ai_execution_events. " \
       "Bounded (BUDGET seconds, default 30) and marker-guarded (no-op once done; FORCE=1 re-runs). " \
       "Idempotent and never raises. Run every boot by rails-start.sh and by hand."
  task scrub_execution_event_errors: :environment do
    budget = ENV.fetch("BUDGET", "30").to_f
    force = ENV["FORCE"].to_s == "1"
    result = Ai::ExecutionEventErrorScrub.run_once!(time_budget: budget, force: force)
    if result.nil?
      puts "execution event error scrub: already done (marker #{Ai::ExecutionEventErrorScrub::DONE_MARKER}); FORCE=1 re-runs"
    else
      puts "execution event error scrub: scrubbed #{result.scrubbed}, skipped #{result.skipped_rows}, " \
           "complete=#{result.complete?}"
    end
  end
end
