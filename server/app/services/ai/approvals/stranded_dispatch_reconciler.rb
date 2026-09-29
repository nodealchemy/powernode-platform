# frozen_string_literal: true

module Ai
  module Approvals
    # Settles approved requests whose post-commit dispatch was owed and never
    # started (IMP-0213523480d1).
    #
    # IMP-9ce0ed39c557 moved the approved-arm dispatch in
    # Ai::ApprovalRequest#notify_source_of_decision to after commit, so the
    # approval commits BEFORE its dispatch runs. A process that dies in between
    # (OOM, deploy restart, SIGKILL), or a non-StandardError escaping the block,
    # leaves the request approved with nothing executed. The request is no
    # longer pending, so nobody can decide it again, and before this class
    # nothing else looked at it either.
    #
    # "Owed and never started" is read off two stamps the approval path writes
    # itself (Ai::ApprovalRequest.owed_dispatch): dispatch_scheduled_at, in the
    # approval's own transaction, and dispatch_started_at, claimed at the start
    # of the dispatch. Past the grace window each such request is either:
    #
    #   * FAILED (the default) — declared failed on the request, its source
    #     settled to match (Ai::DeferredOperation#on_dispatch_abandoned), an
    #     Ai::ExecutionEvent on the same approval_execution surface a dispatch
    #     that raised uses, and an audit row; or
    #   * RE-DISPATCHED — only for a category the operator has listed as
    #     idempotent (REDISPATCH_ALLOWLIST_SETTING, empty by default), and never
    #     for one #never_redispatch? names, whatever the list says.
    #
    # Both arms claim through a conditional update on the request row, the same
    # one the post-commit dispatch claims through, so a dispatch that starts
    # late and this reconciler can never both act on one request.
    #
    # Driven by the approval-expiry sweep (AiApprovalExpiryJob → internal
    # autonomy#expire_overdue_approval_requests), not a cron of its own.
    class StrandedDispatchReconciler
      # Minutes a request may sit owed-but-unstarted before it counts as
      # stranded. The normal gap is the time between a commit and the next
      # line of the same thread; the window has to outlast that with margin
      # (several approvals committed in one transaction dispatch one after
      # another, so a later one waits out the earlier executors).
      GRACE_MINUTES_SETTING = "ai_approvals_stranded_dispatch_grace_minutes"
      DEFAULT_GRACE_MINUTES = 5

      # Exact action categories the operator has established are safe to run
      # a second time. A JSON array of strings; anything else reads as empty.
      REDISPATCH_ALLOWLIST_SETTING = "ai_approvals_stranded_redispatch_categories"

      # Never re-run, allowlisted or not: a command on a live host whose
      # effect cannot be observed from here (out-of-band exec) and a unit
      # override that restarts a service (unit drop-in). File.fnmatch patterns.
      NEVER_REDISPATCH_PATTERNS = %w[*out_of_band_exec* *unit_dropin*].freeze

      SWEEP_LIMIT = 100

      def self.grace_window
        configured = ::SiteSetting.get(GRACE_MINUTES_SETTING)
        minutes = Integer(configured.to_s, exception: false)
        (minutes&.positive? ? minutes : DEFAULT_GRACE_MINUTES).minutes
      end

      # Fail closed: a setting that is not a list of strings allowlists nothing.
      def self.redispatch_allowlist
        configured = ::SiteSetting.get(REDISPATCH_ALLOWLIST_SETTING)
        configured.is_a?(Array) && configured.all?(String) ? configured : []
      end

      def initialize(account:)
        @account = account
      end

      # Returns { failed:, redispatched: } — what THIS call settled. A request
      # another caller claimed first counts toward neither.
      def call
        counts = { failed: 0, redispatched: 0 }
        cutoff = self.class.grace_window.ago
        allowlist = self.class.redispatch_allowlist

        ::Ai::ApprovalRequest.owed_dispatch
                             .where(account_id: @account.id)
                             .where("dispatch_scheduled_at <= ?", cutoff)
                             .order(:dispatch_scheduled_at)
                             .limit(SWEEP_LIMIT)
                             .each do |request|
          settle(request, allowlist, counts)
        rescue StandardError => e
          Rails.logger.error(
            "[StrandedDispatchReconciler] request #{request.id} not settled: #{e.class}: #{e.message}"
          )
        end
        counts
      end

      private

      def settle(request, allowlist, counts)
        categories = categories_for(request)
        refusal = redispatch_refusal(request, categories, allowlist)

        if refusal.nil?
          return unless request.redispatch_stranded!

          counts[:redispatched] += 1
          audit(request, "ai.approvals.dispatch_redispatched", categories, "allowlisted as idempotent")
        else
          reason = "approved at #{request.dispatch_scheduled_at&.iso8601}, but its dispatch never started " \
                   "within the #{self.class.grace_window.inspect} grace window (the process likely stopped " \
                   "between the approval's commit and the dispatch); failed rather than re-run: #{refusal}"
          return unless request.abandon_stranded_dispatch!(reason)

          counts[:failed] += 1
          audit(request, "ai.approvals.dispatch_abandoned", categories, reason)
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
      def redispatch_refusal(request, categories, allowlist)
        return "no action category to judge it by" if categories.empty?

        forbidden = categories.find { |c| never_redispatch_category?(c) }
        return "#{forbidden} is never re-dispatched" if forbidden
        return "it is human-only or needs a person's own session" if request.requires_human_session?
        return "it is a destructive tool call" if ::Ai::Approvals::HumanSessionPolicy.destructive_tool_call?(request)

        unlisted = categories.reject { |c| allowlist.include?(c) }
        return "#{unlisted.join(', ')} is not on the re-dispatch allowlist" if unlisted.any?

        nil
      end

      def never_redispatch_category?(category)
        NEVER_REDISPATCH_PATTERNS.any? { |pattern| File.fnmatch?(pattern, category) } ||
          ::Ai::DeferredOperationApprovalContent.destructive_categories.any? { |frag| category.include?(frag) }
      end

      # Never raises: the declaration and the event already landed; an audit
      # sink failure must not report the request as unsettled.
      def audit(request, action, categories, reason)
        ::AuditLog.log_action(
          action: action,
          resource: request,
          account: @account,
          source: "system",
          severity: action.end_with?("abandoned") ? "high" : "medium",
          metadata: {
            reason: reason,
            action_category: categories.first,
            action_categories: categories,
            source_type: request.source_type,
            source_id: request.source_id,
            dispatch_scheduled_at: request.dispatch_scheduled_at&.iso8601
          }.compact
        )
      rescue StandardError => e
        Rails.logger.error("[StrandedDispatchReconciler] audit #{action} for #{request.id} failed: #{e.message}")
      end
    end
  end
end
