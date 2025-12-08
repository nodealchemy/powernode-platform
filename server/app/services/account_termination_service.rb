# frozen_string_literal: true

# Service for managing account termination workflow
class AccountTerminationService
  class TerminationError < StandardError; end

  class << self
    # Initiate account termination
    def initiate(account:, requested_by:, reason: nil, request_data_export: false)
      validate_can_terminate!(account)

      AccountTermination.initiate(
        account: account,
        requested_by: requested_by,
        reason: reason,
        request_data_export: request_data_export
      )
    end

    # Confirm termination (starts grace period)
    def confirm(termination)
      termination.confirm!
    end

    # Cancel termination
    def cancel(termination, user:, reason: nil)
      termination.cancel!(user, reason)
    end

    # Process terminations ready for deletion
    def process_due_terminations
      results = {
        processed: 0,
        failed: 0,
        errors: []
      }

      AccountTermination.ready_for_processing.find_each do |termination|
        begin
          process_termination(termination)
          results[:processed] += 1
        rescue => e
          results[:failed] += 1
          results[:errors] << { termination_id: termination.id, error: e.message }
          Rails.logger.error "Failed to process termination #{termination.id}: #{e.message}"
        end
      end

      results
    end

    # Process a single termination
    def process_termination(termination)
      return unless termination.can_start_processing?

      termination.start_processing!

      account = termination.account

      # Delete all account data
      ActiveRecord::Base.transaction do
        delete_account_data(account)
        termination.complete!
      end
    end

    # Send reminder notifications
    def send_reminders
      AccountTermination.in_grace_period.find_each do |termination|
        days_remaining = termination.days_remaining

        case days_remaining
        when 7
          send_reminder_notification(termination, '7_days')
        when 3
          send_reminder_notification(termination, '3_days')
        when 1
          send_reminder_notification(termination, '1_day')
        end
      end
    end

    private

    def validate_can_terminate!(account)
      # Check for existing active termination
      if AccountTermination.active.exists?(account: account)
        raise TerminationError, 'Account already has an active termination request'
      end

      # Check for active subscriptions that need cancellation
      if account.subscription&.active?
        raise TerminationError, 'Please cancel your subscription before requesting account termination'
      end

      # Check for pending payments
      if account.subscription&.payments&.pending&.exists?
        raise TerminationError, 'Account has pending payments'
      end
    end

    def delete_account_data(account)
      # Order matters - delete dependent records first

      # Delete user data
      account.users.find_each do |user|
        delete_user_data(user)
      end

      # Delete account-level data
      delete_account_records(account)

      # Mark account as terminated (don't fully delete for audit trail)
      account.update!(
        status: 'terminated',
        terminated_at: Time.current,
        name: "Terminated Account #{account.id[0..7]}"
      )
    end

    def delete_user_data(user)
      # Delete user consents
      UserConsent.where(user: user).delete_all

      # Delete terms acceptances
      TermsAcceptance.where(user: user).delete_all

      # Anonymize audit logs
      AuditLog.where(user: user).update_all(
        ip_address: nil,
        user_agent: nil
      )

      # Delete password histories
      user.password_histories.delete_all if user.respond_to?(:password_histories)

      # Delete user roles
      user.user_roles.delete_all if user.respond_to?(:user_roles)

      # Anonymize user record
      user.update!(
        email: "terminated_#{SecureRandom.hex(8)}@terminated.powernode.local",
        name: 'Terminated User',
        password_digest: nil,
        status: 'terminated',
        two_factor_secret: nil,
        backup_codes: nil,
        last_login_ip: nil,
        preferences: {},
        notification_preferences: {}
      )
    end

    def delete_account_records(account)
      # Delete files
      if defined?(FileObject)
        FileObject.where(account: account).find_each(&:destroy)
      end

      # Delete API keys
      if defined?(ApiKey)
        ApiKey.where(account: account).delete_all
      end

      # Delete webhooks
      if defined?(WebhookEndpoint)
        WebhookEndpoint.where(account: account).delete_all
      end

      # Delete data export requests
      DataExportRequest.where(account: account).find_each do |request|
        request.cleanup_file!
        request.destroy
      end

      # Delete data deletion requests
      DataDeletionRequest.where(account: account).delete_all

      # Anonymize subscription but keep for financial records
      if account.subscription
        account.subscription.update!(
          status: 'terminated',
          metadata: {}
        )
      end
    end

    def send_reminder_notification(termination, reminder_type)
      # TODO: Implement notification sending
      Rails.logger.info "Sending #{reminder_type} reminder for termination #{termination.id}"

      termination.update!(
        termination_log: termination.termination_log + [{
          event: "reminder_#{reminder_type}_sent",
          at: Time.current.iso8601
        }]
      )
    end
  end
end
