# frozen_string_literal: true

module Ai
  # The single writer of the sensitive-access audit row -- the durable,
  # queryable answer to "who retrieved this credential, and when".
  #
  # Extracted from Ai::Tools::BaseTool once the REST kubeconfig endpoint needed
  # the same guarantee. IMP-4ef95e825a7a put the guard on the MCP VERB rather
  # than on the credential, so a second route reached the same cluster-admin
  # material with no durable record. One writer means the two routes cannot
  # drift in action name, row shape, or -- the part that actually matters --
  # in whether they fail closed.
  #
  # FAILS CLOSED BY CONTRACT. `record` returns the persisted row, or nil
  # meaning "do not release the material". It never raises: a caller that
  # forgot a rescue must still reach its refusal branch rather than blow up
  # into some outer handler that might turn the failure into a success.
  #
  # Deliberately NOT built on AuditLogging / Audit::LoggingService. Every
  # method there rescues and swallows so telemetry can never break a request,
  # which is correct for bookkeeping and precisely wrong here: this row is a
  # precondition for disclosure, not a side effect of it.
  class SensitiveAccessAudit
    ACTION = "mcp.tools.sensitive_access"

    # Defence in depth, mirroring BaseTool's TELEMETRY_TOKEN_MAX: callers pass
    # caller-supplied values (a cluster id from params), so no field can carry
    # an embedded newline into the log or an unbounded blob into jsonb.
    TOKEN_MAX = 120

    class << self
      # Returns the persisted AuditLog, or nil. Nil is the refusal signal and
      # the caller MUST treat it as one.
      #
      # NO transaction wrapper, for the reason spelled out at the BaseTool call
      # site: a savepoint is not an independent transaction, so the row would
      # still die with an outer ROLLBACK -- after the credential had been
      # returned -- and `transaction` swallows ActiveRecord::Rollback, which
      # would turn a failed write into a silent proceed. `create!` is already
      # atomic on its own. A caller that wraps the disclosure in its own
      # transaction is a known limit of this control.
      def record(account:, user:, resource_type:, action_name:, context: {}, principal: nil)
        return nil unless account.is_a?(::Account) && account.persisted?

        row = ::AuditLog.create!(
          account: account,
          # Identity, not just principal SHAPE: "who retrieved the credential"
          # is the question this row exists to answer.
          user: user,
          action: ACTION,
          resource_type: token(resource_type),
          resource_id: "sensitive_access",
          source: "system",
          severity: "high",
          risk_level: "high",
          metadata: {
            # Caller context FIRST, so a caller cannot overwrite the identity
            # fields this row exists to hold by passing a colliding key.
            context: context.to_h { |k, v| [ k.to_s, token(v) ] },
            action_name: token(action_name),
            tool_class: token(resource_type),
            principal: principal
          }.compact
        )

        # Existence is checked, not assumed.
        row&.persisted? ? row : nil
      rescue StandardError => e
        # Logged, never re-raised: the caller gets its refusal branch like any
        # other failure, and the exception detail stays server-side.
        Rails.logger.error(
          "[SensitiveAccessAudit] row failed, REFUSING the access: " \
          "action=#{token(action_name)} resource=#{token(resource_type)} " \
          "error=#{e.class}: #{e.message}"
        )
        nil
      end

      def token(value)
        value.to_s.gsub(/[[:cntrl:]]/, " ").slice(0, TOKEN_MAX).to_s
      end
    end
  end
end
