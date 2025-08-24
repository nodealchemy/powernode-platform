# frozen_string_literal: true

require_relative 'application_mailer'

class NotificationMailer < ApplicationMailer
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
  
  private
  
  def fetch_user(user_id)
    api_client.get_user(user_id)
  rescue StandardError => e
    nil
  end
  
  def fetch_account(account_id)
    api_client.get_account(account_id)
  rescue StandardError => e
    nil
  end
  
  def frontend_url
    ENV['FRONTEND_URL'] || 'http://localhost:3001'
  end
  
  def app_name
    EmailConfigurationService.instance.settings[:smtp_from_name] || 'Powernode'
  end
  
  def api_client
    @api_client ||= ApiClient.new
  end
end