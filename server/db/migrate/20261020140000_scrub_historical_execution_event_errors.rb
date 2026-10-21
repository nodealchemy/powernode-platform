# frozen_string_literal: true

# IMP-dbabbea6f81c. Marker only. The retroactive scrub of raw executor error
# text in ai_execution_events.error_message is NOT done here: a lock wait on a
# busy table inside db:migrate must not keep the app from starting. The scrub
# runs every boot from the host's boot script (and by hand via the rake task):
#
#   bin/rails ai:scrub_execution_event_errors
#
# (Ai::ExecutionEventErrorScrub.run_once!; bounded, marker-guarded, idempotent
# and resumable.)
class ScrubHistoricalExecutionEventErrors < ActiveRecord::Migration[8.1]
  def up
    say "execution event error scrub moved to `rails ai:scrub_execution_event_errors` (run by the boot script, not here)"
  end

  def down; end
end
