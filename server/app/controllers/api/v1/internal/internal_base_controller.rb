# frozen_string_literal: true

# Base controller for internal API endpoints (`/api/v1/internal/*`).
# These endpoints are called exclusively by the standalone Sidekiq worker.
#
# Auth model: mTLS. Workers are deployed as NodeInstances (Stage 8b);
# the worker host runs the powernode-agent, which manages the mTLS
# cert lifecycle (enrollment via /node_api/enroll, rotation via the
# agent's CertRotator). Traefik terminates the handshake on the
# `<slug>-internal-api` router (mTLS-required against the platform's
# internal CA) and forwards the verified CN — which is the
# NodeInstance.id — via `X-Forwarded-Tls-Client-Cert-Info`. This
# controller resolves the Worker via `node_instance_id`.
class Api::V1::Internal::InternalBaseController < ApplicationController
  include MtlsClientAuthentication

  skip_before_action :authenticate_request
  before_action :authenticate_worker_via_mtls!

  private

  # Audit logging helper for internal service operations
  # @param action [String] The action being performed (e.g., 'account.anonymize', 'user.delete')
  # @param resource_type [String] The type of resource being affected
  # @param resource_id [String] The ID of the resource being affected
  # @param metadata [Hash] Additional context for the audit log
  def log_internal_audit(action, resource_type, resource_id, metadata = {})
    AuditLog.create!(
      account_id: metadata[:account_id],
      user_id: nil, # Internal service request - no user
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: metadata.merge(
        internal_request: true,
        service: "worker",
        timestamp: Time.current.iso8601
      )
    )
  rescue StandardError => e
    # IMP-26a95cba1d43: this rescue used to be the whole story — a failed
    # write (most often AuditLog's `action` inclusion validation rejecting
    # an unregistered literal, see the *_DATA_LIFECYCLE_ACTIONS /
    # DATA_DELETION_REQUEST_ACTIONS groups in audit_actions.rb) was logged
    # at `error` and then vanished, indistinguishable from an audit event
    # that correctly never fired. Many of these callers sit on the GDPR/CCPA
    # deletion and account-anonymization path, where the write being audited
    # is irreversible — a missing row there is not a cosmetic gap.
    #
    # Deliberately NOT re-raised outside test: by the time this runs, the
    # destructive/anonymizing operation (destroy!/update!/delete_all) has
    # already committed in every caller — there is no in-flight mutation
    # left to protect by failing the request, and turning an already-
    # successful deletion into a 500 would only risk the calling worker
    # retrying an operation that (depending on the resource) may not be
    # idempotent. So the decision is "never swallow SILENTLY", not "never
    # swallow": loud logging plus a durable, self-referential audit row
    # (attempted unconditionally, in every environment) beats aborting a
    # completed deletion after the fact.
    #
    # The self-referential row reuses the already-registered
    # SYSTEM_ACTIONS token "audit_logging_error" (mirrors
    # Audit::LoggingService#log_system_error's fallback for the
    # log_audit_event path) — a registered, known-good action so this write
    # cannot fail for the same reason the original one did.
    Rails.logger.fatal "Failed to log internal audit event '#{action}' " \
                        "(resource_type=#{resource_type} resource_id=#{resource_id}): #{e.message}"
    Rails.logger.fatal e.backtrace&.join("\n")

    # IMP-26a95cba1d43 review (D1): the fallback row must NEVER guess a
    # tenant. `account_id` is a real FK that drives every tenant-scoped
    # audit query and compliance report, and this row is permanent
    # (integrity-hashed, sequence-numbered — see Audit::LogIntegrityService).
    # An earlier version of this fix fell back to `Account.first&.id` when
    # metadata carried none (mirroring Audit::LoggingService#log_system_error's
    # `account || Account.first`) — but that precedent is for a caller that
    # already resolved a real account and only lost the reference on the way
    # to the rescue; here `metadata[:account_id]` can be genuinely ABSENT for
    # a tenant-less resource (e.g. maintenance_controller.rb's
    # "backup.create", which audits a Database::Backup — not itself
    # account-scoped, and separately unregistered; see IMP-01a0b2f5). Against
    # that caller, guessing `Account.first` would attribute a tenant-less
    # infrastructure event to a real customer's audit trail on every request
    # — a cross-tenant defect this fix must not introduce. When no account
    # can be honestly attributed, the fatal log line above is the only
    # durable signal available; there is no safe row to write.
    if metadata[:account_id]
      begin
        AuditLog.create!(
          account_id: metadata[:account_id],
          user_id: nil,
          action: "audit_logging_error",
          resource_type: "AuditLog",
          resource_id: "error",
          ip_address: request.remote_ip,
          user_agent: request.user_agent,
          metadata: {
            original_action: action,
            original_resource_type: resource_type,
            original_resource_id: resource_id,
            error_message: e.message,
            error_class: e.class.name,
            internal_request: true,
            service: "worker"
          }
        )
      rescue StandardError => fallback_error
        Rails.logger.fatal "Failed to log internal audit_logging_error fallback " \
                            "for '#{action}': #{fallback_error.message}"
      end
    else
      Rails.logger.fatal "No account_id available for internal audit fallback " \
                          "(original action '#{action}') — skipping the durable row " \
                          "rather than attributing it to a guessed tenant."
    end

    # Re-raise in test only, mirroring AuditLogging#log_audit_event — this is
    # what turns a broken/unregistered action literal into a red spec instead
    # of a request that quietly returns 200 with no audit row.
    raise if Rails.env.test?
  end
end
