# frozen_string_literal: true

require_relative '../base_job'
require_relative '../../mailers/notification_mailer'

# Worker half of WorkerJobService.enqueue_password_reset_email.
#
# The reset token MUST travel in the job arguments: User#generate_reset_token!
# BCrypt-hashes it into reset_token_digest and returns the plaintext exactly
# once, so the worker cannot recover it from the internal users endpoint later
# (that endpoint's `reset_token` field reads an instance variable that is only
# populated in the process that minted it, and is therefore always nil here).
# Without the token the reset URL would be built with a blank token and every
# reset link would be dead.
#
# Because it must travel, the exposure is bounded explicitly. Job args reach
# FOUR sinks; masking (declared by sensitive_arg_indexes below) closes the three
# log sinks and leaves the payload sink open:
#   CLOSED  JobsController's "Enqueuing ... with args:" line
#   CLOSED  BaseJob#perform's "Starting ... with args:" line and the
#           runaway-loop "Job args:" dumps
#   CLOSED  Sidekiq's OWN default error handler, which logs the whole job hash
#           (args included) on every raised exception — and this job re-raises
#           on purpose, so it is the sink a failing reset email hits hardest.
#           Wrapped in a redacting handler in config/application.rb.
#   OPEN    the Sidekiq/Redis job payload, and any retry/dead-set entry, which
#           hold the plaintext token verbatim for the life of the entry. This is
#           also what Sidekiq::Web renders in the retry/dead views.
# Closing the last one needs the token carried out-of-band — e.g. on the
# EmailDelivery ledger row with an internal GET to exchange the id for it —
# which is filed as follow-up. Residual risk is bounded by the token's 1-hour
# expiry (generate_reset_token!).
#
# Sibling tokens do NOT need any of this: invitations.token and
# users.email_verification_token are plaintext in the DB, so the worker fetches
# them over the internal API and they never enter args at all.
#
# Enqueued by Api::V1::Auth::PasswordsController#forgot.
module Notifications
  class PasswordResetEmailJob < BaseJob
    sidekiq_options queue: 'email', retry: 3, backtrace: true

    # arg 1 is the plaintext reset token. This masks it at all four LOG sinks
    # (JobsController's enqueue line, BaseJob#perform, the runaway-loop dumps,
    # and Sidekiq's default error handler). It does NOT scrub the Sidekiq/Redis
    # payload, which still holds the token for the life of the job and of any
    # retry/dead-set entry — see the note above.
    def self.sensitive_arg_indexes
      [1]
    end

    def execute(user_id, reset_token = nil)
      log_info('Processing password reset email', user_id: user_id)

      message = NotificationMailer.password_reset(user_id, reset_token).deliver_now

      log_info('Password reset email delivered',
        user_id: user_id, message_id: message&.message_id)

      { success: true, user_id: user_id, message_id: message&.message_id }
    rescue StandardError => e
      # Re-raise so Sidekiq retries a genuine fault. This job's own log context
      # carries only the user id (see the args-logging caveat above).
      log_error('Password reset email delivery failed', e, user_id: user_id)
      raise
    end
  end
end
