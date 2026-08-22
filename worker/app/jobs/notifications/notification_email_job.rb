# frozen_string_literal: true

require_relative '../base_job'
require_relative '../../mailers/notification_mailer'

# Worker half of WorkerJobService.enqueue_notification_email — the account
# lifecycle emails (invitation, welcome, email verification).
#
# The producer sends a notification TYPE plus a loose options hash rather than a
# rendered email, so this job is a router: it maps the type onto the matching
# NotificationMailer action and supplies that action's positional arguments from
# the options. Model/DB access stays on the server (Pattern B) — the mailer
# re-fetches the user/invitation over the internal API from the ids given here.
#
# Enqueued by Api::V1::InvitationsController (#create, #resend),
# Api::V1::Admin::UsersController#create, Api::V1::Auth::RegistrationsController
# and Api::V1::Auth::EmailVerificationsController.
module Notifications
  class NotificationEmailJob < BaseJob
    sidekiq_options queue: 'email', retry: 3, backtrace: true

    # notification_type => [mailer action, ordered option keys for its arguments]
    #
    # The key lists ARE the producer contract: each mailer action takes plain
    # positional arguments, and the options hash arrives from JSON with string
    # keys. Adding a type here without a matching ERB template under
    # app/views/notification_mailer/ turns a silent no-op into an
    # ActionView::MissingTemplate at deliver time — author the template first.
    # NOTE: only ids travel here. The invite and verification tokens are
    # plaintext in the database (invitations.token,
    # users.email_verification_token), so the mailer reads them back from the
    # internal API rather than receiving them as job arguments — which are
    # logged twice and persisted verbatim in the Sidekiq/Redis payload.
    DISPATCH = {
      'invitation' => [:invitation_email, %w[invitation_id]],
      'welcome' => [:welcome_email, %w[user_id]],
      'email_verification' => [:email_verification, %w[user_id]]
    }.freeze

    def execute(notification_type, options = {})
      type = notification_type.to_s
      action, keys = DISPATCH[type]

      # Both an unknown type and a missing required option are producer bugs
      # that no retry can fix. Both are raised rather than returned: swallowing
      # them into a { success: false } would let Sidekiq mark the job SUCCEEDED,
      # which is the same silence this job was written to end. Landing in the
      # dead set is the alarm.
      raise ArgumentError, "Unknown notification type: #{type}" unless action

      opts = (options || {}).transform_keys(&:to_s)
      validate_required_params(opts, *keys)

      log_info('Processing notification email', notification_type: type, mailer_action: action)

      message = NotificationMailer.public_send(action, *keys.map { |k| opts[k] }).deliver_now

      log_info('Notification email delivered',
        notification_type: type, message_id: message&.message_id)

      { success: true, notification_type: type, message_id: message&.message_id }
    rescue StandardError => e
      # Re-raise so Sidekiq retries genuine faults (SMTP down, backend API
      # blip). We never swallow a delivery failure into a fake success.
      log_error('Notification email delivery failed', e, notification_type: type)
      raise
    end
  end
end
