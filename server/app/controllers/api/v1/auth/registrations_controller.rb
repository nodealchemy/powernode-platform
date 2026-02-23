# frozen_string_literal: true

class Api::V1::Auth::RegistrationsController < ApplicationController
  # Rate limiting is now included in ApplicationController
  include UserSerialization
  include RefreshTokenCookie

  skip_before_action :authenticate_request, only: [ :create ]

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

      # Handle email verification based on system settings
      if System::SettingsService.email_verification_required?
        # Generate verification token for production/development
        @user.generate_email_verification_token
      else
        @user.email_verified_at = Time.current
      end

      unless @user.save
        raise ActiveRecord::RecordInvalid.new(@user)
      end

      # Create subscription if plan is selected
      plan_id = params[:plan_id] || params.dig(:user, :plan_id)
      if plan_id.present?
        plan = Plan.find_by(id: plan_id, status: "active", is_public: true)
        if plan
          # Create subscription with trial period
          @subscription = @account.build_subscription(
            plan: plan,
            status: "trialing",
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

      tokens = Security::JwtService.generate_user_tokens(@user)
      set_refresh_cookie(tokens[:refresh_token])
      @user.record_login!

      # Send verification email if not auto-verified
      unless @user.verified?
        begin
          WorkerJobService.enqueue_notification_email(
            "email_verification",
            {
              user_id: @user.id,
              email: @user.email,
              verification_token: @user.email_verification_token,
              user_name: @user.full_name,
              smtp_settings: System::SettingsService.get_setting("smtp_settings")
            }
          )
        rescue StandardError => e
          Rails.logger.error "Failed to send verification email during registration: #{e.message}"
          # Don't fail registration if email fails
        end
      end

      response_data = {
        user: user_data(@user),
        account: account_data(@account),
        subscription: @subscription ? subscription_data(@subscription) : nil,
        access_token: tokens[:access_token],
        expires_at: tokens[:expires_at]
      }

      # Add verification reminder if email is not verified
      unless @user.verified?
        response_data[:warning] = "Please check your email and verify your account to secure access"
      end

      render_success(
        message: "Account created successfully",
        data: response_data,
        status: :created
      )
    end
  rescue ActiveRecord::RecordInvalid => e
    # Use the first validation error as the main error message
    error_message = e.record.errors.full_messages.first || "Registration failed"
    render_error(error_message, :unprocessable_content, details: e.record.errors.full_messages)
  rescue StandardError => e
    render_error(e.message.presence || "Registration failed", status: :unprocessable_content)
  end

  private

  def should_rate_limit?
    true # Always rate limit registration attempts
  end


  def account_params
    # Support both snake_case and camelCase param names
    account_name = params[:account_name] || params[:accountName] ||
                   params.dig(:user, :account_name) || params.dig(:user, :accountName)
    {
      name: account_name
    }
  end

  def user_params
    # Support both single 'name' field and firstName/lastName combination
    # Also check for snake_case variants (first_name, last_name)
    name = params[:name] || params.dig(:user, :name)
    if name.blank?
      first = params[:firstName] || params[:first_name] ||
              params.dig(:user, :firstName) || params.dig(:user, :first_name)
      last = params[:lastName] || params[:last_name] ||
             params.dig(:user, :lastName) || params.dig(:user, :last_name)
      name = [ first, last ].compact.join(" ").presence
    end

    {
      name: name,
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
