# frozen_string_literal: true

module Ai
  class ApprovalRequest < ApplicationRecord
    self.table_name = "ai_approval_requests"

    # Associations
    belongs_to :account
    belongs_to :approval_chain, class_name: "Ai::ApprovalChain"
    belongs_to :requested_by, class_name: "User", optional: true

    has_many :decisions, class_name: "Ai::ApprovalDecision", dependent: :destroy

    # Validations
    validates :request_id, presence: true, uniqueness: true
    validates :status, presence: true, inclusion: { in: %w[pending approved rejected expired cancelled] }
    validates :execution_status, inclusion: { in: %w[succeeded failed] }, allow_nil: true

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :approved, -> { where(status: "approved") }
    scope :rejected, -> { where(status: "rejected") }
    scope :expired, -> { where(status: "expired") }
    scope :active, -> { pending.where("expires_at IS NULL OR expires_at > ?", Time.current) }
    scope :for_source, ->(type, id) { where(source_type: type, source_id: id) }
    scope :for_period, ->(start_date, end_date) { where(created_at: start_date..end_date) }

    # Callbacks
    before_validation :set_request_id, on: :create
    after_create  :fan_out_step_notifications, if: :pending?
    after_update  :notify_source_of_decision, if: :saved_change_to_status?
    after_update  :fan_out_step_notifications, if: :saved_change_to_current_step?

    # Methods
    def pending?
      status == "pending"
    end

    def approved?
      status == "approved"
    end

    def rejected?
      status == "rejected"
    end

    def expired?
      expires_at.present? && expires_at < Time.current
    end

    def current_step_info
      step_statuses[current_step] if step_statuses.present?
    end

    # Typed approver specs supported:
    #   "*"                                              — any active user
    #   "<user_uuid>"                                    — specific user (legacy)
    #   { "type" => "user",       "value" => "<uuid>" } — specific user
    #   { "type" => "permission", "value" => "<name>" } — anyone with the permission
    #   { "type" => "role",       "value" => "<name>" } — anyone with the role
    def can_approve?(user)
      return false unless pending?
      return false if expired?

      step_info = current_step_info
      return false unless step_info

      approvers = step_info["approvers"] || []
      approvers.any? { |spec| approver_matches?(spec, user) }
    end

    def record_decision!(approver:, decision:, comments: nil, conditions: {})
      return false unless can_approve?(approver)

      decisions.create!(
        approver: approver,
        step_number: current_step,
        decision: decision,
        comments: comments,
        conditions: conditions
      )

      process_decision(decision)
    end

    def check_expiration!
      return unless pending? && expired?

      case approval_chain.timeout_action
      when "approve"
        approve!
      when "reject"
        reject!
      when "escalate"
        escalate!
      else
        update!(status: "expired")
      end
    end

    private

    def approver_matches?(spec, user)
      case spec
      when "*" then true
      when String then spec == user.id.to_s
      when Hash
        case spec["type"]
        when "user"       then spec["value"] == user.id.to_s
        when "permission" then user.respond_to?(:has_permission?) && user.has_permission?(spec["value"])
        when "role"       then user.respond_to?(:has_role?) && user.has_role?(spec["value"])
        else false
        end
      else false
      end
    end

    def set_request_id
      self.request_id ||= UUID7.generate
    end

    # IMP-4bbb4227ac8a — the rescue below used to only log, which made every
    # post-approval executor failure invisible: the request stayed "approved",
    # the operation failed (or stranded), and no operator-visible signal existed
    # anywhere. Observability only — approval semantics are unchanged and
    # nothing retries: the outcome of the dispatch is DECLARED on this row
    # (execution_status/execution_error) and, on failure, emitted as an
    # Ai::ExecutionEvent (surfaced via platform.recent_events).
    #
    # execution_status stays nil unless an on_approval_decision dispatch for an
    # *approved* request actually ran: "succeeded" means that dispatch returned
    # without raising (for Ai::DeferredOperation sources, the executor
    # completed — its own row carries the per-operation detail), "failed" means
    # it raised. Rejected/expired notifications keep the prior log-only
    # behavior — nothing executed, so there is no execution outcome to declare.
    #
    # Known residual, deliberately out of scope here: this callback fires
    # pre-commit inside the status-flip's own transaction, so an executor
    # failing at the DATABASE level (RecordNotUnique/StatementInvalid) aborts
    # that transaction and the declaration writes below no-op — and the status
    # flip itself rolls back with them. Declaring that class requires either a
    # savepoint around the dispatch (which would change what an executor's
    # partial writes and the operation's own fail! survive) or an off-
    # transaction sink; both alter semantics this change is pinned not to touch.
    def notify_source_of_decision
      return unless %w[approved rejected expired].include?(status)
      return if source_type.blank? || source_id.blank?

      klass = source_type.safe_constantize
      return unless klass.respond_to?(:find_by)

      source = klass.find_by(id: source_id)
      return unless source.respond_to?(:on_approval_decision)

      source.on_approval_decision(self)
      declare_execution_outcome!("succeeded") if approved?
    rescue StandardError => e
      Rails.logger.error("[ApprovalRequest##{id}] notify_source_of_decision failed: #{e.message}")
      declare_execution_failure!(e) if approved?
    end

    # Direct column write: this runs inside the status-flip's own after_update,
    # so re-entering the callback chain (or validations) via update! is the one
    # thing it must not do. Never raises — the enclosing rescue's contract is
    # that a declaration problem cannot take down the decision itself.
    def declare_execution_outcome!(outcome, error: nil)
      detail = error ? "#{error.class}: #{error.message}" : nil
      update_columns(execution_status: outcome, execution_error: detail,
                     updated_at: Time.current)
    rescue StandardError => e
      Rails.logger.error("[ApprovalRequest##{id}] declare_execution_outcome! failed: #{e.message}")
    end

    def declare_execution_failure!(error)
      declare_execution_outcome!("failed", error: error)
      # Recorder swallows its own errors, so a broken event sink cannot mask
      # the column declaration above or raise out of the callback.
      ::Ai::Introspection::ExecutionEventRecorder.record(
        source: self,
        event_type: "approval_execution",
        status: "failed",
        error: error,
        metadata: {
          operation_source_type: source_type,
          operation_source_id: source_id,
          action_category: request_data&.dig("action_category")
        }.compact
      )
    end

    def fan_out_step_notifications
      return unless pending?
      return unless defined?(::Ai::ApprovalRequestNotifier)

      ::Ai::ApprovalRequestNotifier.notify_current_step!(self)
    rescue StandardError => e
      Rails.logger.error("[ApprovalRequest##{id}] fan_out_step_notifications failed: #{e.message}")
    end

    def process_decision(decision)
      step_info = step_statuses[current_step]

      case decision
      when "approved"
        step_info["current_approvals"] += 1
        step_info["status"] = "approved" if step_info["current_approvals"] >= step_info["required_approvals"]

        if step_info["status"] == "approved"
          if current_step >= step_statuses.length - 1
            approve!
          else
            advance_to_next_step!
          end
        end
      when "rejected"
        step_info["status"] = "rejected"
        reject!
      when "delegated"
        # Delegation logic - could reassign to another approver
        step_info["status"] = "delegated"
      end

      update!(step_statuses: step_statuses)
    end

    def advance_to_next_step!
      update!(current_step: current_step + 1)
    end

    def approve!
      update!(status: "approved", completed_at: Time.current)
      approval_chain.increment!(:usage_count)
    end

    def reject!
      update!(status: "rejected", completed_at: Time.current)
    end

    def escalate!
      # Could notify higher-level approvers or auto-approve
      update!(status: "expired")
    end
  end
end
