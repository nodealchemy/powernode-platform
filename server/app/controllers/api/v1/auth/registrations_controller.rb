# frozen_string_literal: true

class Api::V1::Auth::RegistrationsController < ApplicationController
  skip_before_action :authenticate_request, only: [ :create ]

  # POST /api/v1/registrations
  def create
    ActiveRecord::Base.transaction do
      @account = Account.new(account_params)

      # Auto-generate subdomain if not provided
      if @account.subdomain.blank?
        base_subdomain = @account.name.parameterize
        @account.subdomain = base_subdomain

        # Ensure uniqueness
        counter = 1
        while Account.exists?(subdomain: @account.subdomain)
          @account.subdomain = "#{base_subdomain}#{counter}"
          counter += 1
        end
      end

      @account.save!

      @user = @account.users.build(user_params)
      @user.save!

      # Assign Owner role to the first user (handled automatically in User model)
      owner_role = Role.find_by(name: "Owner")
      @user.assign_role(owner_role) if owner_role

      tokens = JwtService.generate_tokens(@user)
      @user.record_login!

      render json: {
        success: true,
        user: user_data(@user),
        account: account_data(@account),
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

  def account_params
    params.require(:account).permit(:name, :subdomain)
  end

  def user_params
    params.require(:user).permit(:first_name, :last_name, :email, :password, :password_confirmation)
  end

  def user_data(user)
    {
      id: user.id,
      email: user.email,
      firstName: user.first_name,
      lastName: user.last_name,
      fullName: user.full_name,
      role: user.roles.first&.name&.downcase || 'member',
      status: user.status,
      emailVerified: user.email_verified?
    }
  end

  def account_data(account)
    {
      id: account.id,
      name: account.name,
      subdomain: account.subdomain,
      status: account.status
    }
  end
end
