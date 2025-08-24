# frozen_string_literal: true

class Api::V1::Auth::RegistrationsController < ApplicationController
  include RateLimiting
  include UserSerialization
  
  skip_before_action :authenticate_request, only: [:create]
  after_action :increment_rate_limit_count, only: [:create], if: -> { response.status >= 400 }

  # POST /api/v1/registrations
  def create
    ActiveRecord::Base.transaction do
      @account = Account.new(account_params)

      # Auto-generate subdomain if not provided
      if @account.subdomain.blank? && @account.name.present?
        base_subdomain = @account.name.parameterize
        @account.subdomain = base_subdomain

        # Ensure uniqueness
        counter = 1
        while Account.exists?(subdomain: @account.subdomain)
          @account.subdomain = "#{base_subdomain}#{counter}"
          counter += 1
        end
      end

      unless @account.save
        raise ActiveRecord::RecordInvalid.new(@account)
      end

      @user = @account.users.build(user_params)
      # First user in account gets owner role (this is handled by User model callback)
      
      # Auto-verify email in test mode
      if ENV['DISABLE_RATE_LIMITING'] == 'true'
        @user.email_verified = true
        @user.email_verified_at = Time.current
      end
      
      unless @user.save
        raise ActiveRecord::RecordInvalid.new(@user)
      end

      # Create subscription if plan is selected
      plan_id = params[:planId] || params.dig(:user, :planId)
      if plan_id.present?
        plan = Plan.find_by(id: plan_id, status: 'active', is_public: true)
        if plan
          # Create subscription with trial period
          @subscription = @account.build_subscription(
            plan: plan,
            status: 'trialing',
            quantity: 1,
            trial_start: Time.current,
            trial_end: Time.current + plan.trial_days.days,
            current_period_start: Time.current,
            current_period_end: Time.current + plan.trial_days.days
          )
          @subscription.save!
          
          # Note: Plan-based role assignment not implemented in single-role system
        end
      end

      tokens = JwtService.generate_tokens(@user)
      @user.record_login!

      render json: {
        success: true,
        user: user_data(@user),
        account: account_data(@account),
        subscription: @subscription ? subscription_data(@subscription) : nil,
        access_token: tokens[:access_token],
        refresh_token: tokens[:refresh_token],
        expires_at: tokens[:expires_at],
        message: "Account created successfully"
      }, status: :created
    end
  rescue ActiveRecord::RecordInvalid => e
    # Use the first validation error as the main error message
    error_message = e.record.errors.full_messages.first || "Registration failed"
    render json: {
      success: false,
      error: error_message,
      details: e.record.errors.full_messages
    }, status: :unprocessable_content
  rescue StandardError => e
    render json: {
      success: false,
      error: e.message.presence || "Registration failed"
    }, status: :unprocessable_content
  end

  private

  def should_rate_limit?
    true # Always rate limit registration attempts
  end

  def rate_limit_max_attempts
    3 # Allow only 3 registration attempts per IP per hour
  end

  def rate_limit_window_seconds
    3600 # 1 hour
  end

  def account_params
    {
      name: params[:accountName] || params.dig(:user, :accountName)
    }
  end

  def user_params
    {
      first_name: params[:firstName] || params.dig(:user, :firstName),
      last_name: params[:lastName] || params.dig(:user, :lastName),
      email: params[:email] || params.dig(:user, :email),
      password: params[:password] || params.dig(:user, :password)
    }
  end

  # user_data and account_data methods are provided by UserSerialization concern

  def subscription_data(subscription)
    {
      id: subscription.id,
      status: subscription.status,
      plan: {
        id: subscription.plan.id,
        name: subscription.plan.name,
        price_cents: subscription.plan.price_cents,
        currency: subscription.plan.currency,
        billing_cycle: subscription.plan.billing_cycle
      },
      trial_start: subscription.trial_start&.iso8601,
      trial_end: subscription.trial_end&.iso8601,
      current_period_start: subscription.current_period_start&.iso8601,
      current_period_end: subscription.current_period_end&.iso8601
    }
  end
end
