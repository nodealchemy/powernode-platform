# frozen_string_literal: true

# IMP-dbabbea6f81c. Retroactive scrub of raw executor error text captured in
# ai_execution_events.error_message BEFORE the write side was fixed
# (Ai::ApprovalRequest, 2f6f2f3b3). Rows of event_type "approval_execution"
# written earlier can quote the very params the approval filter masks, and the
# readers served them verbatim.
#
# SCRUB IN PLACE through Ai::SensitiveParams.filter_text, the one redactor. Only
# rows whose text it actually changes are written, so a re-run updates zero
# rows. filter_text also truncates to TEXT_LIMIT; that is acceptable for an
# error column and is what the forward path stores.
#
# Scoped to event_type "approval_execution" with a non-nil error_message.
# Batched by primary-key range (1000), one transaction per batch
# (disable_ddl_transaction!), each taking a plain FOR UPDATE under a
# lock_timeout. A row locked by someone else is WAITED on, never skipped: nothing
# re-runs this migration, so a skipped row would stay unscrubbed for good. A
# batch that cannot get its locks is retried, and after LOCK_ATTEMPTS the
# migration RAISES rather than finishing with rows left behind. Prints COUNTS
# only, never what it redacts.
class ScrubHistoricalExecutionEventErrors < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  BATCH_SIZE = 1_000
  LOCK_TIMEOUT = "5s"
  LOCK_ATTEMPTS = 3
  EVENT_TYPE = "approval_execution"

  # Minimal table-bound model: a migration must not depend on app models.
  class EventRow < ActiveRecord::Base
    self.table_name = "ai_execution_events"
  end

  # Returns the number of rows rewritten so a spec can assert a re-run does
  # nothing.
  def up
    EventRow.reset_column_information
    total = 0
    last_id = nil

    loop do
      ids = candidate_ids(last_id)
      break if ids.empty?

      last_id = ids.last
      total += scrub_batch(ids)
    end

    say "scrubbed #{total} #{EVENT_TYPE} execution event row(s): error_message"
    total
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "Error text was overwritten in place and is unrecoverable by design."
  end

  private

  def candidate_ids(after_id)
    scope = EventRow.where(event_type: EVENT_TYPE).where.not(error_message: nil).order(:id)
    scope = scope.where("id > ?", after_id) if after_id
    scope.limit(BATCH_SIZE).pluck(:id)
  end

  def scrub_batch(ids)
    attempts = 0
    begin
      attempts += 1
      lock_and_scrub(ids)
    rescue ActiveRecord::LockWaitTimeout
      retry if attempts < LOCK_ATTEMPTS
      raise
    end
  end

  def lock_and_scrub(ids)
    count = 0
    EventRow.transaction do
      connection.execute("SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'")
      EventRow.where(id: ids).lock("FOR UPDATE").each do |row|
        filtered = ::Ai::SensitiveParams.filter_text(row.error_message)
        next if filtered == row.error_message

        row.update_columns(error_message: filtered)
        count += 1
      end
    end
    count
  end
end
