# frozen_string_literal: true

# Internal API controller for worker service to manage account terminations
class Api::V1::Internal::AccountTerminationsController < Api::V1::Internal::InternalBaseController
  before_action :set_termination, only: [ :show, :update ]

  # GET /api/v1/internal/account_terminations
  #
  # SECURITY-CRITICAL (IMP-b33a3ecca331 review, B2): this used to ignore
  # `status` / `grace_period_expired` entirely and return EVERY active
  # (pending/grace_period/processing) termination regardless of what the
  # caller asked for. Compliance::AccountTerminationJob#process_ready_terminations
  # sends `{status: 'grace_period', grace_period_expired: true}` specifically
  # so it only ever destructively processes (anonymize users, delete API
  # keys/webhooks, cancel the account) terminations that are BOTH confirmed
  # past `pending` AND past their 30-day grace period. Once the response-body
  # key bug (B1) is fixed, an unfiltered index would have handed the job
  # every `pending` (never confirmed) and every un-expired `grace_period`
  # termination too — irreversibly processing accounts the operator has not
  # actually cleared for deletion yet.
  # NIT (IMP-b33a3ecca331 second review): grace_period_expired without
  # status: 'grace_period' is a malformed query — it isn't a shape the worker
  # ever sends, and silently falling through to the unfiltered `.active`
  # default would hide the caller's mistake instead of surfacing it.
  def index
    if params[:grace_period_expired].present? && params[:status] != "grace_period"
      return render_error(
        "grace_period_expired requires status: 'grace_period'",
        status: :unprocessable_content, code: "INVALID_FILTER_COMBINATION"
      )
    end

    render_success(data: filtered_terminations.map { |t| termination_data(t) })
  end

  # GET /api/v1/internal/account_terminations/:id
  def show
    render_success(data: termination_data(@termination))
  end

  # PATCH/PUT /api/v1/internal/account_terminations/:id
  #
  # SECURITY (IMP-b33a3ecca331 second review, S-A): mirrors the guard added to
  # DataDeletionRequestsController's raw status branch. This used to accept
  # ANY status value with no audit trail — a worker principal could jump a
  # termination straight to 'completed' (destructive: cancels the account)
  # without ever having gone through 'processing', or restart an
  # un-expired 'grace_period' termination early. Allowed transitions:
  #   * grace_period -> processing, ONLY when can_start_processing? holds
  #     (grace_period_ends_at has actually passed — mirrors the model's own
  #     guard on start_processing!)
  #   * processing -> completed (the job finished) or grace_period (the
  #     job's own error-revert, re-arming it for retry)
  #   * a status-LESS write (log-only — reminder-sent entries) is allowed
  #     only while the termination is still active (grace_period/processing);
  #     once completed/cancelled its history is frozen.
  # Every status transition writes a registered audit row
  # (account_termination.status_transition) with from/to status. `with_lock`
  # makes the read-check-write atomic against a concurrent writer (this same
  # endpoint, hit by two job runs, or a human admin action) racing the same
  # termination between the guard check and the write.
  def update
    requested_status = params[:status]

    # Fourth review, nit 1: reject a forged event NAME before anything else —
    # cheap and status-independent, so it fails fast regardless of what else
    # is in the payload.
    unless valid_append_events?(params[:termination_log_append])
      return render_error(
        "termination_log_append contains an event this job never writes",
        status: :unprocessable_content, code: "INVALID_TERMINATION_LOG_EVENT"
      )
    end

    if requested_status.present?
      unless status_transition_allowed?(requested_status)
        return render_error(
          "Invalid status transition from '#{@termination.status}' to '#{requested_status}'",
          status: :unprocessable_content, code: "INVALID_STATUS_TRANSITION"
        )
      end
    else
      unless %w[grace_period processing].include?(@termination.status)
        return render_error(
          "Cannot update this termination's log while it is '#{@termination.status}'",
          status: :unprocessable_content, code: "INVALID_STATUS_TRANSITION"
        )
      end
    end

    # Double-checked locking: the FIRST guard (above) fails fast on the
    # common case without ever taking a row lock. `with_lock` reloads
    # @termination fresh from the DB before the block runs, so the SECOND
    # check below is the one that actually makes check-and-write atomic
    # against a concurrent writer (another worker run, or an admin action)
    # that changed this row's status between the first check and now.
    # `transitioned` — not a status comparison — records whether `update!`
    # actually ran, so a race that lands on some THIRD status (neither the
    # one we read nor the one we requested) is still caught correctly.
    #
    # `previous_status` (fourth review, nit 2) is captured INSIDE the lock,
    # off the freshly-reloaded record — capturing it before `with_lock` would
    # name whatever status this controller read BEFORE the lock, which a
    # concurrent writer could have already moved past; the audit row must
    # name the status this write actually transitioned FROM, not a stale one.
    transitioned = false
    previous_status = nil

    @termination.with_lock do
      previous_status = @termination.status

      guard_passes =
        if requested_status.present?
          status_transition_allowed?(requested_status)
        else
          %w[grace_period processing].include?(@termination.status)
        end

      raise ActiveRecord::Rollback unless guard_passes

      @termination.update!(termination_update_attrs)
      transitioned = true
    end

    unless transitioned
      return render_error(
        "Invalid status transition from '#{@termination.status}' to '#{requested_status}' (lost a concurrent update race)",
        status: :unprocessable_content, code: "INVALID_STATUS_TRANSITION"
      )
    end

    if requested_status.present?
      log_internal_audit("account_termination.status_transition", "Account::Termination", @termination.id,
                         account_id: @termination.account_id, from_status: previous_status, to_status: requested_status)
    end

    render_success(data: termination_data(@termination))
  rescue ActiveRecord::RecordInvalid
    render_validation_error(@termination)
  end

  private

  def status_transition_allowed?(requested_status)
    case @termination.status
    when "grace_period"
      requested_status == "processing" && @termination.can_start_processing?
    when "processing"
      %w[completed grace_period].include?(requested_status)
    else
      false
    end
  end

  # The worker sends exactly two shapes, both handled by reusing the model's
  # OWN scopes rather than reimplementing their semantics here:
  #   * {status: 'grace_period', grace_period_expired: true} — "ready to
  #     actually process" (Compliance::AccountTerminationJob
  #     #process_ready_terminations). This is precisely
  #     Account::Termination.ready_for_processing (= in_grace_period.
  #     grace_period_expired), which already exists and already matches the
  #     model's own `can_start_processing?` guard on `start_processing!`.
  #   * {status: 'grace_period'} alone — "everyone currently in grace period,
  #     expired or not" (#send_termination_reminders, to decide whether a
  #     7/3/1-day reminder is due). This is `in_grace_period` alone.
  # A bare `status:` with any other value (or none) falls back to the
  # pre-existing `.active` scope, filtered by that status — preserves
  # behavior for any other caller that doesn't send grace_period_expired.
  def filtered_terminations
    scope =
      if params[:status] == "grace_period" && truthy_param?(:grace_period_expired)
        Account::Termination.ready_for_processing
      elsif params[:status].present?
        Account::Termination.active.where(status: params[:status])
      else
        Account::Termination.active
      end

    scope.order(grace_period_ends_at: :asc)
  end

  def truthy_param?(key)
    ActiveModel::Type::Boolean.new.cast(params[key])
  end

  def set_termination
    @termination = Account::Termination.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_not_found("Account termination")
  end

  # BLOCKER (IMP-b33a3ecca331 second review): the previous fix permitted a
  # WHOLE-ARRAY `termination_log:` replace. That still corrupted history two
  # ways even setting the race aside: (1) the worker had to re-send every
  # entry it had fetched, including ones written by the MODEL's own methods
  # (confirm!/cancel!/complete!/schedule_reminders), whose keys (`by`,
  # `days_before`, `scheduled_for`) this list never permitted — those keys
  # were silently stripped on every worker write; (2) a whole-array replace
  # is a lost-update race against any concurrent writer. Per the no-legacy
  # rule, the whole-array param is REMOVED (not kept alongside the new one) —
  # `termination_log_append` carries ONLY the caller's new entries, merged
  # onto the current (locked, freshly-reloaded) stored log server-side in
  # `#update`.
  #
  # Fourth review, nit 1: `by`/`days_before`/`scheduled_for` are dropped from
  # this list entirely (not just from the job's OWN writes) — ONLY the
  # model's own writers use them, never the job, so the job has no legitimate
  # reason to append an entry carrying them. The server-side merge still
  # PRESERVES whatever the model already wrote (this list only governs what
  # NEW entries the worker can append, not what's already stored). The
  # remaining keys are every key the JOB's own termination_log writers
  # actually use: event/at (universal), user_id (per-user steps), count
  # (deleted_files), error (error-revert entry), reason
  # (subscription_anonymize_skipped entry).
  TERMINATION_LOG_ENTRY_KEYS = [ :event, :user_id, :count, :error, :reason, :at ].freeze

  # Fourth review, nit 1: key-permitting alone still let a forged EVENT NAME
  # through — `event` and `at` were always permitted keys, so
  # `{event: 'confirmed', at: ...}` (a MODEL-only event, never written by the
  # job) passed the key filter unchallenged. This is the exact set
  # Compliance::AccountTerminationJob itself builds (grepped every
  # `termination_log <<` / `+ [{...}]` call site in the job), including the
  # three concrete reminder-sent names `send_termination_reminders` can
  # produce (`"reminder_#{reminder_type}_sent"` for reminder_type in
  # 7_days/3_days/1_day) — listed literally rather than pattern-matched, so a
  # similar-but-forged name (e.g. `reminder_2_days_sent`) is still rejected.
  JOB_TERMINATION_LOG_EVENTS = %w[
    deleted_consents deleted_terms_acceptances anonymized_audit_logs anonymized_user
    deleted_files deleted_api_keys deleted_webhooks deleted_export_requests
    deleted_deletion_requests subscription_anonymize_skipped error
    reminder_7_days_sent reminder_3_days_sent reminder_1_day_sent
  ].freeze

  def valid_append_events?(raw_entries)
    return true if raw_entries.blank?

    raw_entries.all? { |entry| JOB_TERMINATION_LOG_EVENTS.include?(entry[:event]) }
  end

  def termination_params
    params.permit(
      :status, :completed_at, :processing_started_at,
      termination_log_append: TERMINATION_LOG_ENTRY_KEYS
    )
  end

  def termination_update_attrs
    permitted = termination_params.to_h
    append_entries = permitted.delete("termination_log_append")

    if append_entries.present?
      permitted["termination_log"] = @termination.termination_log + append_entries
    end

    permitted
  end

  def termination_data(termination)
    {
      id: termination.id,
      account_id: termination.account_id,
      status: termination.status,
      reason: termination.reason,
      grace_period_ends_at: termination.grace_period_ends_at,
      completed_at: termination.completed_at,
      requested_at: termination.requested_at,
      created_at: termination.created_at,
      updated_at: termination.updated_at,
      termination_log: termination.termination_log
    }
  end
end
