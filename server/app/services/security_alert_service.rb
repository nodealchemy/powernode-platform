# frozen_string_literal: true

# Resolves security-alert recipients and emits the alert through the EmailDelivery
# pipeline (pending ledger row + worker AlertEmailJob → SMTP → /emails/:id/delivered
# callback). Fixes the latent NameError in Audit::LoggingService#send_alert, which
# referenced this (previously undefined) service.
#
# Recipients = admins, by default:
#   - account given      → that account's admins (users.manage; system.admin is
#                          auto-included by User.with_permission)
#   - account nil (system-wide audit alerts) → platform super-admins (system.admin)
#     only, so a system-wide alert never fans out to every tenant's admins.
class SecurityAlertService
  ACCOUNT_ADMIN_PERMISSION = "users.manage"
  SYSTEM_ADMIN_PERMISSION  = "system.admin"

  def self.send_alert(title:, message:, severity: "high", timestamp: Time.current, account: nil)
    new(account: account).send_alert(title: title, message: message, severity: severity, timestamp: timestamp)
  end

  def initialize(account: nil)
    @account = account
  end

  # @return [Hash] { sent: Integer, email_delivery_ids: [..] } or { sent: 0, reason:/error: }
  def send_alert(title:, message:, severity: "high", timestamp: Time.current)
    recipients = resolve_recipients
    return { sent: 0, reason: "no_recipients" } if recipients.empty?

    deliveries = recipients.filter_map do |user|
      dispatch_to(user, title: title, message: message, severity: severity, timestamp: timestamp)
    end
    { sent: deliveries.size, email_delivery_ids: deliveries.map(&:id) }
  rescue StandardError => e
    Rails.logger.error("[SecurityAlertService] #{e.class}: #{e.message}")
    { sent: 0, error: e.message }
  end

  private

  def resolve_recipients
    scope = @account ? @account.users : User.all
    permission = @account ? ACCOUNT_ADMIN_PERMISSION : SYSTEM_ADMIN_PERMISSION
    scope.with_permission(permission).where.not(email: [ nil, "" ]).distinct.to_a
  end

  def dispatch_to(user, title:, message:, severity:, timestamp:)
    delivery = EmailDelivery.create!(
      recipient_email: user.email,
      subject: "Security Alert: #{title}",
      email_type: "notification",
      status: "pending",
      metadata: {
        category: "security_alert", severity: severity, title: title,
        account_id: @account&.id, alerted_at: timestamp.iso8601
      }
    )

    begin
      WorkerJobService.enqueue_alert_email({
        email_delivery_id: delivery.id,
        recipient: user.email,
        subject: "Security Alert: #{title}",
        heading: "Security Alert",
        body: message,
        details: { severity: severity, detected_at: timestamp.iso8601 }
      })
    rescue WorkerJobService::WorkerServiceError => e
      Rails.logger.error("[SecurityAlertService] enqueue failed for #{user.email}: #{e.message}")
      delivery.update!(status: "failed", error_message: "Failed to enqueue send: #{e.message}")
    end

    delivery
  end
end
