# frozen_string_literal: true

require_relative 'application_mailer'

class NotificationMailer < ApplicationMailer
  # NOTE: email_verification, subscription_renewal, payment_failed and
  # subscription_cancelled have NO ERB template under
  # app/views/notification_mailer/. Until one is authored, calling them raises
  # ActionView::MissingTemplate at `mail(...)`. Before IMP-cd78fa6e7522 they
  # returned early (the lookup always failed) and so failed silently instead;
  # that silence was the bug, and a loud MissingTemplate is the intended
  # interim behaviour. None of the four has a caller today.

  # invitation_email.{html,text}.erb call app_name; private mailer methods are
  # not exposed to views, so without this the template raises NameError at
  # render time and the invitation is never delivered.
  helper_method :app_name

  # Welcome email for new users
  def welcome_email(user_id)
    user = fetch_user(user_id)
    return if user.nil?
    
    @user = user
    @login_url = "#{frontend_url}/login"
    
    mail(
      to: user[:email],
      subject: "Welcome to #{app_name}!"
    )
  end
  
  # Password reset email
  def password_reset(user_id, reset_token = nil)
    user = fetch_user(user_id)
    return if user.nil?
    
    @user = user
    # Use the reset_token from the user data if not provided separately
    token = reset_token || user[:reset_token]
    @reset_url = "#{frontend_url}/reset-password?token=#{token}"
    @expiry_hours = EmailConfigurationService.instance.settings[:password_reset_expiry_hours] || 2
    
    mail(
      to: user[:email],
      subject: "Password Reset Instructions - #{app_name}"
    )
  end
  
  # Email verification
  def email_verification(user_id, verification_token)
    user = fetch_user(user_id)
    return if user.nil?
    
    @user = user
    @verification_url = "#{frontend_url}/verify-email?token=#{verification_token}"
    @expiry_hours = EmailConfigurationService.instance.settings[:email_verification_expiry_hours] || 24
    
    mail(
      to: user[:email],
      subject: "Verify Your Email Address"
    )
  end
  
  # Subscription renewal notification
  def subscription_renewal(account_id)
    account = fetch_account(account_id)
    return if account.nil?
    
    @account = account
    @dashboard_url = "#{frontend_url}/dashboard/billing"
    
    mail(
      to: account[:billing_email] || account[:owner_email],
      subject: "Your Subscription Has Been Renewed"
    )
  end
  
  # Payment failed notification
  def payment_failed(account_id, amount, retry_date)
    account = fetch_account(account_id)
    return if account.nil?
    
    @account = account
    @amount = amount
    @retry_date = retry_date
    @billing_url = "#{frontend_url}/dashboard/billing"
    
    mail(
      to: account[:billing_email] || account[:owner_email],
      subject: "Payment Failed - Action Required"
    )
  end
  
  # Subscription cancellation confirmation
  def subscription_cancelled(account_id, end_date)
    account = fetch_account(account_id)
    return if account.nil?
    
    @account = account
    @end_date = end_date
    @reactivate_url = "#{frontend_url}/dashboard/billing"
    
    mail(
      to: account[:billing_email] || account[:owner_email],
      subject: "Subscription Cancellation Confirmed"
    )
  end
  
  # Test email for configuration verification
  def test_email(email_address)
    @timestamp = Time.current
    @settings = EmailConfigurationService.instance.settings

    mail(
      to: email_address,
      subject: "Test Email from #{app_name}"
    )
  end

  # Account invitation email
  def invitation_email(invitation_id, invitation_token)
    invitation = fetch_invitation(invitation_id)
    return if invitation.nil?

    @invitation = invitation
    @inviter_name = "#{invitation[:inviter_first_name]} #{invitation[:inviter_last_name]}"
    @invitee_name = "#{invitation[:first_name]} #{invitation[:last_name]}"
    @account_name = invitation[:account_name]
    @invitation_url = "#{frontend_url}/accept-invitation?token=#{invitation_token}"
    @expires_at = invitation[:expires_at]
    @role_names = invitation[:role_names]&.join(', ') || 'Member'

    mail(
      to: invitation[:email],
      subject: "You've been invited to join #{@account_name} on #{app_name}"
    )
  end

  # Generic alert / notification email (security alerts, review notifications,
  # ...). The server-side EmailDelivery ledger is updated by the worker job that
  # invokes this mailer, not by the mailer itself.
  def alert_email(recipient:, subject:, heading: 'Notification', body: '', details: {})
    @heading = heading
    @body = body
    @details = details.is_a?(Hash) ? details : {}

    mail(
      to: recipient,
      subject: subject
    )
  end

  private

  def fetch_user(user_id)
    api_client.get_internal_user(user_id)
  rescue StandardError => e
    log_lookup_failure('user', user_id, e)
    nil
  end

  def fetch_account(account_id)
    api_client.get_internal_account(account_id)
  rescue StandardError => e
    log_lookup_failure('account', account_id, e)
    nil
  end

  def fetch_invitation(invitation_id)
    api_client.get_internal_invitation(invitation_id)
  rescue StandardError => e
    log_lookup_failure('invitation', invitation_id, e)
    nil
  end

  # A failed lookup degrades to nil (the mailer then declines to send), but it
  # must not do so silently: without this, a missing constant, a timeout and a
  # 404 were indistinguishable and the mail simply never arrived.
  #
  # Log the exception class and message, never the exception's response_body —
  # that carries the looked-up record in full. Note BackendApiClient#handle_response
  # lifts the server's own error string into the message for 4xx, so keep the
  # server's internal error strings free of record data.
  def log_lookup_failure(kind, id, error)
    worker_logger.error(
      "[NotificationMailer] #{kind} lookup failed for id=#{id}: " \
      "#{error.class}: #{error.message}"
    )
  rescue StandardError => logging_error
    # Never let diagnostics mask the original failure — but do not vanish either.
    warn("[NotificationMailer] failed to log #{kind} lookup failure: #{logging_error.class}")
  end

  def worker_logger
    PowernodeWorker.application.logger
  end

  def frontend_url
    ENV['FRONTEND_URL'] || 'http://localhost:3001'
  end
  
  def app_name
    EmailConfigurationService.instance.settings[:smtp_from_name] || 'Powernode'
  end
  
  # BackendApiClient is the client config/boot.rb actually requires; it also
  # carries the circuit breaker, retry policy and the dev mTLS header the
  # /api/v1/internal/* endpoints authenticate against.
  def api_client
    @api_client ||= BackendApiClient.new
  end
end
