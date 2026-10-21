# frozen_string_literal: true

module Ai
  module PromotionGrants
    # Every write to a promotion grant, and the audit row each one leaves:
    #
    #   issue!   a person, from their own session, creates one  -> ai.promotion_grant.created
    #   revoke!  a person ends one early                        -> ai.promotion_grant.revoked
    #   consume! the gate spends one use in place of parking    -> ai.promotion_grant.used
    #
    # consume! is the concurrency-critical one: it locks the candidate row,
    # re-checks it under the lock, increments, links the operation and audits,
    # all in one transaction, so two promotions racing on a grant's last use
    # cannot both proceed (the row's CHECK constraint is the backstop).
    module Ledger
      # A refusal the REST door renders as-is. `status` is the HTTP status.
      class Refused < StandardError
        attr_reader :status

        def initialize(message, status: :unprocessable_content)
          super(message)
          @status = status
        end
      end

      CREATED = "ai.promotion_grant.created"
      REVOKED = "ai.promotion_grant.revoked"
      USED    = "ai.promotion_grant.used"

      module_function

      # @param origin [String] the door (Ai::ApprovalDecision ORIGINS); only
      #   REST_SESSION may issue. The row re-checks it.
      # @param attributes [Hash] ai_agent_id, environment_id, action_category,
      #   module_ids, max_uses, expires_at, reason
      def issue!(account:, granted_by:, origin:, attributes:, request: nil)
        unless ::Ai::ApprovalDecision.human_session_origin?(origin)
          raise Refused.new(::Ai::PromotionGrant::ISSUE_REFUSAL, status: :forbidden)
        end

        attrs = attributes.to_h.symbolize_keys
        category = attrs[:action_category].presence || ::Ai::PromotionGrant::CATEGORIES.first
        verb_permission = Catalog.required_permission(category)
        if verb_permission.nil?
          raise Refused, "No installed extension declares #{category} as grantable, so no grant for it can be issued"
        end
        unless granted_by.has_permission?(verb_permission)
          raise Refused.new("Granting #{category} needs the permission the action itself requires (#{verb_permission})",
                            status: :forbidden)
        end

        unknown = Catalog.unknown_subject_ids(account: account, action_category: category, ids: attrs[:module_ids])
        raise Refused, "module_ids name no module in this account: #{unknown.join(', ')}" if unknown.any?

        # Resolved through the account, never assigned raw: a foreign id is
        # refused here by name rather than left to the row's own check.
        agent = find_in_account(::Ai::Agent, account, attrs[:ai_agent_id], "agent")
        environment = find_in_account(::Ai::Environment, account, attrs[:environment_id], "environment")

        grant = ::Ai::PromotionGrant.new(
          account: account, granted_by: granted_by, action_category: category,
          agent: agent, environment: environment,
          module_ids: Array(attrs[:module_ids]), max_uses: attrs[:max_uses].presence,
          expires_at: attrs[:expires_at], reason: attrs[:reason], issuing_origin: origin
        )

        ::Ai::PromotionGrant.transaction do
          grant.save!
          audit!(grant, action: CREATED, user: granted_by, source: "web", severity: "high", request: request,
                        details: terms_of(grant))
        end
        grant
      rescue ActiveRecord::RecordInvalid => e
        raise Refused, e.record.errors.full_messages.join(", ")
      end

      def revoke!(grant, by:, request: nil)
        ::Ai::PromotionGrant.transaction do
          grant.lock!
          raise Refused, "This grant is already revoked" if grant.revoked?

          grant.revoke!(by: by)
          audit!(grant, action: REVOKED, user: by, source: "web", severity: "medium", request: request,
                        details: terms_of(grant).merge("uses_count" => grant.uses_count))
        end
        grant
      end

      # Spends one use of an active grant matching every axis, or returns nil
      # (and spends nothing). `subject` is the gated call's own statement of
      # what it acts on ({ module_id:, version_id: }), built server-side by the
      # verb's gate context, never from caller params.
      #
      # Runs in its own transaction (nested into the caller's when there is
      # one). A use is counted when the gate admits the operation, whatever
      # the operation's own outcome.
      def consume!(account:, agent:, action_category:, environment:, subject:, deferred_operation:)
        subject = (subject || {}).to_h.with_indifferent_access
        module_id = subject[:module_id].to_s
        return nil if account.nil? || agent.nil? || environment.nil? || module_id.blank?

        now = Time.current
        candidates = ::Ai::PromotionGrant.active(now)
                                         .where(account_id: account.id, ai_agent_id: agent.id,
                                                action_category: action_category.to_s, environment_id: environment.id)
                                         .order(:expires_at, :id)
                                         .select { |grant| grant.covers_module?(module_id) }
        return nil if candidates.empty?

        ::Ai::PromotionGrant.transaction do
          candidates.find do |grant|
            grant.lock! # SELECT ... FOR UPDATE, then reloads the committed row
            next unless grant.active?(now) && grant.covers_module?(module_id)

            grant.update!(uses_count: grant.uses_count + 1)
            deferred_operation.update!(promotion_grant: grant)
            audit!(grant, action: USED, user: nil, source: "system", severity: "high",
                          details: {
                            "promotion_grant_id" => grant.id, "ai_agent_id" => agent.id,
                            "agent_name" => agent.name, "action_category" => action_category.to_s,
                            "module_id" => module_id, "version_id" => subject[:version_id]&.to_s,
                            "environment_id" => environment.id, "environment_slug" => environment.slug,
                            "deferred_operation_id" => deferred_operation.id,
                            "uses_count" => grant.uses_count, "max_uses" => grant.max_uses,
                            "granted_by_id" => grant.granted_by_id
                          })
            true
          end
        end
      end

      def terms_of(grant)
        {
          "promotion_grant_id" => grant.id, "ai_agent_id" => grant.ai_agent_id,
          "action_category" => grant.action_category, "environment_id" => grant.environment_id,
          "environment_slug" => grant.environment&.slug, "module_ids" => grant.module_ids,
          "max_uses" => grant.max_uses, "expires_at" => grant.expires_at&.iso8601,
          "reason" => grant.reason, "granted_by_id" => grant.granted_by_id
        }
      end

      # REQUIRED, not best-effort: a grant use that cannot be audited does not
      # happen (the transaction rolls back and the gate refuses).
      def audit!(grant, action:, user:, source:, severity:, details:, request: nil)
        ::AuditLog.create!(
          account_id: grant.account_id, user: user, action: action, source: source,
          resource_type: grant.class.name, resource_id: grant.id,
          severity: severity, risk_level: severity,
          new_values: details, metadata: details,
          ip_address: request&.remote_ip, user_agent: request&.user_agent&.to_s&.first(1000),
          request_id: request&.request_id&.to_s&.first(50)
        )
      end

      def find_in_account(model, account, id, noun)
        return nil if id.blank?

        model.where(account_id: account.id).find_by(id: id.to_s) || raise(Refused, "unknown #{noun} #{id}")
      end
    end
  end
end
