# frozen_string_literal: true

# Internal API controller for the worker email pipeline.
#
# Architecture: the Rails server runs NO Sidekiq and sends NO mail itself.
# The server owns the EmailDelivery ledger (all model/DB state stays here);
# the standalone worker owns SMTP delivery. Flow (Pattern B):
#   1. caller hits security_alert / review_notification -> server creates a
#      PENDING EmailDelivery row and enqueues the worker send job
#      (WorkerJobService -> POST /api/v1/jobs on the worker)
#   2. the worker's Notifications::AlertEmailJob renders + delivers the mail
#   3. the worker POSTs the outcome back to #delivered, which moves the ledger
#      row to sent / failed.
#
# These are worker-facing endpoints (mTLS via InternalBaseController). The
# #delivered callback follows worker-receiver discipline: it logs and returns
# 2xx on any processing error so a transient server hiccup never triggers a
# Sidekiq retry storm.
class Api::V1::Internal::EmailsController < Api::V1::Internal::InternalBaseController
  # POST /api/v1/internal/emails/security_alert
  # Params: recipient, alert_type, details (hash), severity (optional)
  def security_alert
    alert_type = params[:alert_type].presence || "security_event"
    details = permitted_hash(params[:details])

    delivery = dispatch_email(
      recipient: params[:recipient],
      subject: "Security Alert: #{alert_type}",
      heading: "Security Alert",
      body: "A security event was detected: #{alert_type}.",
      details: details,
      metadata: {
        category: "security_alert",
        alert_type: alert_type,
        severity: params[:severity].presence || "high",
        details: details
      }
    )

    render_success(data: {
      message: "Security alert email queued",
      email_delivery_id: delivery.id,
      status: delivery.status
    })
  end

  # POST /api/v1/internal/emails/review_notification
  # Params: recipient, subject, body, review_id (optional)
  def review_notification
    delivery = dispatch_email(
      recipient: params[:recipient],
      subject: params[:subject].presence || "Review Required",
      heading: "Review Required",
      body: params[:body].to_s,
      details: {},
      metadata: {
        category: "review_notification",
        review_id: params[:review_id]
      }.compact
    )

    render_success(data: {
      message: "Review notification email queued",
      email_delivery_id: delivery.id,
      status: delivery.status
    })
  end

  # POST /api/v1/internal/emails/:id/delivered
  # Worker callback reporting the SMTP outcome.
  # Body: { status: "sent" | "failed", message_id:, error: }
  def delivered
    delivery = EmailDelivery.find_by(id: params[:id])
    return render_success(applied: false, reason: "delivery_not_found") unless delivery

    if params[:status].to_s == "sent"
      delivery.update!(
        status: "sent",
        sent_at: Time.current,
        external_id: params[:message_id].presence,
        error_message: nil
      )
    else
      delivery.update!(
        status: "failed",
        error_message: params[:error].presence || "Delivery failed"
      )
    end

    render_success(applied: true, status: delivery.status, email_delivery_id: delivery.id)
  rescue StandardError => e
    # Worker-receiver discipline: never 5xx on a callback (retry-storm guard).
    Rails.logger.error "[Internal::Emails#delivered] #{params[:id]}: #{e.message}"
    render_success(applied: false, error: e.message)
  end

  private

  # Create the pending ledger row + enqueue the worker send job.
  # On enqueue failure the row is recorded as failed (honest state — the mail
  # was never handed off) and we still return 2xx to the worker caller.
  def dispatch_email(recipient:, subject:, heading:, body:, details:, metadata:)
    delivery = EmailDelivery.create!(
      recipient_email: recipient,
      subject: subject,
      email_type: "notification",
      status: "pending",
      metadata: metadata
    )

    begin
      WorkerJobService.enqueue_alert_email({
        email_delivery_id: delivery.id,
        recipient: recipient,
        subject: subject,
        heading: heading,
        body: body,
        details: details
      })
    rescue WorkerJobService::WorkerServiceError => e
      Rails.logger.error "[Internal::Emails] failed to enqueue send for #{delivery.id}: #{e.message}"
      delivery.update!(status: "failed", error_message: "Failed to enqueue send: #{e.message}")
    end

    delivery
  end

  # Internal worker traffic is trusted (mTLS); convert nested params to a plain
  # hash for jsonb storage / job payloads.
  def permitted_hash(value)
    case value
    when ActionController::Parameters then value.to_unsafe_h
    when Hash then value
    else {}
    end
  end
end
