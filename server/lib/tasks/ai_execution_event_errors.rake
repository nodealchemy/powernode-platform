# frozen_string_literal: true

namespace :ai do
  desc "IMP-dbabbea6f81c: scrub historical approval_execution error text in ai_execution_events " \
       "(idempotent; prints counts only). Re-run if it reports skipped rows."
  task scrub_execution_event_errors: :environment do
    result = Ai::ExecutionEventErrorScrub.call
    puts "scrubbed #{result.scrubbed} row(s); skipped #{result.skipped_rows} row(s) on lock contention"
    puts "Run again to finish the skipped rows." unless result.complete?
  end
end
