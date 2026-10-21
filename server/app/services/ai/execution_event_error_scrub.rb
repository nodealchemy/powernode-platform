# frozen_string_literal: true

module Ai
  # IMP-dbabbea6f81c. Retroactive scrub of raw executor error text captured in
  # ai_execution_events.error_message BEFORE the write side was fixed
  # (Ai::ApprovalRequest). Rows of event_type "approval_execution" written
  # earlier can quote the very params the approval filter masks.
  #
  # Runs every boot from the host's boot script (and by hand via the rake task,
  # `rails ai:scrub_execution_event_errors`), through run_once!: bounded by a
  # time budget, guarded by DONE_MARKER, and never raising into boot. NOT from a
  # migration: a lock wait on a busy table inside db:migrate would keep the app
  # from starting. Idempotent (only rows whose text filter_text actually changes
  # are written) and resumable (a cut-short run saves PROGRESS_MARKER and the
  # next one starts after it).
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

    DONE_MARKER = "ai_execution_event_error_scrub_done"
    # The last id a run got through with no batch skipped behind it. A run
    # resumes after it instead of re-reading the same prefix every boot, and a
    # complete run clears it.
    PROGRESS_MARKER = "ai_execution_event_error_scrub_progress"

    Result = Struct.new(:scrubbed, :skipped_rows, :stopped_early, keyword_init: true) do
      def complete? = skipped_rows.zero? && !stopped_early
    end

    def self.call(**options)
      new(**options).call
    end

    # What a one-shot run did, so a caller can say so truthfully:
    #   :done      the marker was already set; nothing was touched
    #   :ran       scrubbed everything; the marker is now set
    #   :cut_short the time budget or lock contention left rows; the marker is
    #              unset and the next run resumes
    #   :failed    an error (including a cancelled query) was swallowed; the
    #              marker is unset
    Outcome = Struct.new(:status, :result, :error_class, keyword_init: true)

    # One-shot for deploys, run by the host's boot script after db:migrate (db:seed
    # is first-boot only there): runs the scrub under a time budget and records
    # DONE_MARKER only when it finished completely. NEVER raises into boot.
    def self.run_once!(time_budget: 30, force: false, **options)
      return Outcome.new(status: :done) if !force && ::SiteSetting.get(DONE_MARKER).to_s == "true"

      result = new(deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + time_budget,
                   progress_key: PROGRESS_MARKER, **options).call
      if result.complete?
        ::SiteSetting.set(DONE_MARKER, "true", setting_type: "string")
        ::SiteSetting.where(key: PROGRESS_MARKER).delete_all
      end
      Rails.logger.info("[Ai::ExecutionEventErrorScrub] scrubbed #{result.scrubbed}, skipped #{result.skipped_rows}, " \
                        "complete=#{result.complete?}")
      Outcome.new(status: result.complete? ? :ran : :cut_short, result: result)
    rescue StandardError => e
      Rails.logger.error("[Ai::ExecutionEventErrorScrub] one-shot failed: #{e.class}")
      Outcome.new(status: :failed, error_class: e.class.name)
    end

    # +progress_key+: a SiteSetting the run resumes after and advances as it
    # goes (run_once! passes PROGRESS_MARKER); nil scans from the first row.
    def initialize(batch_size: BATCH_SIZE, lock_timeout: LOCK_TIMEOUT, sleeper: Kernel.method(:sleep), deadline: nil,
                   progress_key: nil)
      @deadline = deadline
      @progress_key = progress_key
      @batch_size = batch_size
      @lock_timeout = lock_timeout
      @sleeper = sleeper
    end

    def call
      scrubbed = 0
      skipped = 0
      last_id = saved_progress
      stopped_early = false
      first = true

      loop do
        ids = candidate_ids(last_id)
        break if ids.empty?

        # The first batch always runs; after that the budget decides.
        if @deadline && !first && Process.clock_gettime(Process::CLOCK_MONOTONIC) > @deadline
          stopped_early = true
          break
        end

        first = false
        last_id = ids.last
        count = scrub_batch(ids)
        if count.nil?
          skipped += ids.size
        else
          scrubbed += count
          # Never past a skipped batch: its rows still need the scrub.
          save_progress(last_id) if skipped.zero?
        end
      end

      Result.new(scrubbed: scrubbed, skipped_rows: skipped, stopped_early: stopped_early)
    end

    private

    def saved_progress
      return nil unless @progress_key

      ::SiteSetting.get(@progress_key).presence
    end

    def save_progress(id)
      ::SiteSetting.set(@progress_key, id, setting_type: "string") if @progress_key
    end

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
      # One key-pattern read and regexp compile for the batch, not per row.
      ::Ai::SensitiveParams.batch do
        ::Ai::ExecutionEvent.transaction do
          ::Ai::ExecutionEvent.connection.execute("SET LOCAL lock_timeout = '#{@lock_timeout}'")
          ::Ai::ExecutionEvent.where(id: ids).lock("FOR UPDATE").each do |row|
            filtered = ::Ai::SensitiveParams.filter_text(row.error_message)
            next if filtered == row.error_message

            row.update_columns(error_message: filtered)
            count += 1
          end
        end
      end
      count
    end
  end
end
