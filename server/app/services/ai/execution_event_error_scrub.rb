# frozen_string_literal: true

module Ai
  # IMP-dbabbea6f81c. Retroactive scrub of raw executor error text captured in
  # ai_execution_events.error_message BEFORE the write side was fixed
  # (Ai::ApprovalRequest). Rows of event_type "approval_execution" written
  # earlier can quote the very params the approval filter masks.
  #
  # Run by an operator (`rake ai:scrub_execution_event_errors`), NOT by a
  # migration: migrations run at boot (docker-entrypoint db:prepare,
  # bootstrap.sh), and a lock wait on a busy table must never keep the app
  # from starting. The scrub is idempotent and resumable: only rows whose text
  # filter_text actually changes are written, so a re-run touches nothing it
  # already scrubbed.
  #
  # Scrubs in place through Ai::SensitiveParams.filter_text, the one redactor,
  # in primary-key batches, one transaction per batch, each taking a FOR UPDATE
  # under a lock_timeout. A batch whose locks cannot be had after LOCK_ATTEMPTS
  # (lock timeout or deadlock, with a growing pause) is SKIPPED and counted in
  # Result#skipped_rows; the caller is told to run it again. Never raises on
  # contention. Reports counts only, never what it redacts.
  class ExecutionEventErrorScrub
    BATCH_SIZE = 1_000
    LOCK_TIMEOUT = "5s"
    LOCK_ATTEMPTS = 3
    BACKOFF_SECONDS = 0.5
    EVENT_TYPE = "approval_execution"

    Result = Struct.new(:scrubbed, :skipped_rows, keyword_init: true) do
      def complete? = skipped_rows.zero?
    end

    def self.call(**options)
      new(**options).call
    end

    def initialize(batch_size: BATCH_SIZE, lock_timeout: LOCK_TIMEOUT, sleeper: Kernel.method(:sleep))
      @batch_size = batch_size
      @lock_timeout = lock_timeout
      @sleeper = sleeper
    end

    def call
      scrubbed = 0
      skipped = 0
      last_id = nil

      loop do
        ids = candidate_ids(last_id)
        break if ids.empty?

        last_id = ids.last
        count = scrub_batch(ids)
        count.nil? ? skipped += ids.size : scrubbed += count
      end

      Result.new(scrubbed: scrubbed, skipped_rows: skipped)
    end

    private

    def candidate_ids(after_id)
      scope = ::Ai::ExecutionEvent.where(event_type: EVENT_TYPE).where.not(error_message: nil).order(:id)
      scope = scope.where("id > ?", after_id) if after_id
      scope.limit(@batch_size).pluck(:id)
    end

    # Rows rewritten, or nil when the batch's locks could not be had.
    def scrub_batch(ids)
      attempts = 0
      begin
        attempts += 1
        lock_and_scrub(ids)
      rescue ::ActiveRecord::LockWaitTimeout, ::ActiveRecord::Deadlocked
        if attempts < LOCK_ATTEMPTS
          @sleeper.call(BACKOFF_SECONDS * attempts)
          retry
        end
        nil
      end
    end

    def lock_and_scrub(ids)
      count = 0
      ::Ai::ExecutionEvent.transaction do
        ::Ai::ExecutionEvent.connection.execute("SET LOCAL lock_timeout = '#{@lock_timeout}'")
        ::Ai::ExecutionEvent.where(id: ids).lock("FOR UPDATE").each do |row|
          filtered = ::Ai::SensitiveParams.filter_text(row.error_message)
          next if filtered == row.error_message

          row.update_columns(error_message: filtered)
          count += 1
        end
      end
      count
    end
  end
end
