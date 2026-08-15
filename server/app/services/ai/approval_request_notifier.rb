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

      content = source_content_for(request)
      approvers = resolve_approvers(request.account, step["approvers"])

      # None of these depend on the approving `user` — compute the card
      # content once per step advance, not once per approver. On a "*"-gated
      # step against a large account this previously issued the full content
      # computation (including a DB-backed executor preview, see
      # DeferredOperationApprovalContent#safe_preview) once per active user.
      notification_type = content.notification_type
      title = content.title(request, step)
      message = content.message(request, step)
      severity = content.severity(request)
      category = content.category
      action_url = content.action_url(request)
      metadata = {
        approval_request_id: request.id,
        current_step: request.current_step,
        total_steps: request.step_statuses.size,
        step_name: step["step_name"] || step["name"],
        source_type: request.source_type,
        source_id: request.source_id
      }.merge(content.metadata(request))

      approvers.find_each do |user|
        Notification.create_for_user(
          user,
          type: notification_type,
          title: title,
          message: message,
          severity: severity,
          category: category,
          action_url: action_url,
          action_label: "Review",
          metadata: metadata
        )
      end
    rescue StandardError => e
      Rails.logger.error("[ApprovalRequestNotifier] notify_current_step! failed for ##{request.id}: #{e.class}: #{e.message}")
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
