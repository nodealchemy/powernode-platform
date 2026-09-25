# frozen_string_literal: true

module Compliance
  # Job for processing account terminations after grace period
  # Runs every 6 hours to check for accounts ready for termination
  class AccountTerminationJob < BaseJob
    sidekiq_options queue: 'compliance', retry: 3

    # IMP-f0560910fa62: a 'processing' row with no live process behind it —
    # the worker crashed after process_termination's own status write
    # (patch_termination!, below) landed but before its begin/rescue could
    # revert-or-complete it.
    # process_ready_terminations' fetch only ever asks for grace_period rows,
    # so nothing else ever re-selects 'processing'; without a resume path a
    # crash here strands the row forever.
    #
    # This does NOT simply mirror DataDeletionJob (IMP-b33a3ecca331) treating
    # any 'processing' row as safe to resume: that precedent is per-id,
    # re-invoked only by Sidekiq's OWN retry, which guarantees the PRIOR
    # attempt is dead. This job is a periodic SWEEP with no such guarantee —
    # a 'processing' row could equally be a run still genuinely in flight,
    # and resuming that one would double-process a live termination. Status
    # alone can't tell the two apart, so the age of processing_started_at
    # (written atomically with the status inside process_termination) is the
    # discriminator: only a row idle longer than this threshold is treated
    # as stranded.
    #
    # THRESHOLD = one full sweep interval (worker/config/sidekiq.yml,
    # account_termination_processing cron '0 */6 * * *'). The two ways this
    # value can be wrong have ASYMMETRIC costs, which is why it errs large:
    #   * TOO SHORT: a live run gets misjudged as stranded and re-entered.
    #     delete_account_data/delete_user_data are idempotent (re-running
    #     them over a half-deleted account is safe -- see
    #     Api::V1::Internal::UsersController#anonymize's own comment on this),
    #     so this is data-safe, but NOT state-safe: the genuine run's own
    #     eventual 'completed' write then targets a row the intruding run has
    #     already moved, and 'grace_period' -> 'completed' is not a permitted
    #     transition (account_terminations_controller.rb#status_transition_allowed?)
    #     -- so the run that did the real work fails, reverts to
    #     'grace_period', and the account gets terminated again next sweep.
    #     Recurring thrash, not a one-off.
    #   * TOO LONG: recovery of a genuinely crashed row is delayed by at most
    #     one extra sweep. The row was already stuck indefinitely before this
    #     fix existed, and this path's grace period is 30 days
    #     (Account::Termination), so a ~12h worst-case recovery delay is
    #     immaterial against that. Delay is cheap; thrash is not.
    # NOTE (an earlier version of this comment argued the opposite and was
    # wrong): a threshold BELOW one sweep interval does not recover a
    # stranded row any SOONER in wall-clock time -- the sweep only runs every
    # 6 hours regardless, so a smaller value buys at most one sweep of
    # LATENCY before the row becomes eligible, never a faster actual
    # recovery. That reasoning is how the original 1-hour value got chosen,
    # and it does not hold.
    #
    # WHY 6 HOURS HOLDS, AND WHEN IT WON'T -- a falsifiable claim, not a bare
    # adjective (the previous version of this comment, "comfortably exceeds
    # realistic per-account processing time", was exactly that, and is why
    # this defect survived review): process_termination makes roughly 6
    # sequential HTTP round trips per user (consents / terms_acceptances /
    # anonymize_audit_logs / password_histories / roles / anonymize -- see
    # delete_user_data) plus roughly 8 fixed per-account calls
    # (delete_account_records' own steps, the account-terminate call, and the
    # initial/final termination writes). At a pessimistic 100ms per round
    # trip, 6 hours of budget covers on the order of 36,000 users' worth of
    # sequential calls -- so THIS HOLDS WHILE NO SINGLE ACCOUNT EXCEEDS
    # ROUGHLY 30,000 USERS. If any real account comes within an order of
    # magnitude of that figure, this fixed threshold stops being sufficient
    # and a progress-write heartbeat (periodically refreshing
    # processing_started_at, or logging per-user progress, as the run
    # proceeds) becomes warranted instead of a bigger constant. That
    # follow-up would need NO server change: the server already accepts a
    # status-less write (a bare termination_log_append) while 'processing'
    # (account_terminations_controller.rb#update), and the job's own per-user
    # event names are already in JOB_TERMINATION_LOG_EVENTS. Not built now,
    # deliberately: a per-user flush would be one locked write per user
    # rewriting the WHOLE termination_log JSONB array (N users -> N locked
    # writes on an array reaching ~6N entries -- contended by concurrent
    # sweeps on the very row this fix is about), and would roughly double
    # this job's HTTP call count, lengthening exactly the runs it exists to
    # bound. A bounded-cadence flush avoids that cost but is a new mechanism
    # with a new failure mode of its own (a flush failure mid-run aborting a
    # termination that would otherwise have completed). Revisit when an
    # account's user count approaches the figure above, not before.
    #
    # THE PREDICATE MUST NEVER RAISE -- scoped precisely to what that
    # actually covers: this guarantee is about the per-row SELECTION
    # predicate below (parse_processing_started_at and its own rescue), not
    # about the HTTP fetch stranded_processing_terminations makes to get its
    # candidate rows in the first place. That fetch (fetch_terminations,
    # below) CAN still raise ApiError on a non-2xx response or a timeout --
    # exactly like the pre-existing grace_period-expired fetch
    # process_ready_terminations already made before this fix. Both are
    # unrescued HTTP calls inside the array-building expression in
    # process_ready_terminations, and either one raising propagates straight
    # out of #execute, skipping send_termination_reminders entirely and
    # bypassing the results[:errors]/fail-loud mechanism at the bottom of
    # #execute.
    #
    # This fix DOES add a second unrescued fetch where there used to be one
    # -- that much is a real change, not "pre-existing" (an earlier version
    # of this comment claimed otherwise, which was wrong about the EXPOSURE
    # even though the decision not to rescue it is right). What actually
    # keeps that addition safe is that both fetches share a single FAILURE
    # DOMAIN: same endpoint, same host, same auth -- anything that fails one
    # (a connectivity/auth/5xx outage, a timeout) fails the other identically,
    # so this does not add a genuinely NEW way for the sweep to abort, only a
    # second call site inside the same one. And the index's only
    # query-shape-specific 422 -- grace_period_expired sent without
    # status: 'grace_period' (account_terminations_controller.rb#index) --
    # cannot be triggered by the stranded query, which never sends
    # grace_period_expired at all. What THIS fix's own predicate promises
    # never to do is abort the sweep over one row's bad processing_started_at
    # VALUE once the HTTP fetch has already succeeded -- that is the "one
    # malformed row must not take the whole sweep down" property, and it is
    # real precisely because it is scoped to the in-process SELECT, not to
    # the network call underneath it.
    STRANDED_PROCESSING_THRESHOLD = 6.hours

    # IMP-0310a1351dab review round 2, item 4. A termination's own requested
    # export can fail to progress for two different reasons that both look
    # identical from here (the export just sits 'pending'): the initial
    # enqueue from Account::Termination.initiate never reached the worker
    # (queue_export_job rescues WorkerApiClient::ApiError and only logs), or
    # a Compliance::DataExportJob run that WAS enqueued crashed/died without
    # ever writing 'processing'/'failed'. Neither leaves a trace this job can
    # distinguish, so both are recovered the same way: re-enqueue.
    # Re-enqueuing an export that is merely still legitimately in flight
    # (young 'pending', not yet picked up) would be wasted work, not
    # incorrect work — DataExportJob's own guard
    # (`unless export_request['status'] == 'pending'`) makes a second
    # concurrent run for an already-'processing' export a no-op skip, and two
    # runs racing while both see 'pending' is bounded by ordinary Sidekiq
    # concurrency, not by anything this threshold controls.
    #
    # 1 hour (my call): matches DataManagement::ExportRequest#time_remaining's
    # own estimate of typical processing time (`created_at + 1.hour`) — an
    # export still 'pending' past its own expected-completion estimate is a
    # reasonable, already-established definition of "taking too long",
    # rather than a second, independently-tuned number.
    EXPORT_STALE_PENDING_THRESHOLD = 1.hour

    # After this many sweeps have each deferred the SAME termination on its
    # own export, write a once-only warning log entry (plus a log_warn) so an
    # operator scanning logs sees a signal distinct from the routine,
    # expected wait for an async export. 3 (my call): at the 6-hour sweep
    # cadence this is an 18-hour floor before the warning fires — long enough
    # that an export merely taking its normal course does not trip it, short
    # enough that a genuinely stuck export (repeatedly re-enqueued above and
    # still not resolving) surfaces well within the 30-day grace period
    # rather than silently consuming most of it.
    EXPORT_STALL_WARNING_DEFERRAL_COUNT = 3

    # A 'failed' export is reset to 'pending' and re-queued this many times
    # (via DataExportRequestsController's action_type: 'retry', which tracks
    # the attempt count in the export's own `metadata` — server-side, so it
    # survives worker restarts and is never lost between sweeps) before this
    # job gives up automating it and PARKS the termination instead. 3 (my
    # call): the same order of magnitude as EXPORT_STALL_WARNING_DEFERRAL_COUNT
    # above, on the reasoning that three independent generation attempts
    # failing is a strong enough signal that this is a systemic problem (bad
    # data, an unavailable dependency the export gatherer calls) rather than
    # a transient blip retrying would routinely fix.
    EXPORT_DELIVERY_RETRY_LIMIT = 3

    # A 'processing' export stuck past this age is treated as failed (review
    # round 3, item 4) — Compliance::DataExportJob normally moves a row out
    # of 'processing' within EXPORT_STALE_PENDING_THRESHOLD's ~1-hour typical
    # runtime; 2 hours (my call, the team lead's own suggested order of
    # magnitude) gives real work a comfortable margin above that before
    # concluding the run that set 'processing' crashed without ever writing
    # 'completed'/'failed'. Deliberately larger than
    # EXPORT_STALE_PENDING_THRESHOLD: a 'processing' row is DOING something
    # (or was, until it crashed), so it gets more benefit of the doubt than a
    # 'pending' one that never started at all.
    EXPORT_STALE_PROCESSING_THRESHOLD = 2.hours

    def execute(_args = nil)
      log_info 'Starting account termination processing'

      results = {
        processed: 0,
        # Cosmetic (IMP-f0560910fa62 review, finding 5): a resumed strand
        # was previously counted indistinguishably inside `processed`, so
        # the completion log conflated "terminations completed" with
        # "strands recovered" -- an operator scanning logs for a recurring
        # crash pattern had no signal without grepping process_termination's
        # own per-row log lines. Tracked separately; `resumed` is always a
        # subset of `processed`, never additional to it.
        resumed: 0,
        reminders_sent: 0,
        errors: []
      }

      # Process terminations ready for deletion
      process_ready_terminations(results)

      # Send reminder notifications
      send_termination_reminders(results)

      log_info "Account termination job complete: #{results[:processed]} processed " \
               "(#{results[:resumed]} resumed from a stranded 'processing' row), " \
               "#{results[:reminders_sent]} reminders sent"

      # Fail loud: a per-account termination that errored was swallowed into
      # results[:errors] and the job would otherwise return normally, so Sidekiq
      # would see success and retry:3 would never fire — stranding a
      # partially-terminated account. Failed terminations are reverted to
      # 'grace_period' (re-selectable) in process_termination's rescue; succeeded
      # ones are 'completed'/'terminated' (outside the re-fetch filter, so the
      # retry only re-attempts the failed ones). Raise so the failure is surfaced
      # and Sidekiq retries.
      if results[:errors].any?
        failed_ids = results[:errors].map { |error| error[:termination_id] }.join(', ')
        raise "Account termination failed for: #{failed_ids}"
      end

      results
    end

    private

    def process_ready_terminations(results)
      # BackendApiClient#handle_response returns the parsed JSON body VERBATIM
      # (string keys) on 2xx and raises ApiError on any non-2xx — not a
      # symbol-keyed {success:, data:} envelope (see the matching note in
      # DataDeletionJob#execute). Every response read in this job was
      # symbol-keyed against a string-keyed hash, so it has never actually
      # processed a termination (IMP-b33a3ecca331 review).
      #
      # Two sources, concatenated and DE-DUPLICATED by id (IMP-f0560910fa62
      # review, finding 3 -- corrects an earlier version of this comment that
      # claimed "status is a DB column, so a row can never appear in both",
      # which is false: a single status column makes the two queries'
      # filters disjoint only in ONE instantaneous snapshot, and these are
      # two SEQUENTIAL HTTP requests).
      #
      # The MOTIVATING SCENARIO an earlier version of THIS rewrite gave was
      # itself wrong (review follow-up): a row that just moved to
      # 'processing' carries a processing_started_at of ~now, fails
      # `started_at < STRANDED_PROCESSING_THRESHOLD.ago`, and is filtered
      # OUT of stranded_terminations by that staleness check BEFORE the
      # union below even runs -- so an ordinary just-transitioned row never
      # collides this way. The collision that CAN actually occur is
      # narrower: an EXTERNAL writer (an admin action, or a future caller)
      # moves a row 'grace_period' -> 'processing' WITHOUT re-stamping
      # processing_started_at, over a STALE timestamp an EARLIER reverted
      # episode left behind. process_termination's own revert-to-grace_period
      # path (in the rescue below) does not clear processing_started_at, so
      # a row that was 'processing' once before, failed, and reverted still
      # carries that old timestamp. The controller permits exactly this
      # shape -- termination_params allows a status-only write with
      # processing_started_at omitted. If this job's FIRST (grace_period-
      # expired) fetch reads the row a moment before that external write
      # lands, and the SECOND (stranded) fetch reads it a moment after, the
      # row appears in both arrays with a processing_started_at already old
      # enough to pass the staleness filter -- landing in both arrays and
      # being iterated (process_termination called) twice in the same loop.
      # Array#uniq keeps the FIRST occurrence, so stranded_terminations is
      # concatenated FIRST: it comes from the request that ran
      # chronologically LATER, so its copy of a colliding row reflects the
      # more current status -- in particular, whether
      # resumed_row?/process_termination should treat it as a resume --
      # PROVIDED that copy survives the staleness filter (see the race this
      # does NOT cover, below).
      ready_terminations = fetch_terminations(status: 'grace_period', grace_period_expired: true)
      stranded_terminations = stranded_processing_terminations
      terminations = (stranded_terminations + ready_terminations).uniq { |t| t['id'] }

      # NOT covered by the de-duplication above -- both reviewers found this
      # independently, and it is ACCEPTED rather than fixed for this window:
      # a row that is 'grace_period'+expired at fetch #1, and is then picked
      # up by a genuinely LIVE run before fetch #2 runs. That live run's own
      # write sets a FRESH processing_started_at (~now), so this row's
      # 'processing' copy fails the staleness filter and is discarded from
      # stranded_terminations BEFORE `uniq` ever runs -- only the stale
      # 'grace_period' copy from fetch #1 survives into `terminations`.
      # resumed_row? then reads false against that stale copy,
      # process_termination sends the initial 'processing' write exactly as
      # it would for a genuine fresh row, and the server 422s (the row is
      # already 'processing', courtesy of the live run this job's own fetch
      # #1 raced against). The cost is one failed job execution: it
      # self-heals on Sidekiq's retry and on the next sweep, when the row is
      # 'processing' and genuinely fresh and therefore appears in NEITHER
      # query. Closing this fully needs a conditional/idempotent write
      # server-side (e.g. an if-match on current status); not built for this
      # window.

      terminations.each do |termination|
        begin
          outcome = process_termination(termination)
          # IMP-0310a1351dab review round 2, item 4: a deferral (the
          # termination's own export isn't resolved yet) is an expected wait,
          # not completed work — counting it into `processed` made a sweep
          # that did nothing but re-check a pending export indistinguishable
          # from one that actually terminated an account.
          next if outcome == :deferred

          results[:processed] += 1
          results[:resumed] += 1 if resumed_row?(termination)
        rescue => e
          log_error "Failed to process termination #{termination['id']}: #{e.message}"
          results[:errors] << { termination_id: termination['id'], error: e.message }
        end
      end
    end

    # Shared by process_ready_terminations' resumed-count bookkeeping and
    # process_termination's own skip-the-redundant-write decision (BLOCKER
    # 1, below) -- both need the same answer to "is this row already
    # 'processing'", so it lives once rather than being recomputed
    # inconsistently in two places.
    def resumed_row?(termination)
      termination['status'] == 'processing'
    end

    # 'processing' rows idle past STRANDED_PROCESSING_THRESHOLD — see that
    # constant's comment for why this is a selection PREDICATE (filtered
    # worker-side on an already-persisted field), not a new status or
    # transition, and why a periodic sweep can't simply resume every
    # 'processing' row the way DataDeletionJob resumes on retry.
    #
    # QUARANTINE, not resume, when the age can't be determined (absent,
    # blank, or unparseable processing_started_at) — IMP-f0560910fa62 review,
    # design decision: the ORIGINAL version of this method resumed
    # unconditionally on a missing age, reasoning that the only way
    # processing_started_at could be missing was process_termination's own
    # write invariant breaking. That premise turned out false on this same
    # review: the server's index serializer (termination_data) never
    # included the field AT ALL, so every 'processing' row arrived with it
    # absent on a perfectly healthy system — the staleness gate was
    # silently inert, resuming every processing row regardless of true age.
    # On a path that anonymizes users and cancels accounts, "I cannot
    # determine this row's state, therefore I will act on it" is the wrong
    # default when the actual cause can be a serialization gap rather than a
    # crash. Skip the row instead: it is left exactly as stuck as it already
    # was (no regression versus today), while surfacing the anomaly to an
    # operator via an error-level log rather than silently re-processing a
    # row that might still be a live run.
    def stranded_processing_terminations
      fetch_terminations(status: 'processing').select do |termination|
        started_at = parse_processing_started_at(termination)

        # nil means quarantined (see parse_processing_started_at) — exclude
        # it from this sweep's terminations rather than treating an
        # undeterminable age as safe to resume. This branch runs OUTSIDE
        # process_ready_terminations' per-item rescue (it builds the array
        # those items come from), so it must never raise: one garbage
        # timestamp on one stranded row must not abort the whole sweep and
        # take every ordinary grace_period termination down with it.
        next false if started_at.nil?

        started_at < STRANDED_PROCESSING_THRESHOLD.ago
      end
    end

    def parse_processing_started_at(termination)
      raw = termination['processing_started_at']

      if raw.blank?
        return quarantine_processing_started_at!(
          termination, "is 'processing' with no processing_started_at (should never happen)"
        )
      end

      parsed = Time.zone.parse(raw)

      # Time.zone.parse returns nil (rather than raising) for some
      # non-blank-but-unparseable strings (confirmed: "garbage", "" both
      # return nil here, distinct from the ArgumentError raised by a
      # structurally invalid date like "2026-99-99") -- handle both shapes
      # the same way, since either means the value can't be trusted as an age.
      return quarantine_processing_started_at!(
        termination, "has an unparseable processing_started_at (#{raw.inspect})"
      ) if parsed.nil?

      # A future-dated processing_started_at PARSES CLEANLY (confirmed:
      # "999999999999-01-01" raises nothing), so it escapes both branches
      # above (IMP-f0560910fa62 review, finding 4). Left unhandled,
      # `started_at < STRANDED_PROCESSING_THRESHOLD.ago` in
      # stranded_processing_terminations would simply evaluate false for a
      # future timestamp -- silently treating it as "not yet stale" with NO
      # anomaly ever logged, which defeats the entire point of quarantine:
      # an operator gets no signal that anything occurred. Route it through
      # the same quarantine-and-error-log path as the other two anomalies,
      # rather than letting it fall through as an ordinary young row.
      #
      # 1-minute tolerance (review follow-up): processing_started_at is
      # written as Time.current.iso8601 on whichever worker host ran
      # process_termination, and read here by whichever host runs the next
      # sweep -- ordinary NTP clock skew between them can put a perfectly
      # healthy, just-written timestamp a few seconds into this host's
      # future. The decision (skip a young row) is unaffected either way,
      # but comparing against bare Time.current would log a false anomaly at
      # error severity for completely normal skew, training operators to
      # ignore the signal. A full minute comfortably absorbs realistic skew
      # without weakening the check against a GENUINELY bogus (day/year-
      # scale) future value.
      return quarantine_processing_started_at!(
        termination, "has a processing_started_at in the future (#{raw.inspect})"
      ) if parsed > Time.current + 1.minute

      parsed
    rescue ArgumentError, TypeError
      quarantine_processing_started_at!(termination, "has an unparseable processing_started_at (#{raw.inspect})")
    end

    def quarantine_processing_started_at!(termination, reason)
      log_error "Termination #{termination['id']} #{reason} — quarantining rather than guessing " \
                'whether it is safe to resume'
      nil
    end

    def fetch_terminations(query)
      response = api_client.get('/api/v1/internal/account_terminations', query)
      return [] unless response['success']

      response['data'] || []
    end

    # IMP-0310a1351dab. No export requested at all (the common case) is
    # trivially ready. A HTTP failure fetching the export's own status is
    # treated as NOT ready (fail-safe: never proceed with irreversible
    # deletion on an unconfirmed premise) — this deliberately does not rescue
    # api_client.get's own errors; letting one propagate reaches this
    # method's caller (process_ready_terminations' per-item rescue) with
    # exactly the same "log it, skip this account this sweep, retry next
    # time" behavior every other pre-flight call in this job already relies
    # on.
    #
    # Returns { ready:, benign_wait: } rather than a bare boolean (review
    # round 3, item 4) — `benign_wait` is true exactly for a 'completed'
    # export with an open, undownloaded download window: an EXPECTED wait
    # (the whole point of the operator's ruling is the user gets the full
    # 7 days), not a signal process_termination's caller should ever count
    # toward the stall warning. Every other "not ready" case leaves it false.
    def export_deletion_gate(termination)
      export_request_id = termination['data_export_request_id']
      return { ready: true, benign_wait: false } if export_request_id.blank?

      export_request = fetch_export_request(export_request_id)
      return { ready: false, benign_wait: false } unless export_request

      # IMP-0310a1351dab review round 2, items 3+6: read the server's OWN
      # verdict (DataManagement::ExportRequest#delivered_for_deletion?, exposed
      # via DataExportRequestsController#serialize_request) instead of
      # re-deriving "which statuses count as ready" here — this job used to
      # independently list `%w[completed failed]`, which both duplicated the
      # policy AND treated a merely-'completed' export (open download window,
      # nothing downloaded yet) and a 'failed' one as equally ready. One
      # place decides (operator ruling 2026-09-24: delivered = downloaded, or
      # download window elapsed unused); this reads it.
      return { ready: true, benign_wait: false } if export_request['delivered_for_deletion'] == true

      case export_request['status']
      when 'failed'
        # Has delivered nothing — never treated as delivered-for-deletion
        # (see the model's own comment). Its own bounded reset-and-retry
        # path, rather than the generic stale-pending requeue below (which
        # only ever applies to a still-'pending' row).
        handle_failed_export!(termination, export_request)
        { ready: false, benign_wait: false }
      when 'processing'
        # Review round 3, item 4: a 'processing' export stuck past
        # EXPORT_STALE_PROCESSING_THRESHOLD is treated as failed and routed
        # through the SAME bounded retry as an explicit failure — it is
        # exactly as undelivered as one, and without this it would sit
        # 'processing' forever (requeue_if_stale_export! below only ever
        # acts on 'pending').
        handle_stale_processing_export!(termination, export_request) if stale_processing_export?(export_request)
        { ready: false, benign_wait: false }
      when 'completed'
        { ready: false, benign_wait: true }
      else
        requeue_if_stale_export!(export_request)
        { ready: false, benign_wait: false }
      end
    end

    def fetch_export_request(export_request_id)
      response = api_client.get("/api/v1/internal/data_export_requests/#{export_request_id}")
      return nil unless response['success']

      response.dig('data', 'data_export_request')
    end

    # Recovers a 'pending' export that has sat too long without progressing —
    # covers BOTH a lost initial enqueue (Account::Termination.initiate's
    # queue_export_job rescues WorkerApiClient::ApiError and only logs; the
    # export row exists but nothing ever picks it up) and a crashed
    # Compliance::DataExportJob run that never wrote 'processing'/'failed'.
    # Deliberately scoped to 'pending' only: a 'processing' export may be a
    # genuinely long-running job still working; re-enqueuing it is a
    # different, unproven failure mode (a stuck 'processing' row) this fix
    # does not attempt to distinguish or recover.
    def requeue_if_stale_export!(export_request)
      return unless export_request['status'] == 'pending'

      created_at = parse_export_created_at(export_request)
      return unless created_at && created_at < EXPORT_STALE_PENDING_THRESHOLD.ago

      export_request_id = export_request['id']
      log_warn "Data export #{export_request_id} has been pending longer than " \
                "#{EXPORT_STALE_PENDING_THRESHOLD.inspect} — re-queuing Compliance::DataExportJob"
      Compliance::DataExportJob.perform_async(export_request_id)
    end

    def parse_export_created_at(export_request)
      raw = export_request['created_at']
      return nil if raw.blank?

      Time.zone.parse(raw.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def stale_processing_export?(export_request)
      started_at = parse_export_processing_started_at(export_request)
      started_at && started_at < EXPORT_STALE_PROCESSING_THRESHOLD.ago
    end

    def parse_export_processing_started_at(export_request)
      raw = export_request['processing_started_at']
      return nil if raw.blank?

      Time.zone.parse(raw.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    # Marks the stuck 'processing' export failed (server-side, via the
    # existing action_type: 'fail' — the ONLY currently-valid transition out
    # of 'processing' besides 'completed'), then routes it through the SAME
    # bounded retry as an explicit failure. Reuses the already-fetched
    # `export_request` hash's own `metadata` (overriding just `status`
    # locally) rather than re-fetching, so handle_failed_export! sees the
    # real accumulated delivery_retry_count — fail_export's own response
    # does not include metadata (not requested with include_details), so
    # trusting THAT response instead would silently reset the retry count
    # every time this path fires.
    def handle_stale_processing_export!(termination, export_request)
      export_request_id = export_request['id']
      fail_response = api_client.patch(
        "/api/v1/internal/data_export_requests/#{export_request_id}",
        {
          action_type: 'fail',
          error_message: "Stuck in 'processing' longer than #{EXPORT_STALE_PROCESSING_THRESHOLD.inspect}"
        }
      )
      return unless fail_response['success']

      handle_failed_export!(termination, export_request.merge('status' => 'failed'))
    end

    # Operator ruling 2026-09-24: a failed export must be RETRIED, not
    # treated as delivered and not silently left failed forever. Bounded by
    # EXPORT_DELIVERY_RETRY_LIMIT, tracked server-side in the export's own
    # metadata (via DataExportRequestsController's action_type: 'retry') so
    # the count survives across sweeps/worker restarts rather than being
    # recomputed from anything this job holds in memory.
    def handle_failed_export!(termination, export_request)
      retry_count = export_request.dig('metadata', 'delivery_retry_count').to_i

      if retry_count >= EXPORT_DELIVERY_RETRY_LIMIT
        park_failed_export!(termination, export_request, retry_count)
        return
      end

      # Review round 3, LOW: no `unless retry_response['success']` guard here
      # — dead code where it stood before. BackendApiClient raises ApiError
      # on any non-2xx (retry_export's own 422 included) rather than
      # returning a success:false body, so that branch could never actually
      # run. A raised ApiError here is treated exactly like every other
      # pre-flight call this method already makes (see this method's own
      # top comment): it propagates to process_ready_terminations' per-item
      # rescue, which logs it and moves on to the next termination.
      export_request_id = export_request['id']
      api_client.patch(
        "/api/v1/internal/data_export_requests/#{export_request_id}",
        { action_type: 'retry' }
      )

      log_warn "Data export #{export_request_id} failed; reset to pending and re-queued " \
                "(attempt #{retry_count + 1}/#{EXPORT_DELIVERY_RETRY_LIMIT})"
      Compliance::DataExportJob.perform_async(export_request_id)
    end

    # Never deletes while undelivered (the operator's explicit constraint):
    # once EXPORT_DELIVERY_RETRY_LIMIT is exhausted, this job stops
    # automating recovery and leaves the termination deferred indefinitely —
    # it does NOT fall through to treating the export as resolved. The
    # once-only log entry (mirroring export_stalled_warning's own guard) is
    # the operator's signal that manual investigation is needed; nothing
    # here escalates further on its own.
    #
    # Round 4 fix: this used to ALSO POST an alert itself
    # (send_export_delivery_parked_alert, removed) through
    # notifications#send_notification — a no-op (that action resolves
    # recipients from `user_ids`, this job's payload carried only
    # `account_id`, so the recipient list always compacted to empty and
    # nothing was ever created). The real, working alert path
    # (SecurityAlertService, via Audit::LoggingService's existing use of it
    # for the same class of platform-ops signal) lives server-side and is
    # not reachable over this job's HTTP seam at all. Rather than build a
    # new worker->server call to reach it, Api::V1::Internal
    # ::AccountTerminationsController#update now fires it directly, in the
    # SAME request this patch_termination! call below already makes — no
    # new call needed, since the trigger (this termination_log_append)
    # already crosses that boundary.
    def park_failed_export!(termination, export_request, retry_count)
      already_parked = (termination['termination_log'] || []).any? { |e| e['event'] == 'export_delivery_parked' }
      return if already_parked

      termination_id = termination['id']
      export_request_id = export_request['id']
      log_error "Termination #{termination_id}'s data export #{export_request_id} has failed " \
                "#{retry_count} times — parking; this account's deletion cannot proceed without " \
                'manual investigation'
      patch_termination!(
        termination_id,
        { termination_log_append: [ { event: 'export_delivery_parked', at: Time.current.iso8601 } ] }
      )
    end

    def process_termination(termination)
      termination_id = termination['id']
      account_id = termination['account_id']
      resuming_stranded_row = resumed_row?(termination)

      log_info "Processing account termination: #{termination_id} (account: #{account_id})"

      # IMP-0310a1351dab: this termination requested a data export
      # (Account::Termination.initiate sets data_export_request_id — see
      # AccountTerminationsController#termination_data), and that export's
      # OWN row is referenced by an FK the server-side delete step cannot
      # violate. Checked BEFORE any destructive step runs (not caught via the
      # begin/rescue below, deliberately — this is an expected, routine wait
      # for an async job, not an error to log-and-revert-after-the-fact) —
      # deferring here for a fresh 'grace_period' row costs nothing (its
      # status is already 'grace_period'; process_ready_terminations simply
      # re-fetches and re-checks it next sweep). A RESUMED stranded
      # 'processing' row is the one case that needs an explicit write: no
      # query ever re-selects a 'processing' row except the stranded-check
      # path, so leaving it as-is would depend on THAT heuristic to notice it
      # again rather than being immediately re-selectable via the normal
      # grace_period query.
      export_gate = export_deletion_gate(termination)
      unless export_gate[:ready]
        log_info "Termination #{termination_id} requested a data export that has not yet " \
                 'been delivered (downloaded, or its download window elapsed unused) — ' \
                 'deferring account deletion to a later sweep'

        existing_log = termination['termination_log'] || []
        already_warned = existing_log.any? { |e| e['event'] == 'export_stalled_warning' }
        already_parked = existing_log.any? { |e| e['event'] == 'export_delivery_parked' }

        # Review round 3, item 4: bound termination_log growth. Once the
        # operator has already been signalled (a stall warning or a park),
        # every further sweep re-appending 'export_pending_deferred' adds no
        # new information — an account stuck at this gate would otherwise
        # grow the log by one entry per sweep indefinitely. The signal has
        # already fired; nothing further is written here until the export
        # actually resolves (at which point export_gate[:ready] flips true
        # and this whole branch stops running).
        if already_warned || already_parked
          return :deferred
        end

        append_entries = [ { event: 'export_pending_deferred', at: Time.current.iso8601 } ]

        # Review round 3, item 4: suppress the stall warning for a
        # `benign_wait` (a 'completed' export with an open, undownloaded
        # download window) — that is the ruling working exactly as intended
        # (the user gets the full 7 days), not a signal an operator should
        # ever be alerted about. The deferral itself is still recorded each
        # sweep (bounded naturally: the window elapses, and
        # delivered_for_deletion? flips true, within 7 days by construction).
        unless export_gate[:benign_wait]
          deferral_count = existing_log.count { |e| e['event'] == 'export_pending_deferred' } + 1

          if deferral_count >= EXPORT_STALL_WARNING_DEFERRAL_COUNT
            log_warn "Termination #{termination_id}'s data export has been deferred " \
                      "#{deferral_count} times without resolving — may need manual investigation"
            append_entries << { event: 'export_stalled_warning', at: Time.current.iso8601 }
          end
        end

        payload = { termination_log_append: append_entries }
        payload[:status] = 'grace_period' if termination['status'] == 'processing'
        patch_termination!(termination_id, payload)

        return :deferred
      end

      # BLOCKER 1 (IMP-f0560910fa62 review): a row this method is RESUMING is
      # already 'processing' server-side -- status_transition_allowed?
      # (account_terminations_controller.rb) permits ONLY processing ->
      # {completed, grace_period} out of 'processing', never processing ->
      # processing, so re-sending this same initial write here 422s. That
      # PATCH call sits BEFORE the begin/rescue below, so the 422 (ApiError)
      # is never caught by THIS method's own revert logic -- it propagates
      # straight to process_ready_terminations' per-item rescue, which logs
      # it and moves on, leaving the row exactly as stranded as it already
      # was. Worse: the job as a whole still fails loud (results[:errors]
      # non-empty), so Sidekiq retries the WHOLE job up to 3 times, and the
      # very next sweep re-selects the same still-'processing' row and 422s
      # again -- forever, every 6 hours, indefinitely. Skip the write
      # entirely for a resume; the row's `processing_started_at` was already
      # persisted by whichever run first marked it 'processing', and
      # re-stamping it here would reset the age stranded_processing_terminations
      # judges it by -- silently defeating the very staleness threshold this
      # fix exists to enforce.
      unless resuming_stranded_row
        patch_termination!(
          termination_id,
          { status: 'processing', processing_started_at: Time.current.iso8601 }
        )
      end

      # Accumulates ONLY the entries THIS run produces. The server now merges
      # these onto the stored log itself (AccountTerminationsController#update
      # / termination_log_append, IMP-b33a3ecca331 third review, BLOCKER 2) —
      # an atomic, locked append rather than a whole-array replace. Seeding
      # this from the fetched `termination['termination_log']` and sending it
      # straight back (the prior fix, second review) is no longer needed and
      # would now double the history on every write; starting from `[]` and
      # sending only new entries as `termination_log_append` is both correct
      # and race-free.
      termination_log = []

      begin
        # Delete account data
        delete_account_data(account_id, termination_log, termination['data_export_request_id'])

        # Update account status. Fork 1 (IMP-b33a3ecca331): operator decision
        # is to mark the account 'cancelled' (the existing accounts.status enum
        # value closest to "this account is done" — no new status, no new
        # column). A narrow, purpose-built action, not a generic PATCH — it
        # takes no payload and is idempotent, so calling it again on retry is
        # safe. This used to PATCH a bare /api/v1/internal/accounts/:id, which
        # has no route (only GET show is/was routed) with status: 'terminated',
        # a value the check constraint has never allowed.
        #
        # Called BEFORE the account_terminations 'completed' write (review
        # follow-up S1): 'completed' terminations are excluded from every
        # re-fetch this job makes (process_ready_terminations' status filter,
        # send_termination_reminders' status filter), so once written there is
        # no automatic retry. Terminating the account first means a failure
        # here still lands in the rescue below and reverts to 'grace_period'
        # (re-selectable); terminating it AFTER would have left the
        # termination record permanently 'completed' while the account itself
        # was never actually cancelled — an inconsistent state with no path
        # back to consistency.
        terminate_account!(account_id)

        # Complete termination
        patch_termination!(
          termination_id,
          {
            status: 'completed',
            completed_at: Time.current.iso8601,
            termination_log_append: termination_log
          }
        )

        log_info "Account #{account_id} termination complete"

        # Send final notification
        send_completion_notification(termination)
      rescue => e
        log_error "Account termination failed: #{e.message}"

        # Re-selectability: revert status from 'processing' back to 'grace_period'
        # so the next run's re-fetch (status: 'grace_period', grace_period_expired:
        # true) re-selects this partially-terminated account instead of stranding
        # it forever in 'processing' (which no query re-selects).
        #
        # patch_termination! itself raises on a failed write — nested
        # begin/rescue so THAT failure can never mask the ORIGINAL error `e`
        # (same defect class as DataDeletionJob, review follow-up
        # IMP-b33a3ecca331). Log the write failure (still visible) and
        # re-raise `e` regardless.
        begin
          patch_termination!(
            termination_id,
            {
              status: 'grace_period',
              termination_log_append: termination_log + [{
                event: 'error',
                error: e.message,
                at: Time.current.iso8601
              }]
            }
          )
        rescue => write_error
          log_error "Failed to revert termination #{termination_id} to grace_period: #{write_error.message}"
        end

        raise e
      end
    end

    # Persisted status writes must never fail silently. IMP-b33a3ecca331 found
    # that the server-side params contract had been dropping every one of
    # these writes (ActionController::ParameterMissing, rescued into a 400 this
    # job never checked) — the fix there is what makes these writes real again,
    # and this raises if that (or any future) write failure ever recurs, so the
    # job's own rescue/retry path takes over instead of silently proceeding as
    # if the state had changed.
    def patch_termination!(termination_id, payload)
      response = api_client.patch("/api/v1/internal/account_terminations/#{termination_id}", payload)
      unless response['success']
        raise "Failed to update account termination #{termination_id}: #{response['error']}"
      end
      response
    end

    # See Api::V1::Internal::AccountsController#terminate — no payload, sets
    # status: 'cancelled', idempotent.
    def terminate_account!(account_id)
      response = api_client.patch("/api/v1/internal/accounts/#{account_id}/terminate", {})
      unless response['success']
        raise "Failed to terminate account #{account_id}: #{response['error']}"
      end
      response
    end

    def delete_account_data(account_id, termination_log, own_export_request_id)
      # Fetch account users
      users_response = api_client.get("/api/v1/internal/accounts/#{account_id}/users")
      users = users_response['data'] || []

      # Process each user
      users.each do |user|
        delete_user_data(user['id'], termination_log)
      end

      # Delete account-level data
      delete_account_records(account_id, termination_log, own_export_request_id)
    end

    def delete_user_data(user_id, termination_log)
      # Delete user consents
      response = api_client.delete("/api/v1/internal/users/#{user_id}/consents")
      termination_log << { event: 'deleted_consents', user_id: user_id, at: Time.current.iso8601 }

      # Delete terms acceptances
      api_client.delete("/api/v1/internal/users/#{user_id}/terms_acceptances")
      termination_log << { event: 'deleted_terms_acceptances', user_id: user_id, at: Time.current.iso8601 }

      # Anonymize audit logs
      api_client.patch("/api/v1/internal/users/#{user_id}/anonymize_audit_logs", {})
      termination_log << { event: 'anonymized_audit_logs', user_id: user_id, at: Time.current.iso8601 }

      # Delete password histories
      api_client.delete("/api/v1/internal/users/#{user_id}/password_histories")

      # Delete user roles
      api_client.delete("/api/v1/internal/users/#{user_id}/roles")

      # Anonymize user record. The internal anonymize endpoint owns the full
      # field list (email/name/status/credentials/PII) — see
      # Api::V1::Internal::UsersController#anonymize — so no payload here.
      # This used to PATCH a bare `/api/v1/internal/users/:id`, which has no
      # route (404) and carried `status: 'terminated'`, a value the users
      # table's `valid_user_status` check constraint has never allowed; every
      # termination therefore failed at this step (IMP-7ff4be3454a6). The
      # routed anonymize endpoint sets status: 'inactive' — the design is
      # anonymize-in-place, not a distinct terminated status.
      api_client.patch("/api/v1/internal/users/#{user_id}/anonymize", {})
      termination_log << { event: 'anonymized_user', user_id: user_id, at: Time.current.iso8601 }
    end

    def delete_account_records(account_id, termination_log, own_export_request_id = nil)
      # Files. Api::V1::Internal::AccountsController#delete_files returns
      # `data: { count:, erased:, reason: }`.
      #
      # IMP-bf52b4da135b: that endpoint has never actually erased a file, and
      # still does not — it now says so explicitly (`erased: false`) instead
      # of returning a success-shaped "Deleted 0 file records". Record that
      # honestly in the termination_log rather than writing a `deleted_files`
      # entry for an erasure that did not happen: an operator reading this
      # log must be able to see that files were NOT erased. Same shape as the
      # `subscription_anonymize_skipped` entry below.
      #
      # `erased` is read with an explicit `== false` rather than a truthiness
      # check so that an OLDER server build (which returns neither key) is
      # treated as the legacy success path rather than being silently
      # reported as skipped.
      response = api_client.delete("/api/v1/internal/accounts/#{account_id}/files")
      files_data = response['data'] || {}
      termination_log << if files_data['erased'] == false
        {
          event: 'files_erasure_skipped',
          reason: files_data['reason'] || 'no_erasure_path',
          at: Time.current.iso8601
        }
      else
        {
          event: 'deleted_files',
          count: files_data['count'] || 0,
          at: Time.current.iso8601
        }
      end

      # Delete API keys
      api_client.delete("/api/v1/internal/accounts/#{account_id}/api_keys")
      termination_log << { event: 'deleted_api_keys', at: Time.current.iso8601 }

      # Delete webhooks
      api_client.delete("/api/v1/internal/accounts/#{account_id}/webhooks")
      termination_log << { event: 'deleted_webhooks', at: Time.current.iso8601 }

      # Delete data export requests. IMP-0310a1351dab review round 2, item 2:
      # `own_export_request_id` (this termination's own requested export, if
      # any) is the ONLY row the server may defer — by the time this runs,
      # export_deletion_gate has already confirmed it is delivered (or
      # that there is none), so `deferred` below is expected to be 0 in
      # practice; it is read rather than assumed so an unexpected server-side
      # deferral is recorded honestly instead of silently claimed as deleted.
      # The old unconditional `deleted_export_requests` entry was written even
      # when the server had deferred every row (the round-1 regression: ANY
      # pending/processing export anywhere in the account blocked deletion of
      # every export, while this log still claimed success) — read the real
      # count back instead of assuming one.
      export_params = own_export_request_id.present? ? { own_export_request_id: own_export_request_id } : {}
      export_response = api_client.delete("/api/v1/internal/accounts/#{account_id}/data_export_requests", export_params)
      export_data = export_response['data'] || {}
      deleted_export_count = export_data['count'] || 0
      deferred_export_count = export_data['deferred'] || 0

      termination_log << { event: 'deleted_export_requests', count: deleted_export_count, at: Time.current.iso8601 } if deleted_export_count.positive?
      termination_log << { event: 'export_deletion_deferred', at: Time.current.iso8601 } if deferred_export_count.positive?

      # Delete data deletion requests
      api_client.delete("/api/v1/internal/accounts/#{account_id}/data_deletion_requests")
      termination_log << { event: 'deleted_deletion_requests', at: Time.current.iso8601 }

      # Subscription anonymization is a business-extension concern (billing
      # subscriptions only exist when that extension is loaded). Core has no
      # route for this and no generic seam covers it either —
      # Powernode::BillingBridge registers subscription/payment/plan MODELS
      # and a provisioning quota/meter handler, but no anonymize handler.
      # Per IMP-b33a3ecca331 direction: skip cleanly in core mode rather than
      # calling an unrouted endpoint or inventing a new bridge seam; the gap
      # is documented in docs/operations/compliance.md.
      log_info "Skipping subscription anonymization for account #{account_id}: " \
               'no billing extension provider registered (core mode)'
      termination_log << {
        event: 'subscription_anonymize_skipped',
        reason: 'no_billing_extension_provider',
        at: Time.current.iso8601
      }
    end

    def send_termination_reminders(results)
      # Fetch terminations in grace period
      response = api_client.get('/api/v1/internal/account_terminations', {
        status: 'grace_period'
      })

      return unless response['success']

      terminations = response['data'] || []

      terminations.each do |termination|
        grace_period_ends = Time.zone.parse(termination['grace_period_ends_at'])
        days_remaining = ((grace_period_ends - Time.current) / 1.day).ceil

        reminder_type = case days_remaining
                        when 7 then '7_days'
                        when 3 then '3_days'
                        when 1 then '1_day'
                        else nil
                        end

        next unless reminder_type

        # Check if reminder already sent
        termination_log = termination['termination_log'] || []
        reminder_event = "reminder_#{reminder_type}_sent"

        next if termination_log.any? { |e| e['event'] == reminder_event }

        begin
          send_reminder(termination, reminder_type, days_remaining)

          # Update log — append only this reminder's own entry (the fetched
          # `termination_log` above is read-only, used to decide whether this
          # reminder is already due/sent; it is not resent to the server).
          patch_termination!(
            termination['id'],
            {
              termination_log_append: [{
                event: reminder_event,
                at: Time.current.iso8601
              }]
            }
          )

          results[:reminders_sent] += 1
        rescue => e
          log_warn "Failed to send reminder for termination #{termination['id']}: #{e.message}"
        end
      end
    end

    def send_reminder(termination, reminder_type, days_remaining)
      api_client.post(
        '/api/v1/internal/notifications/send',
        {
          account_id: termination['account_id'],
          type: 'account_termination_reminder',
          data: {
            termination_id: termination['id'],
            reminder_type: reminder_type,
            days_remaining: days_remaining,
            grace_period_ends_at: termination['grace_period_ends_at']
          }
        }
      )
    end

    def send_completion_notification(termination)
      api_client.post(
        '/api/v1/internal/notifications/send',
        {
          type: 'account_termination_complete',
          email: termination['owner_email'], # Captured before termination
          data: {
            termination_id: termination['id'],
            completed_at: Time.current.iso8601
          }
        }
      )
    rescue => e
      log_warn "Failed to send termination completion notification: #{e.message}"
    end
  end
end
