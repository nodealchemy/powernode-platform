# frozen_string_literal: true

module Ai
  # IMP-3c9a6dc8f0a9 — the shared dry-run/ceiling/audit/failure-semantics
  # shape behind every predicate-scoped bulk archive/retire/hard-delete in
  # this codebase (today: Ai::Memory::SharedKnowledgeService's
  # archive_by_predicate!/hard_delete_archived!, Ai::Learning::
  # CompoundLearningService's retire_by_predicate!/
  # hard_delete_retired_or_superseded!). Extracted after review found a real
  # defect that had been duplicated byte-for-byte into two services: fixing
  # it once here, rather than twice and staying in step forever, is why this
  # module exists at all — the CLAUDE.md Reuse First rule and this loop's own
  # `code_duplication` recommendation kind both point the same way once two
  # copies of the same 50 lines exist.
  #
  # THE DEFECT THIS SHAPE FIXES. The audit write used to sit AFTER the
  # mutation loop, inside the same `rescue StandardError` that wrapped the
  # loop itself. A raise partway through (`entry.destroy!` hitting an FK
  # constraint at row 200 of 500, say) unwound past the audit call entirely:
  # rows 1..199 were already destroyed and committed (no transaction — see
  # below), the method returned `success: false`, and NOTHING was written to
  # AuditLog. A partially-completed IRREVERSIBLE bulk delete with no
  # tamper-evident record is exactly the "a purge with no verifiable record
  # is how a disputed deletion becomes unresolvable" failure this tool exists
  # to avoid, and it is the destructive path — hard-delete — that was most
  # likely to trip it.
  #
  # THE FIX HAS TWO PARTS, both load-bearing on their own:
  #
  # 1. ONE ROW'S FAILURE COUNTS AND CONTINUES, never aborts the run. Before
  #    this fix the two ORIGINAL callers already disagreed on this: the
  #    knowledge-side archive block called `archive(entry_id:)`, which
  #    returns a hash and never raises, so it already counted-and-continued;
  #    the destroy block called `entry.destroy!`/`learning.destroy!`
  #    directly, which raises and aborted the whole loop. That inconsistency
  #    — the same tool behaving differently on a bad row depending which
  #    half of it you called — is resolved by rescuing per row here, so both
  #    halves behave identically: a row that fails to mutate is recorded as
  #    a failure and the loop moves on to the next one.
  #
  # 2. THE AUDIT WRITE IS UNCONDITIONAL w.r.t. the loop's outcome — wrapped
  #    in `ensure`, not placed after the loop where a raise could skip it.
  #    It records what ACTUALLY happened (affected_ids as of the point the
  #    loop stopped, per-row errors, and whether the loop was aborted before
  #    reaching its natural end), never what was merely requested. Point 1
  #    means a StandardError can no longer escape the loop at all — so
  #    `#call` always RETURNS a hash on that path, it never raises, and the
  #    "aborted" case below is not that path at all. `ensure` exists for
  #    what per-row rescue structurally cannot see: a non-StandardError exit
  #    (Interrupt/SystemExit — an operator's Ctrl-C mid-run is the realistic
  #    one). For THAT case, the audit entry is still written — "attempted
  #    500, mutated 199, interrupted: Interrupt" is the artifact that makes
  #    a disputed bulk mutation resolvable even then — and the exception is
  #    then allowed to keep propagating rather than being swallowed into a
  #    fake success. Silence plus a swallowed interrupt would be
  #    indistinguishable from "nothing happened", which is the one wrong
  #    conclusion an operator must never be able to draw about an
  #    irreversible operation, interrupted or not.
  #
  # NOT TRANSACTIONAL, deliberately (decided, not defaulted). Wrapping every
  # row's mutation in one transaction would make the whole call all-or-
  # nothing and remove the partial-state question entirely — but at the cost
  # of a long-held transaction across pgvector/HNSW-indexed rows, and a
  # rollback after 499 successful mutations would throw away exactly the
  # work an operator asked for because row 500 happened to fail. The two-step
  # design each caller already uses (archive/retire is reversible; the
  # separate hard-delete step only ever targets an already-narrowed,
  # already-reviewed base — see each caller's own header comment) already
  # bounds the blast radius of a bad predicate, and the predicate is simply
  # re-run to catch whatever a partial pass missed. A truthful audit record
  # of what actually happened is the safety property this shape guarantees;
  # atomicity is not one of this tool's promises.
  module BulkPredicateMutation
    # A predicate whose dry-run count exceeds this REFUSES the mutating call
    # outright rather than truncating and acting on a partial match — a
    # silently truncated bulk mutation is its own kind of wrong-rows failure,
    # distinct from (and no safer than) matching the wrong rows in the first
    # place. The caller must narrow the predicate or call it in batches;
    # nothing here ever silently does less than the predicate asked for.
    MAX_BULK_PER_CALL = 500

    module_function

    # @param account [Account] the audit log entry's account.
    # @param scope [ActiveRecord::Relation] already fully predicated by the
    #   caller — this module owns none of the predicate construction or any
    #   mandatory base scope (e.g. "archived only"/"retired or superseded
    #   only"); that is each caller's own responsibility, kept at the call
    #   site where the irreversibility boundary is meaningful.
    # @param dry_run [Boolean] true (the caller's own default too) returns
    #   the count/sample without touching the DB at all.
    # @param actor [User, nil] attributed on the audit log entry; nil for a
    #   rake/cron-driven run.
    # @param action [String] must already be registered in
    #   AuditActions (e.g. AI_ANALYTICS_ACTIONS) — Audit::LoggingService
    #   raises ActiveRecord::RecordInvalid otherwise, which IS how this
    #   requirement was discovered rather than assumed.
    # @param predicate [Hash] the caller-supplied predicate, recorded
    #   verbatim on the audit entry for provenance — not interpreted here.
    # @param serializer [#call] row -> Hash, used only for the count-time
    #   first-3/last-1 sample.
    # @param log_tag [String] e.g. "[SharedKnowledge]"/"[CompoundLearning]" —
    #   prefixed on every log line so the callers stay distinguishable in
    #   shared log output.
    # @yield [row] performs ONE row's mutation; return truthy on success. May
    #   raise — rescued per row (see point 1 above) and counted as a failure,
    #   never propagated out of this call.
    def call(account:, scope:, dry_run:, actor:, action:, predicate:, serializer:, log_tag:)
      # IMP-3c9a6dc8f0a9 review round — THE MESSAGE-CAN-LIE DEFECT. This
      # rescue used to be a method-level `rescue` on `#call` itself, which
      # wraps the ENTIRE body — including the call to #mutate_and_audit. Its
      # own `ensure` can raise too (Audit::LoggingService#log hitting a DB
      # blip), and when it did, that exception unwound straight out of
      # #mutate_and_audit into THIS rescue, which logged "failed before any
      # mutation" — false, since rows were already destroyed by that point;
      # the audit write was the only thing that failed. Scoping this rescue
      # to a `begin/end` around ONLY the pre-mutation work (count, the
      # ceiling check, ordering, sampling) makes the message honest by
      # construction: nothing past this `begin/end` can ever reach it, so if
      # it fires, mutation genuinely never started. An audit-write failure
      # is handled separately, inside #mutate_and_audit itself (see there).
      begin
        count = scope.count

        if count > MAX_BULK_PER_CALL
          return {
            success: false,
            error: "Predicate matches #{count} rows, exceeding the #{MAX_BULK_PER_CALL} per-call ceiling " \
                   "— narrow the predicate or call this in batches",
            count: count,
            ceiling: MAX_BULK_PER_CALL
          }
        end

        rows = scope.order(:id).to_a
        sample = (rows.first(3) + rows.last(1)).uniq.map(&serializer)
      rescue StandardError => e
        Rails.logger.error("#{log_tag} Bulk predicate action '#{action}' failed before any mutation: #{e.class}: #{e.message}")
        return { success: false, error: e.message }
      end

      return { success: true, dry_run: true, count: count, sample: sample } if dry_run

      mutate_and_audit(account: account, rows: rows, count: count, actor: actor,
                        action: action, predicate: predicate, sample: sample, log_tag: log_tag) { |row| yield(row) }
    end

    def mutate_and_audit(account:, rows:, count:, actor:, action:, predicate:, sample:, log_tag:)
      affected_ids = []
      row_errors = []
      completed = false
      audit_failed = false

      begin
        rows.each do |row|
          begin
            if yield(row)
              affected_ids << row.id
            else
              row_errors << { id: row.id, error: "mutation returned falsy" }
            end
          rescue StandardError => e
            row_errors << { id: row.id, error: "#{e.class}: #{e.message}" }
            Rails.logger.error(
              "#{log_tag} Bulk predicate action '#{action}' failed on row #{row.id}: #{e.class}: #{e.message}"
            )
          end
        end
        completed = true
      ensure
        # UNCONDITIONAL w.r.t. how the loop above exited — completed
        # normally, hit per-row failures (both leave `completed: true`,
        # since the per-row rescue means those never escape the loop), OR
        # something else entirely aborted it (`completed` stays false).
        #
        # `completed` — NOT a rescue-set flag — is what decides "aborted",
        # deliberately. A per-row `rescue StandardError` means a plain
        # StandardError can no longer escape `rows.each` at all, so an
        # `aborted_error` variable set only inside a `rescue StandardError`
        # here would never fire from a StandardError and would also miss a
        # non-StandardError exit (Interrupt/SystemExit — the realistic case
        # left uncaught: an operator's Ctrl-C mid-run) since `rescue
        # StandardError` cannot see those either. `ensure` runs for ANY
        # exit, so reading "did the loop finish" off a boolean set at its
        # true end, rather than off which rescue clause fired, is the only
        # way this stays correct for both.
        #
        # `$!` — Ruby's "exception currently being unwound" — is read here,
        # not stored earlier, because it is only meaningful while unwinding
        # is actually in progress (i.e. exactly when `completed` is false).
        aborted = !completed
        abort_error = aborted && $! && "#{$!.class}: #{$!.message}"

        Rails.logger.error(
          "#{log_tag} Bulk predicate action '#{action}' ABORTED after #{affected_ids.size}/#{count} rows: #{abort_error}"
        ) if aborted

        # IMP-3c9a6dc8f0a9 review round (BLOCKER 1) — this used to call
        # Audit::LoggingService.instance.log, which is the WRONG sink for an
        # irreversible bulk mutation's audit trail, for two independent
        # reasons neither of which raises:
        #
        # 1. Rate limiting (logging_service.rb#should_rate_limit?) caps
        #    actions matching /admin|delete/ — which "ai.knowledge.
        #    bulk_hard_delete"/"ai.learning.bulk_hard_delete" both do — at 5
        #    per hour, per action+user, via Rails.cache. A purge needing
        #    N > 5 calls (any predicate matching more than
        #    5 * MAX_BULK_PER_CALL rows total) gets its 6th-and-later audit
        #    writes silently dropped: #log returns nil, no AuditLog row, no
        #    exception — indistinguishable from success at this call site.
        # 2. #log also rescues StandardError around its own AuditLog.create!
        #    and returns nil instead of raising, UNLESS Rails.env.test? —
        #    meaning our own specs are structurally incapable of observing
        #    either defeat: should_rate_limit? hard-codes
        #    `return false if Rails.env.test?`, and the rescue only
        #    re-raises in test. We proved the audit_failed contract in the
        #    one environment where the sink cannot fail the way it fails in
        #    production.
        #
        # Fix: call AuditLog.log_action directly. It is what
        # LoggingService#log calls internally anyway, minus the rate limit
        # and the swallowed rescue — create! raises (RecordInvalid, or any
        # DB error) rather than returning nil, so the existing rescue below
        # (already built for exactly this) now has something real to catch.
        # See "is not subject to Audit::LoggingService's rate limiting"
        # in bulk_predicate_mutation_spec.rb — it proves this by writing
        # more audit rows in one run than the production /delete/ ceiling
        # (5/hour) would allow, which is only possible because this path no
        # longer goes through should_rate_limit? at all.
        #
        # IMP-3c9a6dc8f0a9 review round — bypassing #log dropped more than
        # the two defeats above, which is all the original direction
        # argued. Fixed here, narrowly:
        #
        # 1. `source:` — #log_action defaults to "web" when not given.
        #    A rake-driven purge is not a web request; recording it as one
        #    is simply wrong data in the audit log. Set explicitly:
        #    "api" when an actor is present (an MCP-tool-driven call, which
        #    arrived over the platform's API), "automation" otherwise (a
        #    rake/cron-driven run with no actor at all) — both are real
        #    entries in AuditActions::CORE_SOURCES.
        # 2. Request context (ip_address/user_agent/request_id/session_id/
        #    correlation_id) — #log's private #enrich_context reads these
        #    off Audit::LoggingService's PUBLIC #current_context (thread-
        #    local, populated by a controller concern for an actual HTTP
        #    request — empty for a rake run, which has none to capture).
        #    Merged in directly here rather than reimplementing
        #    #enrich_context, since #current_context is already public.
        # 3. The real-time monitoring hook (#monitor_event / the
        #    "audit_monitoring" ActionCable broadcast / #check_alert_
        #    conditions) — deliberately NOT dropped. Invoked via `.send`
        #    (both are private on Audit::LoggingService) AFTER a successful
        #    write, not routed through #log — this reuses the non-trivial
        #    alerting logic without going anywhere near the rate limit or
        #    the swallowed rescue #log itself sits behind.
        #
        #    WIRED BUT DORMANT FOR THESE FOUR ACTIONS TODAY — read this
        #    before assuming a bulk hard delete raises an alert; it does
        #    not. #should_monitor? is `is_suspicious? || is_security_related?`,
        #    which check AuditLog.suspicious_actions/.security_actions —
        #    "ai.knowledge.bulk_archive"/"bulk_hard_delete"/"ai.learning.
        #    bulk_retire"/"bulk_hard_delete" appear only in the AI
        #    analytics action registry (audit_actions.rb), in neither list,
        #    so #should_monitor? is false for all four, always, right now.
        #    This call exists so the HOOK ITSELF is not silently lost (the
        #    shape of defect this whole task exists to prevent) — it is not
        #    claiming these actions currently alert on anything. The specs
        #    below stub #should_monitor? specifically because no real
        #    action name here can exercise the true branch today. Making
        #    this live is a deliberate follow-up, not done here: registering
        #    hard-delete action names as suspicious/security-related raises
        #    alert volume for every operator, which is a policy call with
        #    blast radius past this diff — filed as offer 01a0bd8a-ac70.
        begin
          request_context = Audit::LoggingService.instance.current_context

          audit_log = ::AuditLog.log_action(
            action: action,
            resource: account,
            user: actor,
            account: account,
            source: actor ? "api" : "automation",
            ip_address: request_context[:ip_address],
            user_agent: request_context[:user_agent],
            request_id: request_context[:request_id],
            session_id: request_context[:session_id],
            correlation_id: request_context[:correlation_id],
            metadata: {
              predicate: predicate,
              requested_count: count,
              affected_count: affected_ids.size,
              failed: row_errors.size,
              row_errors: row_errors,
              dry_run: false,
              affected_ids: affected_ids,
              aborted: aborted,
              abort_error: abort_error
            }.compact
          )

          # Rescued separately from the audit write above: monitor_event
          # failing (an ActionCable broadcast blip, say) is not the same
          # failure as the audit write failing, and audit_failed's message
          # would lie about which one happened if this shared that rescue —
          # the AuditLog row above is real and already committed either way.
          begin
            logging_service = Audit::LoggingService.instance
            logging_service.send(:monitor_event, audit_log) if logging_service.send(:should_monitor?, audit_log)
          rescue NoMethodError => wiring_error
            # Caught AHEAD OF the StandardError rescue below on purpose.
            # #monitor_event/#should_monitor? are reached via `.send` past
            # Ruby's normal visibility check specifically because they are
            # private — if either is ever renamed or removed by a later
            # refactor, THIS is the exception `.send` raises, and it means
            # "the hook is now disconnected", not "the broadcast hiccupped".
            # A shared rescue would log it as a monitoring failure and hide
            # exactly the failure mode worth knowing about: the mechanism
            # disappearing rather than merely misfiring. Same shape as the
            # blocker-1 sink defect — the rescue that protects the happy
            # path must not also hide the wiring breaking.
            Rails.logger.error(
              "#{log_tag} Bulk predicate action '#{action}' audited successfully but the real-time " \
              "monitoring hook is DISCONNECTED — #{wiring_error.message} — Audit::LoggingService's " \
              "private #monitor_event/#should_monitor? no longer exist as called; this is a wiring " \
              "break from a refactor, not a runtime monitoring failure. The AuditLog row is NOT in " \
              "question here."
            )
          rescue StandardError => monitor_error
            Rails.logger.error(
              "#{log_tag} Bulk predicate action '#{action}' audited successfully but the real-time " \
              "monitoring hook failed: #{monitor_error.class}: #{monitor_error.message} — the AuditLog " \
              "row is NOT in question here, only the alert/broadcast."
            )
          end
        rescue StandardError => audit_error
          audit_failed = true
          Rails.logger.error(
            "#{log_tag} Bulk predicate action '#{action}' mutated #{affected_ids.size}/#{count} rows " \
            "successfully but the AUDIT WRITE FAILED: #{audit_error.class}: #{audit_error.message} — " \
            "the mutation is NOT in question here, only the missing audit record."
          )
        end
      end

      result = {
        success: true, dry_run: false,
        count: affected_ids.size, failed: row_errors.size, ids: affected_ids,
        row_errors: row_errors.presence, sample: sample
      }
      result[:audit_failed] = true if audit_failed
      result
    end
    private_class_method :mutate_and_audit

    # ==================================================
    # Invocation-level safety for a multi-account caller (rake tasks)
    # ==================================================
    #
    # IMP-3c9a6dc8f0a9 review round — `#call` above bounds ONE account's
    # scope against MAX_BULK_PER_CALL. A caller that loops every account
    # (`Account.find_each { |a| ... .call(...) }`, which is what a rake task
    # invoked with no account filter does) defeats that bound BY
    # CONSTRUCTION: a hundred accounts each matching 400 rows each pass
    # their own per-account ceiling check while the INVOCATION destroys
    # 40,000 rows. Every individual call was "safe"; the invocation was not.
    # These two methods are the seam that closes that gap — kept here,
    # alongside the per-account ceiling they exist to back up, rather than
    # duplicated into both rake files that need it.
    #
    # #resolve_accounts_for_rake! — a MUTATING invocation (dry_run: false)
    # MUST name exactly one account_id. A dry run may still sweep every
    # account: it mutates nothing, and surveying the full backlog before
    # choosing an account to act on is the whole point of a dry run.
    #
    # @param account_id [String, nil] from the caller's ACCOUNT_ID env/arg.
    # @param dry_run [Boolean]
    # @return [ActiveRecord::Relation<Account>] or aborts the process
    #   (Kernel#abort — this is a CLI entry point, not a service call with a
    #   caller to hand a hash back to).
    def resolve_accounts_for_rake!(account_id:, dry_run:)
      if !dry_run && account_id.blank?
        abort(
          "EXECUTE=true requires ACCOUNT_ID=<uuid> — a mutating bulk action must name its account. " \
          "Dry runs (ACCOUNT_ID omitted) may sweep every account to survey the backlog; looping every " \
          "account on a MUTATING run would defeat the per-account #{MAX_BULK_PER_CALL}-row ceiling by " \
          "construction (each account's call passes its own check while the invocation does not)."
        )
      end

      return ::Account.all if account_id.blank?

      scoped = ::Account.where(id: account_id)
      abort("No account found for ACCOUNT_ID=#{account_id}") if scoped.none?

      scoped
    end

    # #enforce_aggregate_ceiling! — sums dry-run counts ALREADY COLLECTED by
    # the caller (one dry-run preview per account, taken BEFORE any real
    # mutation runs anywhere). On a MUTATING invocation, exceeding
    # MAX_BULK_PER_CALL aborts the WHOLE invocation — no account mutated.
    # Kept as a real, separate check even though #resolve_accounts_for_rake!
    # already forces a mutating run down to one account (where this total
    # simply equals that account's own count, redundant with #call's own
    # ceiling): it is what keeps working if the ACCOUNT_ID requirement above
    # is ever loosened by a future edit that does not re-derive why both
    # checks exist.
    #
    # IMP-3c9a6dc8f0a9 review round — REGRESSION FIX: `dry_run:` added.
    # This used to abort unconditionally, including on a DRY RUN — but a
    # dry run sweeping every account (no ACCOUNT_ID) is exactly how an
    # operator surveys a backlog before touching anything, and this task's
    # own stated scale (~6,250 rows) exceeds the 500-row ceiling by
    # construction. The very first survey an operator ran would abort
    # instead of reporting, on the one invocation shape that mutates
    # nothing and therefore has nothing to protect against. A dry run now
    # WARNS (via Rails.logger, same message) and returns the aggregate so
    # the survey completes and every account's own preview still prints;
    # only a MUTATING invocation (`dry_run: false`) actually aborts.
    #
    # @param previews [Array<[Account, Hash]>] one (account, dry-run result)
    #   pair per account with at least one matching row. Callers filter out
    #   zero-count accounts before calling this — an account with nothing to
    #   do contributes nothing to the total either way.
    # @param dry_run [Boolean] the caller's own dry_run flag — determines
    #   whether an over-ceiling aggregate warns (dry run) or aborts (real run).
    # @return [Integer] the aggregate count. On a dry run this is returned
    #   even over the ceiling (a warning was logged); on a real run,
    #   returning at all means the caller may proceed.
    def enforce_aggregate_ceiling!(previews, dry_run:)
      aggregate = previews.sum { |_account, preview| preview[:count].to_i }
      return aggregate unless aggregate > MAX_BULK_PER_CALL

      message = "Aggregate across #{previews.size} account(s) matches #{aggregate} rows, exceeding the " \
                "#{MAX_BULK_PER_CALL}-row per-invocation ceiling — narrow the predicate, target one " \
                "ACCOUNT_ID, or run this in batches."

      if dry_run
        Rails.logger.warn("#{message} (dry run — reporting only; nothing is mutated by this invocation)")
        return aggregate
      end

      abort("#{message} No rows were mutated.")
    end

    # ==================================================
    # Predicate validation (shared shape, per-caller allowed-key set)
    # ==================================================
    #
    # IMP-3c9a6dc8f0a9 review round (BLOCKER 3) — a predicate key the caller
    # supplied but the builder silently ignored used to fall through as "no
    # filter on this dimension" rather than an error: a blank domain
    # (`{ domain: "" }`), an unrecognised key (a typo), or an empty array
    # all matched EVERY row instead of none — on a destructive predicate-
    # scoped path, that is a silent WIDENING to the opposite of what the
    # caller asked for, not a graceful default. It surfaced first as
    # #retire_domain!'s `return ... if domain.blank?` guard not being
    # re-hosted when the predicate path replaced it — the deleted method's
    # safety property, not just its row-selection, had to be reproduced.
    #
    # A caller must OMIT a key entirely to mean "no filter on this
    # dimension" (Hash#key? is false) — any key present with a blank value,
    # or any key not in allowed_keys, raises instead of being ignored.
    #
    # WARNING for whoever adds the first BOOLEAN predicate key: `false.blank?`
    # is true in Rails (ActiveSupport's Object#blank? treats `false` the same
    # as nil/""/[]/{}) — so `{ some_flag: false }`, a perfectly legitimate,
    # deliberate value, would raise here as if it had been omitted or left
    # blank. Nothing today is affected (no predicate key across either
    # caller is boolean), so this is a documented trap, not a live bug — but
    # it will misfire the moment one is added unless this method is given a
    # boolean-aware exception for that key first.
    #
    # @param predicate [Hash] symbol-keyed.
    # @param allowed_keys [Array<Symbol>] the keys this predicate builder
    #   actually implements — callers pass their own list; this module owns
    #   no opinion on what a valid predicate key is for either caller.
    # @raise [ArgumentError] on an unknown key or a blank value for a known one.
    def validate_predicate!(predicate, allowed_keys:)
      predicate.each_key do |key|
        next if allowed_keys.include?(key)

        raise ArgumentError, "Unknown predicate key #{key.inspect} — allowed: #{allowed_keys.join(', ')}"
      end

      predicate.each do |key, value|
        next unless value.nil? || (value.respond_to?(:blank?) && value.blank?)

        raise ArgumentError,
              "predicate[#{key.inspect}] was given a blank value (#{value.inspect}) — omit the key " \
              "entirely to mean 'no filter on this dimension'; a blank value silently matching " \
              "everything is exactly the widening this check exists to prevent"
      end
    end
  end
end
