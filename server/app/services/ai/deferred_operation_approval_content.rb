# frozen_string_literal: true

module Ai
  # Default content provider for approval requests sourced from
  # `Ai::DeferredOperation`. Reads `executor_class.preview(params)` to render
  # a generic title/message — extensions typically don't need their own
  # content provider unless they want richer formatting (icons, action_url
  # routing to a domain-specific page, etc.).
  #
  # All methods are class-level — providers are stateless.
  class DeferredOperationApprovalContent
    def self.notification_type
      "autonomy_approval_required"
    end

    def self.category
      "ai"
    end

    def self.action_url(_request)
      "/app/notifications"
    end

    def self.severity(request)
      op = deferred_for(request)
      return "info" unless op
      destructive_categories.any? { |frag| op.action_category.include?(frag) } ? "warning" : "info"
    end

    def self.title(request, _step)
      op = deferred_for(request)
      return "Approval needed" unless op

      preview = safe_preview(op)
      preview[:summary].presence || "Approval needed: #{op.action_category}"
    end

    def self.message(request, step)
      op = deferred_for(request)
      step_label = step["step_name"] || step["name"] || "Approval"
      total = request.step_statuses&.size || 1
      header = "#{step_label} (step #{request.current_step + 1}/#{total})"
      return header unless op

      preview = safe_preview(op)
      lines = [header]
      lines << preview[:summary] if preview[:summary].present?
      lines << "Impact: #{preview[:impact]}" if preview[:impact].present?
      lines << "Requested by: #{op.requested_by&.email}" if op.requested_by
      lines << "Agent: #{op.ai_agent.name}" if op.ai_agent
      lines.join("\n")
    end

    def self.metadata(request)
      op = deferred_for(request)
      return {} unless op
      {
        deferred_operation_id: op.id,
        action_category: op.action_category,
        executor_class: op.executor_class
      }
    end

    def self.deferred_for(request)
      return nil unless request.source_type == "Ai::DeferredOperation"
      ::Ai::DeferredOperation.find_by(id: request.source_id)
    end

    def self.safe_preview(op)
      op.preview || {}
    rescue StandardError
      {}
    end

    def self.destructive_categories
      %w[delete destroy terminate revoke decommission deprovision drop]
    end
  end
end
