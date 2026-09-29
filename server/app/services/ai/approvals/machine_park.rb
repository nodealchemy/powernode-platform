# frozen_string_literal: true

module Ai
  module Approvals
    # THE PARK GUARD for a human-only request a MACHINE principal (an instance)
    # asks for. A person decides it in their own session, so the only thing a
    # runaway or injected instance session can do here is fill that person's
    # queue. This bounds that: at most one pending request per (principal,
    # action category, dedupe key), and a per-principal count of parks in a
    # window. Both are answered from the approval rows themselves, so there is
    # no second ledger to drift from them.
    #
    # The check and the park are one critical section. A transaction-scoped
    # advisory lock, keyed on the principal, serialises concurrent parks from
    # one principal, so two racing callers cannot both see "no pending request"
    # or both read a count under the limit. A different principal takes a
    # different lock, and the lock releases with the transaction.
    #
    # It refuses and dedupes; it never approves, and it changes nothing about
    # who may decide. The principal identity is read from the request the gate
    # wrote from the tool's own constructor state, never from caller params.
    class MachinePark
      # DB-driven: SiteSetting RATE_LIMIT_SETTING (a positive integer), with this
      # constant as the fallback, as Ai::Tools::BaseTool's list limits do.
      RATE_LIMIT_SETTING = "ai_machine_park_rate_limit_per_hour"
      DEFAULT_RATE_LIMIT = 10
      WINDOW = 1.hour

      Deduped = Struct.new(:request)
      RateLimited = Struct.new(:limit)

      AUDIT_DEDUPED = "ai.approvals.machine_park_deduped"
      AUDIT_RATE_LIMITED = "ai.approvals.machine_park_rate_limited"

      PRINCIPAL_PATH = "request_data->'params'->'principal'->>'node_instance_id'"
      DEDUPE_PATH = "request_data->'params'->>'dedupe_key'"
      HUMAN_ONLY_PATH = "request_data->'params'->>'human_only'"

      class << self
        # Runs the block (the park) inside the critical section unless an
        # equivalent request is already pending or the principal is over its
        # limit, in which case it returns Deduped or RateLimited and parks
        # nothing. Otherwise it returns the block's own value.
        def guard(account:, principal_id:, action_category:, dedupe_key:, session_label: nil)
          ::ApplicationRecord.transaction do
            lock!(account, principal_id)

            existing = pending_for(account, principal_id, action_category, dedupe_key)
            if existing
              audit(AUDIT_DEDUPED, existing, account, principal_id, action_category, session_label)
              next Deduped.new(existing)
            end

            limit = rate_limit
            if recent_count(account, principal_id) >= limit
              audit(AUDIT_RATE_LIMITED, account, account, principal_id, action_category, session_label,
                    limit: limit)
              next RateLimited.new(limit)
            end

            yield
          end
        end

        def rate_limit
          configured = ::SiteSetting.get(RATE_LIMIT_SETTING).to_i
          configured.positive? ? configured : DEFAULT_RATE_LIMIT
        end

        private

        def lock!(account, principal_id)
          key = "machine_park:#{account.id}:#{principal_id}"
          connection = ::ApplicationRecord.connection
          connection.execute("SELECT pg_advisory_xact_lock(hashtextextended(#{connection.quote(key)}, 0))")
        end

        def scope(account, principal_id)
          ::Ai::ApprovalRequest.where(account_id: account.id)
                               .where("#{PRINCIPAL_PATH} = ?", principal_id.to_s)
                               .where("#{HUMAN_ONLY_PATH} = 'true'")
        end

        def pending_for(account, principal_id, action_category, dedupe_key)
          return nil if dedupe_key.blank?

          scope(account, principal_id)
            .where(status: "pending")
            .where("request_data->>'action_category' = ?", action_category.to_s)
            .where("lower(#{DEDUPE_PATH}) = ?", dedupe_key.to_s.downcase)
            .order(:created_at).first
        end

        def recent_count(account, principal_id)
          scope(account, principal_id).where(created_at: WINDOW.ago..).count
        end

        # A refusal is recorded, never allowed to break the answer the caller
        # gets: this is the trail, and losing a row costs visibility only.
        # Names the principal and the door, never a value.
        def audit(action, resource, account, principal_id, action_category, session_label, **extra)
          ::AuditLog.log_action(
            action: action, resource: resource, account: account, source: "api",
            metadata: {
              requester_kind: "instance", node_instance_id: principal_id.to_s,
              action_category: action_category.to_s, session_label: session_label
            }.merge(extra).compact
          )
        rescue StandardError => e
          Rails.logger.error("[MachinePark] audit row #{action} failed: #{e.class}: #{e.message}")
        end
      end
    end
  end
end
