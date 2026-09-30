# frozen_string_literal: true

module Ai
  module Approvals
    # THE PARK GUARD for a human-only request a MACHINE principal (an instance)
    # asks for. A person decides it in their own session, so the only thing a
    # runaway or injected instance session can do here is fill that person's
    # queue. This bounds that: at most one pending request per (principal,
    # action category, dedupe key), and a count of parks per (principal, action category) in a
    # window. Both are answered from the approval rows themselves, so there is
    # no second ledger to drift from them.
    #
    # OPT-IN: Ai::Tools::BaseTool applies it only to a tool that names a
    # #park_dedupe_key, so no other human-only verb an instance parks changes.
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
      # One audit row per (principal, category, outcome) in this span, so a
      # looping session cannot bloat the log.
      AUDIT_COLLAPSE = 1.minute

      Deduped = Struct.new(:request)
      RateLimited = Struct.new(:limit)

      AUDIT_DEDUPED = "ai.approvals.machine_park_deduped"
      AUDIT_RATE_LIMITED = "ai.approvals.machine_park_rate_limited"
      # Written by the TOOL for a park it refused (Ai::Tools::SiteSettingTool#
      # audit_park_refusal); counted here when it names this principal and category.
      AUDIT_REFUSED = "ai.approvals.machine_park_refused"

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
            if recent_count(account, principal_id, action_category) >= limit
              audit(AUDIT_RATE_LIMITED, account, account, principal_id, action_category, session_label,
                    limit: limit)
              next RateLimited.new(limit)
            end

            yield
          end
        end

        # True when a refusal/dedupe/limit row for `key` should be written: the
        # first in AUDIT_COLLAPSE. It FAILS OPEN: if the cache cannot answer (the
        # write fails or raises and the key is not there to be seen), the row is
        # written rather than suppressed, so a cache outage loses no audit row.
        def audit_once?(key)
          return true if ::Rails.cache.write(key, 1, expires_in: AUDIT_COLLAPSE, unless_exist: true)

          !::Rails.cache.exist?(key)
        rescue StandardError
          true
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

        # Per (principal, action category): one tool's parks never spend another's
        # budget. Parks AND metered refusals (IMP-1765f6f09458): a refusal a tool
        # raises inside the guard (Ai::Tools::BaseTool#guarded_park_refusal) is
        # audited as AUDIT_REFUSED naming this principal and category, and that
        # row spends the window exactly as a park does, so a value-dependent
        # refusal cannot be asked more often than a park could be made.
        def recent_count(account, principal_id, action_category)
          parks = scope(account, principal_id).where("request_data->>'action_category' = ?", action_category.to_s)
                                              .where(created_at: WINDOW.ago..).count
          parks + refused_count(account, principal_id, action_category)
        end

        # Only rows the tool marked `metered`: a value-dependent refusal. A
        # refusal for a bad key, an uncovered grant or a non-parkable key is
        # collapsed, depends on nothing the instance may not know, and must not
        # spend the window — a retried typo would otherwise lock a legitimate
        # tightening out for an hour.
        def refused_count(account, principal_id, action_category)
          ::AuditLog.where(account_id: account.id, action: AUDIT_REFUSED)
                    .where("metadata->>'node_instance_id' = ?", principal_id.to_s)
                    .where("metadata->>'action_category' = ?", action_category.to_s)
                    .where("metadata->>'metered' = 'true'")
                    .where(created_at: WINDOW.ago..).count
        end

        # A refusal is recorded, never allowed to break the answer the caller
        # gets: this is the trail, and losing a row costs visibility only.
        # Names the principal and the door, never a value.
        def audit(action, resource, account, principal_id, action_category, session_label, **extra)
          return unless audit_once?("machine_park:audit:#{principal_id}:#{action_category}:#{action}")

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
