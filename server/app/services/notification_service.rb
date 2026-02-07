# frozen_string_literal: true

# Service for sending notifications (in-app and email)
# Coordinates between backend models and worker service for delivery
class NotificationService
  class DeliveryError < StandardError; end

  class << self
    # Send transactional email via worker service
    # @param template [String] Email template name
    # @param user_id [String] Optional user ID for user-specific emails
    # @param account_id [String] Optional account ID for account-wide emails
    # @param email [String] Optional direct email address (for terminated users)
    # @param data [Hash] Template data for variable interpolation
    # @return [Hash] Result from worker service
    def send_email(template:, user_id: nil, account_id: nil, email: nil, data: {})
      validate_email_params!(template, user_id, account_id, email)

      job_args = {
        "email_type" => template,
        "data" => data.deep_stringify_keys
      }

      # Determine recipient
      if email.present?
        job_args["recipient"] = email
      elsif user_id.present?
        job_args["user_id"] = user_id
        job_args["recipient"] = resolve_user_email(user_id)
      elsif account_id.present?
        job_args["account_id"] = account_id
        # For account emails, send to all account users
        job_args["recipients"] = resolve_account_emails(account_id)
      end

      queue_email_job(job_args)
    rescue StandardError => e
      Rails.logger.error "[NotificationService] Failed to send email: #{e.message}"
      raise DeliveryError, "Failed to send email: #{e.message}"
    end

    # Send in-app notification to user(s)
    # @param user_id [String] User ID or array of user IDs
    # @param message [String] Notification message
    # @param notification_type [String] Type of notification
    # @param metadata [Hash] Additional metadata
    # @return [Array<Notification>] Created notifications
    def send_in_app(user_id:, message:, notification_type: "info", account_id: nil, metadata: {})
      user_ids = Array(user_id)

      user_ids.map do |uid|
        Notification.create!(
          user_id: uid,
          account_id: account_id,
          message: message,
          notification_type: notification_type,
          metadata: metadata,
          read: false
        )
      end
    rescue StandardError => e
      Rails.logger.error "[NotificationService] Failed to create in-app notification: #{e.message}"
      []
    end

    # Send both email and in-app notification
    # @param template [String] Email template name
    # @param message [String] In-app notification message
    # @param user_id [String] User ID
    # @param notification_type [String] Type of notification
    # @param data [Hash] Email template data and notification metadata
    def send_all(template:, message:, user_id:, notification_type: "info", account_id: nil, data: {})
      # Send in-app notification
      send_in_app(
        user_id: user_id,
        message: message,
        notification_type: notification_type,
        account_id: account_id,
        metadata: data
      )

      # Queue email
      send_email(
        template: template,
        user_id: user_id,
        account_id: account_id,
        data: data
      )
    end

    # Send system alert notification
    # @param account [Account] Account to notify
    # @param type [String] Alert type identifier
    # @param level [Symbol] Alert level (:info, :warning, :error, :critical)
    # @param title [String] Alert title
    # @param message [String] Alert message
    # @param details [Hash] Alert details
    # @param metadata [Hash] Additional metadata
    def send_system_alert(account:, type:, level: :info, title:, message:, details: {}, metadata: {})
      Rails.logger.info "[NotificationService] System alert [#{level}] for account #{account.id}: #{title}"

      admin_user_ids = account.users.active.pluck(:id)
      return if admin_user_ids.empty?

      notification_type = case level
                          when :critical, :error then "error"
                          when :warning then "warning"
                          else "info"
      end

      send_in_app(
        user_id: admin_user_ids,
        message: "#{title}: #{message}",
        notification_type: notification_type,
        account_id: account.id,
        metadata: metadata.merge(alert_type: type, alert_level: level.to_s, details: details)
      )
    rescue StandardError => e
      Rails.logger.warn "[NotificationService] Failed to send system alert: #{e.message}"
    end

    # Send notification to all users in an account
    # @param account_id [String] Account ID
    # @param template [String] Email template name
    # @param message [String] In-app notification message
    # @param notification_type [String] Type of notification
    # @param data [Hash] Email template data and notification metadata
    def send_to_account(account_id:, template:, message:, notification_type: "info", data: {})
      account = Account.find(account_id)
      user_ids = account.users.active.pluck(:id)

      # Send in-app notifications
      send_in_app(
        user_id: user_ids,
        message: message,
        notification_type: notification_type,
        account_id: account_id,
        metadata: data
      )

      # Queue email to account
      send_email(
        template: template,
        account_id: account_id,
        data: data
      )
    rescue ActiveRecord::RecordNotFound
      Rails.logger.warn "[NotificationService] Account not found: #{account_id}"
      nil
    end

    private

    def validate_email_params!(template, user_id, account_id, email)
      raise ArgumentError, "Template is required" if template.blank?

      if user_id.blank? && account_id.blank? && email.blank?
        raise ArgumentError, "Either user_id, account_id, or email is required"
      end
    end

    def resolve_user_email(user_id)
      User.find(user_id).email
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def resolve_account_emails(account_id)
      Account.find(account_id).users.active.pluck(:email)
    rescue ActiveRecord::RecordNotFound
      []
    end

    def queue_email_job(args)
      worker_client.queue_job(
        "Notifications::TransactionalEmailJob",
        [ args ],
        queue: "email"
      )
    end

    def worker_client
      @worker_client ||= WorkerApiClient.new
    end
  end
end
