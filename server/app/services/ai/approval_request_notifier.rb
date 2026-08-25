# frozen_string_literal: true

module Ai
  # Step-aware fanout of `Notification` records for approval requests.
  #
  # Called from `Ai::ApprovalRequest`'s after_create + after_update callbacks
  # (when `current_step` advances). Notifies only the current step's approvers
  # — when a multi-step chain advances, step 2's approvers get fresh
  # notifications without re-pinging step 1's approvers.
  #
  # Per-source content rendering is delegated to a registered "content provider"
  # class. Extensions register handlers for their source_types via the
  # SOURCE_HANDLERS map (typically in their Engine#after_initialize):
  #
  #   ::Ai::ApprovalRequestNotifier::SOURCE_HANDLERS["Sdwan::Network"] = "::Sdwan::ApprovalContent"
  #
  # Default handler `Ai::DeferredOperationApprovalContent` covers the common
  # case of source_type == "Ai::DeferredOperation" — reads executor.preview()
  # for the message body so most extensions don't need their own content
  # provider.
  class ApprovalRequestNotifier
    SOURCE_HANDLERS = {}

    def self.notify_current_step!(request)
      return unless request.pending?

      step = request.step_statuses&.dig(request.current_step)
      return unless step

      # Content is computed ONCE per step advance, not per approver: none of it
      # depends on the approving user, and DeferredOperationApprovalContent's
      # title/message each run a DB-backed executor preview (IMP-6858255cea72).
      card = build_card(request, step)

      approvers = resolve_approvers(request.account, step["approvers"])

      approvers.find_each do |user|
        # ISOLATED PER APPROVER (G5). Previously one raise anywhere in this loop
        # was caught by the method-level rescue below, so every approver the
        # loop had not reached yet was silently starved. A PARTIAL fan-out is
        # the nastiest shape available here: some operators hear, so the request
        # does not look abandoned, while the rest never learn it is pending.
        Notification.create_for_user(user, **card)
      rescue StandardError => e
        Rails.logger.error(
          "[ApprovalRequestNotifier] delivery failed for approver #{user.id} on " \
          "request ##{request.id}: #{e.class}: #{e.message}"
        )
      end
    rescue StandardError => e
      Rails.logger.error("[ApprovalRequestNotifier] notify_current_step! failed for ##{request.id}: #{e.class}: #{e.message}")
    end

    # Build the notification payload, NEVER raising.
    #
    # G5: a SOURCE_HANDLERS provider that raised in title/message/severity/
    # metadata aborted before the loop, so NOBODY was notified — the thing
    # suppressed was the operator obligation itself, and a gate whose
    # notification silently fails is indistinguishable from one nobody needed to
    # act on. The card is PRESENTATION; failing to render it prettily must never
    # cost the notification.
    #
    # Two rungs, then a floor: the resolved handler, the generic handler, and
    # finally a literal card built from what we always know (the request's own
    # identity and chain position). Provenance keys are merged LAST and win on
    # every rung.
    def self.build_card(request, step)
      content = source_content_for(request)
      card_from(content, request, step)
    rescue StandardError => e
      Rails.logger.error(
        "[ApprovalRequestNotifier] content handler #{content&.name} raised for " \
        "request ##{request.id} — falling back to generic content: #{e.class}: #{e.message}"
      )
      begin
        card_from(::Ai::DeferredOperationApprovalContent, request, step)
      rescue StandardError => inner
        Rails.logger.error(
          "[ApprovalRequestNotifier] generic content ALSO raised for request " \
          "##{request.id} — using the minimal card: #{inner.class}: #{inner.message}"
        )
        minimal_card(request, step)
      end
    end

    def self.card_from(content, request, step)
      {
        type: content.notification_type,
        title: content.title(request, step),
        message: content.message(request, step),
        severity: content.severity(request),
        category: content.category,
        action_url: content.action_url(request),
        action_label: "Review",
        metadata: provenance_for(content.metadata(request), request, step)
      }
    end

    # The card we can always build, from the request alone.
    def self.minimal_card(request, step)
      {
        type: "autonomy_approval_required",
        title: "Approval needed",
        message: "An approval is pending at step #{request.current_step + 1}.",
        severity: "info",
        category: "ai",
        action_url: "/app/notifications",
        action_label: "Review",
        metadata: provenance_for({}, request, step)
      }
    end

    # Merge order is load-bearing (IMP-e75e843bd42b): the base hash names the
    # request's own identity and chain position, and the base WINS on collision
    # — a content handler customises card content, never provenance.
    # `approval_request_id` in particular is the producer-side declaration
    # Ai::InterventionPolicyService#notification_limit_reached? keys its
    # consent-traffic exclusion on; with handler-wins order, a SOURCE_HANDLERS
    # provider echoing a gate-result hash (where that key is ubiquitous, often
    # nil) would silently strip the declaration and its fan-out would count
    # toward the daily budget again.
    #
    # Stringified on both sides: a handler may key its hash with strings and the
    # column is json (string-keyed after round-trip anyway), so a symbol/string
    # mix would not collide in Hash#merge and would land as duplicate JSON keys,
    # leaving which value `->>` reads undefined.
    #
    # G5: a handler returning a NON-HASH from #metadata used to raise here on
    # .stringify_keys and take the whole fan-out down with it. Coerced instead —
    # provenance is what the consent-budget exclusion reads, so it must survive
    # a junk handler.
    def self.provenance_for(handler_metadata, request, step)
      base = handler_metadata.is_a?(Hash) ? handler_metadata.stringify_keys : {}
      unless handler_metadata.is_a?(Hash)
        Rails.logger.warn(
          "[ApprovalRequestNotifier] content handler returned " \
          "#{handler_metadata.class} from #metadata for request ##{request.id}; ignoring it"
        )
      end

      base.merge(
        "approval_request_id" => request.id,
        "current_step" => request.current_step,
        "total_steps" => request.step_statuses.size,
        "step_name" => step["step_name"] || step["name"],
        "source_type" => request.source_type,
        "source_id" => request.source_id
      )
    end

    # Resolve typed approver specs to a User relation for the current account.
    # Specs supported (matches Ai::ApprovalRequest#can_approve? logic):
    #   "*"                                              — any active user
    #   "<user_uuid>"                                    — specific user
    #   { "type" => "user",       "value" => "<uuid>" }
    #   { "type" => "permission", "value" => "<name>" }
    #   { "type" => "role",       "value" => "<name>" }
    def self.resolve_approvers(account, specs)
      return account.users.active if specs == ["*"]

      ids = []
      Array(specs).each do |spec|
        case spec
        when "*"
          return account.users.active
        when String
          ids << spec
        when Hash
          case spec["type"]
          when "user"
            ids << spec["value"]
          when "permission"
            ids.concat(account.users.active.with_permission(spec["value"]).pluck(:id))
          when "role"
            ids.concat(account.users.active.with_role(spec["value"]).pluck(:id))
          end
        end
      end

      account.users.active.where(id: ids.uniq.compact)
    end

    def self.source_content_for(request)
      handler_const_name = SOURCE_HANDLERS[request.source_type] || "::Ai::DeferredOperationApprovalContent"
      handler_const_name.constantize
    rescue NameError => e
      Rails.logger.warn("[ApprovalRequestNotifier] Content handler #{handler_const_name} not found, falling back to generic: #{e.message}")
      ::Ai::DeferredOperationApprovalContent
    end
  end
end
