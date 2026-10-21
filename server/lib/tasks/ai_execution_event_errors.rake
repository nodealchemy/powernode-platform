# frozen_string_literal: true

namespace :ai do
  desc "IMP-dbabbea6f81c: scrub historical approval_execution error text in ai_execution_events. " \
       "Bounded (BUDGET seconds, default 30) and marker-guarded (no-op once done; FORCE=1 re-runs). " \
       "Idempotent and never raises. The host's boot script runs the same one-shot; run it by hand elsewhere."
  task scrub_execution_event_errors: :environment do
    outcome = Ai::ExecutionEventErrorScrub.run_once!(
      time_budget: ENV.fetch("BUDGET", "30").to_f, force: ENV["FORCE"].to_s == "1"
    )
    result = outcome.result
    case outcome.status
    when :done
      puts "execution event error scrub: already done (marker #{Ai::ExecutionEventErrorScrub::DONE_MARKER}); FORCE=1 re-runs"
    when :ran
      puts "execution event error scrub: scrubbed #{result.scrubbed}, skipped #{result.skipped_rows}, complete=true"
    when :cut_short
      puts "execution event error scrub: cut short (scrubbed #{result.scrubbed}, skipped #{result.skipped_rows}, " \
           "complete=false); the marker is unset, run again to finish"
    else
      puts "execution event error scrub: FAILED (#{outcome.error_class}); the marker is unset, see the log"
    end
  end
end
