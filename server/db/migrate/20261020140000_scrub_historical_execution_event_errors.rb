# frozen_string_literal: true

# IMP-dbabbea6f81c. Marker only. The retroactive scrub of raw executor error
# text in ai_execution_events.error_message is NOT done here: migrations run at
# boot (docker-entrypoint db:prepare, bootstrap.sh), and a lock wait on a busy
# table must not keep the app from starting. Run the scrub as an operator task:
#
#   bin/rails ai:scrub_execution_event_errors
#
# (Ai::ExecutionEventErrorScrub; idempotent and resumable.)
class ScrubHistoricalExecutionEventErrors < ActiveRecord::Migration[8.1]
  def up
    say "execution event error scrub moved to `rails ai:scrub_execution_event_errors` (not run at boot)"
  end

  def down; end
end
