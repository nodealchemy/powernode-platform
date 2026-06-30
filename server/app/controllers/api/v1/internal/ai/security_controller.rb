# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        # Internal (worker → server, mTLS) endpoints for periodic AI security
        # audits. The audit logic lives in core services so it is unit-testable
        # server-side; the worker only triggers it on a schedule and alerts.
        class SecurityController < InternalBaseController
          # POST /api/v1/internal/ai/security/token_scope_audit
          # G7 token-scope / permission-creep audit. Reviews access scopes on
          # active AI provider credentials and API tokens, flagging
          # over-provisioning (wildcard / admin / unrestricted / off-baseline
          # scopes). The worker's AiTokenScopeAuditJob calls this on a monthly
          # cron and alerts when over_provisioned_count > 0. Findings carry only
          # ids + scope names — never secret values.
          def token_scope_audit
            result = ::Ai::Security::TokenScopeAuditService.new.run

            if result[:over_provisioned_count].positive?
              Rails.logger.warn(
                "[TokenScopeAudit] #{result[:over_provisioned_count]} over-provisioned " \
                "credential(s)/token(s) detected"
              )
            end

            render_success(
              over_provisioned_count: result[:over_provisioned_count],
              findings: result[:findings]
            )
          end
        end
      end
    end
  end
end
