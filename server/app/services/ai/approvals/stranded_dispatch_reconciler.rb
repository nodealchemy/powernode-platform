# frozen_string_literal: true

module Ai
  module Approvals
    # Settles approved requests whose post-commit dispatch was owed and never
    # started, and signals ones whose dispatch started and never finished
    # (IMP-0213523480d1).
    #
    # IMP-9ce0ed39c557 moved the approved-arm dispatch in
    # Ai::ApprovalRequest#notify_source_of_decision to after commit, so the
    # approval commits BEFORE its dispatch runs. A process that dies in between
    # (OOM, deploy restart, SIGKILL), or a non-StandardError escaping the block,
    # leaves the request approved with nothing executed. The request is no
    # longer pending, so nobody can decide it again, and before this class
    # nothing else looked at it either.
    #
    # Both states are read off stamps the approval path writes itself:
    # dispatch_scheduled_at (in the approval's own transaction),
    # dispatch_started_at (the claim at the start of the dispatch) and
    # dispatch_finished_at (every terminal path of a claimed dispatch).
    #
    # STRANDED — owed, never started (Ai::ApprovalRequest.owed_dispatch), past
    # the grace window. Each is either:
    #
    #   * FAILED (the default) — declared failed on the request, its source
    #     settled to match where the source knows how, an audit row in the same
    #     transaction, and an Ai::ExecutionEvent on the same approval_execution
    #     surface a dispatch that raised uses; or
    #   * RE-DISPATCHED — only for a category the operator has listed as
    #     idempotent (REDISPATCH_ALLOWLIST_SETTING, empty by default), and never
    #     for one #redispatch_refusal names, whatever the list says. Audited as
    #     it starts, before the dispatch runs.
    #
    # Only Ai::DeferredOperation settles itself on FAIL
    # (#on_dispatch_abandoned: approved then failed, its parked plan step
    # released). Every other source is failed on the REQUEST only and stays
    # where the lost dispatch left it, recoverable through its own door:
    #
    #   * Ai::CampaignLand stays pending_approval — the operator approves it
    #     again (#operator_approve!: the request is no longer pending, so it
    #     takes the direct branch and enqueues the land);
    #   * Ai::Mission stays awaiting_approval at its gate — the mission's own
    #     approval action (Missions::OrchestratorService#handle_approval!) finds
    #     no OPEN gateway request and advances directly;
    #   * Ai::AgentProposal stays pending_review and Ai::ImprovementRecommendation
    #     stays pending — each is decided on the record itself (#approve! /
    #     #reject! / #dismiss!).
    #
    # The audit row and event name the request and its source, which is how an
    # operator finds them.
    #
    # INTERRUPTED — started, never finished (Ai::ApprovalRequest
    # .unfinished_dispatch), past INTERRUPT_HOURS_SETTING. SIGNAL ONLY: the side
    # effect may have happened, so nothing re-runs it and nothing fails the
    # request or its source. Signalled once (dispatch_interrupt_signalled_at)
    # with an audit row, an event, and a count.
    #
    # Every settling arm claims through a conditional update on the request
    # row — for FAIL and RE-DISPATCH the same one the post-commit dispatch
    # claims through — so a dispatch that starts late and this reconciler can
    # never both act on one request.
    #
    # Driven by the approval-expiry sweep (AiApprovalExpiryJob → internal
    # autonomy#expire_overdue_approval_requests), not a cron of its own.
    class StrandedDispatchReconciler
      # Minutes a request may sit owed-but-unstarted before it counts as
      # stranded. The normal gap is the time between a commit and the next
      # line of the same thread, but the stamp is written at flip time, before
      # commit: an enclosing transaction, or post-commit blocks queued behind a
      # slow executor in the same commit, add to it. The sweep is hourly, so a
      # generous window costs almost no detection time.
      GRACE_MINUTES_SETTING = "ai_approvals_stranded_dispatch_grace_minutes"
      DEFAULT_GRACE_MINUTES = 30

      # Hours a claimed dispatch may run without finishing before it is
      # signalled as interrupted. Executors run synchronously in the server
      # process and some are long, so this is far wider than the grace window.
      INTERRUPT_HOURS_SETTING = "ai_approvals_interrupted_dispatch_hours"
      DEFAULT_INTERRUPT_HOURS = 6

      # Exact action categories the operator has established are safe to run
      # a second time. A JSON array of strings; anything else reads as empty.
      REDISPATCH_ALLOWLIST_SETTING = "ai_approvals_stranded_redispatch_categories"

      # Never re-run, allowlisted or not, on top of
      # HumanSessionPolicy::DESTRUCTIVE_CATEGORY_PATTERNS and
      # Ai::DeferredOperationApprovalContent.destructive_categories: a command
      # on a live host whose effect cannot be observed from here (out-of-band
      # exec), a unit override that restarts a service (unit drop-in), and
      # verbs that rebuild or undo (reprovision destroys persist; replace and
      # rollback act on what the first run left). File.fnmatch patterns.
      NEVER_REDISPATCH_PATTERNS = %w[
        *out_of_band_exec* *unit_dropin* *reprovision* *replace* *rollback*
      ].freeze

      SWEEP_LIMIT = 100

      def self.grace_window
        positive_setting(GRACE_MINUTES_SETTING, DEFAULT_GRACE_MINUTES).minutes
      end

      def self.interrupt_window
        positive_setting(INTERRUPT_HOURS_SETTING, DEFAULT_INTERRUPT_HOURS).hours
      end

      # Fail closed: a setting that is not a list of strings allowlists nothing.
      def self.redispatch_allowlist
        configured = ::SiteSetting.get(REDISPATCH_ALLOWLIST_SETTING)
        configured.is_a?(Array) && configured.all?(String) ? configured : []
      end

      def self.positive_setting(key, default)
        value = Integer(::SiteSetting.get(key).to_s, exception: false)
        value&.positive? ? value : default
      end
      private_class_method :positive_setting

      def initialize(account:)
        @account = account
      end

      # Returns what THIS call did: { failed:, redispatched:, interrupted:,
      # errored: }. A request another caller claimed first counts toward none;
      # one that raised while being settled or signalled counts as errored and
      # is left for the next sweep.
      def call
        counts = { failed: 0, redispatched: 0, interrupted: 0, errored: 0 }
        settle_stranded(counts)
        signal_interrupted(counts)
        counts
      end

      private

      def settle_stranded(counts)
        allowlist = self.class.redispatch_allowlist
        each_guarded(::Ai::ApprovalRequest.owed_dispatch, :dispatch_scheduled_at, self.class.grace_window, counts) do |request|
          settle(request, allowlist, counts)
        end
      end

      def signal_interrupted(counts)
        window = self.class.interrupt_window
        each_guarded(::Ai::ApprovalRequest.unfinished_dispatch, :dispatch_started_at, window, counts) do |request|
          reason = "its dispatch started at #{request.dispatch_started_at&.iso8601} and never finished within " \
                   "#{window.inspect}; the process likely stopped mid-dispatch, so its effect is unknown. " \
                   "Not re-run and not failed: check the source before acting on it"
          signalled = request.signal_interrupted_dispatch!(reason) do
            audit!(request, "ai.approvals.dispatch_interrupted", categories_for(request), reason)
          end
          counts[:interrupted] += 1 if signalled
        end
      end

      def each_guarded(scope, clock, window, counts)
        scope.where(account_id: @account.id)
             .where(clock => ..window.ago)
             .order(clock)
             .limit(SWEEP_LIMIT)
             .each do |request|
          yield request
        rescue StandardError => e
          counts[:errored] += 1
          Rails.logger.error(
            "[StrandedDispatchReconciler] request #{request.id} not settled: #{e.class}: #{e.message}"
          )
        end
      end

      def settle(request, allowlist, counts)
        categories = categories_for(request)
        refusal = redispatch_refusal(request, categories, allowlist)

        if refusal.nil?
          redispatched = request.redispatch_stranded! do
            audit!(request, "ai.approvals.dispatch_redispatched", categories, "allowlisted as idempotent")
          end
          counts[:redispatched] += 1 if redispatched
        else
          reason = "approved at #{request.dispatch_scheduled_at&.iso8601}, but its dispatch never started " \
                   "within the #{self.class.grace_window.inspect} grace window (the process likely stopped " \
                   "between the approval's commit and the dispatch); failed rather than re-run: #{refusal}"
          failed = request.abandon_stranded_dispatch!(reason) do
            audit!(request, "ai.approvals.dispatch_abandoned", categories, reason)
          end
          counts[:failed] += 1 if failed
        end
      end

      # Every name the request and its source give the action. All of them
      # must clear the checks, so a mismatch between the card and the
      # operation errs towards failing.
      def categories_for(request)
        data = request.request_data.is_a?(Hash) ? request.request_data.with_indifferent_access : {}
        source = source_for(request)
        [
          data[:action_category], data[:action_type],
          (source.action_category if source.respond_to?(:action_category))
        ].map { |c| c.to_s.presence }.compact.uniq
      end

      def source_for(request)
        klass = request.source_type.to_s.safe_constantize
        klass.respond_to?(:find_by) ? klass.find_by(id: request.source_id) : nil
      end

      # nil when the request may be re-dispatched; otherwise why not.
      #
      # The person-needed check reads the request's OWN reasons, not the
      # account's intervention mark: the mark decides who may approve a
      # request, not whether it is safe to run twice, so a mark of false must
      # not lift a protected plane, a destructive call or a listed category.
      def redispatch_refusal(request, categories, allowlist)
        return "no action category to judge it by" if categories.empty?

        forbidden = categories.find { |c| never_redispatch_category?(c) }
        return "#{forbidden} is never re-dispatched" if forbidden
        if request.requires_human_session? || ::Ai::Approvals::HumanSessionPolicy.required_ignoring_account_mark?(request)
          return "it is human-only, destructive, on a protected environment, or needs a person's own session"
        end

        unlisted = categories.reject { |c| allowlist.include?(c) }
        return "#{unlisted.join(', ')} is not on the re-dispatch allowlist" if unlisted.any?

        nil
      end

      def never_redispatch_category?(category)
        patterns = NEVER_REDISPATCH_PATTERNS + ::Ai::Approvals::HumanSessionPolicy::DESTRUCTIVE_CATEGORY_PATTERNS
        patterns.any? { |pattern| File.fnmatch?(pattern, category) } ||
          ::Ai::DeferredOperationApprovalContent.destructive_categories.any? { |frag| category.include?(frag) }
      end

      # Runs inside the claim's transaction and RAISES on failure, so the claim
      # and its audit commit together or not at all; the row is then counted
      # errored and retried next sweep.
      def audit!(request, action, categories, reason)
        ::AuditLog.log_action(
          action: action,
          resource: request,
          account: @account,
          source: "system",
          severity: action.end_with?("redispatched") ? "medium" : "high",
          metadata: {
            reason: reason,
            action_category: categories.first,
            action_categories: categories,
            source_type: request.source_type,
            source_id: request.source_id,
            dispatch_scheduled_at: request.dispatch_scheduled_at&.iso8601,
            dispatch_started_at: request.dispatch_started_at&.iso8601
          }.compact
        )
      end
    end
  end
end
